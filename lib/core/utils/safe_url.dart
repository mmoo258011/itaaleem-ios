import 'package:itaaleem/core/config/obf.dart';
import 'package:url_launcher/url_launcher.dart';

/// The only URL schemes the app will hand to the OS. Links come from the
/// backend (support/social/update URLs, attachments, news, app-config), so
/// anything else — `http:`, `intent:`, `file:`, `javascript:`, `data:`,
/// `content:`, custom app schemes — is refused instead of launched.
const _allowedLaunchSchemes = {'https', 'tel', 'mailto'};

bool isAllowedLaunchUri(Uri uri) =>
    _allowedLaunchSchemes.contains(uri.scheme.toLowerCase()) &&
    uri.userInfo.isEmpty;

/// [launchUrl], but returns `false` without launching anything unless [uri]'s
/// scheme is https, tel or mailto. Same return contract as [launchUrl]
/// (`false` = couldn't open), so callers' existing "تعذر فتح الرابط" handling
/// covers a blocked scheme too.
Future<bool> launchUrlSafely(
  Uri uri, {
  LaunchMode mode = LaunchMode.platformDefault,
}) async {
  if (!isAllowedLaunchUri(uri)) return false;
  return launchUrl(uri, mode: mode);
}

/// Hosts the in-app WebView may show: `itaaleem.com` and its subdomains,
/// over https on the default port, with no `user@`.
bool isInAppWebAllowed(Uri uri) {
  if (uri.scheme.toLowerCase() != 'https') return false;
  if (uri.userInfo.isNotEmpty || (uri.hasPort && uri.port != 443)) {
    return false;
  }
  final host = uri.host.toLowerCase();
  final root = Obf.rootDomain;
  return host == root || host.endsWith('.$root');
}

/// The only host the student's token is ever sent to (as a header).
bool sendsAuthToken(Uri uri) =>
    uri.scheme.toLowerCase() == 'https' &&
    uri.userInfo.isEmpty &&
    (!uri.hasPort || uri.port == 443) &&
    uri.host.toLowerCase() == Obf.apiHost;

/// Where a server-sent link may open.
enum LinkTarget {
  /// The app's own WebView ([isInAppWebAllowed] only).
  inAppWeb,

  /// Custom Tabs (Android) / SFSafariViewController (iOS).
  browser,

  /// Another app: the browser, WhatsApp, Facebook…
  external,

  /// The dialer (`tel:` with `type: phone` only).
  phone,

  /// Refused.
  blocked,
}

/// Decides where [raw] (a URL from the server) opens, given the dashboard's
/// `type` (`webview`, `external`, `whatsapp`, `phone`, or none).
LinkTarget classifyLink(String raw, {String? type}) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null) return LinkTarget.blocked;
  final scheme = uri.scheme.toLowerCase();
  final kind = type?.trim().toLowerCase();
  if (scheme == 'tel') {
    return kind == 'phone' && uri.path.isNotEmpty
        ? LinkTarget.phone
        : LinkTarget.blocked;
  }
  if (scheme != 'https' || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
    return LinkTarget.blocked;
  }
  if (kind == 'external' || kind == 'whatsapp') return LinkTarget.external;
  return isInAppWebAllowed(uri) ? LinkTarget.inAppWeb : LinkTarget.browser;
}
