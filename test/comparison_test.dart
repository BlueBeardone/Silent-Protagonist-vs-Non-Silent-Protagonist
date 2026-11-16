import 'package:flutter_test/flutter_test.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/stats/logic/comparison.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/stats/logic/stats.dart';

void main() {
  test('totals, averages and leader come from the values', () {
    final c = compareValues(label: 'x', silent: [100, 200], nonSilent: [50]);
    expect(c.silentTotal, 300);
    expect(c.nonSilentTotal, 50);
    expect(c.silentAverage, 150);
    expect(c.nonSilentAverage, 50);
    expect(c.leader, Camp.silent);
    expect(c.margin, 250);
    expect(c.marginPercent, closeTo(500, 0.001));
  });

  test('a one-sided row has no leader and no percentage', () {
    final c = compareValues(label: 'x', silent: [100], nonSilent: []);
    expect(c.leader, isNull);
    expect(c.marginPercent, isNull);
  });

  test('an exact tie has no leader', () {
    expect(compareValues(label: 'x', silent: [5], nonSilent: [5]).leader,
        isNull);
  });

  test('overallLeader counts only rows with a leader', () {
    final rows = [
      compareValues(label: 'a', silent: [10], nonSilent: [1]),
      compareValues(label: 'b', silent: [10], nonSilent: [1]),
      compareValues(label: 'c', silent: [], nonSilent: [1]),
    ];
    expect(overallLeader(rows), Camp.silent);
  });

  test('overallLeader is null on a split', () {
    final rows = [
      compareValues(label: 'a', silent: [10], nonSilent: [1]),
      compareValues(label: 'b', silent: [1], nonSilent: [10]),
    ];
    expect(overallLeader(rows), isNull);
  });

  test('decidingRow picks the widest relative gap and skips one-sided rows',
      () {
    final rows = [
      compareValues(label: 'wide', silent: [400], nonSilent: [100]),
      compareValues(label: 'one-sided', silent: [], nonSilent: [1]),
      compareValues(label: 'narrow', silent: [110], nonSilent: [100]),
    ];
    expect(decidingRow(rows)!.label, 'wide');
  });

  test('decidingRow returns null when nothing separates the sides', () {
    final rows = [
      compareValues(label: 'tie', silent: [5], nonSilent: [5]),
      compareValues(label: 'empty', silent: [], nonSilent: []),
    ];
    expect(decidingRow(rows), isNull);
  });
}
