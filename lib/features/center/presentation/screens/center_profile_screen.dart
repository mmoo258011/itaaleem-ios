import 'dart:async';

import 'package:itaaleem/core/widgets/app_button.dart';
import 'package:itaaleem/core/widgets/app_toast.dart';
import 'package:itaaleem/core/widgets/rating_chip.dart';
import 'package:itaaleem/core/widgets/section_header.dart';
import 'package:itaaleem/core/theme/app_radius.dart';
import 'package:itaaleem/core/theme/app_spacing.dart';
import 'package:itaaleem/features/center/domain/entities/center_model.dart';
import 'package:itaaleem/features/center/presentation/providers/center_providers.dart';
import 'package:itaaleem/features/center/presentation/utils/center_color.dart';
import 'package:itaaleem/features/center/presentation/widgets/social_links_bar.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:itaaleem/core/design/design.dart';
import 'package:itaaleem/core/widgets/app_shimmer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:itaaleem/features/grade_change/grade_change_screen.dart';
import 'package:itaaleem/core/utils/safe_url.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:itaaleem/core/theme/app_palette.dart';

/// The live `GET /centers/{id}` (behind [centerByIdProvider]) 403s with
/// "غير مصرح لك بعرض بيانات السنتر ده" for a center the student hasn't
/// joined yet — i.e. always, on this screen, which only exists to join one.
/// [preview] (the already-fetched `GET /centers?code=` search result) is
/// what's actually rendered here; the detail fetch is still attempted in
/// the background purely to pick up richer data (phones, socials, grades,
/// rating) for a center this student happens to already have access to
/// (e.g. re-opened from a state where membership changed), but its absence
/// or failure never blocks this screen.
class CenterProfileScreen extends ConsumerWidget {
  const CenterProfileScreen({super.key, required this.centerId, this.preview});

  final int centerId;
  final CenterModel? preview;

