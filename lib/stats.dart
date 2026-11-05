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

/// Averages the last six monthly "Avg. Players" rows of a SteamCharts page.
///
/// The running "Last 30 Days" row is not a calendar month, so it is skipped;
/// once six months are collected any older rows are ignored. Months the page
/// reports without a parseable number are skipped rather than counted. Throws
/// when the page has no monthly rows at all.
double parseSteamCharts6mAvg(String body) {
  final document = html_parser.parse(body);
  final months = <double>[];
  for (final cell in document.querySelectorAll('td.month-cell')) {
    if (cell.text.trim() == 'Last 30 Days') continue;
    final avgText = cell.parent?.querySelector('td.num-f')?.text.trim();
    final value = double.tryParse(avgText ?? '');
    if (value == null) continue;
    months.add(value);
    if (months.length == 6) break;
  }
  if (months.isEmpty) {
    throw FormatException('No monthly rows in SteamCharts page');
  }
  return months.reduce((a, b) => a + b) / months.length;
}

/// Scrapes the "all-time peak" player count out of a SteamCharts page.
///
/// The page header holds several `div.app-stat` blocks (playing, 24-hour peak,
/// all-time peak); only the one whose text says "all-time peak" is the record.
/// The number may carry thousands separators.
int parseSteamChartsAllTimePeak(String body) {
  final document = html_parser.parse(body);
  for (final stat in document.querySelectorAll('div.app-stat')) {
    if (!stat.text.contains('all-time peak')) continue;
    final text = stat.querySelector('span.num')?.text.trim() ?? '';
    final value = int.tryParse(text.replaceAll(',', ''));
    if (value == null) {
      throw FormatException('All-time peak had no number: $text');
    }
    return value;
  }
  throw FormatException('No all-time peak in SteamCharts page');
}

/// Which camp a game belongs to for the comparison.
enum Camp { silent, nonSilent }

/// One game's numbers. [current], [avg30d], [avg6m] and [peakAllTime] are null
/// when their source lookup failed, so the UI can show a dash instead of a
/// misleading zero.
class GameStats {
  const GameStats({
    required this.name,
    required this.camp,
    required this.appid,
    this.current,
    this.avg30d,
    this.avg6m,
    this.peakAllTime,
  });

  final String name;
  final Camp camp;
  final int appid;
  final int? current;
  final double? avg30d;
  final double? avg6m;
  final int? peakAllTime;

  Map<String, dynamic> toJson() => {
        'name': name,
        'camp': camp.name,
        'appid': appid,
        'current': current,
        'avg30d': avg30d,
        'avg6m': avg6m,
        'peakAllTime': peakAllTime,
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
        avg6m: (item['avg6m'] as num?)?.toDouble(),
        peakAllTime: item['peakAllTime'] as int?,
      ),
  ];
}

/// The four numbers we compare for each game.
enum Metric { current, avg30d, avg6m, peak }

/// Picks a game's value for [metric], or null when that lookup failed.
double? metricValue(GameStats game, Metric metric) => switch (metric) {
      Metric.current => game.current?.toDouble(),
      Metric.avg30d => game.avg30d,
      Metric.avg6m => game.avg6m,
      Metric.peak => game.peakAllTime?.toDouble(),
    };

/// Human-readable name for a metric.
String metricLabel(Metric metric) => switch (metric) {
      Metric.current => 'Current players',
      Metric.avg30d => '30-day average',
      Metric.avg6m => '6-month average',
      Metric.peak => 'All-time peak',
    };

/// Human-readable name for a camp.
String campLabel(Camp camp) => switch (camp) {
      Camp.silent => 'Silent',
      Camp.nonSilent => 'Non-silent',
    };

/// The values [stats] holds for [camp] on [metric], skipping failed lookups.
List<double> _campValues(List<GameStats> stats, Camp camp, Metric metric) => [
      for (final game in stats)
        if (game.camp == camp) ?metricValue(game, metric),
    ];

/// One metric's silent-vs-non-silent comparison, totalled across every game.
///
/// Totals and averages skip games whose lookup for the metric failed, so a
/// dash in the table never counts as a zero here.
class MetricSummary {
  const MetricSummary({
    required this.metric,
    required this.silentTotal,
    required this.nonSilentTotal,
    required this.silentAverage,
    required this.nonSilentAverage,
    required this.silentCount,
    required this.nonSilentCount,
  });

  final Metric metric;
  final double silentTotal;
  final double nonSilentTotal;
  final double? silentAverage;
  final double? nonSilentAverage;
  final int silentCount;
  final int nonSilentCount;

  /// The camp with the larger total, or null when the two are equal.
  Camp? get leader {
    if (silentTotal == nonSilentTotal) return null;
    return silentTotal > nonSilentTotal ? Camp.silent : Camp.nonSilent;
  }

  /// How many players separate the two camps (always positive).
  double get margin => (silentTotal - nonSilentTotal).abs();

  /// The margin as a percentage of the smaller total, or null when the smaller
  /// total is zero (the gap cannot then be expressed as a percentage).
  double? get marginPercent {
    final smaller =
        silentTotal < nonSilentTotal ? silentTotal : nonSilentTotal;
    if (smaller <= 0) return null;
    return margin / smaller * 100;
  }
}

