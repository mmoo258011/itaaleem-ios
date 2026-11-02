import 'dart:async';

import 'package:itaaleem/core/widgets/app_button.dart';
import 'package:itaaleem/core/widgets/app_toast.dart';
import 'package:itaaleem/features/auth/presentation/providers/auth_controller.dart';
import 'package:itaaleem/features/center/domain/entities/center_model.dart';
import 'package:itaaleem/features/center/presentation/providers/center_providers.dart';
import 'package:itaaleem/features/center/presentation/screens/center_profile_screen.dart';
import 'package:itaaleem/features/center/presentation/widgets/center_no_courses_state.dart';
import 'package:itaaleem/features/grade_change/grade_change_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:itaaleem/core/design/design.dart';
import 'package:itaaleem/core/widgets/app_shimmer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:itaaleem/core/theme/app_palette.dart';
import 'package:itaaleem/core/theme/app_radius.dart';
import 'package:itaaleem/core/theme/app_spacing.dart';

/// Confirming here calls [CenterMembershipController.join] — which sets
/// [centerMembershipProvider]'s state directly from the successful `/join`
/// response — then navigates back to `/home` itself and shows a success
/// toast; [HomeScreen] picks up the now-joined membership and renders the
/// branded home. The whole call is wrapped so a slow or failing network
/// call always resets the button's loading state instead of spinning
/// forever, with a 10s timeout as a hard backstop.
///
/// Doubles as the account screen's "تغيير الكورس": pushed with the same
/// `centerId` the student already joined, it preselects their current
/// grade and `join()` below is a plain upsert, so re-confirming just
/// updates the grade instead of failing or duplicating the membership.
class SelectGradeScreen extends ConsumerStatefulWidget {
  const SelectGradeScreen({super.key, required this.centerId, this.preview});

  final int centerId;

  /// The center as already fetched by the search/profile screens (with
  /// `grades` included) — used immediately instead of waiting on another
  /// `GET /centers/{id}` round trip, and as a fallback if that fetch fails.
  final CenterModel? preview;

  @override
  ConsumerState<SelectGradeScreen> createState() => _SelectGradeScreenState();
}

