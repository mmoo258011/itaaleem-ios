import 'package:itaaleem/core/content/content_policy.dart';
import 'package:itaaleem/features/app_config/app_config_providers.dart'
    show serverText;
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:itaaleem/app/theme/app_theme.dart';
import 'package:itaaleem/core/error/failure.dart';
import 'package:itaaleem/core/network/dio_client.dart';
import 'package:itaaleem/core/services/download_service.dart';
import 'package:itaaleem/core/widgets/app_shimmer.dart';
import 'package:itaaleem/core/widgets/app_toast.dart';
import 'package:itaaleem/core/widgets/error_view.dart';
import 'package:itaaleem/core/widgets/secure_screen.dart';
import 'package:itaaleem/features/auth/presentation/providers/auth_controller.dart';
import 'package:itaaleem/features/courses/domain/entities/course_details.dart';
import 'package:itaaleem/features/courses/domain/entities/lecture_details.dart';
import 'package:itaaleem/features/courses/domain/usecases/post_lecture_progress_usecase.dart';
import 'package:itaaleem/features/courses/presentation/providers/courses_providers.dart';
import 'package:itaaleem/features/courses/presentation/widgets/course_progress_bar.dart';
import 'package:itaaleem/features/courses/presentation/widgets/identity_watermark.dart';
import 'package:itaaleem/features/courses/presentation/widgets/players/lecture_playback_handle.dart';
import 'package:itaaleem/features/courses/presentation/widgets/players/playback_progress_reporter.dart';
import 'package:itaaleem/features/courses/presentation/widgets/players/private_server_playback_resolver.dart';
import 'package:itaaleem/features/courses/presentation/widgets/players/webview_lecture_player.dart';
import 'package:itaaleem/core/utils/youtube_utils.dart';
import 'package:itaaleem/features/courses/presentation/widgets/players/player_selection_sheet.dart';
import 'package:itaaleem/features/courses/presentation/widgets/subscribe_request_sheet.dart';
import 'package:itaaleem/features/courses/presentation/screens/section_lessons_screen.dart'
    show isSequentiallyLocked;
import 'package:itaaleem/features/settings/presentation/providers/settings_providers.dart';
import 'package:itaaleem/features/video/data/offline/offline_database.dart';
import 'package:itaaleem/features/video/presentation/widgets/lecture_download_button.dart';
import 'package:dio/dio.dart' as dio;
import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show kDebugMode, debugPrint;
import 'package:itaaleem/core/widgets/content_watermark.dart';
import 'package:itaaleem/core/widgets/server_watermark.dart';
import 'package:flutter/material.dart';
import 'package:itaaleem/features/subjects/presentation/widgets/lesson_access.dart';
import 'package:itaaleem/features/subjects/data/content_file_access.dart';
import 'package:itaaleem/features/subscriptions/presentation/widgets/contact_center_access_sheet.dart';
import 'package:itaaleem/core/utils/platform_utils.dart';
import 'package:itaaleem/core/utils/open_file_in_app.dart';
import 'package:itaaleem/core/theme/app_palette.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:itaaleem/core/theme/app_radius.dart';
import 'package:itaaleem/core/theme/app_spacing.dart';

/// `GET /lectures/{id}`: three-tab lesson screen (فيديوهات / امتحانات /
/// مرفقات). The video tab dispatches to the right player widget by
/// `provider`, protects the screen with [SecureScreen], overlays the
/// identifying watermark, and reports playback progress every 15 seconds.
/// Exams come from the parent course (`GET /lectures/{id}` has no
/// per-lecture exam link) via [courseExams], carried through the router as
/// [LectureNavArgs].
class LecturePlayerScreen extends ConsumerStatefulWidget {
  const LecturePlayerScreen({
    super.key,
    required this.lectureId,
    this.initialTitle,
    this.courseExams = const [],
    this.courseId,
    this.courseTitle,
    this.orderedLectures = const [],
    this.currentIndex = -1,
    this.forceOffline = false,
    this.videoOnly = false,
  });

  final int lectureId;
  final String? initialTitle;
  final List<CourseExam> courseExams;

  /// Carried along so a locked previous/next lecture can still open the
  /// normal subscribe-request sheet — see [LectureNavArgs].
  final int? courseId;
  final String? courseTitle;

  /// The section's lecture order the student navigated from, plus this
  /// lecture's position in it — powers the "المحاضرة السابقة"/"التالية" row
  /// under the video. Empty/-1 when opened without that context (e.g. a
  /// deep link), in which case the row simply doesn't show.
  final List<CourseLecture> orderedLectures;
  final int currentIndex;

  /// From "المحمّلات"' play button — skips the online/offline prompt and
  /// always plays this lecture's downloaded copy (see
  /// `PrivateServerPlaybackResolver`).
  final bool forceOffline;

  /// From the smart UI's `play_video`: just the video (title, progress,
  /// the lesson's video list) — no tabs, exams, attachments, notes or
  /// download; the smart UI shows those around it. The old UI never sets it.
  final bool videoOnly;

  @override
  ConsumerState<LecturePlayerScreen> createState() =>
      _LecturePlayerScreenState();
}

