import 'package:itaaleem/features/subjects/presentation/widgets/locked_lecture_access.dart';
import 'package:itaaleem/features/app_config/app_config_providers.dart'
    show serverText;
import 'package:itaaleem/core/content/content_policy.dart';
import 'package:itaaleem/features/home/presentation/providers/content_refresh.dart';
import 'package:itaaleem/app/router/app_router.dart';
import 'package:itaaleem/app/router/route_args.dart';
import 'package:itaaleem/core/error/failure.dart';
import 'package:itaaleem/core/theme/app_radius.dart';
import 'package:itaaleem/core/widgets/app_card.dart';
import 'package:itaaleem/core/widgets/error_view.dart';
import 'package:itaaleem/features/exams/presentation/widgets/lecture_exams_section.dart';
import 'package:itaaleem/features/subjects/domain/entities/subject.dart';
import 'package:itaaleem/features/subjects/presentation/providers/subjects_providers.dart';
import 'package:itaaleem/features/subjects/presentation/screens/lesson_video_screen.dart';
import 'package:itaaleem/features/subjects/presentation/utils/pdf_download.dart';
import 'package:itaaleem/features/subjects/presentation/widgets/lesson_access.dart';
import 'package:itaaleem/features/video/presentation/widgets/lecture_download_button.dart';
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:itaaleem/features/subjects/presentation/utils/protected_file_open.dart';
import 'package:itaaleem/core/design/design.dart';
import 'package:itaaleem/features/subscriptions/presentation/widgets/contact_center_access_sheet.dart';
import 'package:itaaleem/core/utils/platform_utils.dart';
import 'package:itaaleem/core/utils/youtube_utils.dart';
import 'package:itaaleem/features/courses/presentation/widgets/players/player_selection_sheet.dart';
import 'package:itaaleem/core/widgets/app_shimmer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:itaaleem/core/theme/app_palette.dart';
import 'package:itaaleem/core/theme/app_spacing.dart';

// Category accents — from the active theme so they follow the center color
// (attachments) and dark mode (the semantic ones).
Color _attachmentColor(BuildContext context) =>
    Theme.of(context).colorScheme.secondary;
Color _examColor(BuildContext context) => context.palette.info;
Color _questionColor(BuildContext context) => context.palette.success;

/// `/lessons/:id`'s `state.extra` payload — [AppRouter] has no other way to
/// carry the already-loaded [SubjectLesson]/[SubjectExam]s across the push
/// (there's no standalone `GET /lessons/{id}` this screen relies on; it
/// reuses what [SubjectDetailScreen] already fetched).
class LessonDetailNavArgs {
  const LessonDetailNavArgs({
    required this.lesson,
    required this.subjectId,
    this.subjectExams = const [],
  });

  final SubjectLesson lesson;
  final int subjectId;
  final List<SubjectExam> subjectExams;
}

/// One lecture's full detail — video, attachments, exams, homework and
/// "ask a question", replacing the old bottom-sheet-only actions
/// ([SubjectDetailScreen]'s previous `_openLesson`). [subjectId] and
/// [subjectExams] ride along from the subject the lesson was opened from,
/// since there's no per-lecture attachments/exams endpoint — only the
/// subject-scoped `GET /attachments?subject_id=` and the subject's already
/// -loaded `exams` array.
class LessonDetailScreen extends ConsumerWidget {
  const LessonDetailScreen({
    super.key,
    required this.lesson,
    required this.subjectId,
    this.subjectExams = const [],
  });

  final SubjectLesson lesson;
  final int subjectId;
  final List<SubjectExam> subjectExams;

  Future<void> _openVideo(
    BuildContext context,
    WidgetRef ref,
    SubjectLesson lesson, {
    required bool locked,
  }) async {
    if (locked) {
      // Activation lives on the subject's page — go back and open it.
      openSubjectActivation(context, ref, subjectId);
      return;
    }
    // `has_video: true` but no usable `video_url`: treat as a lesson without
    // video — never push a player screen with nothing to play (black screen).
    if (!lesson.canPlayVideo) {
      if (lesson.hasPdfFile) _openAttachments(context, lesson);
      return;
    }
    // YouTube: the student picks the player first; dismissing cancels.
    YoutubePlayerKind? playerKind;
    if (looksLikeYouTube(lesson.videoUrl)) {
      playerKind = await pickYoutubePlayer(context);
      if (playerKind == null || !context.mounted) return;
    }
    if (kDebugMode) {
      debugPrint('>>> VIDEO: opening via GoRouter push (lesson=${lesson.id})');
    }
    context
        .push<void>(
          lessonVideoPath,
          extra: LessonVideoArgs(
            title: lesson.title,
            videoUrl: lesson.videoUrl,
            lessonId: lesson.id,
            pdfUrl: lesson.pdfUrl,
            playerKind: playerKind,
          ),
        )
        .whenComplete(() {
          if (kDebugMode) {
            debugPrint('>>> VIDEO: back pressed, popped');
          }
          SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        });
  }

