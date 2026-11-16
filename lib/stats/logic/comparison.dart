import 'stats.dart';

/// One metric compared across the two camps, independent of its source.
///
/// Totals and averages skip failed lookups, so a dash in the UI never counts
/// as a zero. [silentCount] and [nonSilentCount] tell the UI how many games
/// actually contributed to each side.
class Comparison {
  const Comparison({
    required this.label,
    required this.silentTotal,
    required this.nonSilentTotal,
    required this.silentCount,
    required this.nonSilentCount,
    this.silentAverage,
    this.nonSilentAverage,
  });

  final String label;
  final double silentTotal;
  final double nonSilentTotal;
  final double? silentAverage;
  final double? nonSilentAverage;
  final int silentCount;
  final int nonSilentCount;

  /// The camp with the larger total, or null when either side has no values
  /// or the two totals are equal.
  Camp? get leader {
    if (silentCount == 0 || nonSilentCount == 0) return null;
    if (silentTotal == nonSilentTotal) return null;
    return silentTotal > nonSilentTotal ? Camp.silent : Camp.nonSilent;
  }

  /// How far apart the two totals are (always positive).
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

/// Totals [silent] and [nonSilent] values into one [Comparison].
Comparison compareValues({
  required String label,
  required List<double> silent,
  required List<double> nonSilent,
}) {
  double total(List<double> values) =>
      values.fold(0, (sum, value) => sum + value);
  double? average(List<double> values) =>
      values.isEmpty ? null : total(values) / values.length;

  return Comparison(
    label: label,
    silentTotal: total(silent),
    nonSilentTotal: total(nonSilent),
    silentAverage: average(silent),
    nonSilentAverage: average(nonSilent),
    silentCount: silent.length,
    nonSilentCount: nonSilent.length,
  );
}

/// The camp leading the most rows, or null on a tie (including when no row has
/// both sides populated).
Camp? overallLeader(List<Comparison> rows) {
  var silentWins = 0;
  var nonSilentWins = 0;
  for (final row in rows) {
    switch (row.leader) {
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

/// The row with the largest relative gap between the camps.
///
/// Rows where either side has no values, and rows the camps tie on, are not a
/// gap and are skipped. A gap the percentage cannot express (a zero total)
/// counts as the widest possible. Ties keep the earliest row.
Comparison? decidingRow(List<Comparison> rows) {
  Comparison? best;
  var bestScore = -1.0;
  for (final row in rows) {
    if (row.silentCount == 0 || row.nonSilentCount == 0) continue;
    if (row.leader == null) continue;
    final score = row.marginPercent ?? double.infinity;
    if (score > bestScore) {
      best = row;
      bestScore = score;
    }
  }
  return best;
}
