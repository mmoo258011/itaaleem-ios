import 'package:cached_network_image/cached_network_image.dart';
import 'package:itaaleem/core/widgets/error_view.dart';
import 'package:itaaleem/features/courses/domain/entities/course_details.dart';
import 'package:itaaleem/features/courses/presentation/providers/courses_providers.dart';
import 'package:itaaleem/features/courses/presentation/widgets/course_details_shimmer.dart';
import 'package:itaaleem/features/courses/presentation/widgets/course_progress_bar.dart';
import 'package:itaaleem/features/courses/presentation/widgets/course_section_card.dart';
import 'package:itaaleem/features/certificates/certificates.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:itaaleem/core/theme/app_palette.dart';
import 'package:itaaleem/core/theme/app_radius.dart';
import 'package:itaaleem/core/theme/app_spacing.dart';

/// `GET /courses/{id}`: cover image header, progress summary, and the list
/// of sections ("مواد") — tapping one opens `SectionLessonsScreen` (that
/// section's teachers, then lectures), the same "مادة" flow the home tab's
/// subject cards use.
class CourseDetailsScreen extends ConsumerWidget {
  const CourseDetailsScreen({super.key, required this.courseId});

  final int courseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailsAsync = ref.watch(courseDetailsProvider(courseId));

    return Scaffold(
      body: detailsAsync.when(
        loading: () => CustomScrollView(
          slivers: [
            _buildSliverAppBar(context, title: '', imageUrl: null),
            const SliverToBoxAdapter(child: CourseDetailsShimmer()),
          ],
        ),
        error: (error, stackTrace) => CustomScrollView(
          slivers: [
            _buildSliverAppBar(context, title: '', imageUrl: null),
            SliverFillRemaining(
              child: ErrorView(
                message: 'تعذر تحميل تفاصيل الكورس، حاول مرة أخرى',
                retryLabel: 'إعادة المحاولة',
                onRetry: () => ref.invalidate(courseDetailsProvider(courseId)),
              ),
            ),
          ],
        ),
        data: (details) => CustomScrollView(
          slivers: [
            _buildSliverAppBar(
              context,
              title: details.title,
              imageUrl: details.imageUrl,
            ),
            SliverToBoxAdapter(
              child: _DetailsBody(
                details: details,
                onSectionTap: (section) =>
                    context.push('/courses/$courseId/sections/${section.id}'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSliverAppBar(
    BuildContext context, {
    required String title,
    required String? imageUrl,
  }) {
    return SliverAppBar(
      pinned: true,
      expandedHeight: 220,
      backgroundColor: context.palette.primary,
      foregroundColor: context.palette.onPrimary,
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            if (imageUrl != null && imageUrl.isNotEmpty)
              CachedNetworkImage(
                imageUrl: imageUrl,
                memCacheWidth:
                    (MediaQuery.sizeOf(context).width *
                            MediaQuery.devicePixelRatioOf(context))
                        .round(),
                fit: BoxFit.cover,
                placeholder: (context, url) => DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: context.palette.brandGradient,
                  ),
                ),
                errorWidget: (context, url, error) => DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: context.palette.brandGradient,
                  ),
                ),
              )
            else
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: context.palette.brandGradient,
                ),
              ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.1),
                    Colors.black.withValues(alpha: 0.55),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailsBody extends ConsumerWidget {
  const _DetailsBody({required this.details, required this.onSectionTap});

  final CourseDetails details;
  final void Function(CourseSection section) onSectionTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final progressPercent = details.progressPercent;

    return Padding(
      padding: const EdgeInsetsDirectional.all(AppSpacing.screenHorizontal),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            details.title,
            style: textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          if (details.description?.isNotEmpty ?? false) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              details.description!,
              style: textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
          ],
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsetsDirectional.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      'نسبة إنجازك',
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${progressPercent.round()}٪',
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                CourseProgressBar(percent: progressPercent, height: 10),
                if (progressPercent >= 100) ...[
                  const SizedBox(height: 14),
                  _CertificateButton(courseId: details.id),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'محتوى الكورس',
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.md),
          if (details.sections.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Center(
                child: Text(
                  'لا توجد مواد مضافة بعد',
                  style: textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ),
            )
          else
            for (var i = 0; i < details.sections.length; i++)
              CourseSectionCard(
                title: details.sections[i].title,
                lectures: details.sections[i].lectures,
                index: i,
                onTap: () => onSectionTap(details.sections[i]),
              ),
          if (details.exams.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xl),
            Text(
              'الامتحانات المتاحة',
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            for (final exam in details.exams)
              _ExamTile(
                exam: exam,
                onTap: () => context.push('/exams/${exam.id}'),
              ),
          ],
        ],
      ),
    );
  }
}

/// A single exam row — opens [ExamDetailsScreen] (`GET /exams/{id}`), which
/// itself owns the "بدء الامتحان" action and the rest of the attempt flow.
class _ExamTile extends StatelessWidget {
  const _ExamTile({required this.exam, required this.onTap});

