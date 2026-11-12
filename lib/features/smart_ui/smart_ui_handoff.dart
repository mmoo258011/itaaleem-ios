import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:itaaleem/core/network/api_endpoints.dart';
import 'package:itaaleem/features/smart_ui/smart_ui_access.dart';

/// A one-time sign-in to the smart UI: the app POSTs [ticket] to [url] from
/// inside the WebView, so the ticket never appears in a URL (history, logs,
/// Referer).
class SmartUiHandoff {
  const SmartUiHandoff({required this.ticket, required this.url});

  final String ticket;
  final Uri url;

  /// Form body for `POST /app/handoff`: the ticket and the hash route
  /// ([next]) to land on.
  Uint8List body(String next) => Uint8List.fromList(
    utf8.encode(
      'ticket=${Uri.encodeQueryComponent(ticket)}'
      '&next=${Uri.encodeQueryComponent(next)}',
    ),
  );

  static const headers = {'Content-Type': 'application/x-www-form-urlencoded'};

  /// `null` unless the response is a ticket for exactly
  /// `https://{center}.<root>/app/handoff`: a handoff URL on any other host
  /// would hand the student's session to it.
  static SmartUiHandoff? fromJson(Object? raw, SmartUiAccess access) {
    final data = raw is Map && raw['data'] is Map ? raw['data'] : raw;
    if (data is! Map) return null;
    final ticket = data['ticket'];
    final url = Uri.tryParse(data['url']?.toString() ?? '');
    if (ticket is! String || ticket.isEmpty || url == null) return null;
    final origin = access.origin;
    final ok =
        url.scheme == 'https' &&
        url.host.toLowerCase() == origin.host &&
        (!url.hasPort || url.port == 443) &&
        url.userInfo.isEmpty &&
        url.path == '/app/handoff' &&
        !url.hasQuery &&
        !url.hasFragment;
    return ok ? SmartUiHandoff(ticket: ticket, url: url) : null;
  }
}

/// Why a handoff didn't produce a ticket.
enum HandoffFailure {
  /// No connection / timeout: show the offline screen, try again later.
  offline,

  /// The server answered but gave no usable ticket (smart UI switched off,
  /// 4xx/5xx, a bad URL): fall back to the native app.
  refused,
}

class HandoffException implements Exception {
  const HandoffException(this.reason);

  final HandoffFailure reason;

  @override
  String toString() => 'HandoffException($reason)';
}

Future<SmartUiHandoff> requestHandoff(Dio dio, SmartUiAccess access) async {
  try {
    final res = await dio.post<dynamic>(ApiEndpoints.smartUiHandoff);
    final handoff = SmartUiHandoff.fromJson(res.data, access);
    if (handoff == null) throw const HandoffException(HandoffFailure.refused);
    return handoff;
  } on DioException catch (e) {
    final offline =
        e.response == null &&
        (e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.sendTimeout ||
            e.type == DioExceptionType.unknown);
    throw HandoffException(
      offline ? HandoffFailure.offline : HandoffFailure.refused,
    );
  }
}

/// A hash route the smart UI may be sent to (`next`, a push target):
/// `/` followed by path characters, and an optional plain query
/// (`?tab=exams`).
final _safeHash = RegExp(
  r'^/[A-Za-z0-9/_\-]*(\?[A-Za-z0-9_\-]+=[A-Za-z0-9_\-]*(&[A-Za-z0-9_\-]+=[A-Za-z0-9_\-]*)*)?$',
);

String safeSmartHash(String? hash) =>
    hash != null && _safeHash.hasMatch(hash) && !hash.contains('//')
    ? hash
    : '/';
