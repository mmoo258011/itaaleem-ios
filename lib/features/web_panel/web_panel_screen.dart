import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:itaaleem/core/config/obf.dart';
import 'package:itaaleem/core/network/dio_client.dart';
import 'package:itaaleem/core/utils/safe_url.dart';
import 'package:itaaleem/core/widgets/app_error_state.dart';
import 'package:itaaleem/core/widgets/app_toast.dart';
import 'package:itaaleem/features/web_panel/web_handoff.dart';
import 'package:itaaleem/features/web_panel/web_panel_files.dart';
import 'package:itaaleem/features/web_panel/web_panel_scripts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart' show LaunchMode;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

/// A web page on `*.itaaleem.com` inside the app — the center's Filament
/// panel or a server menu link — signed in with a one-time [WebHandoff]
/// when [handoff] is set (no token in any URL, no password again).
///
/// Back goes back inside the page; file inputs open the picker (Android);
/// downloads and exports are saved and offered to share; links on our
/// domain stay inside, others open outside on a real tap only. No screen
/// protection: this is staff work, not lesson content. Logout clears the
/// session with the rest of the WebView cookies (`clearSmartUiSession`).
class WebPanelScreen extends ConsumerStatefulWidget {
  const WebPanelScreen({
    super.key,
    required this.url,
    required this.title,
    this.handoff = true,
  });

  final Uri url;
  final String title;
  final bool handoff;

  @override
  ConsumerState<WebPanelScreen> createState() => _WebPanelScreenState();
}

enum _State { loading, ready, offline, refused }

