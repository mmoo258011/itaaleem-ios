import 'package:itaaleem/core/network/api_endpoints.dart';
import 'package:itaaleem/features/grade_change/grade_change_api.dart';
import 'package:itaaleem/core/network/dio_client.dart';
import 'package:itaaleem/features/center/data/models/center_json_mapper.dart';
import 'package:itaaleem/features/center/domain/entities/center_model.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Raw Dio calls against the `/centers` endpoints — not documented in
/// APP_SPEC.md, but confirmed live against the backend directly (paginated
/// `{items, meta}` list, detail with `grades`, join/leave by grade).
class CentersRemoteDataSource {
  CentersRemoteDataSource(this._dio);

  final Dio _dio;

  /// `GET /centers?code=` — the center matching this exact code, or `null`
  /// when there isn't one.
  ///
  /// The live response for this endpoint is a bare `{"centers": [...]}` —
  /// not the `{"data": {"items": [...]}}` envelope [getCenterDetails] and
  /// the rest of this class's calls use — so `centers` is tried first, with
  /// the usual `data`/`data.items` shapes kept as fallbacks in case that
  /// ever changes.
  Future<CenterModel?> getCenterByCode(String code) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.centers,
      queryParameters: {'code': code},
    );
    if (kDebugMode) {
      debugPrint('Search URL: ${response.requestOptions.uri}');
      debugPrint('Response status: ${response.statusCode}');
      debugPrint('Response body: ${response.data}');
    }
    final body = response.data;
    final data = body?['data'];
    final rawList =
        _asList(body?['centers']) ??
        _asList(data) ??
        _asList(data is Map<String, dynamic> ? data['items'] : null) ??
        const [];
    if (rawList.isEmpty) return null;
    return centerModelFromJson(rawList.first as Map<String, dynamic>);
  }

  static List<dynamic>? _asList(Object? value) => value is List ? value : null;

  Future<CenterModel> getCenterDetails(int id) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.centerDetails(id),
    );
    if (kDebugMode) {
      debugPrint(
        '>>> GET ${ApiEndpoints.centerDetails(id)} raw response: ${response.data}',
      );
    }
    // `{center: …}` (the live shape), `data` or the bare body.
    return centerModelFromJson(_unwrapCenter(response.data));
  }

  /// `GET /center/support-info` — the raw center JSON for the student's
  /// own center (`data.center`, `data` or the bare body). Raw so the caller
  /// can cache it as-is.
  Future<Map<String, dynamic>> getSupportInfoJson() async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.centerSupportInfo,
    );
    return _unwrapCenter(response.data);
  }

  /// `GET /centers/{id}` as raw JSON (see [getSupportInfoJson]).
  Future<Map<String, dynamic>> getCenterDetailsJson(int id) async {
    final response = await _dio.get<Map<String, dynamic>>(
      ApiEndpoints.centerDetails(id),
    );
    return _unwrapCenter(response.data);
  }

  static Map<String, dynamic> _unwrapCenter(Map<String, dynamic>? body) {
    final data = body?['data'];
    final map = data is Map<String, dynamic>
        ? data
        : (body ?? const <String, dynamic>{});
    final center = map['center'];
    if (center is Map<String, dynamic>) {
      // Contact fields sometimes sit next to `center` rather than inside it.
      return {...map, ...center};
    }
    return map;
  }

  /// Joins (or, re-confirmed with a different grade, upserts) the center
  /// membership, by [code] — the backend resolves the center from its
  /// `code`, not from an id in the URL. [gradeId] is omitted for centers
  /// with no grades to choose from. Throws [DioException] on failure — the
  /// caller decides how to surface it.
  Future<CenterJoinResult> joinCenter({
    required String code,
    int? gradeId,
  }) async {
    if (kDebugMode) {
      debugPrint(
        '>>> POST ${ApiEndpoints.centerJoin} code=$code grade_id=$gradeId',
      );
    }
    final res = await _dio.post<Object?>(
      ApiEndpoints.centerJoin,
      data: {'code': code, if (gradeId != null) 'grade_id': gradeId},
    );
    return CenterJoinResult.fromJson(res.data);
  }

  Future<void> leaveCenter() async {
    await _dio.post<Map<String, dynamic>>(ApiEndpoints.centersLeave);
  }
}

/// What `POST /centers/join` says beyond success. Rejoining with a
/// different grade (grade change on for the center) keeps the old grade and
/// opens a pending grade-change [request] instead, with a [notice] for the
/// student. Both are `null` for a plain join.
class CenterJoinResult {
  const CenterJoinResult({this.notice, this.request});

  final String? notice;
  final GradeChangeRequest? request;

  /// Accepts the body directly or wrapped in `data`.
  factory CenterJoinResult.fromJson(Object? raw) {
    final json = raw is Map && raw['data'] is Map ? raw['data'] : raw;
    if (json is! Map) return const CenterJoinResult();
    final notice = json['notice'];
    return CenterJoinResult(
      notice: notice is String && notice.trim().isNotEmpty
          ? notice.trim()
          : null,
      request: GradeChangeRequest.fromJson(json['grade_change_request']),
    );
  }
}

final centersRemoteDataSourceProvider = Provider<CentersRemoteDataSource>((
  ref,
) {
  final dio = ref.watch(dioClientProvider);
  return CentersRemoteDataSource(dio);
});
