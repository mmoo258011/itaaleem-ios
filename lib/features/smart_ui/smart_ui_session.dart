import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// What code outside the shell (pushes, the rating prompt) needs from it.
class SmartShellHooks {
  SmartShellHooks._();

  /// Set while the shell is mounted: reloads the page it is on.
  static Future<void> Function()? reload;

  /// Set while the shell is mounted: shows a hash route in it.
  static void Function(String hash)? openHash;

  /// The signed-in student's home is the shell (kept in sync by the
  /// router), so a push opens there even before the shell is mounted.
  static bool active = false;

  /// A route for the shell to open with, when a push arrives before it's up.
  static String? pendingHash;

  /// Set by the rating watcher: the student just finished something (a
  /// lesson, a won game) — a good moment to ask for a rating.
  static void Function()? onPositiveMoment;

  /// The shell is on a lesson, an exam or a game: no rating prompt.
  static final busy = ValueNotifier<bool>(false);
}

/// The smart UI's own screen kinds (`native.js` `screenKind`), matched on
/// the hash without `#` and without its `?query`:
/// study `/lesson/{id}/tool/…`, lesson `/lesson/{id}`, exam `/exam/{id}`,
/// `/play`, `/gplay/{id}`, pdf `/pdf/{id}` — plus the essay screen
/// `/essay/{id}`, which `screenKind` reports as `other`.
final _studyHash = RegExp(r'^/lesson/\d+/tool/');
final _lessonHash = RegExp(r'^/lesson/\d+$');
final _examHash = RegExp(r'^/(exam/\d+|play|gplay/\d+)$');
final _pdfHash = RegExp(r'^/pdf/\d+$');
final _essayHash = RegExp(r'^/essay/\d+$');

String _route(String fragment) {
  final q = fragment.indexOf('?');
  return q < 0 ? fragment : fragment.substring(0, q);
}

/// An exam, a game or an essay: no pull-to-refresh.
bool isTestSmartHash(String fragment) {
  final route = _route(fragment);
  return _examHash.hasMatch(route) || _essayHash.hasMatch(route);
}

/// Studying (lesson, tools, PDF) or being tested: no rating prompt.
/// [fragment] is the URL's `#…` without the `#`.
bool isBusySmartHash(String fragment) {
  final route = _route(fragment);
  return isTestSmartHash(fragment) ||
      _studyHash.hasMatch(route) ||
      _lessonHash.hasMatch(route) ||
      _pdfHash.hasMatch(route);
}

/// A lesson (its video / PDF) or the PDF reader: the only smart UI screens
/// under screen protection (FLAG_SECURE / the iOS shield).
bool isProtectedSmartHash(String fragment) {
  final route = _route(fragment);
  return _lessonHash.hasMatch(route) || _pdfHash.hasMatch(route);
}

/// Logout: the next student on this device must not inherit the smart UI
/// session — cookies, and also the WebView's cache, localStorage and
/// sessionStorage (the smart UI and the panel keep page state there).
/// Each step runs even if another fails. [steps] is for tests.
Future<void> clearSmartUiSession({
  List<(String, Future<void> Function())>? steps,
}) async {
  for (final (name, run) in steps ?? _webViewWipeSteps()) {
    try {
      await run();
    } catch (e) {
      if (kDebugMode) debugPrint('[SmartShell] $name failed: $e');
    }
  }
  SmartShellHooks.pendingHash = null;
  SmartShellHooks.busy.value = false;
}

List<(String, Future<void> Function())> _webViewWipeSteps() {
  WebViewController? controller;
  WebViewController web() => controller ??= WebViewController();
  return [
    ('clearCookies', () => WebViewCookieManager().clearCookies()),
    ('clearCache', () => web().clearCache()),
    ('clearLocalStorage', () => web().clearLocalStorage()),
  ];
}