  /// Attachments (PDFs) are open to everyone, even on a paid lesson — only
  /// the video is gated behind a subscription.
  void _openAttachments(BuildContext context, SubjectLesson lesson) {
    context.push<void>(
      lessonAttachmentsPath,
      extra: LessonAttachmentsArgs(lesson: lesson, subjectId: subjectId),
    );
  }

  void _openQuestion(BuildContext context) {
    context.push(chatPath);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The freshest copy of this lesson from the (refreshable) subject data,
    // so a changed `is_accessible` shows up without leaving the screen.
    final lesson =
        ref.watch(
          subjectDetailsProvider(subjectId).select(
            (s) => s.valueOrNull?.lessons
                .where((l) => l.id == this.lesson.id)
                .firstOrNull,
          ),
        ) ??
        this.lesson;
    final locked = isLessonLocked(ref, lesson);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          lesson.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontFamily: 'Cairo',
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: AppBackground(
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: () => refreshAll(ref, subjectId: subjectId),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Reveal(child: _LessonHeaderCard(lesson: lesson)),
                  const SizedBox(height: AppSpacing.lg),
                  Reveal(
                    index: 1,
                    child: _VideoHeroCard(
                      // Locked -> subscription-request sheet; otherwise always
                      // tappable; a lesson with no playable video_url is shown
                      // as having no video.
                      hasVideo: lesson.canPlayVideo,
                      locked: locked,
                      onTap: () =>
                          _openVideo(context, ref, lesson, locked: locked),
                    ),
                  ),
                  if (locked) ...[
                    const SizedBox(height: AppSpacing.md),
                    LockedLectureAccess(subjectId: subjectId),
                  ],
                  if (!locked && lesson.canPlayVideo) ...[
                    const SizedBox(height: AppSpacing.md),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: LectureDownloadButton(
                        lectureId: lesson.id,
                        subjectName: '',
                        lessonTitle: lesson.title,
                        sourceUrl: lesson.videoUrl ?? '',
                      ),
                    ),
                  ],
                  // Subject → lecture → video → its exams, right here.
                  // Hidden entirely when the lecture has no exams.
                  LectureExamsSection(
                    subjectId: subjectId,
                    header: const Padding(
                      padding: EdgeInsets.only(top: 28, bottom: 14),
                      child: _SectionTitle(title: 'الامتحانات'),
                    ),
                  ),
                  const SizedBox(height: 28),
                  const _SectionTitle(title: 'المحتوى التعليمي'),
                  const SizedBox(height: 14),
                  Reveal(
                    index: 2,
                    child: GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 14,
                      childAspectRatio: 1.05,
                      children: [
                        _ContentTile(
                          icon: Icons.attach_file_rounded,
                          label: 'المرفقات',
                          color: _attachmentColor(context),
                          onTap: () => _openAttachments(context, lesson),
                        ),
                        // Exams are the lecture's own (section above);
                        // assignments are hidden app-wide.
                        _ContentTile(
                          icon: Icons.help_rounded,
                          label: 'اسأل سؤالاً',
                          color: _questionColor(context),
                          onTap: () => _openQuestion(context),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LessonHeaderCard extends StatelessWidget {
  const _LessonHeaderCard({required this.lesson});

  final SubjectLesson lesson;

  @override
  Widget build(BuildContext context) {
    final thumb = lesson.thumbnailUrl;
    final hasThumb = thumb != null && thumb.isNotEmpty;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasThumb)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Hero(
                tag: 'lesson-thumb-${lesson.id}',
                child: CachedNetworkImage(
                  imageUrl: thumb,
                  memCacheWidth:
                      (MediaQuery.sizeOf(context).width *
                              MediaQuery.devicePixelRatioOf(context))
                          .round(),
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.high,
                  placeholder: (_, _) =>
                      const ShimmerBox(height: double.infinity, radius: 0),
                  errorWidget: (_, _, _) => DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: context.palette.brandGradient,
                    ),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.cardPadding),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: context.palette.brandGradient,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    Icons.menu_book_rounded,
                    color: context.palette.onPrimary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lesson.title,
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (lesson.durationMinutes != null || lesson.isFree) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Row(
                          children: [
                            if (lesson.durationMinutes != null)
                              Text(
                                '${lesson.durationMinutes} دقيقة',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: context.palette.textSecondary,
                                    ),
                              ),
                            if (lesson.durationMinutes != null && lesson.isFree)
                              const SizedBox(width: AppSpacing.sm),
                            if (lesson.isFree) const FreeLessonBadge(),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VideoHeroCard extends StatelessWidget {
  const _VideoHeroCard({
    required this.hasVideo,
    required this.locked,
    required this.onTap,
  });

  final bool hasVideo;
  final bool locked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return PressableScale(
      child: Opacity(
        opacity: hasVideo || locked ? 1 : 0.55,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.xxl),
            boxShadow: hasVideo && !locked
                ? DesignTokens.softShadow(
                    Theme.of(context).colorScheme,
                    strength: 1.6,
                  )
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.xxl),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Ink(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  gradient: hasVideo && !locked
                      ? context.palette.brandGradient
                      : LinearGradient(
                          colors: [
                            context.palette.textTertiary,
                            context.palette.textSecondary,
                          ],
                        ),
                  borderRadius: BorderRadius.circular(AppRadius.xxl),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            locked
                                ? PlatformUtils.hideSubscriptions
                                      ? 'فيديوهات المحاضرة 🔒'
                                      : 'فيديوهات المحاضرة — مدفوع 🔒'
                                : 'فيديوهات المحاضرة',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: context.palette.onPrimary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            locked
                                ? PlatformUtils.hideSubscriptions
                                      ? serverText(
                                          context,
                                          'locked_content',
                                          lockedContentMessage,
                                        )
                                      : 'محتوى مقفول — فعّله بالكود أو اطلب اشتراك'
                                : hasVideo
                                ? 'مشاهدة الفيديو'
                                : 'لا يوجد فيديو متاح',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 13,
                              color: context.palette.onPrimary.withValues(
                                alpha: 0.85,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: context.palette.onPrimary.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        locked ? Icons.lock_rounded : Icons.play_arrow_rounded,
                        color: context.palette.onPrimary,
                        size: 32,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Theme.of(context).colorScheme.primary,
                Theme.of(context).colorScheme.secondary,
              ],
            ),
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text(
          title,
          style: const TextStyle(
            fontFamily: 'Cairo',
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _ContentTile extends StatelessWidget {
  const _ContentTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: AlignmentDirectional.topStart,
                end: AlignmentDirectional.bottomEnd,
                colors: [
                  color.withValues(alpha: 0.22),
                  color.withValues(alpha: 0.08),
                ],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                'اضغط للفتح',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11,
                  color: context.palette.textSecondary,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Icon(Icons.arrow_back_ios_rounded, size: 10, color: color),
            ],
          ),
        ],
      ),
    );
  }
}

/// This lecture's own file (if it has a `pdf_url`), followed by the
/// subject's shared attachments (`GET /attachments?subject_id=` — there's
/// no per-lecture attachments endpoint).
class LessonAttachmentsScreen extends ConsumerWidget {
  const LessonAttachmentsScreen({
    super.key,
    required this.lesson,
    required this.subjectId,
  });

  final SubjectLesson lesson;
  final int subjectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attachmentsAsync = ref.watch(
      lessonAttachmentsProvider((subjectId, lesson.id)),
    );
    final canDownloadPdf = ref.watch(
      contentPolicyProvider.select((p) => p.canDownloadPdf),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('المرفقات')),
      body: AppBackground(
        child: attachmentsAsync.when(
          loading: () => const ShimmerList(count: 4, thumbnailSize: 44),
          error: (error, _) => ErrorView(
            message: failureOf(error).message,
            retryLabel: 'إعادة المحاولة',
            onRetry: () => ref.invalidate(
              lessonAttachmentsProvider((subjectId, lesson.id)),
            ),
          ),
          data: (allFiles) {
            // The lesson's own PDF may also come back as an id-less
            // `source: lesson_pdf` attachment — show it once.
            final files = [
              for (final f in allFiles)
                if (!(lesson.hasPdfFile &&
                    f.source == 'lesson_pdf' &&
                    f.lessonId == lesson.id))
                  f,
            ];
            if (!lesson.hasPdfFile && files.isEmpty) {
              return Center(
                child: Text(
                  'لا توجد مرفقات لهذه المحاضرة',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.palette.textSecondary,
                  ),
                ),
              );
            }
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: [
                if (lesson.hasPdfFile) ...[
                  _AttachmentTile(
                    name: '${lesson.title} — ملف المحاضرة',
                    type: 'PDF',
                    locked: lesson.pdfLocked,
                    onTap: () => openLessonPdf(context, lesson),
                    onDownload:
                        canDownloadPdf &&
                            lesson.isDownloadable &&
                            !lesson.pdfLocked
                        ? () => downloadPdf(
                            context,
                            ref,
                            url: lesson.pdfUrl ?? '',
                            title: lesson.title,
                            fileRef: lesson.pdfRef,
                          )
                        : null,
                  ),
                  if (files.isNotEmpty) const SizedBox(height: AppSpacing.md),
                ],
                for (var i = 0; i < files.length; i++) ...[
                  if (i > 0) const SizedBox(height: AppSpacing.md),
                  _AttachmentTile(
                    name: files[i].name,
                    type: files[i].type,
                    sizeLabel: files[i].sizeLabel,
                    locked: files[i].isLocked,
                    onTap: () => openAttachment(context, ref, files[i]),
                    onDownload:
                        canDownloadPdf &&
                            files[i].isPdf &&
                            files[i].isDownloadable &&
                            !files[i].isLocked
                        ? () => downloadPdf(
                            context,
                            ref,
                            url: files[i].url,
                            title: files[i].name,
                            fileRef: files[i].ref,
                          )
                        : null,
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({
    required this.name,
    required this.onTap,
    this.type,
    this.sizeLabel,
    this.onDownload,
    this.locked = false,
  });

  /// Shows a lock instead of the open affordance; tapping opens the
  /// locked-content sheet (handled by [onTap]).
  final bool locked;
  final VoidCallback? onDownload;
  final String name;
  final String? type;
  final String? sizeLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final metaParts = [
      if (type != null && type!.isNotEmpty) type!,
      if (sizeLabel != null) sizeLabel!,
    ];
    return AppCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: context.palette.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(
              Icons.insert_drive_file_rounded,
              color: context.palette.error,
              size: 22,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (metaParts.isNotEmpty)
                  Text(
                    metaParts.join(' • '),
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 11,
                      color: context.palette.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          if (onDownload != null)
            IconButton(
              tooltip: 'تحميل',
              onPressed: onDownload,
              icon: const Icon(Icons.download_rounded),
            ),
          if (locked)
            IconButton(
              tooltip: 'مقفول',
              onPressed: onTap,
              icon: Icon(
                Icons.lock_rounded,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          else
            TextButton(onPressed: onTap, child: const Text('فتح')),
        ],
      ),
    );
  }
}

/// This subject's exams — there's no per-lecture exam link in the API, so
/// the same list [SubjectDetailScreen] already loaded is shown here too.
class LessonExamsScreen extends StatelessWidget {
  const LessonExamsScreen({super.key, required this.exams});

  final List<SubjectExam> exams;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الامتحانات')),
      body: AppBackground(
        child: exams.isEmpty
            ? Center(
                child: Text(
                  'مفيش امتحانات متاحة بعد',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: context.palette.textSecondary,
                  ),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.all(AppSpacing.lg),
                itemCount: exams.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: AppSpacing.md),
                itemBuilder: (context, index) {
                  final exam = exams[index];
                  return AppCard(
                    onTap: exam.isLocked
                        ? null
                        : () => context.push('/exams/${exam.id}'),
                    child: Opacity(
                      opacity: exam.isLocked ? 0.6 : 1,
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: _examColor(
                                context,
                              ).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(AppRadius.md),
                            ),
                            child: Icon(
                              Icons.assignment_rounded,
                              color: _examColor(context),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  exam.title,
                                  style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  '${exam.questionsCount} سؤال'
                                  '${exam.durationMinutes != null ? " • ${exam.durationMinutes} دقيقة" : ""}'
                                  ' • نجاح ${exam.passPercentage}%',
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 11,
                                    color: context.palette.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            exam.isLocked
                                ? Icons.lock_rounded
                                : Icons.chevron_left_rounded,
                            color: context.palette.textTertiary,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
