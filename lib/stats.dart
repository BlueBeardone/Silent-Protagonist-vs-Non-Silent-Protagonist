import 'dart:convert';

import 'package:html/parser.dart' as html_parser;

/// Parses the body of Steam's `ISteamUserStats/GetNumberOfCurrentPlayers`
/// response into the live player count.
///
/// Steam omits `player_count` (returning only a `result` code) when the appid
/// has no stats, so we throw rather than silently reporting zero.
int parseCurrentPlayers(String body) {
  final decoded = jsonDecode(body) as Map<String, dynamic>;
  final response = decoded['response'] as Map<String, dynamic>;
  final count = response['player_count'];
  if (count is! int) {
    throw FormatException('Steam response had no player_count: $body');
  }
  return count;
}

/// Scrapes the "Last 30 Days" average player count out of a SteamCharts page.
///
/// The monthly table lists Avg. Players in a `td.num-f` cell; only the row
/// whose month cell reads exactly "Last 30 Days" is the running average.
double parseSteamChartsAvg(String body) {
  final document = html_parser.parse(body);
  for (final cell in document.querySelectorAll('td.month-cell')) {
    if (cell.text.trim() != 'Last 30 Days') continue;
    final avgText = cell.parent?.querySelector('td.num-f')?.text.trim();
    final value = double.tryParse(avgText ?? '');
    if (value == null) {
      throw FormatException('SteamCharts row had no avg value: $avgText');
    }
    return value;
  }
  throw FormatException('No "Last 30 Days" row in SteamCharts page');
}

/// Which camp a game belongs to for the comparison.
enum Camp { silent, nonSilent }

/// One game's numbers. [current] and [avg30d] are null when their source
/// lookup failed, so the UI can show a dash instead of a misleading zero.
class GameStats {
  const GameStats({
    required this.name,
    required this.camp,
    required this.appid,
    this.current,
    this.avg30d,
  });

  final String name;
  final Camp camp;
  final int appid;
  final int? current;
  final double? avg30d;

  Map<String, dynamic> toJson() => {
        'name': name,
        'camp': camp.name,
        'appid': appid,
        'current': current,
        'avg30d': avg30d,
      };
}

/// Rebuilds the games from the proxy's `/api/stats` JSON body.
List<GameStats> parseStatsResponse(String body) {
  final decoded = jsonDecode(body) as List<dynamic>;
  return [
    for (final item in decoded.cast<Map<String, dynamic>>())
      GameStats(
        name: item['name'] as String,
        camp: Camp.values.byName(item['camp'] as String),
        appid: item['appid'] as int,
        current: item['current'] as int?,
        avg30d: (item['avg30d'] as num?)?.toDouble(),
      ),
  ];
}

/// The four games we compare, hardcoded as agreed.
const List<GameStats> games = [
  GameStats(name: 'Dark Souls Remastered', camp: Camp.silent, appid: 570940),
  GameStats(name: 'Elden Ring', camp: Camp.silent, appid: 1245620),
  GameStats(name: 'GTA V', camp: Camp.nonSilent, appid: 271590),
  GameStats(name: 'God of War', camp: Camp.nonSilent, appid: 1593500),
];
