import 'dart:async';

import 'package:bot_toast/bot_toast.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_inappwebview_platform_interface/flutter_inappwebview_platform_interface.dart';
import 'package:flutter_inappwebview_windows/flutter_inappwebview_windows.dart';
import 'package:pixez/custom_tab_plugin.dart';
import 'package:pixez/er/leader.dart';
import 'package:pixez/main.dart';
import 'package:pixez/weiss_plugin.dart';

class WebViewPage extends StatefulWidget {
  final String url;

  const WebViewPage({Key? key, required this.url}) : super(key: key);

  @override
  _WebViewPageState createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> {
  late final WindowsInAppWebViewWidget _webViewWidget;
  PlatformInAppWebViewController? _webViewController;
  double progressValue = 0.0;
  bool _handledRedirect = false;

  @override
  void initState() {
    super.initState();
    _webViewWidget = WindowsInAppWebViewWidget(
      WindowsInAppWebViewWidgetCreationParams(
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
    final redirectUri = _oauthRedirectUri(navigationAction.request.url);
    if (redirectUri != null) {
      _handleLoginRedirect(redirectUri);
      return NavigationActionPolicy.CANCEL;
    }
    return NavigationActionPolicy.ALLOW;
  }

  Uri? _oauthRedirectUri(Uri? uri) {
    if (uri == null) return null;
    if (uri.scheme == "pixiv") return uri;
    if (uri.host == "app-api.pixiv.net" &&
        uri.path.endsWith("/web/v1/users/auth/pixiv/callback")) {
      final code = uri.queryParameters["code"];
      if (code != null && code.isNotEmpty) {
        return Uri(
          scheme: "pixiv",
          host: "account",
          queryParameters: {"code": code},
        );
      }
    }
    return null;
  }

  void _handleLoginRedirect(Uri? uri) {
    final redirectUri = _oauthRedirectUri(uri);
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
    _webViewWidget.dispose();
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
      content: _webViewWidget.build(context),
    );
  }
}
