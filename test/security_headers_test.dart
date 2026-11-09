import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/shared/utils/security_headers.dart';

void main() {
  test('adds the standard headers to every response', () async {
    final handler = securityHeadersMiddleware()((request) => Response.ok('ok'));
    final response = await handler(Request('GET', Uri.parse('http://x/')));
    expect(response.headers['x-content-type-options'], 'nosniff');
    expect(response.headers['x-frame-options'], 'DENY');
    expect(response.headers['referrer-policy'], 'no-referrer');
    expect(response.headers['permissions-policy'], contains('camera=()'));
    expect(response.headers['strict-transport-security'], contains('max-age='));
    expect(response.headers['content-security-policy'], contains("default-src 'self'"));
  });

  test('adds no-store to API responses', () async {
    final handler = securityHeadersMiddleware()((request) => Response.ok('ok'));
    final response = await handler(Request('GET', Uri.parse('http://x/api/stats')));
    expect(response.headers['cache-control'], 'no-store');
  });

  test('keeps a route cache policy that was set explicitly', () async {
    final handler = securityHeadersMiddleware()(
      (request) => Response.ok(
        'ok',
        headers: {'cache-control': 'public, max-age=60'},
      ),
    );
    final response = await handler(Request('GET', Uri.parse('http://x/api/stats')));
    expect(response.headers['cache-control'], 'public, max-age=60');
  });

  test('adds the API origin to the CSP connect-src', () async {
    final handler = securityHeadersMiddleware(
      apiOrigin: 'https://api.example.com',
    )((request) => Response.ok('ok'));
    final response = await handler(Request('GET', Uri.parse('http://x/')));
    expect(
      response.headers['content-security-policy'],
      contains("connect-src 'self' https://api.example.com"),
    );
  });

  test('a custom CSP wins over the default', () async {
    final handler = securityHeadersMiddleware(csp: "default-src 'none'")(
      (request) => Response.ok('ok'),
    );
    final response = await handler(Request('GET', Uri.parse('http://x/')));
    expect(response.headers['content-security-policy'], "default-src 'none'");
  });
}
