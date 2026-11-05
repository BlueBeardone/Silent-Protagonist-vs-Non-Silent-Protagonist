import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/comments.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/rate_limit.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/server.dart';

import '../bin/server.dart' show LazyMongoCommentsStore, commentsAvailabilityMiddleware;

Handler build({
  String adminToken = 'secret',
  int trustedProxyHops = 0,
  int writeLimit = 5,
  CommentsStore? store,
}) =>
    commentsHandler(
      store: store ?? InMemoryCommentsStore(),
      writeLimiter: RateLimiter(maxRequests: writeLimit, window: const Duration(minutes: 10)),
      readLimiter: RateLimiter(maxRequests: 60, window: const Duration(minutes: 1)),
      allowedOrigin: 'http://localhost',
      adminToken: adminToken,
      trustedProxyHops: trustedProxyHops,
    );

Request post(Object body) => Request(
      'POST',
      Uri.parse('http://localhost/api/comments'),
      body: jsonEncode(body),
      headers: {'content-type': 'application/json'},
    );

/// A store whose [recent] always fails as if the backend were down.
class _DownStore implements CommentsStore {
  @override
  Future<Comment> add({required String email, required String comment}) async =>
      throw UnimplementedError();

  @override
  Future<List<Comment>> recent({int limit = 50, String? before}) async =>
      throw CommentsUnavailableException('down');

  @override
  Future<bool> deleteById(String id) async => false;
}

