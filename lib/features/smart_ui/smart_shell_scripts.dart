import 'dart:convert';

/// JavaScript the shell injects into the smart UI's main frame only
/// (`runJavaScript` never reaches iframes such as YouTube embeds).

/// Gives the page the nonce it must put in every `ItaaleemNative` message,
/// then tells it the bridge is ready. Runs only when the main frame is on
/// [origin], and the nonce can't be overwritten afterwards.
String bridgeScript({required String nonce, required String origin}) =>
    '''
(function () {
  if (location.origin !== ${jsonEncode(origin)}) return;
  if (window.ItaaleemNativeNonce === undefined) {
    try {
      Object.defineProperty(window, 'ItaaleemNativeNonce', {
        value: ${jsonEncode(nonce)}, writable: false, configurable: false
      });
    } catch (e) {}
  }
  // A real tap (not a script-made click) on a link outside our domain —
  // the teacher's Facebook, YouTube, Instagram... — opens outside the app.
  // Only this main page: taps inside iframes (a YouTube embed's logo) and
  // automatic navigations stay blocked by the navigation delegate.
  if (!window.__itaaleemOutsideLinks) {
    window.__itaaleemOutsideLinks = true;
    document.addEventListener('click', function (e) {
      try {
        if (!e.isTrusted || e.defaultPrevented || e.button !== 0) return;
        var a = e.target && e.target.closest ? e.target.closest('a[href]') : null;
        if (!a) return;
        var u = new URL(a.href, location.href);
        if (u.protocol !== 'https:') return;
        var h = u.hostname.toLowerCase();
        if (h === ${jsonEncode(rootHostOf(origin))} || h.endsWith('.' + ${jsonEncode(rootHostOf(origin))})) return;
        e.preventDefault();
        ItaaleemNative.postMessage(JSON.stringify({
          nonce: window.ItaaleemNativeNonce, action: 'open_link', url: u.href
        }));
      } catch (err) {}
    }, true);
  }
  try { window.dispatchEvent(new Event('itaaleem-native-ready')); } catch (e) {}
})();
''';

/// Moves the page to a hash route (already validated by `safeSmartHash`).
String openHashScript(String hash) => 'location.hash = ${jsonEncode(hash)};';

/// The registrable root of the center origin (`a.itaaleem.com` → `itaaleem.com`):
/// links under it stay with the page; the native side re-checks every link.
String rootHostOf(String origin) {
  final host = Uri.tryParse(origin)?.host.toLowerCase() ?? '';
  final parts = host.split('.');
  return parts.length <= 2 ? host : parts.sublist(parts.length - 2).join('.');
}
