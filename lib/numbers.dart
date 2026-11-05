import 'package:flutter/material.dart';

import 'chart.dart';
import 'stats.dart';

/// Formats a margin percentage for display, or a dash when it is undefined.
String formatPercent(double? value) => value == null ? '—' : '${value.round()}%';

/// The numbers tab: a per-game table with camp subtotals, and a verdict panel
/// pinned at the bottom that names the more popular side and what decides it.
class NumbersComparison extends StatelessWidget {
  const NumbersComparison({super.key, required this.stats});

  final List<GameStats> stats;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(child: _StatsTable(stats: stats)),
        _VerdictPanel(overall: summarizeCamps(stats)),
      ],
    );
  }
}

class _StatsTable extends StatelessWidget {
  const _StatsTable({required this.stats});

  final List<GameStats> stats;

  @override
  Widget build(BuildContext context) {
    final overall = summarizeCamps(stats);
    final byMetric = {for (final s in overall.summaries) s.metric: s};

    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 28,
          headingTextStyle: const TextStyle(fontWeight: FontWeight.bold),
          columns: const [
            DataColumn(label: Text('Game')),
            DataColumn(label: Text('Camp')),
            DataColumn(label: Text('Current'), numeric: true),
            DataColumn(label: Text('30-day'), numeric: true),
            DataColumn(label: Text('6-month'), numeric: true),
          ],
          rows: [
            for (final camp in Camp.values) ...[
              ..._gameRows(stats.where((g) => g.camp == camp)),
              _footerRow(
                context,
                '${campLabel(camp)} total',
                camp,
                byMetric,
                (s, c) =>
                    c == Camp.silent ? s.silentTotal : s.nonSilentTotal,
              ),
              _footerRow(
                context,
                '${campLabel(camp)} average',
                camp,
                byMetric,
                (s, c) =>
                    c == Camp.silent ? s.silentAverage : s.nonSilentAverage,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Iterable<DataRow> _gameRows(Iterable<GameStats> games) => [
        for (final game in games)
          DataRow(
            cells: [
              DataCell(Text(game.name)),
              DataCell(Text(
                campLabel(game.camp).toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: campColor(game.camp),
                ),
              )),
              DataCell(Text(formatCount(game.current?.toDouble()))),
              DataCell(Text(formatCount(game.avg30d))),
              DataCell(Text(formatCount(game.avg6m))),
            ],
          ),
      ];

  DataRow _footerRow(
    BuildContext context,
    String label,
    Camp camp,
    Map<Metric, MetricSummary> byMetric,
    double? Function(MetricSummary summary, Camp camp) pick,
  ) {
    const bold = TextStyle(fontWeight: FontWeight.bold);
    return DataRow(
      color: WidgetStatePropertyAll(
        Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      cells: [
        DataCell(Text(label, style: bold)),
        const DataCell(SizedBox.shrink()),
        for (final metric in Metric.values)
          DataCell(Text(
            formatCount(pick(byMetric[metric]!, camp)),
            style: bold,
          )),
      ],
    );
  }
}

/// The bottom panel: a line per metric, then who wins overall and why.
class _VerdictPanel extends StatelessWidget {
  const _VerdictPanel({required this.overall});

  final OverallSummary overall;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final leader = overall.leader;
    final deciding = overall.decidingMetric;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          top: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "Who's more popular",
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          for (final summary in overall.summaries)
            Text(_metricLine(summary), style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
          Text(
            leader == null
                ? 'Both sides are equally popular'
                : '${campLabel(leader)} games are more popular overall',
            style: theme.textTheme.titleMedium!.copyWith(
              fontWeight: FontWeight.bold,
              color: leader == null ? null : campColor(leader),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _decidingLine(deciding),
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  String _metricLine(MetricSummary summary) {
    final leader = summary.leader;
    if (leader == null) return '${metricLabel(summary.metric)}: tied';
    return '${metricLabel(summary.metric)}: '
        '${campLabel(leader)} by ${formatCount(summary.margin)}';
  }

  String _decidingLine(MetricSummary deciding) {
    final leader = deciding.leader;
    if (leader == null) {
      return 'Deciding factor: ${metricLabel(deciding.metric)} — tied';
    }
    return 'Deciding factor: ${metricLabel(deciding.metric)} — '
        '${campLabel(leader)} +${formatPercent(deciding.marginPercent)}';
  }
}
