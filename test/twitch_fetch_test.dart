import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/shared/utils/server.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/stats/logic/stats.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/stats/logic/twitch.dart';

/// A MockClient that answers the token endpoint and routes the two Helix
/// endpoints to the supplied handlers.
MockClient twitchClient({
  required Future<http.Response> Function(http.Request request) games,
  required Future<http.Response> Function(http.Request request) streams,
  Future<http.Response> Function(http.Request request)? token,
}) {
  return MockClient((request) async {
    if (request.url.host == 'id.twitch.tv') {
      return token?.call(request) ??
          http.Response(
              '{"access_token":"tok","expires_in":3600,"token_type":"bearer"}',
              200);
    }
    if (request.url.path.endsWith('/helix/games')) return games(request);
    if (request.url.path.endsWith('/helix/streams')) return streams(request);
    return http.Response('unexpected ${request.url}', 500);
  });
}

http.Response gamesBody(String id) =>
    http.Response('{"data":[{"id":"$id"}]}', 200);

http.Response streamsBody(List<int> viewerCounts, {String? cursor}) =>
    http.Response(
      '{"data":[${[
        for (final count in viewerCounts) '{"viewer_count":$count}',
      ].join(',')}]${cursor == null ? '' : ',"pagination":{"cursor":"$cursor"}'}}',
      200,
    );

/// An auth and fetch pair sharing one mock client.
Future<List<TwitchStats>> fetchWith(MockClient client,
    {String clientId = 'id'}) {
  return fetchLiveTwitch(
    TwitchAuth(
      clientId: clientId,
      clientSecret: 'secret',
      httpClient: client,
    ),
    client: client,
  );
}

