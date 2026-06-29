import 'package:flutter_test/flutter_test.dart';
import 'package:pixez/fluent/page/webview/oauth_redirect_uri.dart';

void main() {
  group('isPixivOAuthWebViewUrl', () {
    test('accepts login and account creation urls', () {
      expect(
        isPixivOAuthWebViewUrl(
          'https://app-api.pixiv.net/web/v1/login?client=pixiv-android',
        ),
        isTrue,
      );
      expect(
        isPixivOAuthWebViewUrl(
          'https://app-api.pixiv.net/web/v1/provisional-accounts/create'
          '?client=pixiv-android',
        ),
        isTrue,
      );
    });

    test('keeps unrelated links outside the embedded login webview', () {
      expect(
        isPixivOAuthWebViewUrl('https://www.pixiv.net/terms/?page=term'),
        isFalse,
      );
    });
  });

  group('normalizePixivOAuthRedirect', () {
    test('converts app-api callback into the existing pixiv account uri', () {
      final uri = normalizePixivOAuthRedirect(
        Uri.parse(
          'https://app-api.pixiv.net/web/v1/users/auth/pixiv/callback'
          '?code=abc123',
        ),
      );

      expect(uri, Uri.parse('pixiv://account?code=abc123'));
    });

    test('passes pixiv scheme redirects through unchanged', () {
      final redirect = Uri.parse('pixiv://account?code=abc123');

      expect(normalizePixivOAuthRedirect(redirect), redirect);
    });

    test('ignores callbacks without an authorization code', () {
      expect(
        normalizePixivOAuthRedirect(
          Uri.parse(
            'https://app-api.pixiv.net/web/v1/users/auth/pixiv/callback',
          ),
        ),
        isNull,
      );
    });
  });
}
