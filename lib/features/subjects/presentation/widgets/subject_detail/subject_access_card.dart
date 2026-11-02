import 'package:flutter/material.dart';
import 'package:itaaleem/features/app_config/app_config_providers.dart'
    show serverText;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:itaaleem/core/error/failure.dart';
import 'package:itaaleem/core/theme/app_spacing.dart';
import 'package:itaaleem/core/utils/platform_utils.dart';
import 'package:itaaleem/core/utils/result.dart';
import 'package:itaaleem/core/utils/safe_url.dart';
import 'package:itaaleem/core/widgets/app_sheet.dart';
import 'package:itaaleem/features/center_admin/presentation/widgets/admin_common.dart';
import 'package:itaaleem/features/activation/presentation/providers/activation_invalidation.dart';
import 'package:itaaleem/features/activation/presentation/providers/activation_providers.dart';
import 'package:itaaleem/features/subjects/data/datasources/subjects_remote_data_source.dart';
import 'package:itaaleem/features/subjects/domain/entities/subject.dart';
import 'package:itaaleem/features/subjects/presentation/providers/subjects_providers.dart';
import 'package:itaaleem/features/subscriptions/presentation/providers/subscription_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Per-account marker of a sent, not-yet-approved subscription request.
/// Not in the logout keep-list, so it's wiped with the account's data.
String _pendingKey(int subjectId) => 'sub_request_pending_$subjectId';

/// Whether a subscription request for [subjectId] is awaiting the center:
/// the server's `pending` status when it sends one, else the local marker.
final subscriptionRequestPendingProvider = FutureProvider.autoDispose
    .family<bool, int>((ref, subjectId) async {
      final status = ref
          .watch(subjectSubscriptionProvider(subjectId))
          .valueOrNull;
      final serverStatus = status?.subscription?.status.toLowerCase();
      if (serverStatus == 'pending' || serverStatus == 'requested') {
        return true;
      }
      if (status?.subscribed ?? false) return false;
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_pendingKey(subjectId)) ?? false;
    });

/// A subject whose page should open the code sheet as soon as its access
/// card shows — set by a locked lecture's "فعّل المادة" button.
final pendingActivationSheetProvider = StateProvider<int?>((ref) => null);

/// Stand-in when the server sent no `access_card` (older server) but the
/// subject has locked lectures: the code button only.
const fallbackAccessCard = SubjectAccessCard(
  show: true,
  activationEnabled: true,
);

/// The card to show for [subject], or `null` for none: the server's
/// `access_card` when sent (it knows about subscriptions and free
/// subjects), else [fallbackAccessCard] while any lecture is locked.
SubjectAccessCard? effectiveAccessCard(
  Subject subject, {
  required bool hasLockedLessons,
}) {
  final card = subject.accessCard;
  if (card != null) return shouldShowAccessCard(card) ? card : null;
  return hasLockedLessons ? fallbackAccessCard : null;
}

/// Whether [card] has anything to render on this platform.
bool shouldShowAccessCard(SubjectAccessCard? card) {
  if (card == null || !card.show) return false;
  // Android always offers "طلب اشتراك"; iOS only the code.
  return card.activationEnabled || !PlatformUtils.isIOS;
}

/// "اشترك في المادة" — shown above the lectures while `access_card.show` is
/// true (hidden once subscribed, or for a free subject).
///
/// * Android: "تفعيل بالكود" (if `activation_enabled`), "طلب اشتراك"
///   (tracking `request_status`), and "شراء المادة" (if `purchase_enabled`).
/// * iOS: "تفعيل بالكود" only — never a request, purchase or price.
class SubjectAccessCardView extends ConsumerStatefulWidget {
  const SubjectAccessCardView({
    super.key,
    required this.subjectId,
    required this.card,
    this.subjectName,
  });

  final int subjectId;
  final SubjectAccessCard card;
  final String? subjectName;

  @override
  ConsumerState<SubjectAccessCardView> createState() =>
      _SubjectAccessCardViewState();
}

