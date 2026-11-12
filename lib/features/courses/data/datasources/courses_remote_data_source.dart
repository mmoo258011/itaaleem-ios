import 'package:itaaleem/core/network/api_endpoints.dart';
import 'package:itaaleem/core/network/dio_client.dart';
import 'package:itaaleem/features/courses/data/models/available_course_model.dart';
import 'package:itaaleem/features/courses/data/models/course_details_model.dart';
import 'package:itaaleem/features/courses/data/models/course_model.dart';
import 'package:itaaleem/features/courses/data/models/lecture_details_model.dart';
import 'package:itaaleem/features/courses/domain/entities/lecture_details.dart';
import 'package:itaaleem/features/teachers/data/models/teacher_model.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CoursesRemoteDataSource {
  CoursesRemoteDataSource(this._dio);

  final Dio _dio;

  Future<List<CourseModel>> getCourses() async {
    final response = await _dio.get<Map<String, dynamic>>(ApiEndpoints.courses);
    final data = response.data?['data'];
    final rawList = data is List ? data : const [];
    return rawList
        .map((e) => CourseModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<CourseDetailsModel> getCourseDetails(int id) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.courseDetails(id),
    );
    if (kDebugMode) {
      debugPrint('>>> GET /courses/$id raw response: ${response.data}');
    }
    final data = response.data?['data'];
    final body = data is Map<String, dynamic>
        ? data
        : (response.data ?? const <String, dynamic>{});
    return CourseDetailsModel.fromJson(body);
  }

  /// `GET /courses/{id}/exams` — the course's exams plus each one's attempt
  /// status, a richer source than the exam stubs embedded directly in
  /// `GET /courses/{id}`.
  Future<List<CourseExamModel>> getCourseExams(int courseId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.courseExams(courseId),
    );
    if (kDebugMode) {
      debugPrint(
        '>>> GET ${ApiEndpoints.courseExams(courseId)} raw response: '
        '${response.data}',
      );
    }
    final data = response.data?['data'];
    final rawList = data is List ? data : const [];
    return rawList
        .map((e) => CourseExamModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Fallback source for "مدرسو هذه المادة" when `GET /courses/{id}` doesn't
  /// embed any section pivot on its teachers (neither nested on the section
  /// nor as `sections`/`section_ids` on the course-level teacher) — tried
  /// only once that's confirmed empty, since it's an extra request.
  Future<List<TeacherModel>> getPublicTeachers(int courseId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.publicTeachers,
      queryParameters: {'course_id': courseId},
    );
    if (kDebugMode) {
      debugPrint(
        '>>> GET ${ApiEndpoints.publicTeachers}?course_id=$courseId '
        'raw response: ${response.data}',
      );
    }
    final data = response.data?['data'];
    final rawList = data is List ? data : const [];
    return rawList
        .map((e) => TeacherModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<AvailableCourseModel>> getAvailableCourses() async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.availableCourses,
    );
    if (kDebugMode) {
      debugPrint('>>> GET /courses/available raw response: ${response.data}');
    }
    final data = response.data?['data'];
    final rawList = data is List ? data : const [];
    return rawList
        .map((e) => AvailableCourseModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Only ever succeeds for an unlocked lecture — the API 403s otherwise.
  Future<LectureDetailsModel> getLectureDetails(int id) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.lectureDetails(id),
    );
    if (kDebugMode) {
      debugPrint('>>> GET /lectures/$id raw response: ${response.data}');
    }
    return LectureDetailsModel.fromJson(lectureBodyOf(response.data));
  }

  /// `GET /lectures/{id}/playback` — a signed streaming URL for the
  /// lecture's video, meant to replace the plain `video_url` embedded in
  /// `GET /lectures/{id}` whenever this call succeeds. Field names parsed
  /// defensively (not yet confirmed against a populated live response).
  Future<LecturePlaybackInfo> getLecturePlayback(int lectureId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.lecturePlayback(lectureId),
    );
    if (kDebugMode) {
      debugPrint(
        '>>> GET ${ApiEndpoints.lecturePlayback(lectureId)} raw response: '
        '${response.data}',
      );
    }
    final data = response.data?['data'];
    final body = data is Map<String, dynamic>
        ? data
        : response.data ?? const {};
    return _parsePlaybackInfo(body);
  }

  LecturePlaybackInfo _parsePlaybackInfo(Map<String, dynamic> body) {
    String? urlOf(Object? raw) {
      if (raw is String) return raw;
      if (raw is Map) {
        return (raw['url'] ??
                raw['signed_url'] ??
                raw['playback_url'] ??
                raw['src'] ??
                raw['file'])
            ?.toString();
      }
      return null;
    }

    String labelOf(Object? key, Map<dynamic, dynamic>? q) {
      final raw = q?['label'] ?? q?['quality'] ?? q?['name'] ?? key;
      final height = q?['height'] ?? q?['resolution'];
      final label = raw?.toString().trim() ?? '';
      if (label.isNotEmpty) {
        // A bare `720` reads as "720p" in the picker.
        return RegExp(r'^\d{3,4}$').hasMatch(label) ? '${label}p' : label;
      }
      return height == null ? '' : '${height}p';
    }

    final rawUrl =
        body['url'] ??
        body['signed_url'] ??
        body['playback_url'] ??
        body['stream_url'];
    // Either a list (`[{label, url}]`) or a map (`{"720p": url}` /
    // `{"720p": {url}}`), under `qualities` / `sources` / `renditions`.
    final rawQualities =
        body['qualities'] ?? body['sources'] ?? body['renditions'];
    final qualities = <PlaybackQuality>[];
    if (rawQualities is List) {
      for (final q in rawQualities) {
        if (q is! Map) continue;
        final url = ApiEndpoints.playbackUrl(urlOf(q));
        final label = labelOf(null, q);
        if (url != null && label.isNotEmpty) {
          qualities.add(PlaybackQuality(label: label, url: url));
        }
      }
    } else if (rawQualities is Map) {
      for (final entry in rawQualities.entries) {
        final value = entry.value;
        final url = ApiEndpoints.playbackUrl(urlOf(value));
        final label = labelOf(entry.key, value is Map ? value : null);
        if (url != null && label.isNotEmpty) {
          qualities.add(PlaybackQuality(label: label, url: url));
        }
      }
    }
    final rawHeaders = body['headers'];
    final headers = <String, String>{
      if (rawHeaders is Map)
        for (final entry in rawHeaders.entries)
          entry.key.toString(): entry.value.toString(),
    };
    return LecturePlaybackInfo(
      url: ApiEndpoints.playbackUrl(rawUrl?.toString()) ?? '',
      sourceType: body['source_type']?.toString(),
      qualities: qualities,
      headers: headers,
      expiresAt: _expiryOf(body),
    );
  }

  /// `expires_at` as ISO-8601 or a unix timestamp (s / ms), or
  /// `expires_in` seconds from now — else the signed URL's own `expires` /
  /// `Expires` query parameter (Laravel / CloudFront / S3-style signing).
  static DateTime? _expiryOf(Map<String, dynamic> body) {
    DateTime? fromEpoch(num value) => DateTime.fromMillisecondsSinceEpoch(
      (value > 1e12 ? value : value * 1000).toInt(),
    );

    final at = body['expires_at'] ?? body['expiry'];
    if (at is num) return fromEpoch(at);
    if (at is String) {
      final parsed = DateTime.tryParse(at);
      if (parsed != null) return parsed;
      final n = num.tryParse(at);
      if (n != null) return fromEpoch(n);
    }
    final inSeconds = num.tryParse(body['expires_in']?.toString() ?? '');
    if (inSeconds != null) {
      return DateTime.now().add(Duration(seconds: inSeconds.toInt()));
    }
    final url = (body['url'] ?? body['signed_url'] ?? body['playback_url'])
        ?.toString();
    final query = url == null ? null : Uri.tryParse(url)?.queryParameters;
    final expires = num.tryParse(
      (query?['expires'] ?? query?['Expires'] ?? '').toString(),
    );
    return expires == null ? null : fromEpoch(expires);
  }

  /// `GET /lectures/{id}/progress` — the lecture-level saved position, ahead
  /// of playback so the player can offer "متابعة من {time}؟".
  Future<LectureProgress> getLectureProgress(int lectureId) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.lectureProgress(lectureId),
    );
    if (kDebugMode) {
      debugPrint(
        '>>> GET ${ApiEndpoints.lectureProgress(lectureId)} raw response: '
        '${response.data}',
      );
    }
    final data = response.data?['data'];
    final body = data is Map<String, dynamic>
        ? data
        : response.data ?? const {};
    return _parseLectureProgress(body);
  }

  LectureProgress _parseLectureProgress(Map<String, dynamic> body) {
    int asInt(Object? v) => v is num ? v.round() : int.tryParse('$v') ?? 0;
    double asDouble(Object? v) =>
        v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    return LectureProgress(
      positionSeconds: asInt(body['position'] ?? body['position_seconds']),
      durationSeconds: asInt(body['duration'] ?? body['duration_seconds']),
      progressPercentage: asDouble(
        body['progress_percentage'] ?? body['percentage'],
      ),
      isCompleted: body['is_completed'] == true,
    );
  }

  /// `POST /lessons/{id}/progress` — `watched_seconds` (int),
  /// `total_seconds` (int), `percentage` (0–100). Never throws: failures are
  /// only logged.
  Future<void> postLectureProgress(
    int lectureId, {
    required int positionSeconds,
    required int durationSeconds,
    required double progressPercentage,
  }) async {
    final data = {
      'watched_seconds': positionSeconds,
      'total_seconds': durationSeconds,
      'percentage': double.parse(
        progressPercentage.clamp(0, 100).toStringAsFixed(2),
      ),
      // Legacy names, kept so an older server still records progress.
      'position': positionSeconds,
      'duration': durationSeconds,
      'progress_percentage': progressPercentage,
    };
    try {
      final response = await _dio.post<dynamic>(
        ApiEndpoints.lectureProgress(lectureId),
        data: data,
      );
      if (kDebugMode) {
        debugPrint(
          '>>> POST ${ApiEndpoints.lectureProgress(lectureId)} $data → '
          '${response.statusCode}',
        );
      }
    } catch (e) {
      // Progress is best-effort: never surface a failure to the student.
      if (kDebugMode) {
        debugPrint(
          '>>> POST ${ApiEndpoints.lectureProgress(lectureId)} failed '
          '(ignored): $e',
        );
      }
    }
  }

  /// Reports reading progress for a PDF; fire-and-forget from the caller's
  /// perspective (the viewer already knows the current page locally).
  Future<void> postPdfProgress(
    int pdfId, {
    required int lastPage,
    required double readPercentage,
  }) async {
    await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.pdfProgress(pdfId),
      data: {'last_page': lastPage, 'read_percentage': readPercentage},
    );
  }

  /// Returns the API's `message` field so the UI can show the server's own
  /// confirmation text.
  Future<String> requestEnrollment(int courseId) async {
    if (kDebugMode) {
      debugPrint('>>> POST ${ApiEndpoints.courseRequest(courseId)}');
    }
    final response = await _dio.post<Map<String, dynamic>>(
      ApiEndpoints.courseRequest(courseId),
    );
    if (kDebugMode) {
      debugPrint(
        '>>> POST ${ApiEndpoints.courseRequest(courseId)} response '
        '(${response.statusCode}): ${response.data}',
      );
    }
    final message = response.data?['message'];
    return message is String && message.isNotEmpty
        ? message
        : 'تم إرسال طلب الاشتراك بنجاح';
  }
}

final coursesRemoteDataSourceProvider = Provider<CoursesRemoteDataSource>((
  ref,
) {
  final dio = ref.watch(dioClientProvider);
  return CoursesRemoteDataSource(dio);
});

/// The lecture object in a `GET /lessons/{id}` body, under `data`, `lesson`
/// (subject lessons: `{lesson: {...}}`), both, or neither.
Map<String, dynamic> lectureBodyOf(Map<String, dynamic>? raw) {
  var body = raw ?? const <String, dynamic>{};
  for (final key in const ['data', 'lesson']) {
    final inner = body[key];
    if (inner is Map<String, dynamic>) body = inner;
  }
  return body;
}
