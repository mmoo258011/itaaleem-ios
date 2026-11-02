import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:itaaleem/app/router/app_router.dart' show subjectsPath;
import 'package:itaaleem/core/theme/app_spacing.dart';
import 'package:itaaleem/core/utils/platform_utils.dart';
import 'package:itaaleem/core/widgets/content_watermark.dart';
import 'package:itaaleem/core/widgets/secure_screen.dart';
import 'package:itaaleem/core/widgets/server_watermark.dart';
import 'package:itaaleem/features/auth/presentation/providers/auth_controller.dart';
import 'package:itaaleem/features/courses/presentation/widgets/players/lecture_playback_handle.dart';
import 'package:itaaleem/features/courses/presentation/widgets/players/player_selection_sheet.dart';
import 'package:itaaleem/features/live/data/live_api.dart';
import 'package:itaaleem/features/live/presentation/live_providers.dart';
import 'package:itaaleem/features/subjects/data/models/subject_json_mapper.dart';
import 'package:itaaleem/features/subjects/presentation/screens/lesson_detail_screen.dart';

/// One live session (`GET /live-sessions/{id}`): the YouTube player with
/// the lecture watermark while live, a countdown while scheduled, an
/// "ended / cancelled" notice (with "شوف التسجيل" when there's a recording),
/// or the error.
class LiveSessionScreen extends ConsumerStatefulWidget {
  const LiveSessionScreen({super.key, required this.sessionId, this.subjectId});

  final int sessionId;

  /// From the list, when known — for the subscription 403's button.
  final int? subjectId;

  @override
  ConsumerState<LiveSessionScreen> createState() => _LiveSessionScreenState();
}

