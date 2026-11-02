import 'package:dio/dio.dart';

/// Sealed hierarchy of failures the app can surface to presentation code.
///
/// Repositories never throw into presentation — they return
/// `Future<(Failure?, T?)>`-shaped results (see [Result]) so the UI layer
/// can exhaustively `switch` over every failure kind without a try/catch.
sealed class Failure {
  const Failure(this.message);

  /// Human-readable (already localized where possible) message.
  final String message;
}

/// The server responded with an error (4xx/5xx) that isn't one of the more
/// specific cases below (validation, unauthorized).
final class ServerFailure extends Failure {
  const ServerFailure(super.message, {this.statusCode, this.code});

  final int? statusCode;

  /// The API's machine-readable `code` when it sends one (e.g.
  /// `device_limit`).
  final String? code;

  /// The account is locked to another device (`device_limit`, or any other
  /// `device_*` code on a 401/403).
  bool get isDeviceLock => code != null && code!.startsWith('device');

  /// 403 `{locked: true}` — the content is for subscribers only.
  bool get isContentLocked => code == 'locked';
}

const lockedForSubscribersMessage = 'هذا المحتوى متاح للمشتركين فقط';

/// Whether [error] is a 404 — e.g. a subject whose term the center hid.
bool isNotFoundError(Object error) {
  final f = failureOf(error);
  return f is ServerFailure && f.statusCode == 404;
}

/// Whether [error] is a 403 `{locked: true}`.
bool isLockedContentError(Object error) {
  final f = failureOf(error);
  return f is ServerFailure && f.isContentLocked;
}

/// No connectivity, DNS failure, timeout, socket exception, etc. — the
/// request never got a response from the server at all.
final class NetworkFailure extends Failure {
  const NetworkFailure(super.message);
}

/// HTTP 422-style validation failure, with field-level error messages as
/// returned by the Laravel API (`{"errors": {"phone": ["..."]}}`).
final class ValidationFailure extends Failure {
  const ValidationFailure(super.message, {this.fieldErrors = const {}});

  final Map<String, List<String>> fieldErrors;
}

/// HTTP 401 — missing/expired/invalid auth token. Presentation should react
/// by logging the user out and redirecting to `/login`.
final class UnauthorizedFailure extends Failure {
  const UnauthorizedFailure(super.message);
}

/// Any failure that doesn't fit the categories above (unexpected
/// exceptions, decoding errors, etc.).
final class UnknownFailure extends Failure {
  const UnknownFailure(super.message);
}

/// Unwraps the [Failure] a [DioException] carries (stashed on `.error` by
/// `ErrorMappingInterceptor`), for call sites that don't go through a
/// repository's try/catch — e.g. a `FutureProvider` whose thrown
/// [DioException] surfaces as-is in `AsyncValue.error`.
Failure failureOf(Object error) {
  if (error is Failure) return error;
  if (error is DioException && error.error is Failure) {
    return error.error as Failure;
  }
  return const UnknownFailure('حدث خطأ ما، حاول مرة أخرى');
}