/// Totals one metric across both camps.
MetricSummary summarizeMetric(List<GameStats> stats, Metric metric) {
  final silentValues = _campValues(stats, Camp.silent, metric);
  final nonSilentValues = _campValues(stats, Camp.nonSilent, metric);

  double total(List<double> values) =>
      values.fold(0, (sum, value) => sum + value);
  double? average(List<double> values) =>
      values.isEmpty ? null : total(values) / values.length;

  return MetricSummary(
    metric: metric,
    silentTotal: total(silentValues),
    nonSilentTotal: total(nonSilentValues),
    silentAverage: average(silentValues),
    nonSilentAverage: average(nonSilentValues),
    silentCount: silentValues.length,
    nonSilentCount: nonSilentValues.length,
  );
}

/// The whole comparison: one [MetricSummary] per metric, plus which side is
/// ahead overall and which metric separates the two sides most.
class OverallSummary {
  const OverallSummary({required this.summaries});

  final List<MetricSummary> summaries;

  /// The camp that wins more of the three metrics, or null when they tie.
  Camp? get leader {
    var silentWins = 0;
    var nonSilentWins = 0;
    for (final summary in summaries) {
      switch (summary.leader) {
        case Camp.silent:
          silentWins++;
        case Camp.nonSilent:
          nonSilentWins++;
        case null:
          break;
      }
    }
    if (silentWins == nonSilentWins) return null;
    return silentWins > nonSilentWins ? Camp.silent : Camp.nonSilent;
  }

  /// The metric with the largest relative gap between the two camps — the one
  /// that most separates them. A metric the two camps tie on is not a gap and
  /// is skipped; a gap the percentages cannot express (a camp at zero) counts
  /// as the widest possible. Ties keep the earliest metric.
  MetricSummary get decidingMetric {
    double gap(MetricSummary summary) {
      if (summary.leader == null) return -1;
      return summary.marginPercent ?? double.infinity;
    }

    var best = summaries.first;
    var bestScore = gap(best);
    for (final summary in summaries.skip(1)) {
      final score = gap(summary);
      if (score > bestScore) {
        best = summary;
        bestScore = score;
      }
    }
    return best;
  }
}

/// Summarises every metric for the whole field of games.
OverallSummary summarizeCamps(List<GameStats> stats) => OverallSummary(
      summaries: [
        for (final metric in Metric.values) summarizeMetric(stats, metric),
      ],
    );

/// The games we compare, hardcoded as agreed: fifteen where the player creates
/// and projects onto a blank-slate protagonist (silent), and fifteen built
/// around an authored lead with a fixed voice and story (non-silent).
const List<GameStats> games = [
  // Silent / self-insert: you make the character, so you are the character.
  GameStats(name: 'Dark Souls Remastered', camp: Camp.silent, appid: 570940),
  GameStats(name: 'Elden Ring', camp: Camp.silent, appid: 1245620),
  GameStats(name: 'Dark Souls III', camp: Camp.silent, appid: 374320),
  GameStats(name: 'Monster Hunter: World', camp: Camp.silent, appid: 582010),
  GameStats(name: 'Skyrim Special Edition', camp: Camp.silent, appid: 489830),
  GameStats(name: 'Fallout: New Vegas', camp: Camp.silent, appid: 22380),
  GameStats(name: 'Stardew Valley', camp: Camp.silent, appid: 413150),
  GameStats(name: 'Terraria', camp: Camp.silent, appid: 105600),
  GameStats(name: 'Valheim', camp: Camp.silent, appid: 892970),
  GameStats(name: 'ARK: Survival Evolved', camp: Camp.silent, appid: 346110),
  GameStats(name: 'Rust', camp: Camp.silent, appid: 252490),
  GameStats(name: 'Path of Exile', camp: Camp.silent, appid: 238960),
  GameStats(name: 'Warframe', camp: Camp.silent, appid: 230410),
  GameStats(name: "No Man's Sky", camp: Camp.silent, appid: 275850),
  GameStats(name: 'Divinity: Original Sin 2', camp: Camp.silent, appid: 435150),

  // Non-silent: an authored protagonist whose story you follow.
  GameStats(name: 'GTA V', camp: Camp.nonSilent, appid: 271590),
  GameStats(name: 'God of War', camp: Camp.nonSilent, appid: 1593500),
  GameStats(name: 'The Witcher 3: Wild Hunt', camp: Camp.nonSilent, appid: 292030),
  GameStats(name: 'Red Dead Redemption 2', camp: Camp.nonSilent, appid: 1174180),
  GameStats(name: "Assassin's Creed Odyssey", camp: Camp.nonSilent, appid: 812140),
  GameStats(name: "Assassin's Creed Origins", camp: Camp.nonSilent, appid: 582160),
  GameStats(
      name: 'Halo: The Master Chief Collection',
      camp: Camp.nonSilent,
      appid: 976730),
  GameStats(name: 'Resident Evil 2', camp: Camp.nonSilent, appid: 883710),
  GameStats(name: 'NieR: Automata', camp: Camp.nonSilent, appid: 524220),
  GameStats(name: 'Horizon Zero Dawn Complete Edition',
      camp: Camp.nonSilent, appid: 1151640),
  GameStats(
      name: "Marvel's Spider-Man Remastered",
      camp: Camp.nonSilent,
      appid: 1817070),
  GameStats(name: 'The Last of Us Part I', camp: Camp.nonSilent, appid: 1888930),
  GameStats(
      name: 'Star Wars Jedi: Fallen Order',
      camp: Camp.nonSilent,
      appid: 1172380),
  GameStats(name: 'Rise of the Tomb Raider', camp: Camp.nonSilent, appid: 391220),
  GameStats(
      name: "Ghost of Tsushima Director's Cut",
      camp: Camp.nonSilent,
      appid: 2215430),
];
