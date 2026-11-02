import 'package:itaaleem/core/device/device_identity_service.dart'
    show appVersionParts;
import 'package:itaaleem/core/error/error_messages.dart';
import 'package:itaaleem/core/error/failure.dart';
import 'package:itaaleem/core/network/api_endpoints.dart';
import 'package:itaaleem/core/network/auth_events.dart';
import 'package:itaaleem/core/network/center_deactivated_events.dart';
import 'package:itaaleem/core/network/device_lock_events.dart';
import 'package:itaaleem/core/storage/secure_storage_service.dart';
import 'package:dio/dio.dart';
import 'package:itaaleem/core/utils/platform_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Attaches the bearer token (if any) from secure storage to every outgoing
/// request, unless the request opts out via `Options(extra: {'skipAuth':
/// true})` (see [skipAuthOptions]) — used for endpoints that must be called
/// before the student has a token, e.g. the public course catalog on the
/// registration screen.
class AuthInterceptor extends Interceptor {
  AuthInterceptor(this._secureStorage);

  final SecureStorageService _secureStorage;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // Never send the student's token to a third-party host (e.g. PDFs
    // hosted on another server) — only to our own API.
    final isOwnApi = options.uri.host == Uri.parse(ApiEndpoints.baseUrl).host;
    if (options.extra['skipAuth'] == true || !isOwnApi) {
      handler.next(options);
      return;
    }
    final token = await _secureStorage.readAuthToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }
}

/// Request options for endpoints that must never carry an `Authorization`
/// header, regardless of whether a token happens to be stored.
final skipAuthOptions = Options(extra: const {'skipAuth': true});

/// `X-Platform: android|ios`, `X-App-Version: {version}` and
/// `X-App-Build: {build}` on every request — authenticated or not
/// ([skipAuthOptions]) — so the server can answer each platform/build on its
/// own (e.g. a per-platform `/public/app-version`).
class AppVersionInterceptor extends Interceptor {
  AppVersionInterceptor({
    String Function()? platform,
    Future<({String version, String build})> Function()? appVersion,
  }) : _platform = platform ?? (() => platformHeaderValue),
       _appVersion = appVersion ?? appVersionParts;

  final String Function() _platform;
  final Future<({String version, String build})> Function() _appVersion;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final (:version, :build) = await _appVersion();
    if (version.isNotEmpty) options.headers['X-App-Version'] = version;
    if (build.isNotEmpty) options.headers['X-App-Build'] = build;
    // Without it the server treats the device as iOS (no purchase UI).
    options.headers['X-Platform'] = _platform();
    handler.next(options);
  }
}

/// On a 429 waits the server's `retry_after` (body) / `Retry-After`
/// (header) seconds — capped, 2s when absent — and retries the request
/// once. A second 429 falls through to [ErrorMappingInterceptor], which
/// shows the server's own message.
class RateLimitRetryInterceptor extends Interceptor {
  RateLimitRetryInterceptor(this._dio);

  final Dio _dio;
  static const _retriedKey = 'rate_limit_retried';
  static const _maxWait = Duration(seconds: 10);

  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;
    if (err.response?.statusCode != 429 || options.extra[_retriedKey] == true) {
      return handler.next(err);
    }
    final wait = _retryAfter(err.response!);
    if (kDebugMode) {
      debugPrint(
        '>>> 429 on ${options.path} — retrying once in ${wait.inSeconds}s',
      );
    }
    await Future<void>.delayed(wait);
    options.extra[_retriedKey] = true;
    try {
      handler.resolve(await _dio.fetch<dynamic>(options));
    } on DioException catch (e) {
      handler.next(e);
    }
  }

  static Duration _retryAfter(Response<dynamic> response) {
    final data = response.data;
    final fromBody = data is Map
        ? num.tryParse('${data['retry_after']}')
        : null;
    final seconds =
        fromBody ?? num.tryParse(response.headers.value('retry-after') ?? '');
    if (seconds == null || seconds <= 0) return const Duration(seconds: 2);
    final wait = Duration(milliseconds: (seconds * 1000).round());
    return wait > _maxWait ? _maxWait : wait;
  }
}

/// Shown when the server rejects this device without a message of its own.
const deviceLockFallbackMessage =
    'حسابك مسجّل على جهاز آخر. تواصل مع إدارة المركز لتغيير الجهاز.';

/// Maps a [DioException] onto the app's [Failure] hierarchy and stashes the
/// result on `error.error`, so callers can do:
///
/// ```dart
/// on DioException catch (e) {
///   final failure = e.error is Failure ? e.error as Failure : const UnknownFailure('...');
/// }
/// ```
class ErrorMappingInterceptor extends Interceptor {
  ErrorMappingInterceptor(
    this._unauthorizedEvents,
    this._centerDeactivatedEvents,
    this._deviceLockEvents,
  );

