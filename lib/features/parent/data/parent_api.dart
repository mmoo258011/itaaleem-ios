import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:itaaleem/core/device/device_identity_service.dart';
import 'package:itaaleem/core/network/api_endpoints.dart';
import 'package:itaaleem/core/network/dio_client.dart'
    show AppVersionInterceptor;
import 'package:itaaleem/core/storage/secure_storage_service.dart';
import 'package:itaaleem/features/parent/data/parent_models.dart';

/// Endpoints of "متابعة ولي الأمر" and "الترمات" — see the API doc.
abstract final class ParentEndpoints {
  static const parentCode = '/parent-code';
  static const parentCodeRegenerate = '/parent-code/regenerate';
  static const subjectsByTerm = '/subjects-by-term';

  static const register = '/parent/register';
  static const login = '/parent/login';
  static const me = '/parent/me';
  static const children = '/parent/children';
  static String child(int id) => '/parent/children/$id';
  static const fcmToken = '/parent/fcm-token';
  static const logout = '/parent/logout';
}

/// A failed call, carrying the server's own `message` as-is.
class ParentApiException implements Exception {
  const ParentApiException(this.message, {this.statusCode, this.retryAfter});

  final String message;
  final int? statusCode;

  /// `retry_after` seconds of a 429.
  final int? retryAfter;

  bool get isUnauthorized => statusCode == 401;
  bool get isNotFound => statusCode == 404;

  /// What the UI shows: the server message, plus the wait on a 429.
  String get displayMessage => statusCode == 429 && retryAfter != null
      ? '$message (حاول بعد $retryAfter ثانية)'
      : message;

  @override
  String toString() => displayMessage;

  static ParentApiException from(Object error) {
    if (error is ParentApiException) return error;
    if (error is! DioException) {
      return const ParentApiException('حدث خطأ ما، حاول مرة أخرى');
    }
    final response = error.response;
    if (response == null) {
      return const ParentApiException('لا يوجد اتصال بالإنترنت');
    }
    final data = response.data;
    final raw = data is Map ? data['message'] : null;
    final status = response.statusCode;
    int? retryAfter;
    if (status == 429) {
      retryAfter =
          (data is Map ? num.tryParse('${data['retry_after']}') : null)
              ?.toInt() ??
          int.tryParse(response.headers.value('retry-after') ?? '');
    }
    return ParentApiException(
      raw is String && raw.trim().isNotEmpty
          ? raw
          : (status != null && status >= 500
                ? 'حدث خطأ غير متوقع'
                : 'حدث خطأ ما، حاول مرة أخرى'),
      statusCode: status,
      retryAfter: retryAfter,
    );
  }
}

/// A bare Dio on the same API (base URL, `Accept`/`Content-Type: json`,
/// `X-App-Version`/`X-Platform`) with no retry and no global error mapping —
/// errors are read here, so the app-wide 401/403 handling of the student
/// client never fires for these endpoints. [readToken] supplies the bearer.
Dio _plainDio(Future<String?> Function() readToken) {
  final dio = Dio(
    BaseOptions(
      baseUrl: ApiEndpoints.baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 30),
      headers: const {'Accept': 'application/json'},
      contentType: Headers.jsonContentType,
    ),
  );
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await readToken();
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
    ),
  );
  dio.interceptors.add(AppVersionInterceptor());
  return dio;
}

/// Student-token calls: the parent code and subjects grouped by term.
class StudentExtrasApi {
  StudentExtrasApi(this._dio);

  final Dio _dio;

  Future<T> _run<T>(Future<T> Function() call) async {
    try {
      return await call();
    } catch (e) {
      throw ParentApiException.from(e);
    }
  }

  Future<ParentCodeInfo> getParentCode() => _run(() async {
    final res = await _dio.get<Map<String, dynamic>>(
      ParentEndpoints.parentCode,
    );
    return ParentCodeInfo.fromJson(res.data ?? const {});
  });

  Future<ParentCodeInfo> regenerateParentCode() => _run(() async {
    final res = await _dio.post<Map<String, dynamic>>(
      ParentEndpoints.parentCodeRegenerate,
    );
    return ParentCodeInfo.fromJson(res.data ?? const {});
  });

  /// The raw `terms` array of `GET /subjects-by-term`.
  Future<List<Map<String, dynamic>>> getSubjectsByTerm() => _run(() async {
    final res = await _dio.get<Map<String, dynamic>>(
      ParentEndpoints.subjectsByTerm,
    );
    final terms = res.data?['terms'];
    if (terms is! List) throw const FormatException('terms missing');
    return terms.whereType<Map<String, dynamic>>().toList();
  });
}

