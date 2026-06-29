const String pixivAppApiHost = 'app-api.pixiv.net';

bool isPixivOAuthWebViewUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.host != pixivAppApiHost) return false;
  return uri.path == '/web/v1/login' ||
      uri.path == '/web/v1/provisional-accounts/create';
}

Uri? normalizePixivOAuthRedirect(Uri? uri) {
  if (uri == null) return null;
  if (uri.scheme == 'pixiv') return uri;
  if (uri.host == pixivAppApiHost &&
      uri.path.endsWith('/web/v1/users/auth/pixiv/callback')) {
    final code = uri.queryParameters['code'];
    if (code != null && code.isNotEmpty) {
      return Uri(
        scheme: 'pixiv',
        host: 'account',
        queryParameters: {'code': code},
      );
    }
  }
  return null;
}