  final CourseExam exam;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final metaParts = [
      if (exam.questionsCount != null) '${exam.questionsCount} سؤال',
      if (exam.durationMinutes != null) '${exam.durationMinutes} دقيقة',
    ];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.1)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            onTap: onTap,
            contentPadding: const EdgeInsetsDirectional.symmetric(
              horizontal: AppSpacing.base,
              vertical: 6,
            ),
            leading: CircleAvatar(
              radius: 20,
              backgroundColor: context.palette.primary.withValues(alpha: 0.12),
              child: Icon(Icons.quiz_rounded, color: context.palette.primary),
            ),
            title: Text(
              exam.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: metaParts.isEmpty
                ? null
                : Text(
                    metaParts.join(' • '),
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
            trailing: const Icon(Icons.chevron_left_rounded),
          ),
          if (exam.attempted)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 14),
              child: _ExamAttemptedBadge(
                passed: exam.passed,
                score: exam.score,
              ),
            ),
        ],
      ),
    );
  }
}

/// Shown under an exam tile once `GET /courses/{id}/exams` reports
/// `attempted: true` — the server's authoritative attempt status, in place
/// of guessing from local state.
class _ExamAttemptedBadge extends StatelessWidget {
  const _ExamAttemptedBadge({required this.passed, required this.score});

  final bool? passed;
  final double? score;

  @override
  Widget build(BuildContext context) {
    final ok = passed ?? true;
    final color = ok
        ? context.palette.success
        : Theme.of(context).colorScheme.error;
    final label = score != null
        ? 'تم الامتحان • الدرجة ${score!.round()}٪'
        : 'تم الامتحان';

    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        padding: const EdgeInsetsDirectional.symmetric(
          horizontal: 10,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
              size: 16,
              color: color,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "تحميل الشهادة" — only rendered once [CourseDetails.progressPercent]
/// hits 100. Opens "شهاداتي" (`GET /certificates`).
class _CertificateButton extends ConsumerStatefulWidget {
  const _CertificateButton({required this.courseId});

  final int courseId;

  @override
  ConsumerState<_CertificateButton> createState() => _CertificateButtonState();
}

class _CertificateButtonState extends ConsumerState<_CertificateButton> {
  bool _downloading = false;

  Future<void> _download() async {
    if (_downloading) return;
    setState(() => _downloading = true);

    try {
      // `GET /certificates` (our API) — the old per-course
      // `/api/student/courses/{id}/certificate` doesn't exist here.
      await showCertificatesSheet(context, ref);
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: _downloading ? null : _download,
      icon: _downloading
          ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: context.palette.onPrimary,
              ),
            )
          : const Icon(Icons.workspace_premium_rounded),
      label: Text(_downloading ? '...جاري التحميل' : 'تحميل الشهادة'),
      style: FilledButton.styleFrom(
        backgroundColor: context.palette.primary,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
      ),
    );
  }
}
