import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:itaaleem/core/storage/secure_storage_service.dart';
import 'package:itaaleem/core/utils/platform_utils.dart';
import 'package:itaaleem/core/utils/safe_url.dart';
import 'package:itaaleem/core/widgets/app_error_state.dart';
import 'package:itaaleem/core/widgets/app_toast.dart';
import 'package:itaaleem/core/widgets/secure_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Opens a server-provided link (news, home cards, menu items,
/// notifications) where [classifyLink] says: the allowlist in the app's
/// WebView; other https pages in Custom Tabs / SFSafariViewController;
/// `external`/`whatsapp` in their app; `tel:` (type `phone`) in the dialer;
/// anything else refused.
Future<void> openConfigLink(
  BuildContext context,
  String url, {
  String? title,
  String? type,
}) async {
  final target = classifyLink(url, type: type);
  final uri = Uri.tryParse(url.trim());
  if (uri == null || target == LinkTarget.blocked) {
    if (context.mounted) AppToast.showError(context, 'تعذر فتح الرابط');
    return;
  }
  if (target == LinkTarget.inAppWeb) {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => InAppWebScreen(url: uri, title: title),
      ),
    );
    return;
  }
  final ok = switch (target) {
    LinkTarget.browser => await launchUrlSafely(
      uri,
      mode: LaunchMode.inAppBrowserView,
    ),
    LinkTarget.external => await launchUrlSafely(
      uri,
      mode: LaunchMode.externalApplication,
    ),
    LinkTarget.phone => await launchUrlSafely(uri),
    LinkTarget.inAppWeb || LinkTarget.blocked => false,
  };
  if (!ok && context.mounted) AppToast.showError(context, 'تعذر فتح الرابط');
}

/// A page from the allowlist inside the app, screen-protected like lessons.
class InAppWebScreen extends ConsumerStatefulWidget {
  const InAppWebScreen({super.key, required this.url, this.title});

  final Uri url;
  final String? title;

  @override
  ConsumerState<InAppWebScreen> createState() => _InAppWebScreenState();
}

class _InAppWebScreenState extends ConsumerState<InAppWebScreen> {
  late final WebViewController _controller;
  int _progress = 0;
  bool _failed = false;

  /// A navigation we started ourselves with headers — let it through once
  /// instead of re-issuing it.
  String? _ownLoad;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _onNavigationRequest,
          onProgress: (p) {
            if (mounted) setState(() => _progress = p);
          },
          onPageStarted: (_) {
            if (mounted) setState(() => _failed = false);
          },
          onWebResourceError: (error) {
            if (kDebugMode) {
              debugPrint('>>> webview error: ${error.description}');
            }
            if (error.isForMainFrame ?? true) {
              if (mounted) setState(() => _failed = true);
            }
          },
        ),
      );
    _load(widget.url);
  }

  Future<void> _load(Uri uri) async {
    final headers = <String, String>{'X-Platform': platformHeaderValue};
    if (sendsAuthToken(uri)) {
      final token = await ref
          .read(secureStorageServiceProvider)
          .readAuthToken();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    }
    _ownLoad = uri.toString();
    await _controller.loadRequest(uri, headers: headers);
  }

  NavigationDecision _onNavigationRequest(NavigationRequest request) {
    final uri = Uri.tryParse(request.url);
    if (uri == null) return NavigationDecision.prevent;
    if (request.url == _ownLoad) {
      _ownLoad = null;
      return NavigationDecision.navigate;
    }
    if (!request.isMainFrame) {
      // Embedded frames (e.g. a YouTube embed) may load from other https
      // hosts; never http, javascript:, data: or file:.
      return uri.scheme == 'https' && uri.userInfo.isEmpty
          ? NavigationDecision.navigate
          : NavigationDecision.prevent;
    }
    if (isInAppWebAllowed(uri)) {
      // Re-issue with our headers (token only for api.itaaleem.com).
      _load(uri);
      return NavigationDecision.prevent;
    }
    // Off the allowlist: never inside our WebView (it may carry the
    // token's page context); the browser decides, https only.
    if (classifyLink(request.url) == LinkTarget.browser) {
      launchUrlSafely(uri, mode: LaunchMode.externalApplication);
    }
    return NavigationDecision.prevent;
  }

  Future<void> _retry() async {
    setState(() {
      _failed = false;
      _progress = 0;
    });
    final current = await _controller.currentUrl();
    final uri = current == null ? null : Uri.tryParse(current);
    await _load(uri != null && isInAppWebAllowed(uri) ? uri : widget.url);
  }

  @override
  Widget build(BuildContext context) {
    return SecureScreen(
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          final navigator = Navigator.of(context);
          if (!_failed && await _controller.canGoBack()) {
            await _controller.goBack();
          } else {
            navigator.pop();
          }
        },
        child: Scaffold(
          appBar: AppBar(
            title: Text(widget.title ?? ''),
            leading: const BackButton(),
          ),
          body: Stack(
            children: [
              if (_failed)
                AppErrorState(
                  title: 'تعذر فتح الصفحة',
                  message: 'اتأكد من اتصالك بالإنترنت وحاول تاني',
                  onRetry: _retry,
                )
              else
                WebViewWidget(controller: _controller),
              if (!_failed && _progress < 100)
                LinearProgressIndicator(
                  value: _progress == 0 ? null : _progress / 100,
                  minHeight: 3,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
