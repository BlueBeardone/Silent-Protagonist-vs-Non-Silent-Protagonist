import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'comments.dart';
import 'rate_limit.dart';
import 'stats.dart';

/// The largest request body we will read for a new comment.
const int _maxCommentBodyBytes = 8192;

/// Page size for `GET /api/comments` when the caller doesn't ask for one.
const int _defaultPageSize = 50;

/// The largest page a caller may request.
const int _maxPageSize = 100;

/// Builds the community-comments API. This endpoint is public, so every input
/// is treated as hostile: only the exact `email`/`comment` shape is accepted,
/// bodies are size-capped, and the full email never appears in a response.
///
/// Routes:
/// - `POST /api/comments` — create a comment.
/// - `GET /api/comments` — list comments, newest first.
/// - `DELETE /api/comments/<id>` — remove a comment (admin token required).
///
/// [allowedOrigin] is echoed as `access-control-allow-origin` on every
/// response (including errors); it defaults to `*` for the cross-port Flutter
/// web app. Pass `null` to omit the header entirely.
///
/// [trustedProxyHops] is the number of reverse proxies in front of this server.
/// Only when it is greater than zero is `x-forwarded-for` consulted, taking the
/// hop-th entry from the end of the chain. Otherwise the header is ignored so a
/// client cannot spoof its own address.
Handler commentsHandler({
  required CommentsStore store,
  required RateLimiter writeLimiter,
  required RateLimiter readLimiter,
  String? allowedOrigin = '*',
  String adminToken = '',
  int trustedProxyHops = 0,
}) {
  final router = Router();

  router.post('/api/comments', (Request request) async {
    if (!_isJson(request)) {
      return _jsonError(415, 'Content-Type must be application/json.');
    }

    // Reject early when the client advertises an oversized body; otherwise
    // fall through and measure what we actually read.
    final declaredLength = request.contentLength;
    if (declaredLength != null && declaredLength > _maxCommentBodyBytes) {
      return _jsonError(413, 'Request body is too large.');
    }

    final String raw;
    try {
      raw = await request.readAsString();
    } catch (_) {
      return _jsonError(400, 'Could not read the request body.');
    }
    if (utf8.encode(raw).length > _maxCommentBodyBytes) {
      return _jsonError(413, 'Request body is too large.');
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return _jsonError(400, 'Request body must be valid JSON.');
    }
    if (decoded is! Map) {
      return _jsonError(400, 'Request body must be a JSON object.');
    }

    // Never build a query from arbitrary keys: accept exactly two known keys.
    final map = decoded.cast<String, Object?>();
    if (map.length != 2 ||
        !map.containsKey('email') ||
        !map.containsKey('comment')) {
      return _jsonError(
          400, 'Body must contain exactly "email" and "comment".');
    }

    final email = map['email'];
    final comment = map['comment'];
    if (email is! String || comment is! String) {
      return _jsonError(400, 'Email and comment must be strings.');
    }

    final emailError = validateEmail(email);
    if (emailError != null) return _jsonError(400, emailError);
    final commentError = validateComment(comment);
    if (commentError != null) return _jsonError(400, commentError);

    // Rate-limit after validation so rejected input doesn't consume quota.
    if (!writeLimiter.allow(_clientIp(request, trustedProxyHops))) {
      return _jsonError(429, 'Too many requests. Please slow down.');
    }

    final saved = await store.add(
      email: email.trim(),
      comment: comment.trim(),
    );
    return _json(201, saved.toJson());
  });

  router.get('/api/comments', (Request request) async {
    if (!readLimiter.allow(_clientIp(request, trustedProxyHops))) {
      return _jsonError(429, 'Too many requests. Please slow down.');
    }

    final params = request.url.queryParameters;
    var limit = int.tryParse(params['limit'] ?? '') ?? _defaultPageSize;
    if (limit < 1) limit = 1;
    if (limit > _maxPageSize) limit = _maxPageSize;
    final before = params['before'];

    final List<Comment> comments;
    try {
      comments = await store.recent(limit: limit, before: before);
    } catch (_) {
      return _jsonError(400, 'Invalid cursor.');
    }

    return _json(200, {
      'comments': [for (final comment in comments) comment.toJson()],
      'nextCursor': comments.length == limit
          ? comments.last.createdAt.toUtc().toIso8601String()
          : null,
    });
  });

  router.delete('/api/comments/<id>', (Request request, String id) async {
    if (adminToken.isEmpty ||
        !_constantTimeEquals(request.headers['x-admin-token'], adminToken)) {
      return _jsonError(401, 'Unauthorized.');
    }
    final removed = await store.deleteById(id);
    return removed ? Response(204) : Response.notFound(null);
  });

  final routerHandler = router.call;
  return (Request request) async {
    final response = await routerHandler(request);
    if (allowedOrigin == null) return response;
    return response.change(
      headers: {'access-control-allow-origin': allowedOrigin},
    );
  };
}

