import 'comparison.dart';
import 'reddit.dart';
import 'stats.dart';

/// One line of the Overall table: a Steam or Reddit metric compared per camp.
///
/// Rows, in order: Steam current players, Steam 30-day average, Reddit online
/// now, Reddit total members. Failed lookups are skipped by [compareValues],
/// so a dash never counts as a zero.
List<Comparison> overallRows(
  List<GameStats> steam,
  List<RedditStats> reddit,
) {
  List<double> values<T>(Iterable<T> items, double? Function(T) pick) =>
      [for (final item in items) ?pick(item)];

  return [
    compareValues(
      label: 'Steam current players',
      silent: values(
        steam.where((game) => game.camp == Camp.silent),
        (game) => game.current?.toDouble(),
      ),
      nonSilent: values(
        steam.where((game) => game.camp == Camp.nonSilent),
        (game) => game.current?.toDouble(),
      ),
    ),
    compareValues(
      label: 'Steam 30-day average',
      silent: values(
        steam.where((game) => game.camp == Camp.silent),
        (game) => game.avg30d,
      ),
      nonSilent: values(
        steam.where((game) => game.camp == Camp.nonSilent),
        (game) => game.avg30d,
      ),
    ),
    compareValues(
      label: 'Reddit online now',
      silent: values(
        reddit.where((game) => game.camp == Camp.silent),
        (game) => redditMetricValue(game, RedditMetric.online),
      ),
      nonSilent: values(
        reddit.where((game) => game.camp == Camp.nonSilent),
        (game) => redditMetricValue(game, RedditMetric.online),
      ),
    ),
    compareValues(
      label: 'Reddit total members',
      silent: values(
        reddit.where((game) => game.camp == Camp.silent),
        (game) => redditMetricValue(game, RedditMetric.members),
      ),
      nonSilent: values(
        reddit.where((game) => game.camp == Camp.nonSilent),
        (game) => redditMetricValue(game, RedditMetric.members),
      ),
    ),
  ];
}

/// Whether at least one Steam game resolved a value the Overall rows show.
///
/// The Overall rows are current players and the 30-day average, so `avg6m` and
/// `peakAllTime` do not count here even though the Chart page shows them.
bool steamHasData(List<GameStats> steam) =>
    steam.any((game) => game.current != null || game.avg30d != null);

/// Whether at least one subreddit lookup resolved a value.
///
/// Judging availability by data rather than by whether the future threw is
/// what lets the Overall page tell "credentials unset" apart from a real load.
bool redditHasData(List<RedditStats> reddit) =>
    reddit.any((game) => game.online != null || game.members != null);