void main() {
  test('stores a valid comment and returns the masked email', () async {
    final response = await build()(post({'email': 'barry@gmail.com', 'comment': 'loved it'}));
    expect(response.statusCode, 201);
    final json = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    expect(json['email'], 'bar***@gmail.com');
    expect(json.toString(), isNot(contains('barry@gmail.com')));
  });

  test('rejects bad input with 400, never 500', () async {
    for (final body in [
      {'comment': 'no email'},
      {'email': 'nope', 'comment': 'x'},
      {'email': 'a@x.com', 'comment': '   '},
      {'email': 'a@x.com', 'comment': 'a' * 2001},
      {'email': 5, 'comment': 'x'},
      {'email': 'a@x.com', 'comment': 'x', r'$where': '1'},
    ]) {
      final handler = build();
      expect((await handler(post(body))).statusCode, 400, reason: '$body');
    }
  });

  test('rejects a non-JSON body and a wrong content-type', () async {
    final handler = build();
    final bad = await handler(Request('POST', Uri.parse('http://localhost/api/comments'),
        body: 'not json', headers: {'content-type': 'application/json'}));
    expect(bad.statusCode, 400);
    final wrong = await handler(Request('POST', Uri.parse('http://localhost/api/comments'),
        body: '{}', headers: {'content-type': 'text/plain'}));
    expect(wrong.statusCode, 415);
  });

  test('rejects an oversized body with 413', () async {
    final body = jsonEncode({'email': 'a@x.com', 'comment': 'a' * 9000});
    final response = await build()(Request('POST', Uri.parse('http://localhost/api/comments'),
        body: body, headers: {'content-type': 'application/json'}));
    expect(response.statusCode, 413);
  });

  test('rejects a chunked body over the limit with no content-length', () async {
    // A stream body carries no content-length, as a Transfer-Encoding: chunked
    // request would. The handler must abort on the streamed byte count.
    final bytes = utf8.encode(
      jsonEncode({'email': 'a@x.com', 'comment': 'a' * 9000}),
    );
    final stream = Stream<List<int>>.fromIterable([bytes]);
    final request = Request('POST', Uri.parse('http://localhost/api/comments'),
        body: stream, headers: {'content-type': 'application/json'});
    expect(request.contentLength, isNull);
    final response = await build()(request);
    expect(response.statusCode, 413);
  });

  test('stores the sanitized comment, stripping control characters', () async {
    final handler = build();
    final created = await handler(
        post({'email': 'a@x.com', 'comment': 'a\u0000b\u0007c'}));
    expect(created.statusCode, 201);
    final response = await handler(
        Request('GET', Uri.parse('http://localhost/api/comments')));
    final json =
        jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    expect((json['comments'] as List).first['comment'], 'abc');
  });

  test('rejects a comment made only of control characters', () async {
    final handler = build();
    expect(
      (await handler(post({'email': 'a@x.com', 'comment': '\u0000\u0007'})))
          .statusCode,
      400,
    );
  });

  test('reports a malformed cursor as 400 but not a backend outage', () async {
    final handler = build();
    final bad = await handler(Request(
        'GET', Uri.parse('http://localhost/api/comments?before=not-a-date')));
    expect(bad.statusCode, 400);

    // A backend outage must propagate as CommentsUnavailableException so the
    // availability middleware can turn it into a 503 rather than a bogus 400.
    final down = build(store: _DownStore());
    await expectLater(
      down(Request('GET', Uri.parse('http://localhost/api/comments'))),
      throwsA(isA<CommentsUnavailableException>()),
    );
  });

  test('rejects a malformed cursor before the Mongo wrapper can map it to 503',
      () async {
    // On the real path LazyMongoCommentsStore wraps the store's DateTime.parse
    // failure as CommentsUnavailableException, which the availability
    // middleware turns into a 503. The handler must reject the cursor itself so
    // the store never sees it; _DownStore stands in for that wrapper.
    final handler = build(store: _DownStore());
    final response = await handler(Request(
        'GET', Uri.parse('http://localhost/api/comments?before=not-a-date')));
    expect(response.statusCode, 400);
  });

  test('never throws on a malformed X-Forwarded-For value', () async {
    final handler = build(trustedProxyHops: 1, writeLimit: 1);
    FutureOr<Response> postFrom(String ip) => handler(Request(
          'POST',
          Uri.parse('http://localhost/api/comments'),
          body: jsonEncode({'email': 'a@x.com', 'comment': 'x'}),
          headers: {
            'content-type': 'application/json',
            'x-forwarded-for': ip,
          },
        ));
    for (final ip in ['::1.2.3', '::ffff:1.2.3', ':::garbage', '1.2.3.4.5']) {
      final status = (await postFrom(ip)).statusCode;
      expect(status, isIn([200, 201, 429]), reason: ip);
    }
  });

  test('falls back to the socket IP when XFF is shorter than trusted hops',
      () async {
    // With two trusted hops, a single-entry chain is client-controlled and
    // must be ignored: every request then shares the constant socket key.
    final handler = build(trustedProxyHops: 2, writeLimit: 1);
    FutureOr<Response> postFrom(String ip) => handler(Request(
          'POST',
          Uri.parse('http://localhost/api/comments'),
          body: jsonEncode({'email': 'a@x.com', 'comment': 'x'}),
          headers: {
            'content-type': 'application/json',
            'x-forwarded-for': ip,
          },
        ));
    expect((await postFrom('1.1.1.1')).statusCode, 201);
    expect((await postFrom('2.2.2.2')).statusCode, 429);
  });

  test('groups IPv6 clients by /64 prefix', () async {
    final handler = build(trustedProxyHops: 1, writeLimit: 1);
    FutureOr<Response> postFrom(String ip) => handler(Request(
          'POST',
          Uri.parse('http://localhost/api/comments'),
          body: jsonEncode({'email': 'a@x.com', 'comment': 'x'}),
          headers: {
            'content-type': 'application/json',
            'x-forwarded-for': ip,
          },
        ));
    expect((await postFrom('2001:db8:1:2::1')).statusCode, 201);
    // Same /64, different host address: must share the limit.
    expect((await postFrom('2001:db8:1:2:ffff::9')).statusCode, 429);
    // Different /64 is a different key.
    expect((await postFrom('2001:db8:1:3::1')).statusCode, 201);
  });

  test('adds Vary: Origin when reflecting an allowed origin', () async {
    final response = await build()(Request(
        'GET', Uri.parse('http://localhost/api/comments')));
    expect(response.headers['access-control-allow-origin'], 'http://localhost');
    expect(response.headers['vary'], 'Origin');
  });

  test('lists comments newest-first with masked emails only', () async {
    final handler = build();
    await handler(post({'email': 'a@x.com', 'comment': 'one'}));
    await handler(post({'email': 'barry@gmail.com', 'comment': 'two'}));
    final response = await handler(Request('GET', Uri.parse('http://localhost/api/comments')));
    expect(response.statusCode, 200);
    final json = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    final comments = json['comments'] as List;
    expect(comments.first['comment'], 'two');
    expect(comments.first['email'], 'bar***@gmail.com');
    expect(response.headers['access-control-allow-origin'], isNotNull);
  });

  test('round-trips HTML markup as inert text', () async {
    final handler = build();
    await handler(post({'email': 'a@x.com', 'comment': '<script>alert(1)</script>'}));
    final response = await handler(Request('GET', Uri.parse('http://localhost/api/comments')));
    final json = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    expect((json['comments'] as List).first['comment'], '<script>alert(1)</script>');
  });

  test('rate limits writes', () async {
    final handler = build();
    for (var i = 0; i < 5; i++) {
      expect((await handler(post({'email': 'a@x.com', 'comment': 'x'}))).statusCode, 201);
    }
    expect((await handler(post({'email': 'a@x.com', 'comment': 'x'}))).statusCode, 429);
  });

  test('ignores a spoofed X-Forwarded-For when no proxy is trusted', () async {
    final handler = build();
    FutureOr<Response> postFrom(String ip) => handler(Request(
          'POST',
          Uri.parse('http://localhost/api/comments'),
          body: jsonEncode({'email': 'a@x.com', 'comment': 'x'}),
          headers: {'content-type': 'application/json', 'x-forwarded-for': ip},
        ));
    for (var i = 0; i < 5; i++) {
      await postFrom('1.1.1.$i');
    }
    expect((await postFrom('2.2.2.2')).statusCode, 429);
  });

  test('delete needs the admin token and 404s a malformed id', () async {
    final handler = build();
    final created = jsonDecode(await (await handler(post({'email': 'a@x.com', 'comment': 'x'})))
        .readAsString()) as Map<String, dynamic>;
    final id = created['id'] as String;
    expect((await handler(Request('DELETE', Uri.parse('http://localhost/api/comments/$id')))).statusCode, 401);
    expect((await handler(Request('DELETE', Uri.parse('http://localhost/api/comments/abc'),
        headers: {'x-admin-token': 'secret'}))).statusCode, 404);
    expect((await handler(Request('DELETE', Uri.parse('http://localhost/api/comments/$id'),
        headers: {'x-admin-token': 'secret'}))).statusCode, 204);
  });

  test('availability middleware maps a backend outage to 503', () async {
    final store = LazyMongoCommentsStore('mongodb://localhost:1');
    final middleware = commentsAvailabilityMiddleware(store, 'http://localhost');
    // A non-comments path skips the eager probe, so the thrown exception is
    // what the middleware's wrapped call catches.
    final handler = middleware(
      (Request request) async => throw CommentsUnavailableException('down'),
    );
    final response =
        await handler(Request('GET', Uri.parse('http://localhost/health')));
    expect(response.statusCode, 503);
    expect(response.headers['access-control-allow-origin'], 'http://localhost');
  });
}