void main() {
  test('disabled auth returns nulls without any network call', () async {
    var requests = 0;
    final auth = TwitchAuth(
        clientId: '',
        clientSecret: '',
        httpClient: MockClient((_) async {
          requests++;
          return http.Response('{}', 200);
        }));
    expect(auth.enabled, isFalse);
    expect(await auth.token(), isNull);
    final stats = await fetchLiveTwitch(auth,
        client: MockClient((_) async => http.Response('{}', 200)));
    expect(stats, hasLength(games.length));
    expect(stats.every((s) => s.channels == null && s.viewers == null), isTrue);
    expect(requests, 0);
  });

  test('caches the token until shortly before it expires', () async {
    var clock = DateTime.utc(2026, 11, 17, 12);
    var tokenCalls = 0;
    final auth = TwitchAuth(
        clientId: 'id',
        clientSecret: 'secret',
        now: () => clock,
        httpClient: MockClient((request) async {
          tokenCalls++;
          return http.Response(
              '{"access_token":"tok$tokenCalls","expires_in":3600}', 200);
        }));

    expect(await auth.token(), 'tok1');
    expect(await auth.token(), 'tok1');
    expect(tokenCalls, 1);

    clock = clock.add(const Duration(minutes: 60));
    expect(await auth.token(), 'tok2');
    expect(tokenCalls, 2);
  });

  test('a failed token request returns null', () async {
    final auth = TwitchAuth(
        clientId: 'id',
        clientSecret: 'secret',
        httpClient: MockClient((_) async => http.Response('nope', 401)));
    expect(await auth.token(), isNull);
  });

  test('resolves the category, then sums live viewers and channels', () async {
    final stats = await fetchWith(twitchClient(
      games: (_) async => gamesBody('21779'),
      streams: (_) async => streamsBody([100, 25]),
    ));

    expect(stats, hasLength(games.length));
    final elden = stats.firstWhere((s) => s.appid == 1245620);
    expect(elden.channels, 2);
    expect(elden.viewers, 125);
  });

  test('follows the cursor to count every page', () async {
    final stats = await fetchWith(twitchClient(
      games: (_) async => gamesBody('21779'),
      streams: (request) async => request.url.queryParameters['after'] == null
          ? streamsBody([10, 20], cursor: 'next')
          : streamsBody([5]),
    ));

    final elden = stats.firstWhere((s) => s.appid == 1245620);
    expect(elden.channels, 3);
    expect(elden.viewers, 35);
  });

  test('an unknown category dashes only that game', () async {
    final stats = await fetchWith(twitchClient(
      // Elden Ring resolves; every other category name resolves to nothing.
      games: (request) async =>
          request.url.queryParameters['name'] == 'Elden Ring'
              ? gamesBody('21779')
              : http.Response('{"data":[]}', 200),
      streams: (_) async => streamsBody([7]),
    ));

    final elden = stats.firstWhere((s) => s.appid == 1245620);
    expect(elden.viewers, 7);
    final gta = stats.firstWhere((s) => s.appid == 271590);
    expect(gta.channels, isNull);
    expect(gta.viewers, isNull);
  });

  test('zero live channels is a real zero, not a dash', () async {
    final stats = await fetchWith(twitchClient(
      games: (_) async => gamesBody('21779'),
      streams: (_) async => http.Response('{"data":[]}', 200),
    ));

    final elden = stats.firstWhere((s) => s.appid == 1245620);
    expect(elden.channels, 0);
    expect(elden.viewers, 0);
  });

  test('a thrown request leaves nulls instead of throwing', () async {
    final client = MockClient((request) async {
      if (request.url.host == 'id.twitch.tv') {
        return http.Response('{"access_token":"tok","expires_in":3600}', 200);
      }
      throw StateError('offline');
    });
    final stats = await fetchLiveTwitch(
      TwitchAuth(clientId: 'id', clientSecret: 'secret', httpClient: client),
      client: client,
    );
    expect(stats.every((s) => s.channels == null), isTrue);
  });

  test('a failed stream page dashes instead of counting a partial total',
      () async {
    final stats = await fetchWith(twitchClient(
      games: (_) async => gamesBody('21779'),
      streams: (_) async => http.Response('rate limited', 429),
    ));

    final elden = stats.firstWhere((s) => s.appid == 1245620);
    expect(elden.channels, isNull);
    expect(elden.viewers, isNull);
  });

  test('a failure after the first page still dashes the whole game',
      () async {
    final stats = await fetchWith(twitchClient(
      games: (_) async => gamesBody('21779'),
      streams: (request) async =>
          request.url.queryParameters['after'] == null
              ? streamsBody([10, 20], cursor: 'next')
              : http.Response('rate limited', 429),
    ));

    final elden = stats.firstWhere((s) => s.appid == 1245620);
    expect(elden.channels, isNull);
    expect(elden.viewers, isNull);
  });

  test('stops after the page cap instead of following cursors forever',
      () async {
    var streamCalls = 0;
    final stats = await fetchWith(twitchClient(
      games: (_) async => gamesBody('21779'),
      streams: (_) async {
        streamCalls++;
        return streamsBody([1], cursor: 'more');
      },
    ));

    expect(streamCalls, games.length * twitchMaxStreamPages);
    final elden = stats.firstWhere((s) => s.appid == 1245620);
    expect(elden.channels, twitchMaxStreamPages);
  });

  test('sends the client id header on every Helix call', () async {
    final seen = <String?>[];
    final client = MockClient((request) async {
      if (request.url.host == 'id.twitch.tv') {
        return http.Response('{"access_token":"tok","expires_in":3600}', 200);
      }
      seen.add(request.headers['client-id']);
      if (request.url.path.endsWith('/helix/games')) return gamesBody('1');
      return streamsBody([1]);
    });

    await fetchLiveTwitch(
      TwitchAuth(
          clientId: 'my-client', clientSecret: 'secret', httpClient: client),
      client: client,
    );

    expect(seen, isNotEmpty);
    expect(seen.every((id) => id == 'my-client'), isTrue);
  });
}