/// Whether [request] declares a JSON content type.
bool _isJson(Request request) {
  final contentType = request.headers['content-type'];
  if (contentType == null) return false;
  final mediaType = contentType.split(';').first.trim().toLowerCase();
  return mediaType == 'application/json' || mediaType.endsWith('+json');
}

/// A JSON response with [status] and the given [body].
Response _json(int status, Object? body) => Response(
      status,
      body: jsonEncode(body),
      headers: {'content-type': 'application/json'},
    );

/// A JSON error response of the shape `{"error": message}`.
Response _jsonError(int status, String message) =>
    _json(status, {'error': message});

/// Resolves the client address for rate limiting.
///
/// `x-forwarded-for` is trusted only when [trustedProxyHops] is positive, in
/// which case the hop-th entry from the end of the chain is used. The value is
/// otherwise read from the connection info; when neither is available (for
/// example in tests) a constant key is returned so every request shares it.
String _clientIp(Request request, int trustedProxyHops) {
  if (trustedProxyHops > 0) {
    final forwarded = request.headers['x-forwarded-for'];
    if (forwarded != null) {
      final hops = forwarded
          .split(',')
          .map((entry) => entry.trim())
          .where((entry) => entry.isNotEmpty)
          .toList();
      if (hops.isNotEmpty) {
        final index = hops.length - trustedProxyHops;
        return index >= 0 ? hops[index] : hops.first;
      }
    }
  }

  final info = request.context['shelf.io.connection_info'];
  if (info != null) {
    try {
      final address = (info as dynamic).remoteAddress;
      final value = (address as dynamic)?.address;
      if (value is String && value.isNotEmpty) return value;
    } catch (_) {
      // Fall through to the constant key below.
    }
  }
  return 'unknown';
}

/// Compares two strings without short-circuiting on the first difference, so
/// the comparison time does not reveal how much of a token matched.
bool _constantTimeEquals(String? a, String? b) {
  final left = utf8.encode(a ?? '');
  final right = utf8.encode(b ?? '');
  var difference = left.length ^ right.length;
  final length = left.length > right.length ? left.length : right.length;
  for (var i = 0; i < length; i++) {
    final leftByte = i < left.length ? left[i] : 0;
    final rightByte = i < right.length ? right[i] : 0;
    difference |= leftByte ^ rightByte;
  }
  return difference == 0;
}

/// Supplies the current stats for all games. Injectable so the handler can be
/// tested without touching the network.
typedef StatsFetcher = Future<List<GameStats>> Function();

/// Builds the proxy handler. The browser can't reach Steam or SteamCharts
/// directly (no CORS headers), so everything goes through here.
Handler statsHandler(StatsFetcher fetchStats) {
  final router = Router()
    ..get('/api/stats', (Request request) async {
      final stats = await fetchStats();
      return Response.ok(
        jsonEncode([for (final game in stats) game.toJson()]),
        headers: {
          'content-type': 'application/json',
          'access-control-allow-origin': '*',
        },
      );
    });
  return router.call;
}

/// Fetches live numbers for every game from the real sources. A failure on
/// either source leaves just that field null; the request never throws.
Future<List<GameStats>> fetchLiveStats() async {
  final client = http.Client();
  try {
    final results = <GameStats>[];
    for (final game in games) {
      results.add(await _fetchOne(client, game));
    }
    return results;
  } finally {
    client.close();
  }
}

Future<GameStats> _fetchOne(http.Client client, GameStats game) async {
  int? current;
  double? avg30d;
  double? avg6m;
  int? peakAllTime;

  try {
    final response = await client.get(Uri.parse(
        'https://api.steampowered.com/ISteamUserStats/GetNumberOfCurrentPlayers/v1/?appid=${game.appid}'));
    if (response.statusCode == 200) {
      current = parseCurrentPlayers(response.body);
    }
  } catch (_) {
    // Leave current null; the UI shows a dash.
  }

  try {
    final response = await client.get(
      Uri.parse('https://steamcharts.com/app/${game.appid}'),
      headers: {'User-Agent': 'Mozilla/5.0'},
    );
    if (response.statusCode == 200) {
      avg30d = parseSteamChartsAvg(response.body);
      try {
        avg6m = parseSteamCharts6mAvg(response.body);
      } catch (_) {
        // Leave avg6m null; the UI shows a dash.
      }
      try {
        peakAllTime = parseSteamChartsAllTimePeak(response.body);
      } catch (_) {
        // Leave peakAllTime null; the UI shows a dash.
      }
    }
  } catch (_) {
    // Leave avg30d null; the UI shows a dash.
  }

  return GameStats(
    name: game.name,
    camp: game.camp,
    appid: game.appid,
    current: current,
    avg30d: avg30d,
    avg6m: avg6m,
    peakAllTime: peakAllTime,
  );
}
