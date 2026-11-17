import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/shared/utils/server.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/stats/logic/stats.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/stats/logic/twitch.dart';

void main() {
  group('statsHandler', () {
    test('serves fetched stats as JSON from GET /api/stats', () async {
      // Stub the network; assert the contract we own (route + JSON shape).
      final handler = statsHandler(() async => const [
            GameStats(
              name: 'Elden Ring',
              camp: Camp.silent,
              appid: 1245620,
              current: 15269,
              avg30d: 22428.18,
              avg6m: 29000.0,
              peakAllTime: 952523,
            ),
            GameStats(
              name: 'GTA V',
              camp: Camp.nonSilent,
              appid: 271590,
              // Failed lookups stay null so the UI can dash them.
              current: null,
              avg30d: 47137.17,
              avg6m: null,
            ),
          ]);

      final response = await handler(
        Request('GET', Uri.parse('http://localhost/api/stats')),
      );

      expect(response.statusCode, 200);
      expect(response.headers['content-type'], contains('application/json'));
      // The Flutter web app runs on another port, so the browser needs this.
      expect(response.headers['access-control-allow-origin'], '*');
      expect(jsonDecode(await response.readAsString()), [
        {
          'name': 'Elden Ring',
          'camp': 'silent',
          'appid': 1245620,
          'current': 15269,
          'avg30d': 22428.18,
          'avg6m': 29000.0,
          'peakAllTime': 952523,
        },
        {
          'name': 'GTA V',
          'camp': 'nonSilent',
          'appid': 271590,
          'current': null,
          'avg30d': 47137.17,
          'avg6m': null,
          'peakAllTime': null,
        },
      ]);
    });
  });

  group('twitchHandler', () {
    test('serves fetched Twitch stats as JSON from GET /api/twitch', () async {
      final handler = twitchHandler(() async => const [
            TwitchStats(
                name: 'Elden Ring',
                camp: Camp.silent,
                appid: 1245620,
                category: 'Elden Ring',
                channels: 12,
                viewers: 15269),
            TwitchStats(
                name: 'GTA V',
                camp: Camp.nonSilent,
                appid: 271590,
                category: 'Grand Theft Auto V'),
          ]);

      final response = await handler(
          Request('GET', Uri.parse('http://localhost/api/twitch')));

      expect(response.statusCode, 200);
      expect(response.headers['access-control-allow-origin'], '*');
      expect(response.headers['cache-control'], contains('max-age=60'));
      final body = jsonDecode(await response.readAsString()) as List;
      expect(body[0]['category'], 'Elden Ring');
      expect(body[0]['viewers'], 15269);
      expect(body[1]['channels'], isNull);
      expect(body[1]['viewers'], isNull);
    });

    test('reuses one fetch across requests within the TTL', () async {
      var fetches = 0;
      final handler = twitchHandler(() async {
        fetches++;
        return const [
          TwitchStats(
              name: 'Elden Ring',
              camp: Camp.silent,
              appid: 1245620,
              category: 'Elden Ring',
              channels: 1,
              viewers: 2),
        ];
      });

      final first = await handler(
          Request('GET', Uri.parse('http://localhost/api/twitch')));
      await first.readAsString();
      final second = await handler(
          Request('GET', Uri.parse('http://localhost/api/twitch')));
      await second.readAsString();

      expect(fetches, 1);
    });
  });
}
