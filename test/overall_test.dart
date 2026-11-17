import 'package:flutter_test/flutter_test.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/stats/logic/overall.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/stats/logic/stats.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/stats/logic/twitch.dart';

void main() {
  test('builds the four rows in order and skips nulls', () {
    const steam = [
      GameStats(
          name: 'S', camp: Camp.silent, appid: 1, current: 100, avg30d: 200),
      GameStats(
          name: 'N', camp: Camp.nonSilent, appid: 2, current: 50, avg30d: 25),
    ];
    const twitch = [
      TwitchStats(
          name: 'S',
          camp: Camp.silent,
          appid: 1,
          category: 's',
          channels: 3,
          viewers: 1000),
      TwitchStats(
          name: 'N',
          camp: Camp.nonSilent,
          appid: 2,
          category: 'n',
          channels: 1,
          viewers: null),
    ];

    final rows = overallRows(steam, twitch);
    expect(rows.map((r) => r.label), [
      'Steam current players',
      'Steam 30-day average',
      'Twitch live viewers',
      'Twitch live channels',
    ]);
    expect(rows[0].silentTotal, 100);
    expect(rows[0].nonSilentTotal, 50);
    expect(rows[2].silentCount, 1);
    expect(rows[2].nonSilentCount, 0);
    expect(rows[3].nonSilentTotal, 1);
  });

  test('availability is judged by data, not list length', () {
    expect(
      steamHasData(const [GameStats(name: 'x', camp: Camp.silent, appid: 1)]),
      isFalse,
    );
    expect(
      steamHasData(const [
        GameStats(name: 'x', camp: Camp.silent, appid: 1, avg30d: 5),
      ]),
      isTrue,
    );
    expect(
      twitchHasData(const [
        TwitchStats(name: 'x', camp: Camp.silent, appid: 1, category: 'x'),
      ]),
      isFalse,
    );
    expect(
      twitchHasData(const [
        TwitchStats(
            name: 'x', camp: Camp.silent, appid: 1, category: 'x', channels: 0),
      ]),
      isTrue,
      reason: 'zero live channels is a real reading, not missing data',
    );
  });
}
