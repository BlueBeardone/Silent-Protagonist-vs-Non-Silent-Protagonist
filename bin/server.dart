import 'dart:convert';
import 'dart:io';

import 'package:dotenv/dotenv.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_static/shelf_static.dart';

import 'package:silent_protagonist_vs_non_silent_protagonist/comments/logic/comments.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/shared/utils/rate_limit.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/shared/utils/server.dart';

/// How many comments a single client may create in [writeWindow].
const int _writeLimit = 5;
const Duration _writeWindow = Duration(minutes: 10);

/// How many comment reads a single client may make in [readWindow].
const int _readLimit = 60;
const Duration _readWindow = Duration(minutes: 1);

/// A [CommentsStore] that opens its MongoDB connection lazily and retries after
/// a failure.
///
/// The server must be able to boot (and keep serving `/api/stats` and the
/// static app) even when Atlas is unreachable, so connecting is deferred until
/// the first comments request. A failed connect is not cached: the next request
/// tries again. An operation that fails after a successful connect drops the
/// cached connection so a later request can reconnect.
class LazyMongoCommentsStore implements CommentsStore {
  LazyMongoCommentsStore(this._uri);

  final String _uri;

  MongoCommentsStore? _store;
  Future<MongoCommentsStore>? _connecting;

  /// Opens the connection if needed. Exposed so the entrypoint can eagerly
  /// probe at boot (to log a warning) and so the availability middleware can
  /// short-circuit comments routes with a `503`.
  Future<void> ensureConnected() async {
    await _connection();
  }

  Future<MongoCommentsStore> _connection() {
    final existing = _store;
    if (existing != null) return Future<MongoCommentsStore>.value(existing);
    return _connecting ??= _connect();
  }

  Future<MongoCommentsStore> _connect() async {
    try {
      final store = await MongoCommentsStore.connect(_uri);
      _store = store;
      return store;
    } catch (_) {
      // Keep the raw driver error out of the message: it can embed the
      // connection URI (with credentials).
      throw CommentsUnavailableException('Could not connect to MongoDB.');
    } finally {
      _connecting = null;
    }
  }

  Future<T> _with<T>(
    Future<T> Function(MongoCommentsStore store) action,
  ) async {
    final store = await _connection();
    try {
      return await action(store);
    } on CommentsUnavailableException {
      rethrow;
    } catch (_) {
      // A failure mid-operation likely means the connection dropped; forget it
      // so the next request reconnects instead of reusing a dead client. The
      // raw error is not surfaced: it can embed the connection URI.
      _store = null;
      throw CommentsUnavailableException('Comments store unavailable.');
    }
  }

  @override
  Future<Comment> add({required String email, required String comment}) =>
      _with((store) => store.add(email: email, comment: comment));

  @override
  Future<List<Comment>> recent({int limit = 50, String? before}) =>
      _with((store) => store.recent(limit: limit, before: before));

  @override
  Future<bool> deleteById(String id) =>
      _with((store) => store.deleteById(id));
}

/// Answers CORS preflight requests in development.
///
/// Production is same-origin and leaves [allowedOrigin] null, in which case
/// this is a no-op. When an origin is configured, `OPTIONS` short-circuits with
/// a `204` advertising the methods and headers the comments API accepts.
Middleware corsPreflightMiddleware(String? allowedOrigin) {
  return (Handler inner) {
    return (Request request) {
      if (allowedOrigin == null || request.method != 'OPTIONS') {
        return inner(request);
      }
      return Response(
        204,
        headers: {
          'access-control-allow-origin': allowedOrigin,
          'access-control-allow-methods': 'GET, POST, DELETE, OPTIONS',
          'access-control-allow-headers': 'content-type, x-admin-token',
        },
      );
    };
  };
}

