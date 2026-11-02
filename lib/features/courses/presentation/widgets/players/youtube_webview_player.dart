import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show Factory, debugPrint, kDebugMode;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:itaaleem/core/utils/youtube_utils.dart';
import 'package:itaaleem/features/courses/presentation/widgets/players/lecture_playback_handle.dart';
import 'package:itaaleem/features/courses/presentation/widgets/players/playback_progress_reporter.dart';
import 'package:itaaleem/features/courses/presentation/widgets/players/player_error_view.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

/// "المشغل الأساسي": YouTube's IFrame player for the privacy-enhanced
/// youtube-nocookie.com embed, inside a WebView (720p requested).
///
/// * The wrapper page is loaded *at* the nocookie origin, so the embed
///   iframe is same-origin and its chrome (logo, title, share/copy link,
///   suggestions) can be hidden from the page — re-applied every second
///   because YouTube rebuilds its controls.
/// * Long-press, context menus and copying are blocked (JS + Flutter).
/// * Navigation is locked to the embed; YouTube/Google helper frames only.
/// * A JS bridge reports `getCurrentTime()`/`getDuration()` every 5 seconds.
/// * Fullscreen is the app's own (YouTube's is disabled via `fs=0`).
/// * FLAG_SECURE stays on the Activity (`SecureScreen` around the page).
class YoutubeWebviewPlayer extends StatefulWidget {
  const YoutubeWebviewPlayer({
    super.key,
    required this.rawIdOrUrl,
    required this.startAt,
    required this.title,
    required this.onReady,
    required this.onEnded,
    required this.onFullscreenChanged,
    this.thumbnailUrl,
    this.progressReporter,
    this.onFailed,
  });

  /// Called when the video can't be played; the host then offers another
  /// player instead of this widget's own error view.
  final VoidCallback? onFailed;

  /// A video id or any `watch?v=` / `youtu.be/` / `embed/` URL.
  final String rawIdOrUrl;
  final Duration startAt;
  final String title;
  final ValueChanged<LecturePlaybackHandle> onReady;
  final VoidCallback onEnded;
  final ValueChanged<bool> onFullscreenChanged;
  final String? thumbnailUrl;
  final ProgressReporter? progressReporter;

  @override
  State<YoutubeWebviewPlayer> createState() => _YoutubeWebviewPlayerState();
}

class _YoutubeWebviewPlayerState extends State<YoutubeWebviewPlayer> {
  static const _baseUrl = 'https://www.youtube-nocookie.com';

  late final String? _videoId = extractYouTubeId(widget.rawIdOrUrl);
  WebViewController? _controller;
  final _handle = _YoutubeHandle();
  bool _loading = true;
  String? _error;
  bool _fullscreen = false;
  bool _readyReported = false;
  Timer? _loadTimeout;
  bool _copyAttempted = false;

  @override
  void initState() {
    super.initState();
    _handle.position = widget.startAt;
    if (_videoId != null) _init(_videoId);
  }

