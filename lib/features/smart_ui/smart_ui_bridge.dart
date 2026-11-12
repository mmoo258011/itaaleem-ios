import 'dart:convert';

import 'package:itaaleem/features/smart_ui/smart_ui_links.dart';

/// A request from the smart UI to the app. Carries ids only: the app fetches
/// any link itself with the student's token, so a page can never point the
/// app at a URL.
sealed class SmartBridgeMessage {
  const SmartBridgeMessage();
}

class DownloadLesson extends SmartBridgeMessage {
  const DownloadLesson(this.lessonId);

  final int lessonId;

  @override
  bool operator ==(Object other) =>
      other is DownloadLesson && other.lessonId == lessonId;

  @override
  int get hashCode => lessonId.hashCode;
}

/// `play_video`: the lesson's video in the app's own player (YouTube
/// without its branding or links, quality, progress, screen protection).
class PlayVideo extends SmartBridgeMessage {
  const PlayVideo(this.lessonId);

  final int lessonId;

  @override
  bool operator ==(Object other) =>
      other is PlayVideo && other.lessonId == lessonId;

  @override
  int get hashCode => Object.hash(PlayVideo, lessonId);
}

class OpenPdf extends SmartBridgeMessage {
  const OpenPdf({this.lessonId, this.attachmentId});

  final int? lessonId;
  final int? attachmentId;

  @override
  bool operator ==(Object other) =>
      other is OpenPdf &&
      other.lessonId == lessonId &&
      other.attachmentId == attachmentId;

  @override
  int get hashCode => Object.hash(lessonId, attachmentId);
}

class OpenDownloads extends SmartBridgeMessage {
  const OpenDownloads();

  @override
  bool operator ==(Object other) => other is OpenDownloads;

  @override
  int get hashCode => (OpenDownloads).hashCode;
}

class Haptic extends SmartBridgeMessage {
  const Haptic();

  @override
  bool operator ==(Object other) => other is Haptic;

  @override
  int get hashCode => (Haptic).hashCode;
}

/// `rate_moment`: something went well (a game won, a lesson finished) —
/// the app may ask for a store rating, within its weekly policy.
class RateMoment extends SmartBridgeMessage {
  const RateMoment();

  @override
  bool operator ==(Object other) => other is RateMoment;

  @override
  int get hashCode => (RateMoment).hashCode;
}

/// `rate_app`: «قيّم التطبيق» in the smart UI's account page — opens the
/// app's store page.
class OpenStoreRating extends SmartBridgeMessage {
  const OpenStoreRating();

  @override
  bool operator ==(Object other) => other is OpenStoreRating;

  @override
  int get hashCode => (OpenStoreRating).hashCode;
}

/// `logout`: «تسجيل الخروج» in the smart UI's account page.
class Logout extends SmartBridgeMessage {
  const Logout();

  @override
  bool operator ==(Object other) => other is Logout;

  @override
  int get hashCode => (Logout).hashCode;
}

/// `delete_account`: «حذف الحساب» — the app's own confirmation and request.
class DeleteAccount extends SmartBridgeMessage {
  const DeleteAccount();

  @override
  bool operator ==(Object other) => other is DeleteAccount;

  @override
  int get hashCode => (DeleteAccount).hashCode;
}

/// `app_info`: the native «معلومات التطبيق» page.
class AppInfo extends SmartBridgeMessage {
  const AppInfo();

  @override
  bool operator ==(Object other) => other is AppInfo;

  @override
  int get hashCode => (AppInfo).hashCode;
}

/// `open_link`: a link outside our domain the student tapped (the injected
/// script only sends real taps on `<a>` in the main page). The one message
/// that carries a URL — validated by [userTappedOutsideLink] and only ever
/// opened outside the app, never loaded in the shell.
class OpenExternalLink extends SmartBridgeMessage {
  const OpenExternalLink(this.url);

  final Uri url;

  @override
  bool operator ==(Object other) =>
      other is OpenExternalLink && other.url == url;

  @override
  int get hashCode => Object.hash(OpenExternalLink, url);
}

/// `reload`: «تحديث» in the smart UI's menu — the app reloads the page
/// with a fresh sign-in, on the same screen.
class Reload extends SmartBridgeMessage {
  const Reload();

  @override
  bool operator ==(Object other) => other is Reload;

  @override
  int get hashCode => (Reload).hashCode;
}

/// `open_payment`: pay for an order the server created. Built but not
/// switched on yet (see [smartPaymentsEnabled]).
class OpenPayment extends SmartBridgeMessage {
  const OpenPayment(this.orderId);

  final int orderId;

  @override
  bool operator ==(Object other) =>
      other is OpenPayment && other.orderId == orderId;

  @override
  int get hashCode => orderId.hashCode;
}

/// Off until the server's payment-link API is live: until then
/// `open_payment` is ignored like any unknown action.
const smartPaymentsEnabled = false;

int? _positiveId(Object? value) => value is int && value > 0 ? value : null;

/// Android exposes a JavaScript channel to every frame, YouTube embeds
/// included, so a message only counts with the [nonce] given to the main
/// frame. Anything else returns `null` and is ignored.
SmartBridgeMessage? parseBridgeMessage(
  String raw, {
  required String nonce,
  bool payments = smartPaymentsEnabled,
}) {
  final Object? json;
  try {
    json = jsonDecode(raw);
  } on FormatException {
    return null;
  }
  if (json is! Map || nonce.isEmpty || json['nonce'] != nonce) return null;

  final lessonId = _positiveId(json['lesson_id']);
  final attachmentId = _positiveId(json['attachment_id']);
  switch (json['action']) {
    case 'download_lesson':
      return lessonId == null ? null : DownloadLesson(lessonId);
    case 'play_video':
      return lessonId == null ? null : PlayVideo(lessonId);
    case 'open_pdf':
      if ((lessonId == null) == (attachmentId == null)) return null;
      return OpenPdf(lessonId: lessonId, attachmentId: attachmentId);
    case 'open_downloads':
      return const OpenDownloads();
    case 'haptic':
      return const Haptic();
    case 'rate_moment':
      return const RateMoment();
    case 'rate_app':
      return const OpenStoreRating();
    case 'logout':
      return const Logout();
    case 'delete_account':
      return const DeleteAccount();
    case 'app_info':
      return const AppInfo();
    case 'reload':
      return const Reload();
    case 'open_link':
      final url = userTappedOutsideLink(json['url']);
      return url == null ? null : OpenExternalLink(url);
    case 'open_payment' when payments:
      final orderId = _positiveId(json['order_id']);
      return orderId == null ? null : OpenPayment(orderId);
  }
  return null;
}
