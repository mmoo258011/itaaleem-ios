import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:itaaleem/core/theme/app_spacing.dart';
import 'package:itaaleem/core/widgets/app_card.dart';
import 'package:itaaleem/core/widgets/app_error_state.dart';
import 'package:itaaleem/core/widgets/app_progress_bar.dart';
import 'package:itaaleem/core/widgets/app_toast.dart';
import 'package:itaaleem/features/parent/data/parent_api.dart';
import 'package:itaaleem/features/parent/data/parent_models.dart';
import 'package:itaaleem/features/parent/presentation/guardian_controller.dart';
import 'package:itaaleem/features/parent/presentation/screens/parent_home_screen.dart';
import 'package:itaaleem/features/parent/presentation/widgets/parent_format.dart';

/// One child (`GET /parent/children/{id}`): last sign-in, per-subject
/// progress, recently watched lectures and exam results. Read-only — no
/// item here opens anything.
class ParentChildScreen extends ConsumerWidget {
  const ParentChildScreen({super.key, required this.childId});

  final int childId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final async = ref.watch(guardianChildDetailsProvider(childId));

    // Unlinked / not followable any more → back to the children list.
    ref.listen(guardianChildDetailsProvider(childId), (_, next) {
      final error = next.error;
      if (error == null) return;
      final e = ParentApiException.from(error);
      if (!e.isNotFound) return;
      AppToast.showError(context, e.displayMessage);
      ref.invalidate(guardianChildrenProvider);
      context.go(parentHomePath);
    });

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: Text(
          async.valueOrNull?.child.name ?? 'متابعة الطالب',
          style: const TextStyle(
            fontFamily: 'Cairo',
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(guardianChildDetailsProvider(childId));
          try {
            await ref.read(guardianChildDetailsProvider(childId).future);
          } catch (_) {}
        },
        child: async.when(
          skipLoadingOnRefresh: true,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => LayoutBuilder(
            builder: (context, c) => SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: SizedBox(
                height: c.maxHeight,
                child: AppErrorState(
                  message: ParentApiException.from(error).displayMessage,
                  onRetry: () =>
                      ref.invalidate(guardianChildDetailsProvider(childId)),
                ),
              ),
            ),
          ),
          data: (details) => _Details(details: details),
        ),
      ),
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({required this.details});

  final ChildDetails details;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final child = details.child;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        AppCard(
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: scheme.primaryContainer,
                child: Icon(
                  Icons.school_rounded,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      child.name,
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (child.course.isNotEmpty)
                      Text(
                        child.course,
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    if (child.center.isNotEmpty)
                      Text(
                        child.center,
                        style: text.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      children: [
                        Icon(
                          Icons.access_time_rounded,
                          size: 16,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            'آخر دخول: ${formatLastLogin(child.lastLoginAt)}',
                            style: text.labelMedium?.copyWith(
                              color: scheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const _SectionTitle(icon: Icons.menu_book_rounded, title: 'المواد'),
        if (details.subjects.isEmpty)
          const _EmptyLine('لا توجد مواد حالياً')
        else
          for (final s in details.subjects) _SubjectProgressCard(subject: s),
        const _SectionTitle(
          icon: Icons.play_circle_outline_rounded,
          title: 'آخر المحاضرات',
        ),
        if (details.recentLectures.isEmpty)
          const _EmptyLine('لم يشاهد أي محاضرة بعد')
        else
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final (i, l) in details.recentLectures.indexed) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    leading: Icon(
                      Icons.ondemand_video_rounded,
                      color: scheme.primary,
                    ),
                    title: Text(
                      l.lecture,
                      style: text.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      '${l.subject} • ${formatParentDate(l.watchedAt)}',
                      style: text.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        const _SectionTitle(
          icon: Icons.quiz_outlined,
          title: 'نتائج الامتحانات',
        ),
        if (details.examResults.isEmpty)
          const _EmptyLine('لا توجد نتائج امتحانات بعد')
        else
          for (final r in details.examResults) _ExamResultCard(result: r),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl, bottom: AppSpacing.sm),
      child: Row(
        children: [
          Icon(icon, color: scheme.primary, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _SubjectProgressCard extends StatelessWidget {
  const _SubjectProgressCard({required this.subject});

  final ChildSubjectProgress subject;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final pct = subject.progressPercentage.clamp(0, 100).toDouble();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    subject.name,
                    style: text.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '${formatNumber(pct)}%',
                  style: text.labelLarge?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            AppProgressBar(progress: pct / 100, height: 6),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'خلّص ${subject.completedLectures} من ${subject.lecturesCount} محاضرة',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExamResultCard extends StatelessWidget {
  const _ExamResultCard({required this.result});

  final ChildExamResult result;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final pct = result.percentage.clamp(0, 100).toDouble();
    final color = pct >= 50 ? scheme.primary : scheme.error;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.exam,
                    style: text.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    result.subject,
                    style: text.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'الدرجة: ${formatNumber(result.score)} من ${formatNumber(result.total)}',
                    style: text.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    formatParentDate(result.date),
                    style: text.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${formatNumber(pct)}%',
                style: text.titleMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
