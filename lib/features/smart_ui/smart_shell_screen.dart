import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:itaaleem/app/router/app_router.dart';
import 'package:itaaleem/core/device/device_identity_service.dart'
    show appVersionParts;
import 'package:itaaleem/core/network/connectivity_provider.dart';
import 'package:itaaleem/core/network/dio_client.dart';
import 'package:itaaleem/core/theme/app_palette.dart';
import 'package:itaaleem/core/theme/app_spacing.dart';
import 'package:itaaleem/core/utils/platform_utils.dart';
import 'package:itaaleem/core/utils/safe_url.dart';
import 'package:itaaleem/core/widgets/app_toast.dart';
import 'package:itaaleem/core/widgets/secure_screen.dart';
import 'package:itaaleem/features/auth/presentation/providers/auth_controller.dart';
import 'package:itaaleem/features/smart_ui/smart_ui_access.dart';
import 'package:itaaleem/features/smart_ui/smart_ui_bridge.dart';
import 'package:itaaleem/features/smart_ui/smart_ui_handoff.dart';
import 'package:itaaleem/features/smart_ui/smart_ui_links.dart';
import 'package:itaaleem/features/smart_ui/smart_shell_actions.dart';
import 'package:itaaleem/features/smart_ui/smart_shell_uploads.dart';
import 'package:itaaleem/features/smart_ui/smart_shell_scripts.dart';
import 'package:itaaleem/features/smart_ui/smart_shell_state.dart';
import 'package:itaaleem/features/splash/presentation/widgets/launch_view.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

enum _Phase { loading, ready, offline }

/// The smart UI: the center's web app in a WebView, signed in with a
/// one-time handoff ticket, talking to the app over the `ItaaleemNative`
/// channel (ids only — see [parseBridgeMessage]).
class SmartShellScreen extends ConsumerStatefulWidget {
  const SmartShellScreen({super.key});

  @override
  ConsumerState<SmartShellScreen> createState() => _SmartShellScreenState();
}

class _SmartShellScreenState extends ConsumerState<SmartShellScreen> {
  WebViewController? _controller;
  _Phase _phase = _Phase.loading;
  SmartUiAccess? _access;
  final String _nonce = _newNonce();
  bool _starting = false;

  /// The launch overlay is in the tree (it fades out after the page loads).
  bool _launchVisible = true;

