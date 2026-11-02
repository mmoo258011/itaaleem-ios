import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:itaaleem/core/network/api_endpoints.dart';
import 'package:itaaleem/core/network/dio_client.dart';
import 'package:itaaleem/features/app_config/app_config_providers.dart';
import 'package:itaaleem/features/center/presentation/providers/center_providers.dart';

class GradeRef {
  const GradeRef({required this.id, required this.name});

  final int id;
  final String name;

  static GradeRef? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final name = raw['name'];
    if (id is! num || name is! String || name.trim().isEmpty) return null;
    return GradeRef(id: id.toInt(), name: name.trim());
  }
}

enum GradeChangeStatus { pending, approved, rejected, cancelled, reverted }

/// One "تغيير الكورس" request (`request` in every grade-change answer).
class GradeChangeRequest {
  const GradeChangeRequest({
    required this.id,
    required this.status,
    this.fromGrade,
    this.toGrade,
    this.reason,
    this.rejectReason,
    this.createdAt,
    this.reviewedAt,
  });

  final int id;
  final GradeChangeStatus status;
  final GradeRef? fromGrade;
  final GradeRef? toGrade;
  final String? reason;
  final String? rejectReason;
  final DateTime? createdAt;
  final DateTime? reviewedAt;

  bool get isPending => status == GradeChangeStatus.pending;

  /// Accepts the request itself or `{request: …}`; `null` for anything
  /// without an id and a known status.
  static GradeChangeRequest? fromJson(Object? raw) {
    final json = raw is Map && raw['request'] is Map ? raw['request'] : raw;
    if (json is! Map) return null;
    final id = json['id'];
    final status = GradeChangeStatus.values
        .where((s) => s.name == '${json['status']}'.toLowerCase())
        .firstOrNull;
    if (id is! num || status == null) return null;
    String? str(Object? v) =>
        v is String && v.trim().isNotEmpty ? v.trim() : null;
    DateTime? date(Object? v) =>
        v is String ? DateTime.tryParse(v)?.toLocal() : null;
    return GradeChangeRequest(
      id: id.toInt(),
      status: status,
      fromGrade: GradeRef.fromJson(json['from_grade']),
      toGrade: GradeRef.fromJson(json['to_grade']),
      reason: str(json['reason']),
      rejectReason: str(json['reject_reason']),
      createdAt: date(json['created_at']),
      reviewedAt: date(json['reviewed_at']),
    );
  }
}

/// `GET /grade-change/options`.
class GradeChangeOptions {
  const GradeChangeOptions({
    this.currentGrade,
    this.options = const [],
    this.pendingRequest,
  });

  final GradeRef? currentGrade;
  final List<GradeRef> options;
  final GradeChangeRequest? pendingRequest;

  factory GradeChangeOptions.fromJson(Object? raw) {
    final json = raw is Map ? raw : const {};
    final list = json['options'];
    return GradeChangeOptions(
      currentGrade: GradeRef.fromJson(json['current_grade']),
      options: [
        if (list is List)
          for (final o in list) ?GradeRef.fromJson(o),
      ],
      pendingRequest: GradeChangeRequest.fromJson(json['pending_request']),
    );
  }
}

/// The feature is off for this student (403) or the server lacks it (404):
/// the menu entry disappears.
class GradeChangeUnavailable implements Exception {
  const GradeChangeUnavailable();
}

/// A 422 (or 429): [message] is the server's Arabic text, shown as is.
class GradeChangeRefused implements Exception {
  const GradeChangeRefused(this.message);

  final String message;

  @override
  String toString() => message;
}

class GradeChangeApi {
  GradeChangeApi(this._dio);

  final Dio _dio;

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (code == 403 || code == 404) throw const GradeChangeUnavailable();
      if (code == 422 || code == 429) {
        throw GradeChangeRefused(
          _serverMessage(e.response?.data) ??
              (code == 429
                  ? 'طلبات كتير في وقت قصير، استنى شوية وحاول تاني'
                  : 'تعذر إرسال الطلب'),
        );
      }
      rethrow;
    }
  }

  Future<GradeChangeOptions> options() => _guard(() async {
    final r = await _dio.get<Object?>(ApiEndpoints.gradeChangeOptions);
    return GradeChangeOptions.fromJson(r.data);
  });

  Future<GradeChangeRequest?> status() => _guard(() async {
    final r = await _dio.get<Object?>(ApiEndpoints.gradeChangeStatus);
    return GradeChangeRequest.fromJson(r.data);
  });

  Future<GradeChangeRequest?> submit(int toGradeId, {String? reason}) =>
      _guard(() async {
        final trimmed = reason?.trim();
        final r = await _dio.post<Object?>(
          ApiEndpoints.gradeChange,
          data: {
            'to_grade_id': toGradeId,
            if (trimmed != null && trimmed.isNotEmpty) 'reason': trimmed,
          },
        );
        return GradeChangeRequest.fromJson(r.data);
      });

  Future<GradeChangeRequest?> cancel() => _guard(() async {
    final r = await _dio.post<Object?>(ApiEndpoints.gradeChangeCancel);
    return GradeChangeRequest.fromJson(r.data);
  });
}

/// `message`, else the first field error, from a Laravel error body.
String? _serverMessage(Object? data) {
  if (data is! Map) return null;
  final errors = data['errors'] ?? data['data'];
  if (errors is Map) {
    for (final v in errors.values) {
      if (v is List && v.isNotEmpty && v.first is String) return v.first;
      if (v is String && v.trim().isNotEmpty) return v;
    }
  }
  final m = data['message'];
  return m is String && m.trim().isNotEmpty ? m.trim() : null;
}

final gradeChangeApiProvider = Provider<GradeChangeApi>(
  (ref) => GradeChangeApi(ref.watch(dioClientProvider)),
);

final gradeChangeOptionsProvider =
    FutureProvider.autoDispose<GradeChangeOptions>(
      (ref) => ref.read(gradeChangeApiProvider).options(),
    );

/// The student's latest request from the app (`null` = none yet).
final gradeChangeStatusProvider =
    FutureProvider.autoDispose<GradeChangeRequest?>(
      (ref) => ref.read(gradeChangeApiProvider).status(),
    );

/// Whether «تغيير الكورس» (the request flow) shows: `features.grade_change`
/// on, in a center, and `options` answers. Anything else → `false`, quietly.
final gradeChangeAvailableProvider = FutureProvider.autoDispose<bool>((
  ref,
) async {
  final config = ref.watch(currentAppConfigProvider);
  if (configFeature(config, 'grade_change') != true) return false;
  final membership = ref.watch(centerMembershipProvider).valueOrNull;
  if (membership == null) return false;
  try {
    await ref.watch(gradeChangeOptionsProvider.future);
    return true;
  } catch (_) {
    return false;
  }
});
