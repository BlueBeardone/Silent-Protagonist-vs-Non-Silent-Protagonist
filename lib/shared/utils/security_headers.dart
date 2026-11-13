import 'package:shelf/shelf.dart';

const Map<String, String> _defaultHeaders = {
  'x-content-type-options': 'nosniff',
  'x-frame-options': 'DENY',
  'referrer-policy': 'no-referrer',
  'permissions-policy': 'camera=(), microphone=(), geolocation=()',
  'strict-transport-security': 'max-age=31536000; includeSubDomains',
};

/// A CSP that works with the default Flutter web build.
const String _defaultCsp = "default-src 'self'; "
    "script-src 'self' 'unsafe-inline' 'unsafe-eval' "
    "https://www.gstatic.com https://cdn.jsdelivr.net; "
    "style-src 'self' 'unsafe-inline'; "
    "img-src 'self' data: blob:; "
    "font-src 'self' data: https://fonts.gstatic.com; "
    "connect-src 'self' https://www.gstatic.com https://fonts.gstatic.com; "
    "frame-ancestors 'none'; "
    "base-uri 'self'; "
    "form-action 'self';";

/// Adds browser security headers to every response.
///
/// [apiOrigin] is appended to `connect-src` when the app is served from a
/// different origin than the API (for example Netlify + Render).
///
/// [csp] overrides the default policy. The `CSP` environment variable is
/// passed through so a deployment can tighten or loosen it.
Middleware securityHeadersMiddleware({
  String? csp,
  String? apiOrigin,
  Map<String, String>? extraHeaders,
}) {
  final policy = _buildCsp(csp, apiOrigin);
  final headers = <String, String>{
    ..._defaultHeaders,
    'content-security-policy': policy,
    ...?extraHeaders,
  };
  return (Handler inner) {
    return (Request request) async {
      final response = await inner(request);
      final isApi = request.url.path.startsWith('api/');
      return response.change(
        headers: {
          ...headers,
          // API responses are not cacheable, but let a route that already set
          // a cache policy (for example the cached /api/stats) keep it.
          if (isApi && !response.headers.containsKey('cache-control'))
            'cache-control': 'no-store',
        },
      );
    };
  };
}

String _buildCsp(String? csp, String? apiOrigin) {
  if (csp != null && csp.isNotEmpty) return csp;
  final origin = _originOf(apiOrigin);
  if (origin == null) return _defaultCsp;
  return _defaultCsp.replaceFirst(
    "connect-src 'self'",
    "connect-src 'self' $origin",
  );
}

/// Extracts a scheme://host[:port] origin from [value], or null when it is not
/// a valid absolute http(s) URL.
String? _originOf(String? value) {
  if (value == null || value.isEmpty) return null;
  final uri = Uri.tryParse(value);
  if (uri == null || uri.scheme.isEmpty || uri.host.isEmpty) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  final port = uri.hasPort ? ':${uri.port}' : '';
  return '${uri.scheme}://${uri.host}$port';
}
