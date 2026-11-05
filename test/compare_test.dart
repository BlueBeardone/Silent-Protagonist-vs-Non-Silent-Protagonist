import 'package:flutter_test/flutter_test.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/stats.dart';

void main() {
  GameStats silent({int? current, double? avg30d, double? avg6m}) => GameStats(
        name: 'S',
        camp: Camp.silent,
        appid: 1,
        current: current,
        avg30d: avg30d,
        avg6m: avg6m,
      );

  GameStats nonSilent({int? current, double? avg30d, double? avg6m}) =>
      GameStats(
        name: 'N',
        camp: Camp.nonSilent,
        appid: 2,
        current: current,
        avg30d: avg30d,
        avg6m: avg6m,
      );

  group('metricValue', () {
    test('maps each metric to its field', () {
      final game = silent(current: 10, avg30d: 20, avg6m: 30);
      expect(metricValue(game, Metric.current), 10);
      expect(metricValue(game, Metric.avg30d), 20);
      expect(metricValue(game, Metric.avg6m), 30);
    });

    test('returns null for a metric whose lookup failed', () {
      final game = silent(current: null, avg30d: 20, avg6m: null);
      expect(metricValue(game, Metric.current), isNull);
      expect(metricValue(game, Metric.avg6m), isNull);
    });
  });

  group('metricLabel', () {
    test('gives each metric a human-readable label', () {
      expect(metricLabel(Metric.current), 'Current players');
      expect(metricLabel(Metric.avg30d), '30-day average');
      expect(metricLabel(Metric.avg6m), '6-month average');
    });
  });

  group('campLabel', () {
    test('names each camp for display', () {
      expect(campLabel(Camp.silent), 'Silent');
      expect(campLabel(Camp.nonSilent), 'Non-silent');
    });
  });

  group('summarizeMetric', () {
    final stats = <GameStats>[
      // silent totals: current 400, avg30d 600, avg6m 800
      silent(current: 100, avg30d: 200, avg6m: 300),
      silent(current: 300, avg30d: 400, avg6m: 500),
      // non-silent totals: current 100, avg30d 200, avg6m 300
      nonSilent(current: 50, avg30d: 100, avg6m: 150),
      nonSilent(current: 50, avg30d: 100, avg6m: 150),
    ];

    test('totals each camp for the metric', () {
      final summary = summarizeMetric(stats, Metric.current);
      expect(summary.silentTotal, 400);
      expect(summary.nonSilentTotal, 100);
      expect(summary.silentCount, 2);
      expect(summary.nonSilentCount, 2);
    });

    test('averages over the games that have a value', () {
      final summary = summarizeMetric(stats, Metric.avg30d);
      expect(summary.silentAverage, 300); // 600 / 2
      expect(summary.nonSilentAverage, 100); // 200 / 2
    });

    test('skips null values in totals, averages and counts', () {
      final withGaps = <GameStats>[
        silent(current: 100, avg30d: 200),
        silent(current: null, avg30d: 400),
        nonSilent(current: 50, avg30d: 100),
      ];
      final summary = summarizeMetric(withGaps, Metric.current);

      expect(summary.silentTotal, 100); // null not counted
      expect(summary.silentAverage, 100); // divided by 1, not 2
      expect(summary.silentCount, 1);
      expect(summary.nonSilentTotal, 50);
    });

    test('reports a null average when a camp has no values at all', () {
      final onlyNonSilent = <GameStats>[nonSilent(current: 50)];
      final summary = summarizeMetric(onlyNonSilent, Metric.current);

      expect(summary.silentAverage, isNull);
      expect(summary.silentTotal, 0);
      expect(summary.nonSilentAverage, 50);
    });

    test('leader is the camp with the bigger total', () {
      expect(summarizeMetric(stats, Metric.current).leader, Camp.silent);
    });

    test('leader is null on an exact tie', () {
      final tied = <GameStats>[
        silent(current: 100),
        nonSilent(current: 100),
      ];
      expect(summarizeMetric(tied, Metric.current).leader, isNull);
    });

    test('margin is the absolute difference between the totals', () {
      expect(summarizeMetric(stats, Metric.current).margin, 300);
    });

    test('marginPercent is relative to the smaller total', () {
      // 300 of margin over the smaller total of 100 is +300%.
      final summary = summarizeMetric(stats, Metric.current);
      expect(summary.marginPercent, closeTo(300, 0.001));
    });

    test('marginPercent is null when the smaller total is zero', () {
      final onlyNonSilent = <GameStats>[nonSilent(current: 50)];
      expect(summarizeMetric(onlyNonSilent, Metric.current).marginPercent,
          isNull);
    });
  });

  group('summarizeCamps', () {
    test('leader is the camp that wins more of the three metrics', () {
      final stats = <GameStats>[
        // silent wins current and avg30d; non-silent wins avg6m.
        silent(current: 400, avg30d: 600, avg6m: 100),
        nonSilent(current: 100, avg30d: 200, avg6m: 300),
      ];

      final overall = summarizeCamps(stats);

      expect(overall.leader, Camp.silent);
      expect(overall.summaries, hasLength(3));
    });

    test('deciding metric is the one with the biggest relative gap', () {
      final stats = <GameStats>[
        // Absolute margins grow per metric, but the *relative* gap is largest
        // for current players: +300% vs +200% vs +166%.
        silent(current: 400, avg30d: 600, avg6m: 800),
        nonSilent(current: 100, avg30d: 200, avg6m: 300),
      ];

      expect(summarizeCamps(stats).decidingMetric.metric, Metric.current);
    });

    test('leader is null when every metric ties', () {
      final stats = <GameStats>[
        silent(current: 100, avg30d: 100, avg6m: 100),
        nonSilent(current: 100, avg30d: 100, avg6m: 100),
      ];

      expect(summarizeCamps(stats).leader, isNull);
    });
  });
}
