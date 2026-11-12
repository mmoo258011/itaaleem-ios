import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

/// An order's payment page, and the order's uuid when the server gives
/// it (the result page is keyed by it).
class PaymentCheckout {
  const PaymentCheckout({required this.url, this.orderUuid});

  final Uri url;
  final String? orderUuid;

  static final _uuid = RegExp(r'^[A-Za-z0-9\-]{1,64}$');

  /// `null` without a URL; an odd uuid is dropped, never passed on.
  static PaymentCheckout? fromJson(Object? raw) {
    final data = raw is Map && raw['data'] is Map ? raw['data'] : raw;
    if (data is! Map) return null;
    final url = Uri.tryParse(
      (data['checkout_url'] ?? data['url'] ?? '').toString(),
    );
    if (url == null || !url.hasScheme) return null;
    final order = data['order'];
    final uuid = (order is Map ? order['uuid'] : data['uuid'])?.toString();
    return PaymentCheckout(
      url: url,
      orderUuid: uuid != null && _uuid.hasMatch(uuid) ? uuid : null,
    );
  }
}

/// Gets an order's payment page from the server with the student's token.
/// The page never hands the app a URL: only the order id.
abstract class PaymentLinkSource {
  Future<PaymentCheckout> checkoutFor(int orderId);
}

/// `GET /payments/orders/{order_id}/checkout`. Built, not wired: the
/// provider keeps [PendingPaymentLinkSource] until the Fawaterk work is
/// live on the server.
class ApiPaymentLinkSource implements PaymentLinkSource {
  const ApiPaymentLinkSource(this._dio);

  final Dio _dio;

  @override
  Future<PaymentCheckout> checkoutFor(int orderId) async {
    final res = await _dio.get<dynamic>('/payments/orders/$orderId/checkout');
    final checkout = PaymentCheckout.fromJson(res.data);
    if (checkout == null) throw const PaymentUnavailableException();
    return checkout;
  }
}

/// Not connected yet: never yields a link.
class PendingPaymentLinkSource implements PaymentLinkSource {
  const PendingPaymentLinkSource();

  @override
  Future<PaymentCheckout> checkoutFor(int orderId) =>
      Future.error(UnsupportedError('payment link API not connected yet'));
}

class PaymentUnavailableException implements Exception {
  const PaymentUnavailableException();

  static const message = 'تعذر فتح صفحة الدفع، حاول مرة أخرى';

  @override
  String toString() => message;
}

/// The server sends the browser back to
/// `https://{center}.<root>/app#/pay/result?order={uuid}`.
const paymentResultHash = '/pay/result';

/// [uri] is the smart UI's payment result page on [origin].
bool isPaymentReturn(Uri uri, Uri origin) =>
    uri.scheme == 'https' &&
    uri.host.toLowerCase() == origin.host &&
    (!uri.hasPort || uri.port == 443) &&
    uri.userInfo.isEmpty &&
    (uri.path == '/app' || uri.path == '/app/') &&
    uri.fragment.startsWith('$paymentResultHash?order=');

/// The hash to show in the shell after paying for [orderUuid]. The page
/// asks the server for the status itself; the app decides nothing.
String paymentResultRoute(String orderUuid) =>
    '$paymentResultHash?order=$orderUuid';

/// A payment page may be any https site (the gateway), never anything else.
bool isPaymentLinkAllowed(Uri uri) =>
    uri.scheme == 'https' && uri.host.isNotEmpty && uri.userInfo.isEmpty;

/// Opens the payment page in the in-app browser (SFSafariViewController /
/// Chrome Custom Tabs) and, once the student is back in the app, closes it
/// and returns the result page to show in the shell.
class PaymentFlow {
  PaymentFlow({
    required this.links,
    Future<bool> Function(Uri uri)? open,
    Future<void> Function()? close,
    Future<void> Function()? backInApp,
  }) : _open = open ?? _openInAppBrowser,
       _close = close ?? _closeInAppBrowser,
       _backInApp = backInApp ?? _nextResume;

  final PaymentLinkSource links;
  final Future<bool> Function(Uri uri) _open;
  final Future<void> Function() _close;
  final Future<void> Function() _backInApp;

  Completer<String?>? _returned;

  /// Throws [PaymentUnavailableException] when no page could be opened.
  /// Returns the result route to show in the shell, or `null` when the
  /// order's uuid isn't known (the shell then stays where it was).
  Future<String?> pay(int orderId) async {
    final PaymentCheckout checkout;
    try {
      checkout = await links.checkoutFor(orderId);
    } catch (_) {
      throw const PaymentUnavailableException();
    }
    if (!isPaymentLinkAllowed(checkout.url)) {
      throw const PaymentUnavailableException();
    }

    final returned = _returned = Completer<String?>();
    final back = _backInApp();
    if (!await _open(checkout.url)) {
      _returned = null;
      throw const PaymentUnavailableException();
    }
    final fromLink = await Future.any<String?>([
      back.then((_) => null),
      returned.future,
    ]);
    _returned = null;
    await _close();
    final uuid = checkout.orderUuid;
    return fromLink ?? (uuid == null ? null : paymentResultRoute(uuid));
  }

  /// The browser reached the result page and the OS handed that link to
  /// the app (App Links, once added): its hash is what the shell shows.
  bool onReturnLink(Uri uri, Uri origin) {
    final returned = _returned;
    if (returned == null || !isPaymentReturn(uri, origin)) return false;
    if (!returned.isCompleted) returned.complete(uri.fragment);
    return true;
  }

  static Future<bool> _openInAppBrowser(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.inAppBrowserView);

  static Future<void> _closeInAppBrowser() async {
    try {
      // SFSafariViewController closes; Custom Tabs is already gone once
      // the app is back in front.
      await closeInAppWebView();
    } catch (_) {}
  }

  /// Completes when the app comes back to the foreground after leaving it.
  static Future<void> _nextResume() {
    final done = Completer<void>();
    var left = false;
    late final AppLifecycleListener listener;
    listener = AppLifecycleListener(
      onHide: () => left = true,
      onResume: () {
        if (!left || done.isCompleted) return;
        listener.dispose();
        done.complete();
      },
    );
    return done.future;
  }
}