class _SubjectAccessCardViewState extends ConsumerState<SubjectAccessCardView> {
  bool _requesting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoOpen());
  }

  void _maybeAutoOpen() {
    if (!mounted) return;
    if (ref.read(pendingActivationSheetProvider) != widget.subjectId) return;
    ref.read(pendingActivationSheetProvider.notifier).state = null;
    if (widget.card.activationEnabled) _openCodeSheet();
  }

  Future<void> _openCodeSheet() {
    return showAppSheet<void>(
      context: context,
      title: 'تفعيل بالكود',
      subtitle: 'اكتب الكود اللي أخدته من السنتر',
      icon: Icons.vpn_key_rounded,
      builder: (_) => _ActivationCodeSheet(subjectId: widget.subjectId),
    );
  }

  /// "طلب اشتراك": explains what happens, then sends on confirm.
  Future<void> _confirmRequest() async {
    final send = await showAppSheet<bool>(
      context: context,
      title: 'طلب اشتراك',
      subtitle: widget.subjectName,
      icon: Icons.send_rounded,
      builder: (sheetContext) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppSheetCard(
            child: Text(
              'هيوصل طلبك للسنتر، ولما يوافق المادة هتتفتح لك تلقائياً '
              'وهيوصلك إشعار.',
              textAlign: TextAlign.center,
              style: Theme.of(sheetContext).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: AppSpacing.base),
          FilledButton(
            onPressed: () => Navigator.of(sheetContext).pop(true),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
            ),
            child: const Text('إرسال الطلب'),
          ),
        ],
      ),
    );
    await waitForRouteExit();
    if (send == true && mounted) await _request();
  }

  Future<void> _request() async {
    HapticFeedback.lightImpact();
    setState(() => _requesting = true);
    var pending = false;
    String? error;
    try {
      await ref
          .read(subjectsRemoteDataSourceProvider)
          .requestSubscription(subjectId: widget.subjectId);
      pending = true;
    } catch (e) {
      final failure = failureOf(e);
      // A request that's already open comes back as a conflict.
      final status = failure is ServerFailure ? failure.statusCode : null;
      if (status == 409 || status == 422) {
        pending = true;
      } else {
        error = failure.message;
      }
    }
    if (pending) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_pendingKey(widget.subjectId), true);
    }
    if (!mounted) return;
    setState(() => _requesting = false);
    if (pending) {
      ref.invalidate(subscriptionRequestPendingProvider(widget.subjectId));
      // Pull the fresh `request_status` from the server.
      ref.invalidate(subjectDetailsProvider(widget.subjectId));
      ref.invalidate(subjectsListProvider);
      showAppSnack(context, 'تم إرسال طلبك، هيتم التفعيل بعد موافقة السنتر');
    } else if (error != null) {
      showAppSnack(context, error, type: AppSnackType.error);
    }
  }

  /// Android only (the button never shows on iOS).
  Future<void> _purchase() async {
    final card = widget.card;
    final text = card.purchaseText;
    final url = card.purchaseUrl;
    final phones = text == null ? const <String>[] : findEgyptianPhones(text);
    final haveCode = await showAppSheet<bool>(
      context: context,
      title: 'شراء المادة',
      subtitle: widget.subjectName,
      icon: Icons.shopping_bag_outlined,
      builder: (sheetContext) {
        final scheme = Theme.of(sheetContext).colorScheme;
        final textTheme = Theme.of(sheetContext).textTheme;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (text != null)
              AppSheetCard(
                child: SelectableText(
                  text,
                  textAlign: TextAlign.center,
                  style: textTheme.bodyLarge?.copyWith(height: 1.6),
                ),
              ),
            for (final phone in phones) ...[
              const SizedBox(height: AppSpacing.md),
              PhoneActions(phone: phone),
            ],
            if (url != null) ...[
              const SizedBox(height: AppSpacing.md),
              FilledButton.icon(
                onPressed: () async {
                  final ok = await launchUrlSafely(
                    Uri.parse(url),
                    mode: LaunchMode.externalApplication,
                  );
                  if (!ok && sheetContext.mounted) {
                    showAppSnack(
                      sheetContext,
                      'تعذر فتح الرابط',
                      type: AppSnackType.error,
                    );
                  }
                },
                icon: const Icon(Icons.open_in_new_rounded, size: 20),
                label: const Text('فتح الرابط'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Text(
              'بعد الدفع هيبعتلك السنتر كود التفعيل',
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (card.activationEnabled) ...[
              const SizedBox(height: AppSpacing.sm),
              TextButton.icon(
                onPressed: () => Navigator.of(sheetContext).pop(true),
                icon: const Icon(Icons.vpn_key_outlined, size: 18),
                label: const Text('عندي كود بالفعل'),
              ),
            ],
          ],
        );
      },
    );
    await waitForRouteExit();
    if (haveCode == true && mounted) await _openCodeSheet();
  }

  @override
  Widget build(BuildContext context) {
    // A locked lecture asked for the sheet while this card was already up.
    ref.listen<int?>(pendingActivationSheetProvider, (_, next) {
      if (next == widget.subjectId) _maybeAutoOpen();
    });

    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final card = widget.card;
    final isIOS = PlatformUtils.isIOS;
    // The old-server stand-in offers the code only.
    final showRequest = !isIOS && !identical(card, fallbackAccessCard);
    final showPurchase = card.showPurchase(isIOS: isIOS);
    // `request_status` is the source of truth; the 409 / local marker only
    // stands in on an older server that doesn't send it.
    final pending = !showRequest
        ? false
        : card.requestStatusSent
        ? card.requestPending
        : ref
                  .watch(subscriptionRequestPendingProvider(widget.subjectId))
                  .valueOrNull ??
              false;
    final rejected =
        showRequest && card.requestStatusSent && card.requestRejected;
    final radius = BorderRadius.circular(12);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.base),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: radius,
        border: Border.all(color: scheme.primary.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: radius,
                ),
                child: Icon(
                  Icons.lock_open_rounded,
                  color: scheme.onPrimaryContainer,
                  size: 22,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      // iOS never shows "subscribe" wording.
                      isIOS ? 'فعّل المادة' : 'اشترك في المادة',
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (card.activationEnabled)
                      Text(
                        'فعّل المادة بكود من السنتر',
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (card.activationEnabled) ...[
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              onPressed: _openCodeSheet,
              icon: const Icon(Icons.vpn_key_rounded, size: 18),
              label: const Text('تفعيل بالكود'),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(borderRadius: radius),
              ),
            ),
          ],
          if (showRequest) ...[
            const SizedBox(height: AppSpacing.sm),
            if (pending)
              _StatusBanner(
                icon: Icons.hourglass_top_rounded,
                title: serverText(context, 'waiting', 'طلبك قيد المراجعة'),
                background: scheme.secondaryContainer,
                foreground: scheme.onSecondaryContainer,
              )
            else ...[
              if (rejected) ...[
                _StatusBanner(
                  icon: Icons.cancel_outlined,
                  title: 'تم رفض الطلب',
                  subtitle: card.requestRejectedReason,
                  background: scheme.errorContainer,
                  foreground: scheme.onErrorContainer,
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              FilledButton.tonalIcon(
                onPressed: _requesting ? null : _confirmRequest,
                icon: _requesting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded, size: 18),
                label: Text(rejected ? 'إعادة الطلب' : 'طلب اشتراك'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  shape: RoundedRectangleBorder(borderRadius: radius),
                ),
              ),
            ],
          ],
          if (showPurchase) ...[
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: _purchase,
              icon: const Icon(Icons.shopping_bag_outlined, size: 18),
              label: const Text('شراء المادة'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                shape: RoundedRectangleBorder(borderRadius: radius),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.icon,
    required this.title,
    required this.background,
    required this.foreground,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: foreground),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: text.bodyMedium?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: text.bodySmall?.copyWith(color: foreground),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The code field + "تفعيل" button, redeemed via `POST /activate-code`.
/// Closes itself on success; the subject reloads and the lectures unlock.
class _ActivationCodeSheet extends ConsumerStatefulWidget {
  const _ActivationCodeSheet({required this.subjectId});

  final int subjectId;

  @override
  ConsumerState<_ActivationCodeSheet> createState() =>
      _ActivationCodeSheetState();
}

class _ActivationCodeSheetState extends ConsumerState<_ActivationCodeSheet> {
  final _controller = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    final code = _controller.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'اكتب الكود الأول');
      return;
    }
    HapticFeedback.lightImpact();
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _error = null;
    });
    final result = await ref.read(redeemActivationCodeUseCaseProvider)(code);
    if (!mounted) return;
    switch (result) {
      case Ok<String>(:final value):
        showAppSnack(context, value);
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_pendingKey(widget.subjectId));
        if (!mounted) return;
        invalidateAfterActivation(ref);
        ref.invalidate(subjectSubscriptionProvider(widget.subjectId));
        Navigator.of(context).pop();
      case Err<String>(:final failure):
        setState(() {
          _submitting = false;
          _error = failure.message;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(12);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          autofocus: true,
          enabled: !_submitting,
          textInputAction: TextInputAction.done,
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
          autocorrect: false,
          onSubmitted: (_) => _activate(),
          decoration: InputDecoration(
            hintText: 'الكود',
            errorText: _error,
            errorMaxLines: 3,
            border: OutlineInputBorder(borderRadius: radius),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        FilledButton(
          onPressed: _submitting ? null : _activate,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(borderRadius: radius),
          ),
          child: _submitting
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('تفعيل'),
        ),
      ],
    );
  }
}