  void _init(String id) {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel('FlutterYT', onMessageReceived: _onMessage)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _onNavigationRequest,
          onPageFinished: (url) {
            if (kDebugMode) debugPrint('>>> WebView: Page finished ($url)');
          },
          // Trackers/analytics fail all the time — never a playback failure.
          onWebResourceError: (error) {
            if (kDebugMode) {
              debugPrint(
                '>>> WebView: Resource error: ${error.description} '
                'for ${error.url}',
              );
            }
          },
        ),
      );
    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      platform
        ..setMediaPlaybackRequiresUserGesture(false)
        ..setTextZoom(100);
    }
    _controller = controller;
    _load(id);
    WakelockPlus.enable().catchError((_) {});
  }

  void _load(String id) {
    final controller = _controller;
    if (controller == null) return;
    // Failed only if the player never comes up (or YouTube reports a player
    // error) — never because of stray resource errors.
    _loadTimeout?.cancel();
    _loadTimeout = Timer(const Duration(seconds: 15), () {
      if (!mounted || !_loading) return;
      if (kDebugMode) debugPrint('>>> WebView: load timed out');
      _setError('انتهت مهلة تحميل الفيديو');
    });
    if (kDebugMode) debugPrint('>>> WebView: Loading video $id');
    controller.loadHtmlString(_html(id), baseUrl: _baseUrl);
  }

  void _setError(String message) {
    _loadTimeout?.cancel();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = message;
    });
    widget.onFailed?.call();
  }

  static bool _under(String host, String domain) =>
      host == domain || host.endsWith('.$domain');

  static bool _isAllowedHost(String host) {
    bool under(String domain) => _under(host, domain);
    return under('youtube.com') ||
        under('youtube-nocookie.com') ||
        under('googlevideo.com') ||
        under('ytimg.com') ||
        under('google.com') ||
        under('googleapis.com') ||
        under('gstatic.com');
  }

  /// The top-level page may only be the player page (or a Google consent
  /// page); YouTube/Google helper frames load freely. Anything else —
  /// "watch on YouTube", channel links — is refused.
  NavigationDecision _onNavigationRequest(NavigationRequest request) {
    final uri = Uri.tryParse(request.url);
    final host = uri?.host.toLowerCase() ?? '';
    final path = uri?.path ?? '';
    // Exact host or a real subdomain — `endsWith('youtube.com')` alone would
    // also let `evilyoutube.com` load as the top-level page.
    final isYoutube =
        _under(host, 'youtube.com') || _under(host, 'youtube-nocookie.com');
    final allowed = request.isMainFrame
        ? (isYoutube &&
                  (path.startsWith('/embed/') ||
                      path.isEmpty ||
                      path == '/')) ||
              _under(host, 'google.com') ||
              request.url.startsWith('about:')
        : _isAllowedHost(host) || request.url.startsWith('about:');
    if (!allowed && kDebugMode) {
      debugPrint('>>> WebView: Navigation blocked: ${request.url}');
    }
    return allowed ? NavigationDecision.navigate : NavigationDecision.prevent;
  }

  void _onMessage(JavaScriptMessage message) {
    if (!mounted) return;
    Map<String, dynamic> data;
    try {
      data = jsonDecode(message.message) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    switch (data['type']) {
      case 'ready':
        _loadTimeout?.cancel();
        setState(() => _loading = false);
        if (!_readyReported) {
          _readyReported = true;
          widget.onReady(_handle);
        }
      case 'time':
        final t = (data['t'] as num?)?.toDouble() ?? 0;
        final d = (data['d'] as num?)?.toDouble() ?? 0;
        _handle.position = Duration(milliseconds: (t * 1000).round());
        if (d > 0) {
          _handle.duration = Duration(milliseconds: (d * 1000).round());
        }
        final total = _handle.duration;
        if (total != null) {
          widget.progressReporter?.onPositionChanged(_handle.position, total);
        }
      case 'state':
        final state = data['s'] as int?;
        if (state == 2) {
          // Paused.
          widget.progressReporter?.flush();
          _handle.onPause?.call();
        } else if (state == 0) {
          // Ended.
          widget.progressReporter?.reportCompleted(
            _handle.duration ?? _handle.position,
          );
          widget.onEnded();
        }
      case 'copy':
        _copyAttempted = true;
        if (kDebugMode) debugPrint('>>> WebView: copy/share attempt blocked');
        _clearYoutubeClipboard();
        // Again shortly after, in case a write slipped through.
        Timer(const Duration(milliseconds: 800), _clearYoutubeClipboard);
      case 'error':
        // YouTube player errors (2, 5, 100, 101, 150, 152, 153, …).
        if (_error != null) return;
        if (kDebugMode) debugPrint('>>> WebView: player error ${data['code']}');
        _setError('تعذر تشغيل الفيديو (${data['code']})');
    }
  }

  /// Clears the clipboard if it holds a YouTube link. Only called after a
  /// blocked copy/share attempt (and on close): polling the clipboard would
  /// make Android show "pasted from clipboard" and iOS a paste prompt every
  /// second, and wiping it blindly would erase the student's own copies.
  static Future<void> _clearYoutubeClipboard() async {
    try {
      final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
      if (text == null) return;
      final lower = text.toLowerCase();
      if (lower.contains('youtube') ||
          lower.contains('youtu.be') ||
          lower.contains('googlevideo')) {
        await Clipboard.setData(const ClipboardData(text: ''));
      }
    } catch (_) {}
  }

  void _setFullscreen(bool value) {
    setState(() => _fullscreen = value);
    widget.onFullscreenChanged(value);
    if (value) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      _restoreSystemChrome();
    }
  }

  void _restoreSystemChrome() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  void _retry() {
    final id = _videoId;
    if (id == null) return;
    setState(() {
      _error = null;
      _loading = true;
    });
    _load(id);
  }

  @override
  void dispose() {
    _loadTimeout?.cancel();
    // Stop playback (audio) before the platform view goes away.
    final controller = _controller;
    _controller = null;
    controller
        ?.runJavaScript('try{player.stopVideo();}catch(e){}')
        .catchError((_) {});
    controller?.loadHtmlString('<html></html>').catchError((_) {});
    // Never strand the app in landscape/immersive mode.
    _restoreSystemChrome();
    WakelockPlus.disable().catchError((_) {});
    widget.progressReporter?.flush();
    if (_copyAttempted) _clearYoutubeClipboard();
    super.dispose();
  }

  String _html(String id) {
    final start = widget.startAt.inSeconds;
    return '''
<!DOCTYPE html>
<html><head>
<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no">
<style>
html,body{margin:0;padding:0;background:#000;height:100%;overflow:hidden;
  -webkit-touch-callout:none;-webkit-user-select:none;user-select:none}
#player{position:absolute;inset:0;width:100%;height:100%}
</style>
</head><body>
<div id="player"></div>
<script>
  function post(o){try{FlutterYT.postMessage(JSON.stringify(o));}catch(e){}}
  function block(e){e.preventDefault();e.stopPropagation();return false;}
  function guard(doc){
    ['contextmenu','long-press','copy','cut','selectstart','dragstart'].forEach(function(t){
      doc.addEventListener(t,block,true);
    });
  }
  guard(document);

  var HIDE_CSS = $_hideCss;
  var REMOVE_SELECTOR = '.ytp-share-panel, .ytp-overflow-panel, .ytp-copylink-tip, [class*="toast"], [class*="snackbar"], .html5-endscreen, .ytp-endscreen-content, .videowall-endscreen, .ytp-ce-element';
  var SHARE_SELECTOR = '.ytp-share-button, .ytp-overflow-button, .ytp-copylink-button, .ytp-share-panel, .ytp-overflow-panel, [aria-label*="Share"], [aria-label*="مشاركة"], [aria-label*="Copy"], [aria-label*="نسخ"], .ytp-youtube-button, .ytp-title-link, .ytp-impression-link';

  // Neutralise every way a page can write the clipboard. Re-applied every
  // second (YouTube may grab fresh references). A blocked attempt is
  // reported to Flutter, which clears a copied YouTube link.
  function lockClipboard(win){
    try{
      if(!win||win.__fyClip) return; win.__fyClip=1;
      var nav=win.navigator;
      var noop=function(){ post({type:'copy'}); return Promise.resolve(); };
      if(nav.clipboard){
        try{ nav.clipboard.writeText=noop; nav.clipboard.write=noop; }catch(_){}
        try{ Object.defineProperty(nav,'clipboard',{value:{writeText:noop,write:noop,readText:function(){return Promise.resolve('');},read:function(){return Promise.resolve([]);}},configurable:true}); }catch(_){}
      }
      var doc=win.document, exec=doc.execCommand;
      doc.execCommand=function(cmd){
        if(cmd==='copy'||cmd==='cut'){ post({type:'copy'}); return false; }
        return exec.apply(this,arguments);
      };
      win.prompt=function(){ return null; };
      win.open=function(){ return null; };
      ['copy','cut'].forEach(function(t){
        doc.addEventListener(t,function(e){
          e.preventDefault(); e.stopImmediatePropagation(); post({type:'copy'});
        },true);
      });
    }catch(_){}
  }

  // Strips anything that could share/copy/leave, as soon as it appears.
  function scrub(doc){
    try{
      doc.querySelectorAll(REMOVE_SELECTOR).forEach(function(el){ el.remove(); });
      doc.querySelectorAll('a[href*="youtu"]').forEach(function(a){
        a.removeAttribute('href'); a.removeAttribute('target');
        a.onclick=function(e){ e.preventDefault(); return false; };
      });
    }catch(_){}
  }

  // The iframe shares this page's origin (baseUrl), so its chrome can be
  // hidden from here; repeated every second because YouTube rebuilds it.
  function hide(){
    try{
      var f=document.querySelector('iframe');
      var win=f&&f.contentWindow;
      var doc=f&&f.contentDocument;
      if(!doc||!doc.head) return;
      lockClipboard(win);
      if(!doc.getElementById('fy-hide')){
        var style=doc.createElement('style');
        style.id='fy-hide';
        style.textContent=HIDE_CSS;
        doc.head.appendChild(style);
        guard(doc);
        new MutationObserver(function(){ scrub(doc); })
          .observe(doc.body||doc.documentElement,{childList:true,subtree:true});
        // Clicks on share/copy controls are swallowed before YouTube sees them.
        doc.addEventListener('click',function(e){
          var t=e.target&&e.target.closest&&e.target.closest(SHARE_SELECTOR);
          if(t){ e.preventDefault(); e.stopImmediatePropagation(); post({type:'copy'}); }
        },true);
        // Nothing after the video ends (end screen / suggestions).
        doc.addEventListener('ended',function(){ scrub(doc); },true);
      }
      scrub(doc);
    }catch(_){}
  }
  lockClipboard(window);
  setInterval(hide,1000);

  var tag=document.createElement('script');
  tag.src='https://www.youtube.com/iframe_api';
  document.head.appendChild(tag);
  var player;
  function onYouTubeIframeAPIReady(){
    player=new YT.Player('player',{
      videoId:'$id',
      host:'$_baseUrl',
      playerVars:{autoplay:1,playsinline:1,rel:0,modestbranding:1,controls:1,showinfo:0,iv_load_policy:3,disablekb:0,fs:0,cc_load_policy:0,enablejsapi:1,playlist:'$id',start:$start,origin:'$_baseUrl',vq:'hd720'},
      events:{
        onReady:function(e){
          hide();post({type:'ready'});
          try{e.target.setPlaybackQuality('hd720');}catch(_){}
          e.target.playVideo();
        },
        onStateChange:function(e){
          if(e.data===0){ hide(); }
          post({type:'state',s:e.data});
        },
        onError:function(e){post({type:'error',code:e.data});}
      }
    });
    setInterval(function(){
      if(player&&player.getCurrentTime){
        post({type:'time',t:player.getCurrentTime()||0,d:player.getDuration()||0});
      }
    },5000);
  }
</script>
</body></html>
''';
  }

  /// Every YouTube element that could lead out of the app or copy a link.
  /// A JS string literal (JSON-encoded) for [_html].
  static final _hideCss = jsonEncode('''
.ytp-chrome-top, .ytp-chrome-top-buttons, .ytp-title, .ytp-title-text,
.ytp-title-link, .ytp-title-channel, .ytp-title-channel-logo,
.ytp-share-button, .ytp-overflow-button, .ytp-copylink-button,
.ytp-watch-later-button, .ytp-watermark, .ytp-youtube-button,
.ytp-impression-link, .ytp-contextmenu, .ytp-popup.ytp-contextmenu,
.ytp-share-panel, .ytp-share-panel-inner, .branding-img-container,
.ytp-pause-overlay, .ytp-endscreen-content, .ytp-endscreen-previous,
.ytp-endscreen-next, .ytp-ce-element, .ytp-ce-covering-overlay,
.ytp-ce-element-shadow, .ytp-ce-covering-image, .ytp-ce-expanding-image,
.ytp-suggestion-set, .ytp-cards-button, .ytp-cards-teaser,
.ytp-button[data-tooltip-target-id="ytp-autonav-toggle-button"],
.ytp-paid-content-overlay, .iv-branding, .annotation, .ytp-fullscreen-button,
a[href*="youtube.com/watch"], a[href*="youtu.be"],
.ytp-share-panel-close-button, .ytp-overflow-panel, .ytp-popup.ytp-share-panel,
.ytp-menuitem[aria-label*="مشاركة"], .ytp-menuitem[aria-label*="Share"],
.ytp-menuitem[aria-label*="نسخ"], .ytp-menuitem[aria-label*="Copy"],
.ytp-button[aria-label*="مشاركة"], .ytp-button[aria-label*="Share"],
.ytp-copylink-tip, .ytp-tooltip, .paper-toast,
.yt-notification-action-renderer, [id*="toast"], [class*="toast"],
[class*="snackbar"], .ytp-popup:not(.ytp-settings-menu),
.ytp-ce-element.ytp-ce-playlist, .ytp-videowall-still,
.ytp-show-tiles .ytp-videowall-still, .ytp-playlist-menu-button,
.ytp-next-button, .ytp-prev-button,
.ytp-autonav-endscreen-upnext-container,
.ytp-autonav-endscreen-countdown-overlay, .ytp-related-on-finish,
.html5-endscreen, .videowall-endscreen {
  display: none !important; visibility: hidden !important;
  opacity: 0 !important; pointer-events: none !important;
  width: 0 !important; height: 0 !important; overflow: hidden !important;
  position: absolute !important; left: -9999px !important;
}
* {
  -webkit-touch-callout: none !important;
  -webkit-user-select: none !important; user-select: none !important;
  -webkit-tap-highlight-color: transparent !important;
}
''');

  @override
  Widget build(BuildContext context) {
    if (_videoId == null) {
      return PlayerErrorView(message: 'رابط الفيديو غير صالح', onRetry: () {});
    }
    final error = _error;
    final Widget body = error != null
        ? PlayerErrorView(message: error, onRetry: _retry)
        : Stack(
            fit: StackFit.expand,
            children: [
              if (_controller != null)
                WebViewWidget(
                  controller: _controller!,
                  // Swallow long-presses so no menu / "copy link" opens.
                  gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                    Factory<LongPressGestureRecognizer>(
                      () => LongPressGestureRecognizer()
                        ..onLongPress = () {}
                        ..onLongPressStart = (_) {},
                    ),
                  },
                ),
              if (_loading)
                const ColoredBox(
                  color: Colors.black,
                  child: Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                ),
              PositionedDirectional(
                top: 4,
                end: 4,
                child: IconButton(
                  tooltip: _fullscreen ? 'خروج من ملء الشاشة' : 'ملء الشاشة',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black45,
                    foregroundColor: Colors.white,
                  ),
                  icon: Icon(
                    _fullscreen
                        ? Icons.fullscreen_exit_rounded
                        : Icons.fullscreen_rounded,
                  ),
                  onPressed: () => _setFullscreen(!_fullscreen),
                ),
              ),
            ],
          );
    final player = ColoredBox(color: Colors.black, child: body);
    if (_fullscreen) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _setFullscreen(false);
        },
        child: SizedBox.expand(child: player),
      );
    }
    return AspectRatio(aspectRatio: 16 / 9, child: player);
  }
}

class _YoutubeHandle extends LecturePlaybackHandle {
  @override
  Duration position = Duration.zero;

  @override
  Duration? duration;
}