/// The student-token plain Dio (no app-wide 401/403 mapping) — shared by
/// [StudentExtrasApi] and the live-sessions API.
final studentPlainDioProvider = Provider<Dio>((ref) {
  final storage = ref.watch(secureStorageServiceProvider);
  return _plainDio(storage.readAuthToken);
});

final studentExtrasApiProvider = Provider<StudentExtrasApi>((ref) {
  return StudentExtrasApi(ref.watch(studentPlainDioProvider));
});

/// Guardian-token calls (`/parent/*`).
class GuardianApi {
  GuardianApi(this._dio, this._device, {required this.onUnauthorized});

  final Dio _dio;
  final DeviceIdentityService _device;

  /// A 401 on any authenticated guardian call — the session is over.
  final void Function() onUnauthorized;

  Future<T> _run<T>(Future<T> Function() call, {bool authed = true}) async {
    try {
      return await call();
    } catch (e) {
      final error = ParentApiException.from(e);
      if (kDebugMode) {
        debugPrint('>>> guardian api ${error.statusCode}: ${error.message}');
      }
      if (authed && error.isUnauthorized) onUnauthorized();
      throw error;
    }
  }

  Future<GuardianAuthResult> register({
    required String mobile,
    required String parentCode,
    required String password,
    required String passwordConfirmation,
    String? name,
  }) => _run(() async {
    final device = await _device.getIdentity();
    final res = await _dio.post<Map<String, dynamic>>(
      ParentEndpoints.register,
      data: {
        'mobile': mobile,
        'parent_code': parentCode,
        'password': password,
        'password_confirmation': passwordConfirmation,
        if (name != null && name.isNotEmpty) 'name': name,
        'device_id': device.deviceId,
      },
    );
    return GuardianAuthResult.fromJson(res.data ?? const {});
  }, authed: false);

  Future<GuardianAuthResult> login({
    required String mobile,
    required String password,
  }) => _run(() async {
    final device = await _device.getIdentity();
    final res = await _dio.post<Map<String, dynamic>>(
      ParentEndpoints.login,
      data: {
        'mobile': mobile,
        'password': password,
        'device_id': device.deviceId,
      },
    );
    return GuardianAuthResult.fromJson(res.data ?? const {});
  }, authed: false);

  Future<Guardian> me() => _run(() async {
    final res = await _dio.get<Map<String, dynamic>>(ParentEndpoints.me);
    return Guardian.fromJson(
      (res.data?['guardian'] as Map<String, dynamic>?) ?? const {},
    );
  });

  Future<List<ParentChild>> children() => _run(() async {
    final res = await _dio.get<Map<String, dynamic>>(ParentEndpoints.children);
    final list = res.data?['children'];
    return list is List
        ? list
              .whereType<Map<String, dynamic>>()
              .map(ParentChild.fromJson)
              .toList()
        : const [];
  });

  /// Returns the server's success message.
  Future<String> addChild(String parentCode) => _run(() async {
    final res = await _dio.post<Map<String, dynamic>>(
      ParentEndpoints.children,
      data: {'parent_code': parentCode},
    );
    final message = res.data?['message'];
    return message is String ? message : 'تم إضافة الطالب';
  });

  Future<ChildDetails> child(int id) => _run(() async {
    final res = await _dio.get<Map<String, dynamic>>(ParentEndpoints.child(id));
    return ChildDetails.fromJson(res.data ?? const {});
  });

  Future<void> sendFcmToken(String token) => _run(() async {
    await _dio.post<dynamic>(
      ParentEndpoints.fcmToken,
      data: {'fcm_token': token},
    );
  });

  Future<void> logout() => _run(() async {
    await _dio.post<dynamic>(
      ParentEndpoints.logout,
      options: Options(
        sendTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
      ),
    );
  }, authed: false);
}

/// Built by the guardian controller, which owns the 401 reaction.
GuardianApi buildGuardianApi(
  Ref ref, {
  required void Function() onUnauthorized,
}) {
  final storage = ref.read(secureStorageServiceProvider);
  return GuardianApi(
    _plainDio(storage.readGuardianToken),
    ref.read(deviceIdentityServiceProvider),
    onUnauthorized: onUnauthorized,
  );
}