  final UnauthorizedEvents _unauthorizedEvents;
  final CenterDeactivatedEvents _centerDeactivatedEvents;
  final DeviceLockEvents _deviceLockEvents;

  /// Endpoints that already handle their own 401 locally — login/register
  /// simply mean "wrong credentials" (there's no session to end), and the
  /// startup session restore (`AuthRepositoryImpl.restoreSession`) clears
  /// the token itself on a genuine rejection. Every other 401 means an
  /// established session's token was rejected mid-use, which is what
  /// should trigger the global auto-logout.
  static const _localOnlyUnauthorizedPaths = {
    ApiEndpoints.login,
    ApiEndpoints.register,
    ApiEndpoints.profile,
  };

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final failure = _mapToFailure(err);
    // This device was removed from the account mid-session — a clean logout
    // plus an explanation, not the generic 401 path. Login/register show
    // their own dialog instead (there's no session to end yet).
    if (failure is ServerFailure &&
        failure.isDeviceLock &&
        err.requestOptions.path != ApiEndpoints.login &&
        err.requestOptions.path != ApiEndpoints.register) {
      _deviceLockEvents.notify(failure.message);
      return handler.next(err.copyWith(error: failure));
    }
    // `/admin/*` (the in-app dashboard) may sit behind a different guard
    // server-side — a 401 there means "not an admin", not a dead session.
    if (failure is UnauthorizedFailure &&
        !_localOnlyUnauthorizedPaths.contains(err.requestOptions.path) &&
        !_isAdminPath(err.requestOptions.path) &&
        // app-config takes an optional token: its 401 never ends a session.
        !err.requestOptions.path.startsWith('/app-config')) {
      _unauthorizedEvents.notify();
    }
    handler.next(err.copyWith(error: failure));
  }

  Failure _mapToFailure(DioException err) {
    switch (err.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return const NetworkFailure('الاتصال بطيء، حاول مرة أخرى');
      case DioExceptionType.connectionError:
        return const NetworkFailure('لا يوجد اتصال بالإنترنت');
      case DioExceptionType.cancel:
        return const UnknownFailure('تم إلغاء الطلب');
      case DioExceptionType.badCertificate:
        return const NetworkFailure('تعذر الاتصال الآمن، حاول مرة أخرى');
      case DioExceptionType.badResponse:
        return _mapStatusCode(err);
      case DioExceptionType.unknown:
        return const NetworkFailure('لا يوجد اتصال بالإنترنت');
    }
  }

  /// `code` / `error_code`, top level or nested under `data`/`error`.
  static String? _errorCode(Object? data) {
    if (data is! Map) return null;
    for (final source in [data, data['data'], data['error']]) {
      if (source is Map) {
        final v = source['code'] ?? source['error_code'];
        if (v is String && v.isNotEmpty) return v.toLowerCase();
      }
    }
    return null;
  }

  Failure _mapStatusCode(DioException err) {
    final statusCode = err.response?.statusCode;
    final data = err.response?.data;

    String extractMessage() {
      if (data is Map && data['message'] is String) {
        return ErrorMessages.translate(data['message'] as String);
      }
      return ErrorMessages.generic;
    }

    if (statusCode == 401 || statusCode == 403) {
      final code = _errorCode(data);
      if (code != null && code.startsWith('device')) {
        final raw = data is Map ? data['message'] : null;
        return ServerFailure(
          raw is String && raw.trim().isNotEmpty
              ? raw
              : deviceLockFallbackMessage,
          statusCode: statusCode,
          code: code,
        );
      }
    }

    switch (statusCode) {
      case 401:
        // Login/register: the server's "wrong credentials" text; anywhere
        // else the session itself ended (and the app logs out).
        return UnauthorizedFailure(
          _localOnlyUnauthorizedPaths.contains(err.requestOptions.path)
              ? extractMessage()
              : 'انتهت الجلسة، سجّل الدخول مرة أخرى',
        );
      case 403:
        // `{locked: true}` — content for subscribers only, never an error
        // screen and never "center deactivated".
        if (data is Map && data['locked'] == true) {
          return const ServerFailure(
            lockedForSubscribersMessage,
            statusCode: 403,
            code: 'locked',
          );
        }
        final message = data is Map && data['message'] is String
            ? data['message'] as String
            : 'ليس لديك صلاحية للوصول لهذا المحتوى';
        // A 403 on a subscription request or a locked lecture just means "not
        // subscribed" — never the center being deactivated, whatever the wording.
        final path = err.requestOptions.path;
        final isSubscriptionRelated =
            path.contains('subscription-requests') ||
            path.contains('lectures/') ||
            path.contains('lessons/');
        // A feature switched off (news channel, grade change: "غير متاحة")
        // hides that feature only — never the whole center.
        final isFeatureSwitch = _featureSwitchPaths.any(path.startsWith);
        if (!isSubscriptionRelated &&
            !isFeatureSwitch &&
            !_isAdminPath(path) &&
            _looksLikeCenterDeactivated(message)) {
          _centerDeactivatedEvents.notify();
        }
        return ServerFailure(message, statusCode: 403);
      case 422:
        // The live API nests field errors directly under `data` (e.g.
        // `{"success":false,"data":{"mobile":["..."]},"message":"..."}`),
        // not under a separate `data.errors` key — `errors` is kept as a
        // fallback in case some endpoints ever wrap it that way instead.
        final rawErrors = data is Map ? (data['errors'] ?? data['data']) : null;
        final fieldErrors = <String, List<String>>{};
        if (rawErrors is Map) {
          rawErrors.forEach((key, value) {
            if (value is List) {
              fieldErrors[key.toString()] = value
                  .map((e) => e.toString())
                  .toList();
            }
          });
        }
        final translated = {
          for (final e in fieldErrors.entries)
            e.key: e.value.map((m) => ErrorMessages.translate(m)).toList(),
        };
        final firstField = translated.values
            .expand((l) => l)
            .cast<String?>()
            .firstWhere((_) => true, orElse: () => null);
        return ValidationFailure(
          firstField ?? extractMessage(),
          fieldErrors: translated,
        );
      case 404:
        // Not "too many attempts" — the thing simply isn't there.
        final path = err.requestOptions.path;
        return ServerFailure(
          path.contains('exams')
              ? 'الامتحان غير متوفر'
              : 'المحتوى المطلوب غير متوفر',
          statusCode: 404,
        );
      case 429:
        return const ServerFailure(
          'محاولات كثيرة، انتظر قليلاً',
          statusCode: 429,
        );
      default:
        if (statusCode != null && statusCode >= 500) {
          if (kDebugMode) {
            debugPrint(
              '>>> $statusCode ${err.requestOptions.method} '
              '${err.requestOptions.path} X-Request-Id: '
              '${err.response?.headers.value('x-request-id') ?? '-'}',
            );
          }
          return ServerFailure('حدث خطأ غير متوقع', statusCode: statusCode);
        }
        return ServerFailure(
          // Never let an unrelated error read as a rate limit.
          _withoutRateLimitWording(extractMessage()),
          statusCode: statusCode,
        );
    }
  }

  static String _withoutRateLimitWording(String message) =>
      message == 'محاولات كثيرة، حاول لاحقاً' ? ErrorMessages.generic : message;

  static bool _isAdminPath(String path) => path.startsWith('/admin/');

  /// A 403 on any content endpoint (subjects, exams, banners, …) means the
  /// joined center itself was deactivated server-side — distinct from an
  /// ordinary permission 403 (e.g. "يجب الانضمام لسنتر أولاً" before
  /// joining) — matched loosely against the Arabic/English wording the
  /// backend uses for that specific case.
  static const _featureSwitchPaths = ['/news', '/grade-change', '/app-config'];

  static bool _looksLikeCenterDeactivated(String message) {
    final lower = message.toLowerCase();
    return message.contains('غير متاح') || lower.contains('deactivat');
  }
}

final dioClientProvider = Provider<Dio>((ref) {
  final secureStorage = ref.watch(secureStorageServiceProvider);

  final dio = Dio(
    BaseOptions(
      baseUrl: ApiEndpoints.baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 30),
      headers: const {'Accept': 'application/json'},
    ),
  );

  dio.interceptors.add(AuthInterceptor(secureStorage));
  dio.interceptors.add(AppVersionInterceptor());
  dio.interceptors.add(RateLimitRetryInterceptor(dio));
  dio.interceptors.add(
    ErrorMappingInterceptor(
      ref.watch(unauthorizedEventsProvider),
      ref.watch(centerDeactivatedEventsProvider),
      ref.watch(deviceLockEventsProvider),
    ),
  );

  if (kDebugMode) {
    dio.interceptors.add(
      // Never log headers (Authorization) or bodies (passwords, tokens).
      LogInterceptor(
        request: false,
        requestHeader: false,
        requestBody: false,
        responseHeader: false,
        responseBody: false,
      ),
    );
  }

  return dio;
});