  Future<void> _open(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    final launched =
        uri != null &&
        await launchUrlSafely(
          uri,
          mode: uri.scheme == 'tel'
              ? LaunchMode.platformDefault
              : LaunchMode.externalApplication,
        );
    if (!launched && context.mounted) {
      AppToast.showError(context, 'تعذر فتح الرابط');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final center = ref.watch(centerByIdProvider(centerId)) ?? preview;

    if (center == null) {
      final fetchError = ref.watch(centerFetchErrorProvider(centerId));
      if (fetchError != null) {
        return Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.wifi_off_rounded,
                    size: 40,
                    color: context.palette.error,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  const Text(
                    'تعذر تحميل بيانات السنتر',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.base),
                  AppButton.primary(
                    'إعادة المحاولة',
                    onPressed: () => retryCenterFetch(ref, centerId),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      // Still loading `GET /centers/{id}`.
      return const Scaffold(body: SafeArea(child: ShimmerDetail()));
    }

    final color = parseCenterColor(center.primaryColor);
    if (kDebugMode) {
      debugPrint('>>> CENTER logo: ${center.logo}, cover: ${center.cover}');
    }
    final coverFallback = DecoratedBox(
      decoration: BoxDecoration(gradient: context.palette.brandGradient),
    );
    final initialWidget = Center(
      child: Text(
        center.initial,
        style: TextStyle(
          fontFamily: 'Cairo',
          fontSize: 32,
          fontWeight: FontWeight.w800,
          color: context.palette.onPrimary,
        ),
      ),
    );

    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    var revealIndex = 0;
    Widget reveal(Widget child) => Reveal(index: revealIndex++, child: child);

    return Scaffold(
      body: AppBackground(
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              expandedHeight: 220,
              pinned: true,
              stretch: true,
              backgroundColor: scheme.primary,
              foregroundColor: scheme.onPrimary,
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (center.cover == null || center.cover!.isEmpty)
                      coverFallback
                    else
                      CachedNetworkImage(
                        imageUrl: center.cover!,
                        memCacheWidth:
                            (MediaQuery.sizeOf(context).width *
                                    MediaQuery.devicePixelRatioOf(context))
                                .round(),
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.high,
                        placeholder: (context, url) => coverFallback,
                        errorWidget: (context, url, error) => coverFallback,
                      ),
                    // Scrims so the back button and the logo read cleanly.
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            scheme.scrim.withValues(alpha: 0.25),
                            Colors.transparent,
                            scheme.scrim.withValues(alpha: 0.3),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Transform.translate(
                    offset: const Offset(0, -56),
                    child: Hero(
                      tag: 'center-logo-${center.id}',
                      child: Container(
                        width: 112,
                        height: 112,
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: DesignTokens.brandGradient(scheme),
                          boxShadow: DesignTokens.softShadow(
                            scheme,
                            strength: 1.6,
                          ),
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(color: scheme.surface, width: 3),
                          ),
                          child: ClipOval(
                            child: (center.logo == null || center.logo!.isEmpty)
                                ? initialWidget
                                : CachedNetworkImage(
                                    imageUrl: center.logo!,
                                    memCacheWidth: 400,
                                    fit: BoxFit.cover,
                                    filterQuality: FilterQuality.high,
                                    placeholder: (context, url) =>
                                        initialWidget,
                                    errorWidget: (context, url, error) =>
                                        initialWidget,
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Transform.translate(
                    offset: const Offset(0, -40),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          reveal(
                            Text(
                              center.name,
                              textAlign: TextAlign.center,
                              style: text.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          reveal(
                            Center(
                              child: StatusPill(
                                label: 'كود الانضمام: ${center.code}',
                                icon: Icons.qr_code_2_rounded,
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.base),
                          reveal(
                            Row(
                              children: [
                                Expanded(
                                  child: StatTile(
                                    icon: Icons.groups_rounded,
                                    value: center.studentsCount,
                                    label: 'طالب',
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.md),
                                Expanded(
                                  child: _RatingTile(rating: center.rating),
                                ),
                                if (center.grades.isNotEmpty) ...[
                                  const SizedBox(width: AppSpacing.md),
                                  Expanded(
                                    child: StatTile(
                                      icon: Icons.school_rounded,
                                      value: center.grades.length,
                                      label: 'كورس',
                                      color: scheme.secondary,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (center.description != null) ...[
                            const SizedBox(height: AppSpacing.base),
                            reveal(
                              GlassCard(
                                child: Text(
                                  center.description!,
                                  textAlign: TextAlign.center,
                                  style: text.bodyMedium?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                    height: 1.7,
                                  ),
                                ),
                              ),
                            ),
                          ],
                          if (center.phoneNumbers.isNotEmpty ||
                              center.socialLinks.isNotEmpty) ...[
                            const SectionHeader(title: 'التواصل'),
                            for (final phone in center.phoneNumbers)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: reveal(
                                  _PhoneTile(
                                    phone: phone,
                                    onTap: () => _open(context, 'tel:$phone'),
                                  ),
                                ),
                              ),
                            if (center.socialLinks.isNotEmpty) ...[
                              const SizedBox(height: AppSpacing.sm),
                              reveal(
                                SocialLinksBar(
                                  socialLinks: center.socialLinks,
                                  title: null,
                                ),
                              ),
                            ],
                          ],
                          if (center.grades.isNotEmpty) ...[
                            const SectionHeader(title: 'الكورسات'),
                            for (final grade in center.grades)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: reveal(_GradeCard(name: grade.name)),
                              ),
                          ],
                          const SizedBox(height: AppSpacing.xl),
                          JoinCenterButton(center: center),
                          const SizedBox(height: AppSpacing.lg),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GradeCard extends StatelessWidget {
  const _GradeCard({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.base,
        vertical: 14,
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: DesignTokens.brandGradient(scheme),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.school_rounded,
              size: 20,
              color: scheme.onPrimary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _RatingTile extends StatelessWidget {
  const _RatingTile({required this.rating});

  final double rating;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: DesignTokens.cardBorder(scheme)),
        boxShadow: DesignTokens.softShadow(scheme, strength: 0.6),
      ),
      child: Column(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: scheme.tertiary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.star_rounded, size: 20, color: scheme.tertiary),
          ),
          const SizedBox(height: 8),
          RatingChip(rating: rating, size: 18),
          const SizedBox(height: 2),
          Text(
            'التقييم',
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// If [center] has grades to choose from, pushes [SelectGradeScreen];
/// otherwise joins directly with no `grade_id`, same as the pre-grades
/// join flow, with its own loading state and error toast.
class JoinCenterButton extends ConsumerStatefulWidget {
  const JoinCenterButton({super.key, required this.center});

  final CenterModel center;

  @override
  ConsumerState<JoinCenterButton> createState() => JoinCenterButtonState();
}

class JoinCenterButtonState extends ConsumerState<JoinCenterButton> {
  bool _joining = false;

  Future<void> _joinDirectly() async {
    if (_joining) return;
    setState(() => _joining = true);

    try {
      final (:failure, :result) = await ref
          .read(centerMembershipProvider.notifier)
          .join(centerId: widget.center.id, centerCode: widget.center.code)
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;

      if (failure != null) {
        setState(() => _joining = false);
        AppToast.showError(context, failure.message);
        return;
      }

      setState(() => _joining = false);
      if (!goHomeAfterJoin(context, ref, result)) {
        AppToast.showSuccess(
          context,
          'تم الانضمام لـ ${widget.center.name} بنجاح 🎉',
        );
      }
    } on TimeoutException {
      if (!mounted) return;
      setState(() => _joining = false);
      AppToast.showError(
        context,
        'استغرق الانضمام وقتاً طويلاً، حاول مرة أخرى',
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _joining = false);
      AppToast.showError(context, 'حدث خطأ أثناء الانضمام، حاول مرة أخرى');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppButton.primary(
      'انضم لهذا السنتر',
      loading: _joining,
      onPressed: _joining
          ? null
          : widget.center.grades.isNotEmpty
          ? () => context.push(
              '/select-grade/${widget.center.id}',
              extra: widget.center,
            )
          : _joinDirectly,
    );
  }
}

class _PhoneTile extends StatelessWidget {
  const _PhoneTile({required this.phone, required this.onTap});

  final String phone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Radius and border both come from `shape`; passing `borderRadius`
    // alongside it trips Material's assertion.
    return GlassCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: context.palette.success.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Icon(
                Icons.call_rounded,
                size: 20,
                color: context.palette.success,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                phone,
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(
              Icons.chevron_left_rounded,
              color: context.palette.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}
