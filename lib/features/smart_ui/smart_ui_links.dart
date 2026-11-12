import 'package:itaaleem/core/utils/safe_url.dart';

/// The extra user-agent token that tells the smart UI it runs inside the app
/// and on which platform. Display only: it can be spoofed, so nothing
/// security-related may depend on it.
String smartUiAgentMarker(String version, {required bool isIOS}) =>
    'ItaaleemApp/$version (${isIOS ? 'ios' : 'android'})';

/// Where a main-frame navigation from the smart UI goes: the center's own
/// pages stay inside; WhatsApp, phone, mail and the app stores open outside
/// (the page's own contact / rate links); anything else — YouTube (its logo
/// or title in an embed) included — is ignored.
enum SmartLink { inside, outside, blocked }

const _outsideHosts = {
  'wa.me',
  'api.whatsapp.com',
  'whatsapp.com',
  'www.whatsapp.com',
  'play.google.com',
  'apps.apple.com',
};

SmartLink classifySmartLink(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null) return SmartLink.blocked;
  final scheme = uri.scheme.toLowerCase();
  if (scheme == 'tel' || scheme == 'mailto') {
    return uri.path.isEmpty ? SmartLink.blocked : SmartLink.outside;
  }
  if (scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
    return SmartLink.blocked;
  }
  if (isInAppWebAllowed(uri)) return SmartLink.inside;
  if (_outsideHosts.contains(uri.host.toLowerCase())) return SmartLink.outside;
  return SmartLink.blocked;
}

/// A link outside our own domain that the student tapped in the smart UI
/// (a teacher's Facebook, YouTube channel, Instagram, TikTok, X,
/// Telegram...): plain https on the default port, no userinfo, a host that
/// isn't ours, a sane length. Null otherwise. It only ever opens outside the
/// app (`LaunchMode.externalApplication`), never inside the shell.
Uri? userTappedOutsideLink(Object? raw) {
  if (raw is! String || raw.length > 2048) return null;
  final uri = Uri.tryParse(raw.trim());
  if (uri == null ||
      uri.scheme.toLowerCase() != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      (uri.hasPort && uri.port != 443) ||
      isInAppWebAllowed(uri) ||
      isInAppWebAllowed(uri.replace(port: 443))) {
    return null;
  }
  return uri;
}
