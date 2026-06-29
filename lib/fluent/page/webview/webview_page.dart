import 'dart:async';

import 'package:bot_toast/bot_toast.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';
import 'package:flutter_inappwebview_windows/flutter_inappwebview_windows.dart';
import 'package:pixez/custom_tab_plugin.dart';
import 'package:pixez/er/hoster.dart';
import 'package:pixez/er/leader.dart';
import 'package:pixez/fluent/page/webview/oauth_redirect_uri.dart';
import 'package:pixez/main.dart';
import 'package:pixez/network/network_mode.dart';
import 'package:pixez/network/pixez_network_settings.dart';
import 'package:pixez/weiss_plugin.dart';

class WebViewPage extends StatefulWidget {
  final String url;

  const WebViewPage({Key? key, required this.url}) : super(key: key);

  @override
  _WebViewPageState createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {
  WindowsInAppWebViewWidget? _webViewWidget;
  WindowsWebViewEnvironment? _webViewEnvironment;
  PlatformInAppWebViewController? _webViewController;
  double progressValue = 0.0;
  bool _handledRedirect = false;

  @override
  void initState() {
    super.initState();
    unawaited(_initWebView());
  }

  Future<void> _initWebView() async {
    WindowsWebViewEnvironment? environment;
    try {
      environment = await _createWebViewEnvironment();
    } catch (e) {
      BotToast.showText(text: e.toString());
    }

    final webViewWidget = _createWebViewWidget(environment);
    if (!mounted) {
      await environment?.dispose();
      return;
    }

    setState(() {
      _webViewEnvironment = environment;
      _webViewWidget = webViewWidget;
    });
  }

  Future<WindowsWebViewEnvironment?> _createWebViewEnvironment() async {
    final additionalBrowserArguments = _additionalBrowserArguments();
    if (additionalBrowserArguments == null) return null;
    return WindowsWebViewEnvironment.static().create(
      settings: WebViewEnvironmentSettings(
        additionalBrowserArguments: additionalBrowserArguments,
      ),
    );
  }

  String? _additionalBrowserArguments() {
    final mode = userSetting.oauthNetworkMode;
    if (!mode.usesCompatibleConnection) return null;
    // WebView2 runs in its own browser process, so it cannot reuse the app's
    // rhttp TLS/no-SNI client. Use WebView2 host resolver rules for the parts
    // of compatible login networking that can be expressed at browser level.
    final rules = _hostResolverRules(mode);
    return '--host-resolver-rules="$rules"';
  }

  String _hostResolverRules(NetworkMode mode) {
    final appApiIp = mode == NetworkMode.compat
        ? Hoster.api()
        : _cloudflarePixivIp;
    final oauthIp = mode == NetworkMode.compat
        ? Hoster.oauth()
        : _cloudflarePixivIp;
    final accountIp = _cloudflarePixivIp;
    return [
      'MAP ${PixezNetworkSettings.appApiHost} $appApiIp',
      'MAP ${PixezNetworkSettings.oauthHost} $oauthIp',
      'MAP ${PixezNetworkSettings.accountHost} $accountIp',
    ].join(',');
  }

  WindowsInAppWebViewWidget _createWebViewWidget(
    WindowsWebViewEnvironment? environment,
  ) {
    return WindowsInAppWebViewWidget(
      WindowsInAppWebViewWidgetCreationParams(
        webViewEnvironment: environment,
        initialUrlRequest: URLRequest(url: WebUri(widget.url)),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          useShouldOverrideUrlLoading: true,
        ),
        onWebViewCreated: (controller) {
          _webViewController = controller as PlatformInAppWebViewController;
        },
        onProgressChanged: (controller, progress) {
          if (mounted) setState(() => progressValue = progress / 100);
        },
        onLoadStart: (controller, url) => _handleLoginRedirect(url),
        onLoadStop: (controller, url) =>
            _hideUnavailableLoginMethods(controller, url),
        onReceivedError: (controller, request, error) {},
        shouldOverrideUrlLoading: (controller, navigationAction) =>
            _handleNavigation(navigationAction),
      ),
    );
  }

  Future<void> _hideUnavailableLoginMethods(
    PlatformInAppWebViewController controller,
    WebUri? url,
  ) async {
    if (url == null) return;
    if (userSetting.oauthNetworkMode.usesCompatibleConnection &&
        url.host == "accounts.pixiv.net") {
      await controller.evaluateJavascript(
        source: """
javascript:(function() {
 let forms = document.getElementsByTagName('form'); 
 for (let name of forms) {
    if (name['method'] === 'post' || name['method'] === 'POST') {
        name.style.display = 'none';
    }
  
}
 let list = document.getElementsByClassName("sns-button-list");
 for (let name of list) {
        name.style.display = 'none';
} 
  })()
""",
      );
    }
  }

  Future<NavigationActionPolicy> _handleNavigation(
    NavigationAction navigationAction,
  ) async {
    final redirectUri = normalizePixivOAuthRedirect(
      navigationAction.request.url,
    );
    if (redirectUri != null) {
      _handleLoginRedirect(redirectUri);
      return NavigationActionPolicy.CANCEL;
    }
    return NavigationActionPolicy.ALLOW;
  }

  void _handleLoginRedirect(Uri? uri) {
    final redirectUri = normalizePixivOAuthRedirect(uri);
    if (redirectUri == null || _handledRedirect) return;
    _handledRedirect = true;
    final controller = _webViewController;
    if (controller != null) unawaited(controller.stopLoading());
    unawaited(_completeLogin(redirectUri));
  }

  Future<void> _completeLogin(Uri uri) async {
    await Leader.pushWithUri(context, uri);
    if (mounted) Navigator.of(context).pop("OK");
  }

  @override
  void dispose() {
    _webViewWidget?.dispose();
    unawaited(_webViewEnvironment?.dispose() ?? Future.value());
    WeissPlugin.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaffoldPage(
      header: Row(
        children: [
          IconButton(
            icon: Icon(FluentIcons.open_in_new_window),
            onPressed: () {
              try {
                CustomTabPlugin.launch(widget.url);
              } catch (e) {
                BotToast.showText(text: e.toString());
              }
            },
          ),
          IconButton(
            icon: Icon(FluentIcons.refresh),
            onPressed: () => _webViewController?.reload(),
          ),
          SizedBox(width: 8.0),
          Visibility(
            visible: progressValue < 1.0,
            child: ProgressBar(value: progressValue * 100),
          ),
        ],
      ),
      content: _webViewWidget?.build(context) ?? Center(child: ProgressRing()),
    );
  }
}

const String _cloudflarePixivIp = '104.18.10.118';
