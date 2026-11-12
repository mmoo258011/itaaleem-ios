import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:itaaleem/core/network/api_endpoints.dart';
import 'package:itaaleem/core/utils/safe_url.dart';

/// A one-time sign-in to a web page on our domain: the app POSTs [ticket]
/// to [url] from inside the WebView (never in a URL, never the token), and
/// the server redirects to `next`.
class WebHandoff {
  const WebHandoff({required this.ticket, required this.url});

  final String ticket;
  final Uri url;

  static const headers = {'Content-Type': 'application/x-www-form-urlencoded'};

  /// Form body: the ticket and where to land (path + query of [target]).
  Uint8List body(Uri target) => Uint8List.fromList(
    utf8.encode(
      'ticket=${Uri.encodeQueryComponent(ticket)}'
      '&next=${Uri.encodeQueryComponent(nextOf(target))}',
    ),
  );

  static String nextOf(Uri target) {
    final path = target.path.isEmpty ? '/' : target.path;
    return target.hasQuery ? '$path?${target.query}' : path;
  }

  /// `null` unless the ticket is for exactly `https://<target host>/web/handoff`:
  /// any other URL would get the user's session.
  static WebHandoff? fromJson(Object? raw, Uri target) {
    final data = raw is Map && raw['data'] is Map ? raw['data'] : raw;
    if (data is! Map) return null;
    final ticket = data['ticket'];
    final url = Uri.tryParse(data['url']?.toString() ?? '');
    if (ticket is! String || ticket.isEmpty || url == null) return null;
    final ok =
        isInAppWebAllowed(url) &&
        url.host.toLowerCase() == target.host.toLowerCase() &&
        url.path == '/web/handoff' &&
        !url.hasQuery &&
        !url.hasFragment;
    return ok ? WebHandoff(ticket: ticket, url: url) : null;
  }
}

class WebHandoffException implements Exception {
  const WebHandoffException({required this.offline});

  /// No connection / timeout (else the server refused or sent a bad ticket).
  final bool offline;

  @override
  String toString() => 'WebHandoffException(offline: $offline)';
}

Future<WebHandoff> requestWebHandoff(Dio dio, Uri target) async {
  try {
    final res = await dio.post<dynamic>(
      ApiEndpoints.webHandoff,
      data: {'url': target.toString()},
    );
    final handoff = WebHandoff.fromJson(res.data, target);
    if (handoff == null) throw const WebHandoffException(offline: false);
    return handoff;
  } on DioException catch (e) {
    throw WebHandoffException(
      offline:
          e.response == null &&
          (e.type == DioExceptionType.connectionError ||
              e.type == DioExceptionType.connectionTimeout ||
              e.type == DioExceptionType.receiveTimeout ||
              e.type == DioExceptionType.sendTimeout ||
              e.type == DioExceptionType.unknown),
    );
  }
}

/// `https://<api host>/center` — the center's full Filament panel.
Uri centerPanelUrl() => Uri(
  scheme: 'https',
  host: Uri.parse(ApiEndpoints.baseUrl).host,
  path: '/center',
);
