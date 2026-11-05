import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'stats.dart';

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
