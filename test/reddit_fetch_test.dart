import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/shared/utils/server.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/stats/logic/stats.dart';

void main() {
  test('disabled auth returns nulls without any network call', () async {
    var requests = 0;
    final auth = RedditAuth(
        clientId: '',
        clientSecret: '',
        userAgent: 'x',
        httpClient: MockClient((_) async {
          requests++;
          return http.Response('{}', 200);
        }));
    expect(auth.enabled, isFalse);
    expect(await auth.token(), isNull);
    final stats = await fetchLiveReddit(auth,
        client: MockClient((_) async => http.Response('{}', 200)));
    expect(stats, hasLength(games.length));
    expect(stats.every((s) => s.online == null && s.members == null), isTrue);
    expect(requests, 0);
  });

  test('caches the token until shortly before it expires', () async {
    var clock = DateTime.utc(2026, 11, 16, 12);
    var tokenCalls = 0;
    final auth = RedditAuth(
        clientId: 'id',
        clientSecret: 'secret',
        userAgent: 'x',
        now: () => clock,
        httpClient: MockClient((request) async {
          tokenCalls++;
          return http.Response(
              '{"access_token":"tok$tokenCalls","expires_in":3600}', 200);
        }));

    expect(await auth.token(), 'tok1');
    expect(await auth.token(), 'tok1');
    expect(tokenCalls, 1);

    // The token is treated as expiring 60s early: 3600s - 60s = 59 minutes.
    clock = clock.add(const Duration(minutes: 60));
    expect(await auth.token(), 'tok2');
    expect(tokenCalls, 2);
  });

  test('a failed token request returns null', () async {
    final auth = RedditAuth(
        clientId: 'id',
        clientSecret: 'secret',
        userAgent: 'x',
        httpClient: MockClient((_) async => http.Response('nope', 401)));
    expect(await auth.token(), isNull);
  });

  test('fetches about.json per subreddit and nulls a 404', () async {
    final about = '{"data":{"active_user_count":10,"subscribers":20}}';
    final auth = RedditAuth(
        clientId: 'id',
        clientSecret: 'secret',
        userAgent: 'x',
        httpClient: MockClient((_) async =>
            http.Response('{"access_token":"tok","expires_in":3600}', 200)));

    final stats = await fetchLiveReddit(auth, client: MockClient((request) async {
      if (request.url.path.contains('GTAV')) return http.Response('no', 404);
      return http.Response(about, 200);
    }));

    expect(stats, hasLength(games.length));
    final gta = stats.firstWhere((s) => s.subreddit == 'GTAV');
    expect(gta.online, isNull);
    expect(gta.members, isNull);
    final elden = stats.firstWhere((s) => s.subreddit == 'Eldenring');
    expect(elden.online, 10);
    expect(elden.members, 20);
  });

  test('a thrown request leaves nulls instead of throwing', () async {
    final auth = RedditAuth(
        clientId: 'id',
        clientSecret: 'secret',
        userAgent: 'x',
        httpClient: MockClient((_) async =>
            http.Response('{"access_token":"tok","expires_in":3600}', 200)));
    final stats = await fetchLiveReddit(auth,
        client: MockClient((_) async => throw StateError('offline')));
    expect(stats.every((s) => s.online == null), isTrue);
  });
}