class _LiveSessionScreenState extends ConsumerState<LiveSessionScreen> {
  LiveSession? _session;
  LiveApiException? _error;
  bool _loading = true;
  bool _fullscreen = false;
  bool _openingRecording = false;
  Timer? _ticker;
  Timer? _poll;
  final _playerKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _poll?.cancel();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final s = await ref.read(liveApiProvider).getSession(widget.sessionId);
      if (!mounted) return;
      setState(() {
        _session = s;
        _error = null;
        _loading = false;
      });
      _schedule(s);
    } catch (e) {
      if (!mounted) return;
      // A failed background refresh keeps the countdown on screen.
      if (silent && _session != null) return;
      setState(() {
        _error = LiveApiException.from(e);
        _loading = false;
      });
    }
  }

  /// Scheduled: tick the countdown every second; once `starts_at` passes,
  /// re-fetch every 30 seconds until the session is no longer scheduled.
  void _schedule(LiveSession s) {
    _ticker?.cancel();
    _poll?.cancel();
    if (s.status != LiveStatus.scheduled) return;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      final start = s.startsAt;
      if (_poll == null && (start == null || !start.isAfter(DateTime.now()))) {
        _poll = Timer.periodic(
          const Duration(seconds: 30),
          (_) => _load(silent: true),
        );
        _load(silent: true);
      }
    });
  }

  Future<void> _openRecording(LiveSession s) async {
    final id = s.recordingLessonId;
    if (id == null || _openingRecording) return;
    setState(() => _openingRecording = true);
    try {
      final raw = await ref.read(liveApiProvider).getLesson(id);
      if (!mounted) return;
      final subjectId =
          (raw['subject_id'] is num
              ? (raw['subject_id'] as num).toInt()
              : null) ??
          s.subjectId ??
          0;
      context.push(
        '/lessons/$id',
        extra: LessonDetailNavArgs(
          lesson: subjectLessonFromJson(raw),
          subjectId: subjectId,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            LiveApiException.from(e).message,
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _openingRecording = false);
    }
  }

  void _goToSubject() {
    final id = widget.subjectId;
    if (id != null) {
      context.push('/subject-detail/$id');
    } else {
      context.push(subjectsPath);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _session;
    if (s != null && s.isLive && s.youtubeVideoId != null) {
      return _buildLive(context, s);
    }
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        title: Text(
          s?.title ?? 'البث المباشر',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontFamily: 'Cairo'),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: _loading
                ? const CircularProgressIndicator()
                : _error != null
                ? _buildError(context, _error!)
                : _buildStatus(context, s!),
          ),
        ),
      ),
    );
  }

  Widget _message(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? body,
    List<Widget> actions = const [],
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 64, color: scheme.primary),
        const SizedBox(height: AppSpacing.base),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: scheme.onSurface,
          ),
        ),
        if (body != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 14,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
        for (final a in actions) ...[
          const SizedBox(height: AppSpacing.base),
          SizedBox(width: double.infinity, child: a),
        ],
      ],
    );
  }

  Widget _buildError(BuildContext context, LiveApiException e) {
    void back() => context.canPop() ? context.pop() : context.go('/home');
    if (e.isNotFound) {
      return _message(
        context,
        icon: Icons.search_off_rounded,
        title: 'البث غير موجود',
        actions: [FilledButton(onPressed: back, child: const Text('رجوع'))],
      );
    }
    if (e.isForbidden) {
      // Either the feature is off or the student lacks the subject; the
      // server's message says which. The button only leads to the subject
      // page (its existing activation card) — no purchase wording here.
      final featureOff = e.message.contains('غير متاح');
      return _message(
        context,
        icon: Icons.lock_outline_rounded,
        // iOS: no subscription wording at all (App Store rules).
        title: !featureOff && PlatformUtils.hideSubscriptions
            ? 'البث ده متاح لطلاب المادة بس — تواصل مع المركز'
            : e.message,
        actions: [
          if (!featureOff)
            FilledButton(
              onPressed: _goToSubject,
              child: const Text('صفحة المادة'),
            ),
          OutlinedButton(onPressed: back, child: const Text('رجوع')),
        ],
      );
    }
    return _message(
      context,
      icon: Icons.wifi_off_rounded,
      title: e.message,
      actions: [
        FilledButton(onPressed: _load, child: const Text('إعادة المحاولة')),
      ],
    );
  }

  Widget _buildStatus(BuildContext context, LiveSession s) {
    switch (s.status) {
      case LiveStatus.ended:
      case LiveStatus.cancelled:
        final ended = s.status == LiveStatus.ended;
        return _message(
          context,
          icon: ended ? Icons.stop_circle_outlined : Icons.event_busy_rounded,
          title: ended ? 'البث انتهى' : 'البث اتلغى',
          body: s.title,
          actions: [
            if (s.recordingLessonId != null)
              FilledButton.icon(
                onPressed: _openingRecording ? null : () => _openRecording(s),
                icon: const Icon(Icons.play_circle_outline_rounded),
                label: const Text('شوف التسجيل'),
              ),
          ],
        );
      case LiveStatus.live:
        // Live but no video id yet: treat like "about to start".
        return _message(
          context,
          icon: Icons.live_tv_rounded,
          title: 'البث بيبدأ دلوقتي',
          body: s.title,
          actions: [FilledButton(onPressed: _load, child: const Text('تحديث'))],
        );
      case LiveStatus.scheduled:
        final start = s.startsAt;
        final left = start?.difference(DateTime.now());
        final waiting = left == null || left.isNegative;
        return _message(
          context,
          icon: Icons.schedule_rounded,
          title: start == null
              ? 'البث لسه ما بدأش'
              : 'البث يبدأ ${formatLiveWhen(start)}',
          body: [
            s.title,
            if (s.subjectName != null) s.subjectName!,
            if (s.description != null) s.description!,
          ].join('\n'),
          actions: [
            Text(
              waiting ? 'في انتظار بدء البث…' : _countdown(left),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: waiting ? 15 : 32,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.primary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        );
    }
  }

  static String _countdown(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final days = d.inDays;
    final hms =
        '${two(d.inHours.remainder(24))}:${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}';
    return days > 0 ? '$days يوم  $hms' : hms;
  }

  /// Same player, watermark widget and screen protection as the lectures.
  Widget _buildLive(BuildContext context, LiveSession s) {
    final student = ref.watch(authControllerProvider).valueOrNull;
    final player = YoutubeMultiPlayer(
      key: _playerKey,
      rawIdOrUrl: s.youtubeVideoId!,
      startAt: Duration.zero,
      title: s.title,
      onReady: (LecturePlaybackHandle handle) {},
      onEnded: () => _load(silent: true),
      onFullscreenChanged: (value) {
        if (mounted) setState(() => _fullscreen = value);
      },
    );
    return SecureScreen(
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: _fullscreen
            ? null
            : AppBar(
                backgroundColor: Colors.black,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                title: Text(
                  s.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 15),
                ),
              ),
        body: SafeArea(
          top: !_fullscreen,
          bottom: !_fullscreen,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                fit: _fullscreen ? FlexFit.tight : FlexFit.loose,
                child: Align(
                  heightFactor: _fullscreen ? null : 1,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      _fullscreen ? SizedBox.expand(child: player) : player,
                      if (student != null)
                        Positioned.fill(
                          child: ProtectedWatermark(
                            lessonId: null,
                            config: s.watermark,
                            legacy: [
                              ContentWatermark(
                                studentName: student.fullName,
                                studentPhone: student.mobile,
                                opacity: 0.06,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
