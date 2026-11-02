import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:itaaleem/core/content/content_policy.dart';
import 'package:itaaleem/features/parent/data/parent_api.dart';

/// Endpoints of "البث المباشر" — see the API doc.
abstract final class LiveEndpoints {
  static const sessions = '/live-sessions';
  static String session(int id) => '/live-sessions/$id';
}

enum LiveStatus { scheduled, live, ended, cancelled }

class LiveSession {
  const LiveSession({
    required this.id,
    required this.title,
    required this.status,
    required this.startsAt,
    this.description,
    this.endsAt,
    this.subjectId,
    this.subjectName,
    this.gradeId,
    this.recordingLessonId,
    this.youtubeVideoId,
    this.watermark,
  });

  final int id;
  final String title;
  final String? description;
  final LiveStatus status;

  /// Device-local time.
  final DateTime? startsAt;
  final DateTime? endsAt;
  final int? subjectId;
  final String? subjectName;
  final int? gradeId;
  final int? recordingLessonId;

  /// Only on `GET /live-sessions/{id}`.
  final String? youtubeVideoId;
  final WatermarkConfig? watermark;

  bool get isLive => status == LiveStatus.live;

  static int? _int(Object? v) =>
      v is num ? v.toInt() : int.tryParse(v?.toString() ?? '');

  static String? _str(Object? v) {
    if (v is! String) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }

  static DateTime? _date(Object? v) =>
      v is String ? DateTime.tryParse(v)?.toLocal() : null;

  factory LiveSession.fromJson(Map<String, dynamic> json) {
    final subject = json['subject'];
    final isLive = json['is_live'] == true;
    final status = switch ('${json['status'] ?? ''}') {
      'live' => LiveStatus.live,
      'ended' => LiveStatus.ended,
      'cancelled' => LiveStatus.cancelled,
      _ => isLive ? LiveStatus.live : LiveStatus.scheduled,
    };
    return LiveSession(
      id: _int(json['id']) ?? 0,
      title: _str(json['title']) ?? 'بث مباشر',
      description: _str(json['description']),
      status: status,
      startsAt: _date(json['starts_at']),
      endsAt: _date(json['ends_at']),
      subjectId: subject is Map ? _int(subject['id']) : null,
      subjectName: subject is Map ? _str(subject['name']) : null,
      gradeId: _int(json['grade_id']),
      recordingLessonId: _int(json['recording_lesson_id']),
      youtubeVideoId: _str(json['youtube_video_id']),
      watermark: WatermarkConfig.tryParse(json['watermark']),
    );
  }
}

/// A failed live call: the HTTP status (if any) and the server's message.
class LiveApiException implements Exception {
  const LiveApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;

  @override
  String toString() => message;

  static LiveApiException from(Object error) {
    if (error is LiveApiException) return error;
    if (error is! DioException) {
      return const LiveApiException('حدث خطأ ما، حاول مرة أخرى');
    }
    final response = error.response;
    if (response == null) {
      return const LiveApiException('لا يوجد اتصال بالإنترنت');
    }
    final data = response.data;
    final raw = data is Map ? data['message'] : null;
    return LiveApiException(
      raw is String && raw.trim().isNotEmpty
          ? raw
          : 'حدث خطأ ما، حاول مرة أخرى',
      statusCode: response.statusCode,
    );
  }
}

/// Runs on the student-token plain Dio, so a 403 here never reaches the
/// app-wide "center deactivated" handling.
class LiveApi {
  LiveApi(this._dio);

  final Dio _dio;

  Future<T> _run<T>(Future<T> Function() call) async {
    try {
      return await call();
    } catch (e) {
      throw LiveApiException.from(e);
    }
  }

  Future<List<LiveSession>> getSessions() => _run(() async {
    final res = await _dio.get<Map<String, dynamic>>(LiveEndpoints.sessions);
    final raw = res.data?['live_sessions'];
    if (raw is! List) throw const FormatException('live_sessions missing');
    return [
      for (final s in raw)
        if (s is Map<String, dynamic>) LiveSession.fromJson(s),
    ];
  });

  Future<LiveSession> getSession(int id) => _run(() async {
    final res = await _dio.get<Map<String, dynamic>>(LiveEndpoints.session(id));
    final raw = res.data?['live_session'];
    if (raw is! Map<String, dynamic>) {
      throw const FormatException('live_session missing');
    }
    return LiveSession.fromJson(raw);
  });

  /// `GET /lessons/{id}` (the existing lesson endpoint) for a recording —
  /// the raw `lesson` object.
  Future<Map<String, dynamic>> getLesson(int id) => _run(() async {
    final res = await _dio.get<dynamic>('/lessons/$id');
    final body = res.data;
    final data = body is Map && body['data'] is Map ? body['data'] : body;
    if (data is! Map) throw const FormatException('lesson missing');
    final lesson = data['lesson'] is Map ? data['lesson'] : data;
    return Map<String, dynamic>.from(lesson as Map);
  });
}

final liveApiProvider = Provider<LiveApi>((ref) {
  return LiveApi(ref.watch(studentPlainDioProvider));
});