class _SelectGradeScreenState extends ConsumerState<SelectGradeScreen> {
  int? _selectedGradeId;
  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    final membership = ref.read(centerMembershipProvider).valueOrNull;
    if (membership != null && membership.centerId == widget.centerId) {
      _selectedGradeId = membership.gradeId;
    }
  }

  Future<void> _confirm() async {
    final gradeId = _selectedGradeId;
    if (gradeId == null || _confirming) return;
    setState(() => _confirming = true);

    final center =
        ref.read(centerByIdProvider(widget.centerId)) ?? widget.preview;

    if (center == null) {
      setState(() => _confirming = false);
      AppToast.showError(context, 'تعذر تحميل بيانات السنتر، حاول مرة أخرى');
      return;
    }

    try {
      final (:failure, :result) = await ref
          .read(centerMembershipProvider.notifier)
          .join(
            centerId: widget.centerId,
            centerCode: center.code,
            gradeId: gradeId,
          )
          .timeout(const Duration(seconds: 10));
      if (kDebugMode) {
        debugPrint(
          'Join response: ${failure == null ? 'success' : 'failed — ${failure.message}'} '
          '(centerId=${widget.centerId}, gradeId=$gradeId)',
        );
      }
      if (!mounted) return;

      if (failure != null) {
        setState(() => _confirming = false);
        AppToast.showError(context, failure.message);
        return;
      }

      setState(() => _confirming = false);
      if (!goHomeAfterJoin(context, ref, result)) {
        AppToast.showSuccess(context, 'تم الانضمام لـ ${center.name} بنجاح 🎉');
      }

      // Best-effort, fired after navigating away and never awaited: keeps
      // the student's own profile (`authControllerProvider`) in sync with
      // the new center/grade for the handful of reads that go through it
      // directly instead of [centerMembershipProvider] (e.g. offline
      // license checks). [CenterMembershipController.build] already falls
      // back to the membership `join()` just set if this response hasn't
      // caught up yet, so a slow/stale/failing refresh here can't bounce
      // the student back to the join-by-code screen.
      final isDemo =
          ref.read(authControllerProvider).valueOrNull?.isDemo ?? false;
      if (!isDemo) {
        unawaited(
          ref
              .read(authControllerProvider.notifier)
              .refreshProfile()
              .then((_) {
                if (kDebugMode) debugPrint('Profile refresh result: ok');
              })
              .catchError((Object e) {
                if (kDebugMode) {
                  debugPrint('Profile refresh result: failed — $e');
                }
              }),
        );
      }
    } on TimeoutException {
      if (kDebugMode) debugPrint('Join response: timed out');
      if (!mounted) return;
      setState(() => _confirming = false);
      AppToast.showError(
        context,
        'استغرق الانضمام وقتاً طويلاً، حاول مرة أخرى',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('Join response: error — $e');
      if (!mounted) return;
      setState(() => _confirming = false);
      AppToast.showError(context, 'حدث خطأ أثناء الانضمام، حاول مرة أخرى');
    }
  }

  @override
  Widget build(BuildContext context) {
    final center =
        ref.watch(centerByIdProvider(widget.centerId)) ?? widget.preview;

    if (center == null) {
      final fetchError = ref.watch(centerFetchErrorProvider(widget.centerId));
      if (fetchError != null) {
        // A 403 here means the server won't return this center's grades
        // until the student has already joined it — a permanent policy,
        // not a transient failure, so "إعادة المحاولة" would just fail
        // again the same way. Anything else (network blip, 5xx) is
        // genuinely worth retrying.
        final isForbidden =
            fetchError is DioException &&
            fetchError.response?.statusCode == 403;
        return Scaffold(
          appBar: AppBar(title: const Text('اختار الكورس')),
          body: AppBackground(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isForbidden
                          ? Icons.lock_outline_rounded
                          : Icons.wifi_off_rounded,
                      size: 40,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      isForbidden
                          ? 'مش متاح عرض فرق السنتر ده قبل الانضمام'
                          : 'تعذر تحميل بيانات السنتر',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (isForbidden) ...[
                      const SizedBox(height: 6),
                      Text(
                        'تواصل مع السنتر لمعرفة الكورس الصحيح، أو جرب لاحقاً',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 13,
                          color: context.palette.textSecondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.base),
                    AppButton.primary(
                      'إعادة المحاولة',
                      onPressed: () => retryCenterFetch(ref, widget.centerId),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }
      return const Scaffold(
        body: AppBackground(
          child: SafeArea(child: ShimmerDetail(heroHeight: 140, cards: 4)),
        ),
      );
    }

    final grades = [...center.grades]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    if (grades.isEmpty) {
      final alreadyMember =
          ref.watch(centerMembershipProvider).valueOrNull?.centerId ==
          widget.centerId;
      return Scaffold(
        appBar: AppBar(title: const Text('اختار الكورس')),
        body: AppBackground(
          child: RefreshIndicator(
            onRefresh: () async => refreshCenter(ref, widget.centerId),
            child: LayoutBuilder(
              builder: (context, c) => SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: c.maxHeight),
                  child: Center(
                    child: CenterNoCoursesState(
                      center: alreadyMember ? null : center,
                      showBack: true,
                      // The API accepts a join with no grade — let the
                      // student in now; home shows the same notice.
                      extraAction: alreadyMember
                          ? null
                          : JoinCenterButton(center: center),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('اختار الكورس')),
      body: AppBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                    children: [
                      const TextSpan(text: 'أنت بتنضم لـ '),
                      TextSpan(
                        text: center.name,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: context.palette.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'اختار الكورس والقسم',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.palette.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                Expanded(
                  child: ListView.builder(
                    itemCount: grades.length,
                    itemBuilder: (context, index) {
                      final grade = grades[index];
                      return _GradeTile(
                        grade: grade,
                        selected: grade.id == _selectedGradeId,
                        onTap: () =>
                            setState(() => _selectedGradeId = grade.id),
                      );
                    },
                  ),
                ),
                AppButton.primary(
                  'تأكيد الانضمام',
                  onPressed: (_selectedGradeId == null || _confirming)
                      ? null
                      : _confirm,
                  loading: _confirming,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GradeTile extends StatelessWidget {
  const _GradeTile({
    required this.grade,
    required this.selected,
    required this.onTap,
  });

  final GradeModel grade;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(AppRadius.lg);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: LinearGradient(
            begin: AlignmentDirectional.topStart,
            end: AlignmentDirectional.bottomEnd,
            colors: [
              scheme.primary.withValues(alpha: selected ? 0.16 : 0.06),
              scheme.surface,
            ],
          ),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outline,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          splashColor: scheme.primary.withValues(alpha: 0.12),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.school_rounded, color: scheme.primary),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    grade.name,
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: selected ? scheme.primary : scheme.onSurface,
                    ),
                  ),
                ),
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
