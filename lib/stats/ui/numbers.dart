import 'package:flutter/material.dart';

import '../logic/stats.dart';
import 'chart.dart';

/// Formats a margin percentage for display, or a dash when it is undefined.
String formatPercent(double? value) =>
    value == null ? '—' : '${value.round()}%';

/// Below this width the six-column table would need horizontal panning, so the
/// numbers tab switches to a compact list whose rows expand on tap.
const double compactNumbersBreakpoint = 800;

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

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < compactNumbersBreakpoint) {
          return _CompactStatsList(stats: stats, byMetric: byMetric);
        }
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
                DataColumn(label: Text('Peak'), numeric: true),
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
      },
    );
  }

  Iterable<DataRow> _gameRows(Iterable<GameStats> games) => [
    for (final game in games)
      DataRow(
        cells: [
          DataCell(Text(game.name)),
          DataCell(
            Text(
              campLabel(game.camp).toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: campColor(game.camp),
              ),
            ),
          ),
          DataCell(Text(formatCount(game.current?.toDouble()))),
          DataCell(Text(formatCount(game.avg30d))),
          DataCell(Text(formatCount(game.avg6m))),
          DataCell(Text(formatCount(game.peakAllTime?.toDouble()))),
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
          DataCell(
            Text(formatCount(pick(byMetric[metric]!, camp)), style: bold),
          ),
      ],
    );
  }
}

const double _campColumnWidth = 88;
const double _valueColumnWidth = 68;
const double _chevronSpace = 28;

/// The narrow-screen alternative to the wide table. Each game shows only its
/// camp and 30-day average; tapping a row reveals the remaining statistics in
/// a stacked block, so there is never any horizontal panning.
class _CompactStatsList extends StatefulWidget {
  const _CompactStatsList({required this.stats, required this.byMetric});

  final List<GameStats> stats;
  final Map<Metric, MetricSummary> byMetric;

  @override
  State<_CompactStatsList> createState() => _CompactStatsListState();
}

class _CompactStatsListState extends State<_CompactStatsList> {
  final Set<int> _expanded = <int>{};

  void _toggle(GameStats game) {
    setState(() {
      if (!_expanded.remove(game.appid)) _expanded.add(game.appid);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context),
          for (final camp in Camp.values) ...[
            for (final game in widget.stats.where((g) => g.camp == camp))
              _gameRow(context, game),
            _footerRow(
              context,
              '${campLabel(camp)} total',
              camp,
              (s, c) => c == Camp.silent ? s.silentTotal : s.nonSilentTotal,
            ),
            _footerRow(
              context,
              '${campLabel(camp)} average',
              camp,
              (s, c) => c == Camp.silent ? s.silentAverage : s.nonSilentAverage,
            ),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final theme = Theme.of(context);
    const bold = TextStyle(fontWeight: FontWeight.bold);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: const Row(
        children: [
          Expanded(child: Text('Game', style: bold)),
          SizedBox(
            width: _campColumnWidth,
            child: Text('Camp', style: bold),
          ),
          SizedBox(
            width: _valueColumnWidth,
            child: Text('30-day', style: bold, textAlign: TextAlign.right),
          ),
          SizedBox(width: _chevronSpace),
        ],
      ),
    );
  }

  Widget _gameRow(BuildContext context, GameStats game) {
    final theme = Theme.of(context);
    final expanded = _expanded.contains(game.appid);
    return Column(
      children: [
        InkWell(
          onTap: () => _toggle(game),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                Expanded(child: Text(game.name)),
                SizedBox(
                  width: _campColumnWidth,
                  child: Text(
                    campLabel(game.camp).toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: campColor(game.camp),
                    ),
                  ),
                ),
                SizedBox(
                  width: _valueColumnWidth,
                  child: Text(
                    formatCount(game.avg30d),
                    textAlign: TextAlign.right,
                  ),
                ),
                SizedBox(
                  width: _chevronSpace,
                  child: Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.topCenter,
          child: expanded
              ? _detailBlock(context, game)
              : const SizedBox(width: double.infinity),
        ),
        Divider(height: 1, color: theme.dividerColor),
      ],
    );
  }

  Widget _detailBlock(BuildContext context, GameStats game) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        children: [
          _detailLine(
            context,
            'Current players',
            formatCount(game.current?.toDouble()),
          ),
          _detailLine(context, '6-month average', formatCount(game.avg6m)),
          _detailLine(
            context,
            'All-time peak',
            formatCount(game.peakAllTime?.toDouble()),
          ),
        ],
      ),
    );
  }

  Widget _detailLine(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          Text(
            value,
            style: theme.textTheme.bodyMedium!.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _footerRow(
    BuildContext context,
    String label,
    Camp camp,
    double? Function(MetricSummary summary, Camp camp) pick,
  ) {
    final theme = Theme.of(context);
    const bold = TextStyle(fontWeight: FontWeight.bold);
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          Expanded(child: Text(label, style: bold)),
          const SizedBox(width: _campColumnWidth),
          SizedBox(
            width: _valueColumnWidth,
            child: Text(
              formatCount(pick(widget.byMetric[Metric.avg30d]!, camp)),
              style: bold,
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: _chevronSpace),
        ],
      ),
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
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text("Who's more popular", style: theme.textTheme.titleMedium),
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
          Text(_decidingLine(deciding), style: theme.textTheme.bodyMedium),
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
