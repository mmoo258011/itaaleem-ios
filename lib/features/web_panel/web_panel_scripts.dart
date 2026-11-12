import 'dart:convert';

/// Injected into the panel's main frame only, when it's on our domain.
///
/// - A real tap on a link outside our domain → `open_link` (opens outside).
/// - A download (an `a[download]`, a `blob:` link, or a same-origin file /
///   `…/download` / `…/export` link), clicked by the user or by the page
///   (Livewire exports click a detached `<a download>`) → fetched here with
///   the page's own cookies and handed to the app as base64 (`download`).
///
/// Every message carries [nonce]; it can't be read or replaced by the page
/// once set, and the script does nothing off our domain.
String panelScript({
  required String nonce,
  required String root,
  required int maxBytes,
}) =>
    '''
(function () {
  if (location.protocol !== 'https:') return;
  if (window.__itaaleemPanel) return;
  window.__itaaleemPanel = true;
  var nonce = ${jsonEncode(nonce)};
  function send(msg) {
    msg.nonce = nonce;
    try { PanelNative.postMessage(JSON.stringify(msg)); } catch (e) {}
  }
  function isFile(u) {
    if (u.protocol === 'blob:') return true;
    if (u.origin !== location.origin) return false;
    var p = u.pathname.toLowerCase();
    return /\\.(csv|xlsx|xls|pdf|zip|docx)\$/.test(p) || /\\/(download|export)\$/.test(p);
  }
  function nameOf(res, u, attr) {
    var cd = res.headers.get('content-disposition') || '';
    var m = /filename\\*=UTF-8''([^;]+)/i.exec(cd) || /filename="?([^";]+)"?/i.exec(cd);
    if (m) { try { return decodeURIComponent(m[1]); } catch (e) { return m[1]; } }
    if (attr) return attr;
    return u.pathname.split('/').pop() || 'export';
  }
  function download(href, attr) {
    var u;
    try { u = new URL(href, location.href); } catch (e) { return; }
    fetch(u.href, { credentials: 'include' }).then(function (res) {
      if (!res.ok) throw new Error('http');
      var name = nameOf(res, u, attr);
      return res.blob().then(function (b) {
        if (b.size > $maxBytes) { send({ action: 'download_failed', reason: 'size' }); return; }
        var r = new FileReader();
        r.onload = function () {
          var s = String(r.result), i = s.indexOf(',');
          send({ action: 'download', name: name, mime: b.type, data: s.substring(i + 1) });
        };
        r.onerror = function () { send({ action: 'download_failed' }); };
        r.readAsDataURL(b);
      });
    }).catch(function () { send({ action: 'download_failed' }); });
  }
  window.__itaaleemDownload = download;
  function asDownload(a) {
    try {
      var u = new URL(a.href, location.href);
      return a.hasAttribute('download') || isFile(u) ? u : null;
    } catch (e) { return null; }
  }
  var click = HTMLAnchorElement.prototype.click;
  HTMLAnchorElement.prototype.click = function () {
    if (this.href && asDownload(this)) { download(this.href, this.getAttribute('download')); return; }
    return click.apply(this, arguments);
  };
  document.addEventListener('click', function (e) {
    try {
      if (e.defaultPrevented || e.button !== 0) return;
      var a = e.target && e.target.closest ? e.target.closest('a[href]') : null;
      if (!a) return;
      if (asDownload(a)) {
        e.preventDefault();
        download(a.href, a.getAttribute('download'));
        return;
      }
      if (!e.isTrusted) return;
      var u = new URL(a.href, location.href);
      if (u.protocol !== 'https:') return;
      var host = u.hostname.toLowerCase();
      if (host === ${jsonEncode(root)} || host.endsWith(${jsonEncode('.$root')})) return;
      e.preventDefault();
      send({ action: 'open_link', url: u.href });
    } catch (err) {}
  }, true);
})();
''';