class _WebPanelScreenState extends ConsumerState<WebPanelScreen> {
  WebViewController? _controller;
  _State _state = _State.loading;
  int _progress = 0;
  final String _nonce = _newNonce();

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
    unawaited(_start());
  }

  Future<void> _start() async {
    setState(() {
      _state = _State.loading;
      _progress = 0;
    });
    if (!isInAppWebAllowed(widget.url)) {
      setState(() => _state = _State.refused);
      return;
    }
    WebHandoff? handoff;
    if (widget.handoff) {
      try {
        handoff = await requestWebHandoff(
          ref.read(dioClientProvider),
          widget.url,
        );
      } on WebHandoffException catch (e) {
        if (kDebugMode) debugPrint('[WebPanel] handoff failed: $e');
        if (mounted) {
          setState(() => _state = e.offline ? _State.offline : _State.refused);
        }
        return;
      }
    }
    if (!mounted) return;
    final controller = _controller ??= await _createController();
    if (!mounted) return;
    setState(() => _state = _State.ready);
    if (handoff != null) {
      await controller.loadRequest(
        handoff.url,
        method: LoadRequestMethod.post,
        headers: WebHandoff.headers,
        body: handoff.body(widget.url),
      );
    } else {
      await controller.loadRequest(widget.url);
    }
  }

  Future<WebViewController> _createController() async {
    final controller = WebViewController();
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.addJavaScriptChannel(
      'PanelNative',
      onMessageReceived: (m) => unawaited(_onMessage(m.message)),
    );
    await controller.setNavigationDelegate(
      NavigationDelegate(
        onNavigationRequest: _onNavigationRequest,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
        onPageFinished: (url) => unawaited(_injectScript(url)),
        onWebResourceError: (error) {
          if (kDebugMode) {
            debugPrint('[WebPanel] web error: ${error.description}');
          }
          if ((error.isForMainFrame ?? true) && mounted) {
            setState(() => _state = _State.offline);
          }
        },
      ),
    );
    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      await platform.setOnShowFileSelector(_pickFiles);
    }
    return controller;
  }

  Future<void> _injectScript(String url) async {
    final uri = Uri.tryParse(url);
    final controller = _controller;
    if (uri == null || controller == null || !isInAppWebAllowed(uri)) return;
    try {
      await controller.runJavaScript(
        panelScript(
          nonce: _nonce,
          root: Obf.rootDomain,
          maxBytes: maxPanelDownloadBytes,
        ),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[WebPanel] script failed: $e');
    }
  }

  NavigationDecision _onNavigationRequest(NavigationRequest request) {
    final uri = Uri.tryParse(request.url);
    if (uri == null) return NavigationDecision.prevent;
    if (!request.isMainFrame) {
      return uri.scheme == 'https' && uri.userInfo.isEmpty
          ? NavigationDecision.navigate
          : NavigationDecision.prevent;
    }
    if (isInAppWebAllowed(uri)) {
      if (looksLikeDownload(uri)) {
        // A file, not a page: fetch it from the page with its cookies.
        unawaited(
          _controller?.runJavaScript(
            'window.__itaaleemDownload && '
            'window.__itaaleemDownload(${jsonEncode(uri.toString())}, null);',
          ),
        );
        return NavigationDecision.prevent;
      }
      return NavigationDecision.navigate;
    }
    // Off our domain: never inside. A real tap arrives as `open_link`.
    if (kDebugMode) debugPrint('[WebPanel] blocked: ${uri.host}');
    return NavigationDecision.prevent;
  }

  Future<void> _onMessage(String raw) async {
    final Object? json;
    try {
      json = jsonDecode(raw);
    } on FormatException {
      return;
    }
    if (json is! Map || json['nonce'] != _nonce || !mounted) return;
    switch (json['action']) {
      case 'open_link':
        final url = outsideTappedLink(json['url']);
        if (url != null) {
          await launchUrlSafely(url, mode: LaunchMode.externalApplication);
        }
      case 'download':
        await _saveDownload(json['name'], json['mime'], json['data']);
      case 'download_failed':
        AppToast.showError(
          context,
          json['reason'] == 'size'
              ? 'الملف أكبر من ${maxPanelDownloadBytes ~/ (1024 * 1024)} ميجا'
              : 'تعذر تحميل الملف',
        );
    }
  }

  Future<void> _saveDownload(Object? name, Object? mime, Object? data) async {
    final safe = safeDownloadName(
      name is String ? name : null,
      mime: mime is String ? mime : null,
    );
    final bytes = decodeDownload(data);
    if (safe == null || bytes == null) {
      if (mounted) AppToast.showError(context, 'نوع الملف ده مش مسموح');
      return;
    }
    try {
      final tmp = await getTemporaryDirectory();
      final dir = Directory(
        '${tmp.path}/panel_exports/${DateTime.now().microsecondsSinceEpoch}',
      );
      await dir.create(recursive: true);
      final path = downloadPathIn(dir.path, safe);
      if (path == null) return;
      await File(path).writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(path, mimeType: mime is String ? mime : null)],
        ),
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[WebPanel] save failed: $e');
      if (mounted) AppToast.showError(context, 'تعذر حفظ الملف');
    }
  }

  Future<List<String>> _pickFiles(FileSelectorParams params) async {
    try {
      if (params.isCaptureEnabled) {
        final shot = await ImagePicker().pickImage(source: ImageSource.camera);
        return shot == null ? const [] : [Uri.file(shot.path).toString()];
      }
      final picked = params.mode == FileSelectorMode.openMultiple
          ? await FilePicker.pickFiles(
              type: FileType.custom,
              allowedExtensions: panelUploadExtensions,
            )
          : [
              ?await FilePicker.pickFile(
                type: FileType.custom,
                allowedExtensions: panelUploadExtensions,
              ),
            ];
      final accepted = <String>[];
      var rejected = false;
      for (final file in picked) {
        final size = file.lengthSync() ?? await file.length();
        if (isPanelUploadAllowed(file.name, size)) {
          accepted.add(file.uri.toString());
        } else {
          rejected = true;
        }
      }
      if (rejected && mounted) {
        AppToast.showError(
          context,
          'مسموح بـ PDF أو صور أو Excel أو Word، وكل ملف لحد '
          '${maxPanelUploadBytes ~/ (1024 * 1024)} ميجا',
        );
      }
      return accepted;
    } catch (e) {
      if (kDebugMode) debugPrint('[WebPanel] file picker failed: $e');
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (_state == _State.ready &&
            controller != null &&
            await controller.canGoBack()) {
          await controller.goBack();
        } else {
          navigator.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: 'إغلاق',
            onPressed: () => Navigator.of(context).pop(),
          ),
          actions: [
            if (_state == _State.ready && controller != null)
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'تحديث',
                onPressed: controller.reload,
              ),
          ],
        ),
        body: switch (_state) {
          _State.offline => AppErrorState(
            title: 'تعذر فتح الصفحة',
            message: 'اتأكد من اتصالك بالإنترنت وحاول تاني',
            onRetry: _start,
          ),
          _State.refused => AppErrorState(
            title: 'الصفحة دي مش متاحة دلوقتي',
            message: 'حاول تاني بعد شوية',
            onRetry: _start,
          ),
          _State.loading => const Center(child: CircularProgressIndicator()),
          _State.ready => Stack(
            children: [
              if (controller != null) WebViewWidget(controller: controller),
              if (_progress < 100)
                LinearProgressIndicator(
                  value: _progress == 0 ? null : _progress / 100,
                  minHeight: 3,
                ),
            ],
          ),
        },
      ),
    );
  }
}