/// Turns an unreachable comments backend into a `503` instead of a `500`.
///
/// Comments routes are probed first: a known-down Mongo short-circuits with a
/// `503` before the handler runs, which also covers `GET /api/comments` (whose
/// handler reports a bad cursor for any store failure). The wrapped call is
/// also guarded so a connection that drops mid-request still yields `503`.
Middleware commentsAvailabilityMiddleware(
  LazyMongoCommentsStore store,
  String? allowedOrigin,
) {
  return (Handler inner) {
    return (Request request) async {
      if (_isCommentsRoute(request.url.path)) {
        try {
          await store.ensureConnected();
        } on CommentsUnavailableException {
          return _unavailable(allowedOrigin);
        }
      }
      try {
        return await inner(request);
      } on CommentsUnavailableException {
        return _unavailable(allowedOrigin);
      }
    };
  };
}

/// Whether [path] (as in [Request.url], with no leading slash) targets the
/// comments API.
bool _isCommentsRoute(String path) =>
    path == 'api/comments' || path.startsWith('api/comments/');

/// A `503` JSON response for an unavailable comments backend, keeping the CORS
/// header in development so the browser can read the error.
Response _unavailable(String? allowedOrigin) {
  return Response(
    503,
    body: jsonEncode({'error': 'Comments are temporarily unavailable.'}),
    headers: {
      'content-type': 'application/json',
      'access-control-allow-origin': ?allowedOrigin,
    },
  );
}

Future<void> main(List<String> args) async {
  // Load a local `.env` when present so `dart run bin/server.dart` works without
  // exporting the variables by hand. Real process environment variables are
  // still included, and a missing `.env` is fine — production supplies them
  // directly.
  final env = DotEnv(includePlatformEnvironment: true);
  if (File('.env').existsSync()) env.load();

  final mongoUri = env['MONGODB_URI']?.trim() ?? '';
  if (mongoUri.isEmpty) {
    stderr.writeln(
      'MONGODB_URI is required. Set it to your MongoDB connection string.',
    );
    exitCode = 64;
    return;
  }

  final adminToken = env['ADMIN_TOKEN']?.trim() ?? '';
  final rawOrigin = env['ALLOWED_ORIGIN']?.trim();
  final allowedOrigin = (rawOrigin == null || rawOrigin.isEmpty) ? null : rawOrigin;
  final trustedProxyHops =
      int.tryParse(env['TRUSTED_PROXY_HOPS']?.trim() ?? '') ?? 0;
  final port = int.tryParse(env['PORT']?.trim() ?? '') ?? 8080;

  final store = LazyMongoCommentsStore(mongoUri);
  try {
    await store.ensureConnected();
    stdout.writeln('Connected to MongoDB.');
  } on CommentsUnavailableException catch (error) {
    stderr.writeln('Warning: ${error.message}');
    stderr.writeln(
      'Comments API will return 503 until MongoDB becomes reachable.',
    );
  }

  final comments = commentsHandler(
    store: store,
    writeLimiter: RateLimiter(maxRequests: _writeLimit, window: _writeWindow),
    readLimiter: RateLimiter(maxRequests: _readLimit, window: _readWindow),
    allowedOrigin: allowedOrigin,
    adminToken: adminToken,
    trustedProxyHops: trustedProxyHops,
  );

  final staticHandler = _staticHandlerOr404();

  final cascade = Cascade()
      .add(comments)
      .add(statsHandler(fetchLiveStats))
      .add(staticHandler)
      .handler;

  final handler = const Pipeline()
      .addMiddleware(corsPreflightMiddleware(allowedOrigin))
      .addMiddleware(commentsAvailabilityMiddleware(store, allowedOrigin))
      .addHandler(cascade);

  final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  stdout.writeln('Server listening on http://${server.address.host}:${server.port}');
}

/// Builds the static file handler, or a `404` handler when `build/web` is
/// missing.
///
/// `createStaticHandler` throws when its directory is absent. The server still
/// boots so the API and stats keep working before `flutter build web` has
/// produced `build/web`.
Handler _staticHandlerOr404() {
  try {
    return createStaticHandler('build/web', defaultDocument: 'index.html');
  } on ArgumentError {
    stderr.writeln(
      'Warning: build/web not found; static hosting disabled. '
      'Run `flutter build web` to serve the app.',
    );
    return (Request request) => Response.notFound('Not found');
  }
}
