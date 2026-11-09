import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/comments/logic/comments_api.dart';

void main() {
  test('post sends email and comment and parses the reply', () async {
    late http.Request seen;
    final client = MockClient((request) async {
      seen = request;
      return http.Response(
        jsonEncode({'id': '1', 'email': 'bar***@gmail.com', 'comment': 'hi', 'createdAt': '2026-11-05T12:00:00.000Z'}),
        201,
      );
    });
    final api = CommentsApi(client: client);
    final comment = await api.post(email: 'barry@gmail.com', comment: 'hi');
    expect(jsonDecode(seen.body)['email'], 'barry@gmail.com');
    expect(comment.comment, 'hi');
  });

  test('list parses the comments array', () async {
    final client = MockClient((_) async => http.Response(
      jsonEncode({'comments': [{'id': '1', 'email': '***@x.com', 'comment': 'hi', 'createdAt': '2026-11-05T12:00:00.000Z'}], 'nextCursor': null}),
      200,
    ));
    expect((await CommentsApi(client: client).list()).single.comment, 'hi');
  });

  test('post targets /api/comments with a JSON content type', () async {
    late http.Request seen;
    final client = MockClient((request) async {
      seen = request;
      return http.Response(
        jsonEncode({'id': '1', 'email': 'bar***@gmail.com', 'comment': 'hi', 'createdAt': '2026-11-05T12:00:00.000Z'}),
        201,
      );
    });
    await CommentsApi(baseUrl: 'http://localhost:8080', client: client)
        .post(email: 'barry@gmail.com', comment: 'hi');
    expect(seen.method, 'POST');
    expect(seen.url.toString(), 'http://localhost:8080/api/comments');
    expect(seen.headers['content-type'], contains('application/json'));
  });

  test('list sends limit and before as query params', () async {
    late http.Request seen;
    final client = MockClient((request) async {
      seen = request;
      return http.Response(
        jsonEncode({'comments': <Object>[], 'nextCursor': null}),
        200,
      );
    });
    await CommentsApi(baseUrl: 'http://localhost:8080', client: client)
        .list(limit: 10, before: '2026-11-05T12:00:00.000Z');
    expect(seen.method, 'GET');
    expect(seen.url.path, '/api/comments');
    expect(seen.url.queryParameters['limit'], '10');
    expect(seen.url.queryParameters['before'], '2026-11-05T12:00:00.000Z');
  });

  test('list omits before when it is null', () async {
    late http.Request seen;
    final client = MockClient((request) async {
      seen = request;
      return http.Response(
        jsonEncode({'comments': <Object>[], 'nextCursor': null}),
        200,
      );
    });
    await CommentsApi(client: client).list();
    expect(seen.url.queryParameters.containsKey('before'), isFalse);
    expect(seen.url.queryParameters['limit'], '50');
  });

  test('listAll follows the cursor until a short page is returned', () async {
    final seenBefores = <String?>[];
    final client = MockClient((request) async {
      final before = request.url.queryParameters['before'];
      seenBefores.add(before);
      if (before == null) {
        return http.Response(
          jsonEncode({
            'comments': [
              for (var i = 0; i < 100; i++)
                {
                  'id': 'a$i',
                  'email': '***@x.com',
                  'comment': 'c$i',
                  'createdAt': '2026-11-05T12:00:00.000Z',
                },
            ],
            'nextCursor': '2026-11-05T12:00:00.000Z',
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'comments': [
            {
              'id': 'b',
              'email': '***@x.com',
              'comment': 'last',
              'createdAt': '2026-11-05T11:00:00.000Z',
            },
          ],
          'nextCursor': null,
        }),
        200,
      );
    });

    final all = await CommentsApi(client: client).listAll();

    expect(all, hasLength(101));
    expect(all.last.comment, 'last');
    expect(seenBefores, [null, '2026-11-05T12:00:00.000Z']);
  });

  test('post throws on a non-2xx status', () async {
    final client = MockClient((_) async =>
        http.Response(jsonEncode({'error': 'nope'}), 400));
    expect(
      () => CommentsApi(client: client).post(email: 'a@x.com', comment: 'hi'),
      throwsA(isA<Exception>()),
    );
  });

  test('list throws on a non-2xx status', () async {
    final client = MockClient((_) async =>
        http.Response(jsonEncode({'error': 'nope'}), 500));
    expect(
      () => CommentsApi(client: client).list(),
      throwsA(isA<Exception>()),
    );
  });
}
