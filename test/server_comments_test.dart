import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/comments.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/rate_limit.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/server.dart';

Handler build({String adminToken = 'secret'}) => commentsHandler(
      store: InMemoryCommentsStore(),
      writeLimiter: RateLimiter(maxRequests: 5, window: const Duration(minutes: 10)),
      readLimiter: RateLimiter(maxRequests: 60, window: const Duration(minutes: 1)),
      adminToken: adminToken,
    );

Request post(Object body) => Request(
      'POST',
      Uri.parse('http://localhost/api/comments'),
      body: jsonEncode(body),
      headers: {'content-type': 'application/json'},
    );

void main() {
  test('stores a valid comment and returns the masked email', () async {
    final response = await build()(post({'email': 'barry@gmail.com', 'comment': 'loved it'}));
    expect(response.statusCode, 201);
    final json = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
    expect(json['email'], 'bar***@gmail.com');
    expect(json.toString(), isNot(contains('barry@gmail.com')));
  });

  test('rejects bad input with 400, never 500', () async {
    final handler = build();
    for (final body in [
      {'comment': 'no email'},
      {'email': 'nope', 'comment': 'x'},
      {'email': 'a@x.com', 'comment': '   '},
      {'email': 'a@x.com', 'comment': 'a' * 2001},
      {'email': 5, 'comment': 'x'},
      {'email': 'a@x.com', 'comment': 'x', r'$where': '1'},
    ]) {
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
}