  static String _newNonce() {
    final random = Random.secure();
    return List.generate(
      24,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  @override
  void initState() {
    super.initState();
    SmartShellHooks.openHash = _openHash;
    SmartShellHooks.reload = _reload;
    unawaited(_start());
  }

  @override
  void dispose() {
    if (SmartShellHooks.openHash == _openHash) SmartShellHooks.openHash = null;
    if (SmartShellHooks.reload == _reload) SmartShellHooks.reload = null;
    SmartShellHooks.busy.value = false;
    super.dispose();
  }

  Future<void> _start() async {
    if (_starting) return;
    _starting = true;
    if (mounted) {
      setState(() {
        _phase = _Phase.loading;
        _launchVisible = true;
        _softReloading = false;
        _revealDeadline = null;
      });
    }
    try {
      final access = ref.read(authControllerProvider).valueOrNull?.smartUi;
      if (access == null || !access.enabled) {
        _fallBack();
        return;
      }
      _access = access;
      final next = safeSmartHash(SmartShellHooks.pendingHash);
      SmartShellHooks.pendingHash = null;

      final SmartUiHandoff handoff;
      try {
        handoff = await requestHandoff(ref.read(dioClientProvider), access);
      } on HandoffException catch (e) {
        if (!mounted) return;
        if (e.reason == HandoffFailure.offline || !await _isOnline()) {
          setState(() => _phase = _Phase.offline);
        } else {
          _fallBack();
        }
        return;
      }
      if (!mounted) return;
      final controller = _controller ??= await _createController();
      if (!mounted) return;
      setState(() {});
      await controller.loadRequest(
        handoff.url,
        method: LoadRequestMethod.post,
        headers: SmartUiHandoff.headers,
        body: handoff.body(next),
      );
    } finally {
      _starting = false;
    }
  }

  Future<bool> _isOnline() async {
    try {
      return await ref.read(connectivityStatusProvider.future);
    } catch (_) {
      return true;
    }
  }

  /// Back to the native app for the rest of this run.
  void _fallBack() {
    if (kDebugMode) debugPrint('[SmartShell] falling back to the native app');
    ref.read(smartUiFallbackProvider.notifier).state = true;
  }

  Future<WebViewController> _createController() async {
    final PlatformWebViewControllerCreationParams params;
    if (WebViewPlatform.instance is WebKitWebViewPlatform) {
      params = WebKitWebViewControllerCreationParams(
        allowsInlineMediaPlayback: true,
        mediaTypesRequiringUserAction: const <PlaybackMediaTypes>{},
      );
    } else {
      params = const PlatformWebViewControllerCreationParams();
    }
    final controller = WebViewController.fromPlatformCreationParams(params);

    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setBackgroundColor(launchBackground);

    final (:version, build: _) = await appVersionParts();
    final base = await controller.getUserAgent() ?? '';
    final marker = smartUiAgentMarker(
      version.isEmpty ? '0.0.0' : version,
      isIOS: PlatformUtils.isIOS,
    );
    await controller.setUserAgent(base.isEmpty ? marker : '$base $marker');

    await controller.addJavaScriptChannel(
      'ItaaleemNative',
      onMessageReceived: (message) {
        final parsed = parseBridgeMessage(message.message, nonce: _nonce);
        // Debug builds only: the type, never the payload (it holds the nonce).
        if (kDebugMode) {
          debugPrint(
            '[SmartShell] bridge: ${parsed?.runtimeType ?? 'rejected'}',
          );
        }
        if (parsed != null && mounted) {
          unawaited(handleSmartBridgeMessage(context, ref, parsed));
        }
      },
    );

    await controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: _onNavigationRequest,
        onPageFinished: (url) => unawaited(_onPageFinished(url)),
        onUrlChange: (change) => _trackBusy(change.url),
        onWebResourceError: _onWebResourceError,
        onHttpError: _onHttpError,
      ),
    );

    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      await platform.setMediaPlaybackRequiresUserGesture(false);
      await platform.setOnShowFileSelector(_pickFiles);
    }
    return controller;
  }

  bool _onOrigin(String? url) {
    final uri = url == null ? null : Uri.tryParse(url);
    final access = _access;
    return uri != null &&
        access != null &&
        uri.scheme == 'https' &&
        uri.host.toLowerCase() == access.origin.host;
  }

  Future<void> _onPageFinished(String url) async {
    if (kDebugMode) {
      debugPrint('[SmartShell] page finished: ${Uri.tryParse(url)?.path}');
    }
    final controller = _controller;
    if (controller == null || !mounted) return;
    if (_onOrigin(url)) {
      final origin = _access!.origin.toString();
      try {
        await controller.runJavaScript(
          bridgeScript(
            nonce: _nonce,
            origin: origin.endsWith('/')
                ? origin.substring(0, origin.length - 1)
                : origin,
          ),
        );
      } catch (e) {
        if (kDebugMode) debugPrint('[SmartShell] inject failed: $e');
      }
    }
    _trackBusy(url);
    if (_softReloading) {
      final uri = Uri.tryParse(url);
      if (uri != null && _onOrigin(url) && _isAppPath(uri.path)) {
        if (mounted) setState(() => _softReloading = false);
      } else {
        unawaited(_softReloadFailed(_lastAppUri));
      }
    }
    if (_onOrigin(url)) {
      final uri = Uri.tryParse(url);
      if (uri != null && _isAppPath(uri.path)) _lastAppUri = uri;
    }
    if (_phase == _Phase.loading) unawaited(_revealWhenDrawn(controller));
  }

  /// `onPageFinished` fires for the handoff page and again for the app
  /// before it has drawn its first screen, so the launch screen stays until
  /// the page has a real DOM, its fonts are in and it stopped changing —
  /// then fades away. Never longer than [_revealCap] after the first finish.
  static const _revealCap = Duration(seconds: 4);
  static const _drawnScript =
      "document.fonts.status + ':' + document.querySelectorAll('*').length";
  DateTime? _revealDeadline;
  bool _revealing = false;

  Future<void> _revealWhenDrawn(WebViewController controller) async {
    _revealDeadline ??= DateTime.now().add(_revealCap);
    if (_revealing) return;
    _revealing = true;
    try {
      var last = -1;
      var steady = 0;
      while (mounted &&
          _phase == _Phase.loading &&
          DateTime.now().isBefore(_revealDeadline!)) {
        try {
          final raw = await controller.runJavaScriptReturningResult(
            _drawnScript,
          );
          final parts = raw.toString().replaceAll('"', '').split(':');
          final nodes = int.tryParse(parts.last) ?? 0;
          final drawn = parts.first == 'loaded' && nodes >= 50;
          steady = drawn && nodes == last ? steady + 1 : 0;
          last = nodes;
          if (steady >= 2) break;
        } catch (_) {
          // Page mid-navigation: try again on the next tick.
        }
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
    } finally {
      _revealing = false;
    }
    if (mounted && _phase == _Phase.loading) {
      _revealDeadline = null;
      setState(() => _phase = _Phase.ready);
    }
  }

  DateTime? _busySince;

  /// Screen protection follows the page: on only for a lesson or a PDF.
  bool _protected = false;

  void _trackBusy(String? url) {
    final uri = url == null ? null : Uri.tryParse(url);
    final protected =
        uri != null && _onOrigin(url) && isProtectedSmartHash(uri.fragment);
    if (protected != _protected && mounted) {
      setState(() => _protected = protected);
    }
    final busy = uri != null && _onOrigin(url) && isBusySmartHash(uri.fragment);
    final since = _busySince;
    if (busy && since == null) _busySince = DateTime.now();
    if (!busy && since != null) {
      _busySince = null;
      // Back from a lesson / exam / game the student stayed in: a good
      // moment to (maybe) ask for a rating.
      if (DateTime.now().difference(since) >= const Duration(minutes: 3)) {
        SmartShellHooks.busy.value = false;
        SmartShellHooks.onPositiveMoment?.call();
      }
    }
    SmartShellHooks.busy.value = busy;
  }

  FutureOr<NavigationDecision> _onNavigationRequest(NavigationRequest request) {
    if (!request.isMainFrame) return NavigationDecision.navigate;
    switch (classifySmartLink(request.url)) {
      case SmartLink.inside:
        return NavigationDecision.navigate;
      case SmartLink.outside:
        final uri = Uri.parse(request.url.trim());
        unawaited(launchUrlSafely(uri, mode: LaunchMode.externalApplication));
        return NavigationDecision.prevent;
      case SmartLink.blocked:
        return NavigationDecision.prevent;
    }
  }

  // Cancelled loads (a prevented navigation, a quick second tap) aren't
  // failures: Android -3 (ERR_ABORTED), iOS -999 (NSURLErrorCancelled).
  static const _cancelled = {-3, -999};

  Future<void> _onWebResourceError(WebResourceError error) async {
    if (error.isForMainFrame != true || _cancelled.contains(error.errorCode)) {
      return;
    }
    // Only the smart UI's own pages: a YouTube page failing is not ours.
    if (error.url != null && !_onOrigin(error.url)) return;
    if (_softReloading) {
      if (mounted) setState(() => _softReloading = false);
    }
    await _pageFailed();
  }

  void _onHttpError(HttpResponseError error) {
    final status = error.response?.statusCode ?? 0;
    final url = error.request?.uri.toString();
    // Soft reload refused (401/419: session expired, or any 4xx/5xx on the
    // page itself): fall back to a fresh handoff.
    if (_softReloading && _onOrigin(url) && status >= 400) {
      unawaited(_softReloadFailed(_lastAppUri));
      return;
    }
    // Before the UI is up, a 5xx/404 on the handoff or the app page means
    // the smart UI isn't usable right now.
    if (_phase != _Phase.ready && _onOrigin(url) && status >= 400) {
      unawaited(_pageFailed());
    }
  }

  Future<void> _pageFailed() async {
    if (!mounted) return;
    if (await _isOnline()) {
      _fallBack();
    } else if (mounted) {
      setState(() => _phase = _Phase.offline);
    }
  }

  Future<List<String>> _pickFiles(FileSelectorParams params) async {
    try {
      if (params.isCaptureEnabled) {
        final shot = await ImagePicker().pickImage(source: ImageSource.camera);
        return shot == null ? const [] : [Uri.file(shot.path).toString()];
      }
      // Homework: images and PDFs only, each up to [maxUploadBytes].
      final picked = params.mode == FileSelectorMode.openMultiple
          ? await FilePicker.pickFiles(
              type: FileType.custom,
              allowedExtensions: uploadExtensions,
            )
          : [
              ?await FilePicker.pickFile(
                type: FileType.custom,
                allowedExtensions: uploadExtensions,
              ),
            ];
      final accepted = <String>[];
      var rejected = false;
      for (final file in picked) {
        final size = file.lengthSync() ?? await file.length();
        if (isUploadAllowed(file.name, size)) {
          accepted.add(file.uri.toString());
        } else {
          rejected = true;
        }
      }
      if (rejected && mounted) {
        AppToast.showError(
          context,
          'مسموح بصور أو PDF بس، وكل ملف لحد ${maxUploadBytes ~/ (1024 * 1024)} ميجا',
        );
      }
      return accepted;
    } catch (e) {
      if (kDebugMode) debugPrint('[SmartShell] file picker failed: $e');
      return const [];
    }
  }

  void _openHash(String hash) {
    final controller = _controller;
    final safe = safeSmartHash(hash);
    if (controller == null || _phase != _Phase.ready) {
      SmartShellHooks.pendingHash = safe;
      return;
    }
    unawaited(
      controller.runJavaScript(openHashScript(safe)).catchError((_) {}),
    );
  }

  /// «تحديث» (`reload` action): the same page (same hash) again, in place,
  /// with a thin bar at the top — no launch screen, no new handoff while
  /// the session is alive. A GET of the current URL, not `location.reload()`,
  /// which could re-post the already-used handoff ticket. If the session
  /// has expired ([_softReloadFailed]) it falls back to a fresh handoff to
  /// the same screen.
  Future<void> _reload() async {
    if (_starting || _softReloading) return;
    final controller = _controller;
    final url = await controller?.currentUrl();
    final uri = url == null ? null : Uri.tryParse(url);
    if (controller == null ||
        uri == null ||
        _phase != _Phase.ready ||
        !_onOrigin(url) ||
        !_isAppPath(uri.path)) {
      await _handoffReload(uri);
      return;
    }
    setState(() => _softReloading = true);
    if (kDebugMode) {
      debugPrint('[SmartShell] reload in place: ${uri.path}#${uri.fragment}');
    }
    try {
      // The handoff page is a POST result: reload its target, `/app`.
      final target = uri.path.startsWith('/app/handoff')
          ? uri.replace(path: '/app')
          : uri;
      await controller.loadRequest(target);
    } catch (_) {
      await _handoffReload(uri);
    }
  }

  bool _softReloading = false;

  /// The last smart UI page shown, so an expired-session reload returns there.
  Uri? _lastAppUri;

  static bool _isAppPath(String path) =>
      path == '/app' || path.startsWith('/app/');

  /// The soft reload landed off the smart UI (the session expired and the
  /// server sent the page to its login) or was refused: sign in again
  /// through a fresh handoff, back to the same screen.
  Future<void> _softReloadFailed(Uri? last) async {
    if (!_softReloading) return;
    if (mounted) setState(() => _softReloading = false);
    await _handoffReload(last);
  }

  Future<void> _handoffReload(Uri? uri) async {
    if (kDebugMode) debugPrint('[SmartShell] reload via handoff');
    if (uri != null && _onOrigin(uri.toString()) && uri.fragment.isNotEmpty) {
      SmartShellHooks.pendingHash = uri.fragment;
    }
    await _start();
  }

  /// At the UI's start page there's nothing to go back to: going back
  /// further would re-post the (already used) handoff ticket.
  Future<bool> _atStart() async {
    final url = await _controller?.currentUrl();
    final uri = url == null ? null : Uri.tryParse(url);
    if (uri == null || !_onOrigin(url)) return false;
    return uri.path == '/app/handoff' ||
        ((uri.path == '/app' || uri.path == '/app/') &&
            (uri.fragment.isEmpty || uri.fragment == '/'));
  }

  Future<void> _onBack() async {
    final controller = _controller;
    if (controller != null &&
        _phase == _Phase.ready &&
        !await _atStart() &&
        await controller.canGoBack()) {
      await controller.goBack();
      return;
    }
    if (!mounted) return;
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تخرج؟'),
        content: const Text('هل تريد الخروج من التطبيق؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('لا'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('خروج'),
          ),
        ],
      ),
    );
    if (leave == true) await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    // The server switched the smart UI off (profile refresh): the router
    // moves the student to `/home`; nothing to do here.
    final controller = _controller;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_onBack());
      },
      child: SecureScreen(
        enabled: _protected,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Scaffold(
              backgroundColor: launchBackground,
              body: SafeArea(
                child: Stack(
                  children: [
                    if (controller != null && _phase != _Phase.offline)
                      WebViewWidget(controller: controller),
                    if (_phase == _Phase.offline)
                      _SmartOffline(onRetry: () => unawaited(_start())),
                    // «تحديث» in place: just a thin bar at the top.
                    if (_softReloading)
                      const Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: LinearProgressIndicator(minHeight: 3),
                      ),
                  ],
                ),
              ),
            ),
            // The launch screen carries on (same picture as the splash)
            // until the page has finished, then fades away. Drawn over the
            // whole screen like the splash, so the logo doesn't move.
            if (_launchVisible)
              IgnorePointer(
                ignoring: _phase != _Phase.loading,
                child: AnimatedOpacity(
                  opacity: _phase == _Phase.loading ? 1 : 0,
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                  onEnd: () {
                    if (_phase != _Phase.loading && mounted) {
                      setState(() => _launchVisible = false);
                    }
                  },
                  child: const LaunchView(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SmartOffline extends StatelessWidget {
  const _SmartOffline({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final onPrimary = context.palette.onPrimary;
    return Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: context.palette.brandGradient),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.wifi_off_rounded, color: onPrimary, size: 64),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'لا يوجد اتصال بالإنترنت',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: onPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'تقدر تتفرج على الدروس اللي حمّلتها من «التحميلات»',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: onPrimary.withValues(alpha: 0.85)),
                ),
                const SizedBox(height: AppSpacing.xxl),
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('إعادة المحاولة'),
                  style: FilledButton.styleFrom(
                    backgroundColor: onPrimary,
                    foregroundColor: context.palette.primary,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                TextButton.icon(
                  onPressed: () => context.push(downloadsPath),
                  icon: Icon(Icons.download_done_rounded, color: onPrimary),
                  label: Text('التحميلات', style: TextStyle(color: onPrimary)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
