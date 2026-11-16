import 'package:flutter_test/flutter_test.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/stats/logic/overall.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/stats/logic/reddit.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/stats/logic/stats.dart';

void main() {
  test('builds the four rows in order and skips nulls', () {
    const steam = [
      GameStats(
          name: 'S', camp: Camp.silent, appid: 1, current: 100, avg30d: 200),
      GameStats(
          name: 'N', camp: Camp.nonSilent, appid: 2, current: 50, avg30d: 25),
    ];
    const reddit = [
      RedditStats(
          name: 'S',
          camp: Camp.silent,
          appid: 1,
          subreddit: 's',
          online: 10,
          members: 1000),
      RedditStats(
          name: 'N',
          camp: Camp.nonSilent,
          appid: 2,
          subreddit: 'n',
          online: null,
          members: 500),
    ];

    final rows = overallRows(steam, reddit);
    expect(rows.map((r) => r.label), [
      'Steam current players',
      'Steam 30-day average',
      'Reddit online now',
      'Reddit total members',
    ]);
    expect(rows[0].silentTotal, 100);
    expect(rows[0].nonSilentTotal, 50);
    expect(rows[2].silentCount, 1);
    expect(rows[2].nonSilentCount, 0);
    expect(rows[3].nonSilentTotal, 500);
  });
}
