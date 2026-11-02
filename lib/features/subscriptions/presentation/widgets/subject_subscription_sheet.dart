import 'package:flutter/material.dart';
import 'package:itaaleem/features/subscriptions/presentation/widgets/contact_center_access_sheet.dart';
import 'package:itaaleem/core/utils/platform_utils.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:itaaleem/core/theme/app_spacing.dart';
import 'package:itaaleem/core/widgets/app_toast.dart';
import 'package:itaaleem/features/subscriptions/data/models/subject_subscription_model.dart';
import 'package:itaaleem/features/subscriptions/presentation/providers/subscription_providers.dart';

/// "هذه المادة تحتاج اشتراك" sheet for a locked subject: the price (when the
/// center set one) and a "طلب اشتراك" button that notifies the center —
/// activation itself is done by an admin from the dashboard.
Future<void> showSubjectSubscriptionSheet(
  BuildContext context, {
  required int subjectId,
  required String subjectName,
  required SubjectSubscriptionStatus status,
}) {
  // iOS: no subscribe / renew — how to get access instead.
  if (PlatformUtils.hideSubscriptions) {
    return showContactCenterAccessSheet(
      context,
      message: lockedSubjectMessage,
      showActivate: true,
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _SubjectSubscriptionSheet(
      subjectId: subjectId,
      subjectName: subjectName,
      status: status,
    ),
  );
}

class _SubjectSubscriptionSheet extends ConsumerStatefulWidget {
  const _SubjectSubscriptionSheet({
    required this.subjectId,
    required this.subjectName,
    required this.status,
  });

  final int subjectId;
  final String subjectName;
  final SubjectSubscriptionStatus status;

  @override
  ConsumerState<_SubjectSubscriptionSheet> createState() =>
      _SubjectSubscriptionSheetState();
}

class _SubjectSubscriptionSheetState
    extends ConsumerState<_SubjectSubscriptionSheet> {
  bool _sending = false;

  Future<void> _request() async {
    final navigator = Navigator.of(context);
    final repo = ref.read(subscriptionRepositoryProvider);
    setState(() => _sending = true);
    var sent = false;
    try {
      await repo.requestSubscription(widget.subjectId);
      sent = true;
    } catch (_) {
      // Shown below as "contact the center" — the request is a convenience.
    }
    if (!mounted) return;
    final messageContext = navigator.context;
    if (navigator.canPop()) navigator.pop();
    if (!messageContext.mounted) return;
    if (sent) {
      AppToast.showSuccess(
        messageContext,
        'تم إرسال طلب الاشتراك — سيتم التفعيل من الإدارة',
      );
    } else {
      AppToast.showError(messageContext, 'تواصل مع الإدارة لتفعيل الاشتراك');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final price = widget.status.price;
    final expired = widget.status.subscription?.isExpired ?? false;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          0,
          AppSpacing.xl,
          AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.lock_outline_rounded,
                size: 32,
                color: cs.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: AppSpacing.base),
            Text(
              widget.subjectName,
              textAlign: TextAlign.center,
              style: text.titleLarge,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              expired
                  ? 'انتهى اشتراكك في هذه المادة — جدّده للوصول إلى محتواها'
                  : 'هذه المادة تحتاج اشتراك للوصول إلى محتواها',
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            if (price != null) ...[
              const SizedBox(height: AppSpacing.base),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: cs.tertiaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${price.toStringAsFixed(price.truncateToDouble() == price ? 0 : 2)} جنيه',
                  style: text.headlineSmall?.copyWith(
                    color: cs.onTertiaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _sending ? null : _request,
                icon: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded, size: 20),
                label: const Text('طلب اشتراك'),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'أو تواصل مع إدارة المركز لتفعيل اشتراكك',
              textAlign: TextAlign.center,
              style: text.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
