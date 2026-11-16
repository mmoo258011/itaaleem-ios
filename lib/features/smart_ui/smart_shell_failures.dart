import 'package:flutter/foundation.dart' show debugPrint;
import 'package:webview_flutter/webview_flutter.dart';

/// What the shell does with a WebView load error.
enum SmartLoadError {
  /// Not ours to act on: a cancelled load, a sub-resource (image, font,
  /// iframe), or a page on another site (YouTube…).
  ignore,

  /// iOS killed the page's content process (memory pressure, often while
  /// the app was in the background): sign in again with a fresh handoff.
  /// Never a reason to leave the smart UI.
  processGone,

  /// The smart UI's own page failed to load.
  pageFailed,
}

// Cancelled loads (a prevented navigation, a quick second tap) aren't
// failures: Android -3 (ERR_ABORTED), iOS -999 (NSURLErrorCancelled).
const _cancelled = {-3, -999};

SmartLoadError classifyLoadError(
  WebResourceError error, {
  required bool Function(String? url) onOrigin,
}) {
  if (error.errorType == WebResourceErrorType.webContentProcessTerminated) {
    return SmartLoadError.processGone;
  }
  if (error.isForMainFrame != true || _cancelled.contains(error.errorCode)) {
    return SmartLoadError.ignore;
  }
  if (error.url != null && !onOrigin(error.url)) return SmartLoadError.ignore;
  return SmartLoadError.pageFailed;
}

final _fileExtension = RegExp(
  r'\.(js|css|png|jpe?g|webp|svg|woff2?|mp3|json|map|pdf)$',
  caseSensitive: false,
);

/// A page of the smart UI itself: `/app`, `/app/`, `/app/<route>` — not its
/// API (`/app/api/…`), its build assets (`/app/assets/…`) or any file.
bool isSmartUiPagePath(String path) {
  if (path != '/app' && !path.startsWith('/app/')) return false;
  if (path.startsWith('/app/api/') || path.startsWith('/app/assets/')) {
    return false;
  }
  return !_fileExtension.hasMatch(path);
}

/// An HTTP error worth acting on: only the smart UI's own pages
/// ([isSmartUiPagePath]). `onHttpError` doesn't say which frame or
/// resource failed (the Android plugin drops `isForMainFrame`; iOS reports
/// iframes too), so the path decides.
bool isPageHttpError(Uri? uri, int status, {required bool onOrigin}) =>
    uri != null && onOrigin && status >= 400 && isSmartUiPagePath(uri.path);

/// Counts the smart UI's failures in a row: the first ones retry with a
/// fresh handoff; only [limit] in a row send the student back to the
/// native app. Every failure is logged with its reason.
class SmartFailureTracker {
  SmartFailureTracker({this.limit = 2, void Function(String)? log})
    : _log = log ?? debugPrint;

  final int limit;
  final void Function(String) _log;
  int _count = 0;

  int get count => _count;

  /// Records a failure; true when it's time to fall back.
  bool fail(String reason) {
    _count++;
    final fallBack = _count >= limit;
    _log(
      '[SmartShell] failure $_count/$limit: $reason'
      '${fallBack ? ' -> falling back to the native app' : ' -> retrying'}',
    );
    return fallBack;
  }

  /// The page came up: the next failure starts counting from zero.
  void reset() => _count = 0;
}

/// Caps the reloads after iOS killed the page's content process: at most
/// [limit] in a sliding [window]. Past that the shell shows its own error
/// screen (never the native app). Cleared once the page stayed ready for
/// [stableAfter], or by «إعادة المحاولة».
class ProcessGoneLimiter {
  ProcessGoneLimiter({
    this.limit = 3,
    this.window = const Duration(seconds: 120),
    this.stableAfter = const Duration(seconds: 30),
    DateTime Function()? now,
    void Function(String)? log,
  }) : _now = now ?? DateTime.now,
       _log = log ?? debugPrint;

  final int limit;
  final Duration window;
  final Duration stableAfter;
  final DateTime Function() _now;
  final void Function(String) _log;
  final _times = <DateTime>[];
  DateTime? _readySince;

  int get count => _times.length;

  /// The page is up: if it stays up for [stableAfter] (no termination in
  /// between) the count starts over.
  void markReady() => _readySince = _now();

  /// Records a termination; true = reload, false = show the error screen.
  bool record() {
    final now = _now();
    final readySince = _readySince;
    _readySince = null;
    if (readySince != null && now.difference(readySince) >= stableAfter) {
      _times.clear();
    }
    _times
      ..removeWhere((t) => now.difference(t) >= window)
      ..add(now);
    final reload = _times.length <= limit;
    _log(
      '[SmartShell] process terminated ${_times.length}/$limit'
      '${reload ? ' -> reload' : ' -> error screen'}',
    );
    return reload;
  }

  void reset() {
    _times.clear();
    _readySince = null;
  }
}