class _LecturePlayerScreenState extends ConsumerState<LecturePlayerScreen>
    with TickerProviderStateMixin {
  LecturePlaybackHandle? _handle;
  LectureVideo? _video;
  int? _selectedVideoId;
  Timer? _progressTimer;
  final _watchStopwatch = Stopwatch();
  bool _resumeMessageShown = false;
  bool _subscribeSheetShown = false;
  bool _isFullscreen = false;
  final _videoBoxKey = GlobalKey();
  late final TabController _tabController;

  /// Phone layout of a lecture that has a PDF: الفيديو / المذكرة / الامتحانات /
  /// المرفقات under a video that stays mounted above the tabs.
  late final TabController _pdfTabController;

  // `ref` throws once the element is disposed, so the use case must be
  // grabbed eagerly in initState — a `late` field initializer isn't enough,
  // since it would only evaluate on first access, which could be inside
  // dispose() itself if the player closes before the first progress tick.
  late final PostLectureProgressUseCase _postLectureProgressUseCase;

  /// A demo session never hits the playback/progress API — see
  /// [PrivateServerPlaybackResolver] and [_reportProgress].
  late final bool _isDemo;

  /// One online reporter per YouTube video (the private-server path gets its
  /// own from [PrivateServerPlaybackResolver]); a demo session never reports.
  final _youtubeReporters = <int, ProgressReporter>{};

  ProgressReporter? _youtubeReporterFor(LectureVideo video) {
    if (_isDemo) return null;
    return _youtubeReporters.putIfAbsent(
      video.id,
      () => PlaybackProgressReporter(
        dio: ref.read(dioClientProvider),
        lessonId: widget.lectureId,
      ),
    );
  }

  /// Set by [PrivateServerPlaybackResolver.onSourceResolved] — true while
  /// the current video is being served from its offline copy, in which
  /// case [_reportProgress] records progress locally instead of over the
  /// network (see `OfflineLicenseChecker.syncPendingProgress`).
  bool _isPlayingOffline = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _pdfTabController = TabController(length: 4, vsync: this);
    _postLectureProgressUseCase = ref.read(postLectureProgressUseCaseProvider);
    _isDemo = ref.read(authControllerProvider).valueOrNull?.isDemo ?? false;
  }

  @override
  void dispose() {
    _tabController.dispose();
    _pdfTabController.dispose();
    _progressTimer?.cancel();
    _reportProgress();
    for (final reporter in _youtubeReporters.values) {
      reporter.dispose();
    }
    super.dispose();
  }

  LectureVideo? _resolveSelectedVideo(List<LectureVideo> videos) {
    if (videos.isEmpty) return null;
    final selectedId = _selectedVideoId;
    if (selectedId == null) return videos.first;
    for (final video in videos) {
      if (video.id == selectedId) return video;
    }
    return videos.first;
  }

  void _selectVideo(LectureVideo video) {
    if (video.id == _selectedVideoId) return;
    _reportProgress();
    _progressTimer?.cancel();
    setState(() => _selectedVideoId = video.id);
  }

  void _onPlayerReady(LectureVideo video, LecturePlaybackHandle handle) {
    _video = video;
    _handle = handle;
    // Reports immediately on pause rather than waiting for the next
    // 15-second tick — see [LecturePlaybackHandle.onPause].
    handle.onPause = _reportProgress;
    _watchStopwatch
      ..reset()
      ..start();
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _reportProgress(),
    );
  }

  /// Reports progress to `POST /lessons/{id}/progress` (`watched_seconds`,
  /// `total_seconds`) only — the old `/videos/{id}/progress` and
  /// `/api/student/.../track-view` aren't on this API. Skipped entirely in a demo
  /// session — see [_isDemo]. While playing the offline copy
  /// ([_isPlayingOffline]), records to the local `OfflineVideos` row
  /// instead of the network — `OfflineLicenseChecker.syncPendingProgress`
  /// flushes it once connectivity is back.
  void _reportProgress() {
    if (_isDemo) return;
    final handle = _handle;
    final video = _video;
    if (handle == null || video == null) return;

    if (_isPlayingOffline) {
      ref
          .read(offlineDatabaseProvider)
          .updateByLessonId(
            widget.lectureId,
            (base) => base.copyWith(
              pendingSyncPositionSeconds: Value(handle.position.inSeconds),
              pendingSyncDurationSeconds: Value(
                handle.duration?.inSeconds ?? 0,
              ),
              pendingSyncProgressPercentage: Value(handle.watchPercentage),
            ),
          );
      return;
    }

    _postLectureProgressUseCase(
      widget.lectureId,
      positionSeconds: handle.position.inSeconds,
      durationSeconds: handle.duration?.inSeconds ?? 0,
      progressPercentage: handle.watchPercentage,
    );
  }

  /// [PrivateServerPlaybackResolver] already prompts its own "متابعة من
  /// {time}؟" dialog before playback starts, so this toast would just be a
  /// redundant second nudge for that provider — shown only for the other
  /// providers, which still resume silently.
  void _maybeShowResumeMessage(LectureVideo video) {
    if (_resumeMessageShown) return;
    if (video.provider == VideoProvider.privateServer) return;
    if ((video.progress?.lastPositionSeconds ?? 0) <= 5) return;
    _resumeMessageShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      AppToast.showSuccess(context, 'تم الاستئناف من حيث توقفت');
    });
  }

  /// The course's lecture list is the source of truth for the lesson name
  /// (confirmed correct wherever it's shown); `GET /lectures/{id}` has been
  /// observed returning a numeric-looking `title` for some lectures, so it's
  /// only used as a fallback when navigation didn't carry a title along.
  String _resolveTitle(LectureDetails? details) {
    final initial = widget.initialTitle?.trim();
    if (initial != null && initial.isNotEmpty) return initial;
    return details?.title.trim() ?? '';
  }

  CourseLecture? get _previousLecture {
    final index = widget.currentIndex;
    if (index <= 0 || index > widget.orderedLectures.length) return null;
    return widget.orderedLectures[index - 1];
  }

  CourseLecture? get _nextLecture {
    final index = widget.currentIndex;
    if (index < 0 || index + 1 >= widget.orderedLectures.length) return null;
    return widget.orderedLectures[index + 1];
  }

  /// Same lock precedence as [SectionLessonsScreen]'s own lecture tap: a
  /// subscription lock first (subscribe sheet), then a sequential lock (a
  /// toast to finish the previous lecture), then the normal navigation.
  void _goToSibling(CourseLecture target, int targetIndex) {
    if (target.isLocked) {
      final courseId = widget.courseId;
      if (courseId != null) {
        showSubscribeRequestSheet(
          context,
          courseId: courseId,
          courseTitle: widget.courseTitle,
        );
      }
      return;
    }
    final sequentialMode =
        ref.read(appSettingsProvider).valueOrNull?.sequentialMode ?? false;
    if (isSequentiallyLocked(
      widget.orderedLectures,
      targetIndex,
      sequentialMode,
    )) {
      AppToast.showError(context, 'أكمل الدرس السابق أولاً');
      return;
    }
    _reportProgress();
    context.pushReplacement(
      '/lectures/${target.id}',
      extra: LectureNavArgs(
        title: target.title,
        courseExams: widget.courseExams,
        courseId: widget.courseId,
        courseTitle: widget.courseTitle,
        orderedLectures: widget.orderedLectures,
        currentIndex: targetIndex,
      ),
    );
  }

  static bool _isNotSubscribedError(Object? error) =>
      error is ServerFailure && error.statusCode == 403;

  /// Opens the subscribe-request sheet once (a rebuild must not stack
  /// several). Needs [LecturePlayerScreen.courseId]; without it the error
  /// view is all there is.
  ///
  /// Request sent → back to the previous screen. Dismissed without sending →
  /// the error view stays, with its "طلب اشتراك" button to open the sheet
  /// again (and the header's back button).
  Future<void> _offerSubscription() async {
    final courseId = widget.courseId;
    if (courseId == null || _subscribeSheetShown || !mounted) return;
    _subscribeSheetShown = true;
    final requested = await showSubscribeRequestSheet(
      context,
      courseId: courseId,
      courseTitle: widget.courseTitle,
    );
    if (requested == true && mounted && context.mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final detailsAsync = ref.watch(lectureDetailsProvider(widget.lectureId));
    // A lecture the list didn't mark as locked can still be refused by
    // `GET /lectures/{id}` (403) — offer the subscribe sheet right away
    // instead of leaving the student on a dead player screen.
    ref.listen(lectureDetailsProvider(widget.lectureId), (previous, next) {
      if (_isNotSubscribedError(next.error)) _offerSubscription();
    });
    if (detailsAsync.hasError && _isNotSubscribedError(detailsAsync.error)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _offerSubscription());
    }
    if (kDebugMode) {
      debugPrint(
        '[LecturePlayerScreen] initialTitle="${widget.initialTitle}" '
        'apiTitle="${detailsAsync.valueOrNull?.title}"',
      );
    }

    return SecureScreen(
      child: PopScope(
        onPopInvokedWithResult: (didPop, _) => _reportProgress(),
        child: Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            top: !_isFullscreen,
            bottom: !_isFullscreen,
            child: Column(
              children: [
                if (!_isFullscreen)
                  _Header(title: _resolveTitle(detailsAsync.valueOrNull)),
                Expanded(
                  child: detailsAsync.when(
                    loading: () => Center(
                      child: CircularProgressIndicator(
                        color: context.palette.primaryOnDark,
                      ),
                    ),
                    // ErrorView paints its own theme background, so it stays
                    // readable on this black Scaffold.
                    error: (error, stackTrace) =>
                        _isNotSubscribedError(error) && widget.courseId != null
                        ? ErrorView(
                            message: PlatformUtils.hideSubscriptions
                                ? serverText(
                                    context,
                                    'locked_content',
                                    lockedContentMessage,
                                  )
                                : 'المحاضرة دي محتاجة اشتراك',
                            retryLabel: PlatformUtils.hideSubscriptions
                                ? 'تواصل مع المركز'
                                : 'طلب اشتراك',
                            onRetry: () {
                              _subscribeSheetShown = false;
                              _offerSubscription();
                            },
                          )
                        : ErrorView(
                            message: 'تعذر تحميل الفيديو، حاول مرة أخرى',
                            retryLabel: 'إعادة المحاولة',
                            onRetry: () => ref.invalidate(
                              lectureDetailsProvider(widget.lectureId),
                            ),
                          ),
                    data: _buildLoaded,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoaded(LectureDetails details) {
    final video = _resolveSelectedVideo(details.videos);
    if (video != null) _maybeShowResumeMessage(video);
    final student = ref.watch(authControllerProvider).valueOrNull;
    // The normal-layout `_Header` above the tabs disappears in fullscreen
    // (see build()), so players that support fullscreen show the title
    // themselves inside their own overlay instead.
    final title = _resolveTitle(details);

    // Only one of these is ever in the tree at a time (fullscreen vs. inside
    // the tab), so a GlobalKey lets Flutter move the player between them
    // instead of disposing it and starting playback over.
    Widget videoBox() => Stack(
      key: _videoBoxKey,
      alignment: Alignment.center,
      children: [
        Center(child: _buildPlayerFor(video!, title)),
        if (student != null)
          Positioned.fill(
            child: ProtectedWatermark(
              lessonId: widget.lectureId,
              legacy: [
                ContentWatermark(
                  studentName: student.fullName,
                  studentPhone: student.mobile,
                  opacity: 0.06,
                ),
                IdentityWatermark(
                  studentName: student.fullName,
                  studentMobile: student.mobile,
                ),
              ],
            ),
          ),
      ],
    );

    // Fullscreen (video providers that support it) takes over the whole
    // remaining area — the tabs only make sense in the normal layout.
    if (_isFullscreen && video != null) return videoBox();

    if (widget.videoOnly) {
      return _VideosTab(
        title: title,
        description: null,
        videos: details.videos,
        selectedVideo: video,
        videoBox: video != null ? videoBox() : null,
        onSelectVideo: _selectVideo,
        watchPercentage: video?.progress?.watchPercentage,
        downloadButton: null,
        previousLecture: null,
        nextLecture: null,
        onPrevious: () {},
        onNext: () {},
      );
    }

    // Offline download only makes sense for a video actually served by our
    // own backend (LocalRangeServer only knows how to replay that kind) —
    // never offered for YouTube/Bunny/Vimeo, and never in a demo session
    // (OfflineDownloadManager.startDownload rejects those anyway).
    final showDownload =
        !_isDemo &&
        details.isDownloadable &&
        ref.watch(contentPolicyProvider).canDownloadVideo &&
        video?.provider == VideoProvider.privateServer;

    // [withPlayer] false → the video is mounted elsewhere (above the tabs, in
    // the phone + PDF layout), so this tab only carries the info/playlist.
    Widget videosTab({required bool withPlayer}) => _KeepAlive(
      child: _VideosTab(
        title: title,
        description: details.description,
        videos: details.videos,
        selectedVideo: video,
        videoBox: withPlayer && video != null ? videoBox() : null,
        showPlayer: withPlayer,
        onSelectVideo: _selectVideo,
        watchPercentage: video?.progress?.watchPercentage,
        downloadButton: showDownload
            ? LectureDownloadButton(
                lectureId: widget.lectureId,
                subjectName: widget.courseTitle ?? '',
                lessonTitle: title,
                sourceUrl: video?.videoUrl ?? '',
              )
            : null,
        previousLecture: _previousLecture,
        nextLecture: _nextLecture,
        onPrevious: () {
          final previous = _previousLecture;
          if (previous != null) {
            _goToSibling(previous, widget.currentIndex - 1);
          }
        },
        onNext: () {
          final next = _nextLecture;
          if (next != null) {
            _goToSibling(next, widget.currentIndex + 1);
          }
        },
      ),
    );

    final examsTab = _ExamsTab(
      exams: widget.courseExams,
      courseId: widget.courseId,
    );
    final attachmentsTab = _AttachmentsTab(
      lectureId: widget.lectureId,
      pdfs: details.pdfs,
      attachments: details.attachments,
    );

    final pdf = details.primaryPdf;
    final isTablet = MediaQuery.sizeOf(context).width >= 600;

    // Phone + a PDF: the video sits above the tabs so it keeps playing while
    // the student reads the مذكرة.
    if (pdf != null && !isTablet) {
      return Column(
        children: [
          if (video != null)
            AspectRatio(aspectRatio: 16 / 9, child: videoBox()),
          _LessonTabBar(controller: _pdfTabController, hasPdf: true),
          Expanded(
            child: TabBarView(
              controller: _pdfTabController,
              children: [
                videosTab(withPlayer: false),
                _KeepAlive(
                  child: _PdfPane(
                    key: ValueKey('pdf-pane-${pdf.id}'),
                    pdf: pdf,
                  ),
                ),
                examsTab,
                attachmentsTab,
              ],
            ),
          ),
        ],
      );
    }

    final standardLayout = Column(
      children: [
        _LessonTabBar(controller: _tabController),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [videosTab(withPlayer: true), examsTab, attachmentsTab],
          ),
        ),
      ],
    );
    if (pdf == null) return standardLayout;

    // Tablet + a PDF: video/content 60% on the right, PDF 40% on the left —
    // pinned to RTL so the sides don't flip with the app's locale.
    return Row(
      textDirection: TextDirection.rtl,
      children: [
        Expanded(flex: 6, child: standardLayout),
        const VerticalDivider(width: 1, thickness: 1),
        Expanded(
          flex: 4,
          child: _PdfPane(key: ValueKey('pdf-pane-${pdf.id}'), pdf: pdf),
        ),
      ],
    );
  }

  Widget _buildPlayerFor(LectureVideo video, String title) {
    final startAt = Duration(seconds: video.progress?.lastPositionSeconds ?? 0);
    if (kDebugMode) {
      debugPrint(
        '[LecturePlayerScreen] _buildPlayerFor: video.id=${video.id} '
        'provider=${video.provider} videoUrl=${video.videoUrl} '
        'providerVideoId=${video.providerVideoId} startAt=$startAt',
      );
    }

    switch (video.provider) {
      case VideoProvider.privateServer:
        if (kDebugMode) {
          debugPrint(
            '[LecturePlayerScreen] routing video ${video.id} to PrivateServerPlaybackResolver',
          );
        }
        return PrivateServerPlaybackResolver(
          key: ValueKey('resolver-${video.id}'),
          lectureId: widget.lectureId,
          video: video,
          isDemo: _isDemo,
          onReady: (handle) => _onPlayerReady(video, handle),
          onEnded: _reportProgress,
          onSourceResolved: (isOffline) =>
              setState(() => _isPlayingOffline = isOffline),
          onFullscreenChanged: (isFullscreen) =>
              setState(() => _isFullscreen = isFullscreen),
        );
      case VideoProvider.youtube:
        final raw = video.providerVideoId ?? video.videoUrl;
        if (raw == null || extractYouTubeId(raw) == null) {
          if (kDebugMode) {
            debugPrint(
              '[LecturePlayerScreen] youtube video ${video.id} has no usable id/url — showing _unavailable()',
            );
          }
          return _unavailable();
        }
        if (kDebugMode) {
          debugPrint(
            '[LecturePlayerScreen] routing video ${video.id} to YoutubeMultiPlayer',
          );
        }
        return YoutubeMultiPlayer(
          key: ValueKey('youtube-${video.id}'),
          rawIdOrUrl: raw,
          startAt: startAt,
          title: title,
          thumbnailUrl: video.thumbnailUrl,
          progressReporter: _youtubeReporterFor(video),
          onReady: (handle) => _onPlayerReady(video, handle),
          onEnded: _reportProgress,
          onFullscreenChanged: (isFullscreen) =>
              setState(() => _isFullscreen = isFullscreen),
        );
      case VideoProvider.bunny:
      case VideoProvider.vimeo:
      case VideoProvider.unknown:
        if (WebviewLecturePlayer.resolveEmbedUrl(video) == null) {
          if (kDebugMode) {
            debugPrint(
              '[LecturePlayerScreen] ${video.provider} video ${video.id} has no resolvable embed url — showing _unavailable()',
            );
          }
          return _unavailable();
        }
        if (kDebugMode) {
          debugPrint(
            '[LecturePlayerScreen] routing video ${video.id} (provider=${video.provider}) to WebviewLecturePlayer',
          );
        }
        return WebviewLecturePlayer(
          key: ValueKey('webview-${video.id}'),
          video: video,
          startAt: startAt,
          onReady: (handle) => _onPlayerReady(video, handle),
        );
    }
  }

  Widget _unavailable() => const Center(
    child: Text(
      'تعذر تحميل الفيديو',
      style: TextStyle(color: AppColors.textOnDark),
    ),
  );
}

/// Top tab bar: فيديوهات / امتحانات / مرفقات, purple pill indicator on a
/// translucent dark bar to match the black player screen background.
class _LessonTabBar extends StatelessWidget {
  const _LessonTabBar({required this.controller, this.hasPdf = false});

  final TabController controller;

  /// Phone layout of a lecture with a PDF: "الفيديو" + "المذكرة" tabs ahead of
  /// the exams/attachments ones (the video itself lives above the tab bar).
  final bool hasPdf;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsetsDirectional.fromSTEB(12, 0, 12, 10),
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.textOnDark.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: TabBar(
        controller: controller,
        indicator: BoxDecoration(
          color: context.palette.primaryOnDark,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        splashBorderRadius: BorderRadius.circular(AppRadius.md),
        labelColor: AppColors.textOnDark,
        unselectedLabelColor: Colors.white60,
        labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        tabs: [
          Tab(
            height: 42,
            child: _TabLabel(
              icon: Icons.play_circle_fill_rounded,
              label: hasPdf ? 'الفيديو' : 'الفيديوهات',
            ),
          ),
          if (hasPdf)
            const Tab(
              height: 42,
              child: _TabLabel(
                icon: Icons.description_rounded,
                label: 'المذكرة',
              ),
            ),
          const Tab(
            height: 42,
            child: _TabLabel(icon: Icons.percent_rounded, label: 'الامتحانات'),
          ),
          const Tab(
            height: 42,
            child: _TabLabel(
              icon: Icons.attach_file_rounded,
              label: 'المرفقات',
            ),
          ),
        ],
      ),
    );
  }
}

class _TabLabel extends StatelessWidget {
  const _TabLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17),
        const SizedBox(width: 6),
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

/// Keeps [child]'s state alive inside a lazily-building parent (a
/// [TabBarView] page or a [ListView] item) while it's off-screen — used so the
/// video player isn't disposed (and playback restarted) by switching tabs or
/// scrolling.
class _KeepAlive extends StatefulWidget {
  const _KeepAlive({required this.child});

  final Widget child;

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// Video player plus, when a lecture carries more than one video, a
/// thumbnail+title playlist beneath it to switch between them.
class _VideosTab extends StatelessWidget {
  const _VideosTab({
    required this.title,
    required this.description,
    required this.videos,
    required this.selectedVideo,
    required this.videoBox,
    required this.onSelectVideo,
    required this.watchPercentage,
    required this.downloadButton,
    required this.previousLecture,
    required this.nextLecture,
    required this.onPrevious,
    required this.onNext,
    this.showPlayer = true,
  });

  final String title;
  final String? description;
  final List<LectureVideo> videos;
  final LectureVideo? selectedVideo;
  final Widget? videoBox;

  /// False when the player is mounted above the tab bar instead (phone + PDF).
  final bool showPlayer;
  final ValueChanged<LectureVideo> onSelectVideo;
  final double? watchPercentage;

  /// A [LectureDownloadButton], only when this lecture's video is eligible
  /// for offline download — see `_LecturePlayerScreenState._buildLoaded`.
  final Widget? downloadButton;
  final CourseLecture? previousLecture;
  final CourseLecture? nextLecture;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    if (selectedVideo == null) {
      return const Center(
        child: Text(
          'لا يوجد فيديو لهذا الدرس بعد',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsetsDirectional.only(bottom: 16),
      children: [
        // Kept alive so scrolling the info section far enough that the
        // player leaves the ListView's cache extent doesn't dispose it.
        if (showPlayer)
          _KeepAlive(
            child: AspectRatio(aspectRatio: 16 / 9, child: videoBox),
          ),
        _LectureInfoSection(
          title: title,
          description: description,
          watchPercentage: watchPercentage,
          downloadButton: downloadButton,
          previousLecture: previousLecture,
          nextLecture: nextLecture,
          onPrevious: onPrevious,
          onNext: onNext,
        ),
        if (videos.length > 1) ...[
          const Padding(
            padding: EdgeInsetsDirectional.fromSTEB(16, 16, 16, 8),
            child: Text(
              'فيديوهات الدرس',
              style: TextStyle(
                color: AppColors.textOnDark,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ),
          for (var i = 0; i < videos.length; i++)
            _VideoListTile(
              index: i,
              video: videos[i],
              isSelected: videos[i].id == selectedVideo!.id,
              onTap: () => onSelectVideo(videos[i]),
            ),
        ],
      ],
    );
  }
}

/// The lecture's title/description, its own watch-progress bar, and a
/// "المحاضرة السابقة"/"التالية" row — shown right under the video, only in
/// the normal (non-fullscreen) layout since it lives inside the videos tab.
class _LectureInfoSection extends StatelessWidget {
  const _LectureInfoSection({
    required this.title,
    required this.description,
    required this.watchPercentage,
    required this.downloadButton,
    required this.previousLecture,
    required this.nextLecture,
    required this.onPrevious,
    required this.onNext,
  });

  final String title;
  final String? description;
  final double? watchPercentage;
  final Widget? downloadButton;
  final CourseLecture? previousLecture;
  final CourseLecture? nextLecture;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final desc = description?.trim();
    final hasNav = previousLecture != null || nextLecture != null;

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title.isNotEmpty)
            Text(
              title,
              style: const TextStyle(
                color: AppColors.textOnDark,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
            ),
          if (desc != null && desc.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              desc,
              style: const TextStyle(color: Colors.white60, fontSize: 14),
            ),
          ],
          if (watchPercentage != null) ...[
            const SizedBox(height: 14),
            CourseProgressBar(
              percent: watchPercentage!,
              trackColor: Colors.white12,
            ),
          ],
          if (downloadButton != null) ...[
            const SizedBox(height: 14),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: downloadButton,
            ),
          ],
          if (hasNav) ...[
            const SizedBox(height: AppSpacing.base),
            const Divider(color: Colors.white12, height: 1),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: _SiblingNavButton(
                    label: 'المحاضرة السابقة',
                    icon: Icons.arrow_back_ios_new_rounded,
                    lecture: previousLecture,
                    onTap: onPrevious,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SiblingNavButton(
                    label: 'المحاضرة التالية',
                    icon: Icons.arrow_forward_ios_rounded,
                    lecture: nextLecture,
                    onTap: onNext,
                    alignEnd: true,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SiblingNavButton extends StatelessWidget {
  const _SiblingNavButton({
    required this.label,
    required this.icon,
    required this.lecture,
    required this.onTap,
    this.alignEnd = false,
  });

  final String label;
  final IconData icon;
  final CourseLecture? lecture;
  final VoidCallback onTap;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final target = lecture;
    if (target == null) return const SizedBox.shrink();

    final children = [
      if (!alignEnd) Icon(icon, size: 14, color: Colors.white60),
      if (!alignEnd) const SizedBox(width: 6),
      Expanded(
        child: Column(
          crossAxisAlignment: alignEnd
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
            const SizedBox(height: 2),
            Text(
              target.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: alignEnd ? TextAlign.end : TextAlign.start,
              style: const TextStyle(
                color: AppColors.textOnDark,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
      if (alignEnd) const SizedBox(width: 6),
      if (alignEnd) Icon(icon, size: 14, color: Colors.white60),
    ];

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.textOnDark.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(children: children),
      ),
    );
  }
}

class _VideoListTile extends StatelessWidget {
  const _VideoListTile({
    required this.index,
    required this.video,
    required this.isSelected,
    required this.onTap,
  });

  final int index;
  final LectureVideo video;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final thumbnail = video.thumbnailUrl;
    return Container(
      margin: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 10),
      decoration: BoxDecoration(
        color: isSelected
            ? context.palette.primaryOnDark.withValues(alpha: 0.18)
            : AppColors.textOnDark.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: isSelected
            ? Border.all(color: context.palette.primaryOnDark, width: 1.4)
            : null,
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsetsDirectional.symmetric(
          horizontal: 10,
          vertical: 6,
        ),
        leading: SizedBox(
          width: 64,
          height: 44,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: thumbnail != null && thumbnail.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: thumbnail,
                    memCacheWidth: 320,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => _thumbnailFallback(),
                    errorWidget: (context, url, error) => _thumbnailFallback(),
                  )
                : _thumbnailFallback(),
          ),
        ),
        title: Text(
          'فيديو ${index + 1}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: AppColors.textOnDark,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
        trailing: Icon(
          isSelected
              ? Icons.play_circle_fill_rounded
              : Icons.play_circle_outline_rounded,
          color: isSelected ? context.palette.primaryOnDark : Colors.white38,
        ),
      ),
    );
  }

  Widget _thumbnailFallback() => Container(
    color: AppColors.textOnDark.withValues(alpha: 0.1),
    alignment: Alignment.center,
    child: const Icon(Icons.movie_rounded, color: Colors.white38, size: 20),
  );
}

/// Exams belonging to the lecture's parent course — there's no per-lecture
/// exam link in the API, so the same list is shown on every lecture of that
/// course. Uses the exams carried in the navigation args when present, and
/// otherwise loads them through [courseDetailsProvider] (deep links, pushes).
/// Tapping "ابدأ الامتحان" opens `GET /exams/{id}`, which owns the rest of the
/// attempt flow.
class _ExamsTab extends ConsumerWidget {
  const _ExamsTab({required this.exams, required this.courseId});

  final List<CourseExam> exams;
  final int? courseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    var list = exams;
    if (list.isEmpty && courseId != null) {
      final details = ref.watch(courseDetailsProvider(courseId!));
      if (details.isLoading) {
        return const ShimmerList(count: 3, thumbnailSize: 48);
      }
      list = details.valueOrNull?.exams ?? const [];
    }

    if (list.isEmpty) {
      return const _EmptyTabState(
        icon: Icons.quiz_rounded,
        message: 'لا توجد امتحانات لهذه المحاضرة',
      );
    }

    return ListView.builder(
      padding: const EdgeInsetsDirectional.all(16),
      itemCount: list.length,
      itemBuilder: (context, i) => _ExamCard(exam: list[i]),
    );
  }
}

class _ExamCard extends StatelessWidget {
  const _ExamCard({required this.exam});

  final CourseExam exam;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final metaParts = [
      if (exam.questionsCount != null) '${exam.questionsCount} سؤال',
      if (exam.durationMinutes != null) '${exam.durationMinutes} دقيقة',
    ];

    return Container(
      margin: const EdgeInsetsDirectional.only(bottom: 12),
      padding: const EdgeInsetsDirectional.all(14),
      decoration: BoxDecoration(
        color: AppColors.textOnDark.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.textOnDark.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: primary.withValues(alpha: 0.25),
                child: const Icon(
                  Icons.quiz_rounded,
                  color: AppColors.textOnDark,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exam.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        color: AppColors.textOnDark,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    if (metaParts.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        metaParts.join(' • '),
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          color: Colors.white60,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _ExamStatusBadge(attempted: exam.attempted),
            ],
          ),
          if (exam.attempted) ...[
            const SizedBox(height: 10),
            _ExamAttemptedBadge(passed: exam.passed, score: exam.score),
          ],
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            onPressed: () => context.push('/exams/${exam.id}'),
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(
              exam.attempted ? 'إعادة المحاولة' : 'ابدأ الامتحان',
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: primary,
              minimumSize: const Size.fromHeight(44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "لم يبدأ" / "مكتمل" pill at the end of an exam card's header.
class _ExamStatusBadge extends StatelessWidget {
  const _ExamStatusBadge({required this.attempted});

  final bool attempted;

  @override
  Widget build(BuildContext context) {
    final color = attempted ? AppColors.success : Colors.white60;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Text(
        attempted ? 'مكتمل' : 'لم يبدأ',
        style: TextStyle(
          fontFamily: 'Cairo',
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Shown under an exam card once `GET /courses/{id}/exams` reports
/// `attempted: true` — styled for this tab's dark background, unlike
/// [CourseDetailsScreen]'s equivalent badge.
class _ExamAttemptedBadge extends StatelessWidget {
  const _ExamAttemptedBadge({required this.passed, required this.score});

  final bool? passed;
  final double? score;

  @override
  Widget build(BuildContext context) {
    final ok = passed ?? true;
    final color = ok ? AppColors.success : AppColors.error;
    final label = score != null
        ? 'تم الامتحان • الدرجة ${score!.round()}٪'
        : 'تم الامتحان';

    return Row(
      children: [
        Icon(
          ok ? Icons.check_circle_rounded : Icons.cancel_rounded,
          size: 16,
          color: color,
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// Lists a lecture's PDF attachments (in-app viewer, tracked via
/// `POST /pdfs/{id}/progress`) and generic attachments (no in-app viewer or
/// progress endpoint for those, so "عرض" still opens externally). "تحميل" on
/// either kind, though, always downloads the bytes in-app (same authenticated
/// Dio client as [PdfViewerScreen]'s own download button) and saves straight
/// into the device's Downloads folder via [DownloadService] — never a bare
/// `launchUrl` to the server's file URL, which would just open the browser.
class _AttachmentsTab extends ConsumerStatefulWidget {
  const _AttachmentsTab({
    required this.lectureId,
    required this.pdfs,
    required this.attachments,
  });

  final int lectureId;
  final List<LecturePdf> pdfs;
  final List<LectureAttachment> attachments;

  @override
  ConsumerState<_AttachmentsTab> createState() => _AttachmentsTabState();
}

class _AttachmentsTabState extends ConsumerState<_AttachmentsTab> {
  /// Keyed by `"pdf-{id}"`/`"att-{id}"` — null while the total size isn't
  /// known yet, otherwise 0..1.
  final Map<String, double?> _progress = {};

  @override
  Widget build(BuildContext context) {
    if (widget.pdfs.isEmpty && widget.attachments.isEmpty) {
      return const _EmptyTabState(
        icon: Icons.attach_file_rounded,
        message: 'لا توجد مرفقات',
      );
    }

    return ListView(
      padding: const EdgeInsetsDirectional.all(16),
      children: [
        for (final pdf in widget.pdfs)
          _AttachmentTile(
            icon: Icons.picture_as_pdf_rounded,
            title: pdf.title,
            subtitle: pdf.readPercentage > 0
                ? 'تمت قراءة ${pdf.readPercentage.round()}٪'
                : null,
            isDownloadable:
                pdf.isDownloadable &&
                !pdf.locked &&
                ref.watch(contentPolicyProvider).canDownloadPdf,
            locked: pdf.locked,
            isDownloading: _progress.containsKey('pdf-${pdf.id}'),
            downloadProgress: _progress['pdf-${pdf.id}'],
            onView: pdf.locked
                ? () => _showLocked(context)
                : () => context.push(
                    '/lectures/${widget.lectureId}/pdfs/${pdf.id}',
                    extra: pdf.title,
                  ),
            onDownload: () => _download(
              key: 'pdf-${pdf.id}',
              url: pdf.fileUrl,
              title: pdf.title,
              defaultExtension: 'pdf',
              mimeType: 'application/pdf',
            ),
          ),
        for (final attachment in widget.attachments)
          _AttachmentTile(
            icon: Icons.attach_file_rounded,
            title: attachment.title,
            subtitle: null,
            isDownloadable: attachment.isDownloadable && !attachment.locked,
            locked: attachment.locked,
            isDownloading: _progress.containsKey('att-${attachment.id}'),
            downloadProgress: _progress['att-${attachment.id}'],
            onView: attachment.locked
                ? () => _showLocked(context)
                : () => _openLink(context, attachment.fileUrl),
            onDownload: () => _download(
              key: 'att-${attachment.id}',
              url: attachment.fileUrl,
              title: attachment.title,
              defaultExtension: 'bin',
              mimeType: 'application/octet-stream',
            ),
          ),
      ],
    );
  }

  Future<void> _showLocked(BuildContext context) =>
      showPaidContentSheet(context, lessonId: widget.lectureId);

  Future<void> _openLink(BuildContext context, String url) async {
    await openFileInApp(context, url);
  }

  /// Downloads [url]'s bytes in-app and saves them straight into the
  /// device's Downloads folder — no browser tab, no server URL ever shown.
  Future<void> _download({
    required String key,
    required String url,
    required String title,
    required String defaultExtension,
    required String mimeType,
  }) async {
    if (_progress.containsKey(key)) return;
    if (kDebugMode) {
      debugPrint(
        '[AttachmentsTab] "تحميل" tapped for $key: downloading $url in-app',
      );
    }
    setState(() => _progress[key] = null);

    try {
      final client = ref.read(dioClientProvider);
      final response = await client.get<List<int>>(
        url,
        options: dio.Options(responseType: dio.ResponseType.bytes),
        onReceiveProgress: (received, total) {
          if (total > 0 && mounted) {
            setState(() => _progress[key] = received / total);
          }
        },
      );
      final bytes = response.data ?? const [];
      if (bytes.isEmpty) throw StateError('empty response body');

      final savedPath = await ref
          .read(downloadServiceProvider)
          .saveToDownloads(
            fileName: _fileNameFor(url, title, defaultExtension),
            mimeType: mimeType,
            bytes: Uint8List.fromList(bytes),
          );
      if (kDebugMode) {
        debugPrint('[AttachmentsTab] $key saved to: $savedPath');
      }
      if (!mounted) return;
      if (savedPath != null) {
        AppToast.showSuccess(
          context,
          'تم التحميل — الملف في مجلد التنزيلات',
          actionLabel: 'فتح',
          onAction: () => OpenFilex.open(savedPath),
        );
      } else {
        AppToast.showError(context, 'تعذر حفظ الملف على الجهاز');
      }
    } on dio.DioException catch (e) {
      final mapped = classifyContentError(e);
      if (mounted) {
        AppToast.showError(
          context,
          mapped is ContentLockedException
              ? mapped.displayMessage
              : mapped is ContentLinkExpiredException
              ? 'انتهت صلاحية الرابط، افتح الملف من التطبيق تاني'
              : 'تعذر تحميل الملف',
        );
      }
      // An expired link: reload the lecture so the next tap gets a fresh one.
      if (mapped is ContentLinkExpiredException) {
        ref.invalidate(lectureDetailsProvider(widget.lectureId));
      }
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('[AttachmentsTab] $key download failed: $e\n$stackTrace');
      }
      if (mounted) AppToast.showError(context, 'تعذر تحميل الملف');
    } finally {
      if (mounted) setState(() => _progress.remove(key));
    }
  }

  String _fileNameFor(String url, String title, String defaultExtension) {
    final uri = Uri.tryParse(url);
    final last = (uri != null && uri.pathSegments.isNotEmpty)
        ? uri.pathSegments.last
        : null;
    if (last != null && last.isNotEmpty) return last;
    final trimmed = title.trim();
    final name = trimmed.isEmpty ? 'file' : trimmed;
    return name.contains('.') ? name : '$name.$defaultExtension';
  }
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({
    required this.icon,
    required this.title,
    required this.isDownloadable,
    required this.isDownloading,
    required this.downloadProgress,
    required this.onView,
    required this.onDownload,
    this.subtitle,
    this.locked = false,
  });

  /// Locked for this student: "عرض" becomes a lock button.
  final bool locked;
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool isDownloadable;
  final bool isDownloading;
  final double? downloadProgress;
  final VoidCallback onView;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsetsDirectional.all(14),
      decoration: BoxDecoration(
        color: AppColors.textOnDark.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: context.palette.primaryOnDark.withValues(
                  alpha: 0.25,
                ),
                child: Icon(icon, color: AppColors.textOnDark),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textOnDark,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (isDownloading) ...[
            LinearProgressIndicator(
              value: downloadProgress,
              minHeight: 3,
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation(context.palette.primaryOnDark),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onView,
                  icon: Icon(
                    locked ? Icons.lock_rounded : Icons.visibility_rounded,
                    size: 18,
                  ),
                  label: Text(locked ? 'مقفول' : 'عرض'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textOnDark,
                    side: BorderSide(
                      color: AppColors.textOnDark.withValues(alpha: 0.3),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              if (isDownloadable) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: isDownloading ? null : onDownload,
                    icon: isDownloading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.textOnDark,
                            ),
                          )
                        : const Icon(Icons.download_rounded, size: 18),
                    label: Text(
                      isDownloading
                          ? (downloadProgress != null
                                ? '${(downloadProgress! * 100).round()}٪'
                                : '...جاري')
                          : 'تحميل',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyTabState extends StatelessWidget {
  const _EmptyTabState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.textOnDark.withValues(alpha: 0.06),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white38, size: 32),
          ),
          const SizedBox(height: 14),
          Text(
            message,
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 14,
              color: Colors.white60,
            ),
          ),
        ],
      ),
    );
  }
}

/// In-screen viewer for the lecture's PDF (the "المذكرة"), shown beside the
/// video on tablets and in its own tab on phones. Streams the file to the same
/// on-disk cache [PdfViewerScreen] uses (through the authenticated Dio client),
/// then renders it with pdfrx — pinch zoom and scrolling built in. Reading
/// progress is still reported by the full-screen viewer, not from here.
class _PdfPane extends ConsumerStatefulWidget {
  const _PdfPane({super.key, required this.pdf});

  final LecturePdf pdf;

  @override
  ConsumerState<_PdfPane> createState() => _PdfPaneState();
}

class _PdfPaneState extends ConsumerState<_PdfPane> {
  File? _file;
  bool _failed = false;
  double? _progress;
  dio.CancelToken? _cancelToken;

  /// Temporary workaround: the API still sends file URLs on the old domain.
  static String _fixDomain(String url) =>
      url.replaceAll('app.capitaledu.tech', 'api.itaaleem.com');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    super.dispose();
  }

  Future<File> _cacheFile() async {
    final cacheDir = await getTemporaryDirectory();
    return File('${cacheDir.path}/pdf_cache/${widget.pdf.id}.pdf');
  }

  /// True for a non-empty file starting with the `%PDF` magic bytes.
  Future<bool> _isValidPdf(File file) async {
    try {
      if (await file.length() < 8) return false;
      final raf = await file.open();
      try {
        final head = await raf.read(4);
        return head.length == 4 &&
            head[0] == 0x25 &&
            head[1] == 0x50 &&
            head[2] == 0x44 &&
            head[3] == 0x46;
      } finally {
        await raf.close();
      }
    } catch (_) {
      return false;
    }
  }

  Future<void> _load() async {
    setState(() {
      _failed = false;
      _progress = null;
      _file = null;
    });
    File? partial;
    try {
      final target = await _cacheFile();
      if (await target.exists()) {
        if (await _isValidPdf(target)) {
          if (mounted) setState(() => _file = target);
          return;
        }
        await target.delete();
      }

      await target.parent.create(recursive: true);
      partial = File('${target.path}.part');
      _cancelToken = dio.CancelToken();
      await ref
          .read(dioClientProvider)
          .download(
            _fixDomain(widget.pdf.fileUrl),
            partial.path,
            cancelToken: _cancelToken,
            onReceiveProgress: (received, total) {
              if (!mounted || total <= 0) return;
              final next = received / total;
              if (_progress == null || next - _progress! >= 0.01) {
                setState(() => _progress = next);
              }
            },
          );
      if (!await _isValidPdf(partial)) {
        throw const FormatException('downloaded file is not a valid PDF');
      }
      await partial.rename(target.path);
      if (mounted) setState(() => _file = target);
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('[PdfPane] pdf ${widget.pdf.id} failed: $e\n$stackTrace');
      }
      try {
        if (partial != null && await partial.exists()) await partial.delete();
      } catch (_) {}
      if (e is dio.DioException && e.type == dio.DioExceptionType.cancel) {
        return;
      }
      if (mounted) setState(() => _failed = true);
    }
  }

  /// A corrupt file made it past the header check — drop it so the retry
  /// downloads a fresh copy.
  Future<void> _onViewerFailed() async {
    try {
      final cache = await _cacheFile();
      if (await cache.exists()) await cache.delete();
    } catch (_) {}
    if (mounted) setState(() => _failed = true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final student = ref.watch(authControllerProvider).valueOrNull;
    final file = _file;

    final Widget body;
    if (_failed) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, color: scheme.error, size: 40),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'تعذر تحميل المذكرة',
              style: TextStyle(color: scheme.onSurface),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      );
    } else if (file == null) {
      body = Center(
        child: CircularProgressIndicator(
          color: scheme.primary,
          value: _progress,
        ),
      );
    } else {
      body = Stack(
        fit: StackFit.expand,
        children: [
          PdfViewer.file(
            file.path,
            params: PdfViewerParams(
              maxScale: 5,
              backgroundColor: scheme.surfaceContainerHighest,
              onDocumentLoadFinished: (documentRef, loadSucceeded) {
                if (!loadSucceeded) _onViewerFailed();
              },
            ),
          ),
          if (student != null)
            Positioned.fill(
              child: ProtectedWatermark(
                lessonId: null,
                isPdf: true,
                legacy: [
                  ContentWatermark(
                    studentName: student.fullName,
                    studentPhone: student.mobile,
                  ),
                  IdentityWatermark(
                    studentName: student.fullName,
                    studentMobile: student.mobile,
                  ),
                ],
              ),
            ),
        ],
      );
    }
    return ColoredBox(color: scheme.surface, child: body);
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(gradient: context.palette.brandGradient),
      child: Row(
        children: [
          IconButton(
            onPressed: () => context.pop(),
            icon: const BackButtonIcon(),
            color: AppColors.textOnDark,
          ),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppColors.textOnDark,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xxxl),
        ],
      ),
    );
  }
}
