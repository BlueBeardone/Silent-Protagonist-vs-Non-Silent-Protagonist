import 'package:flutter/material.dart';

import '../logic/comparison.dart';
import '../logic/overall.dart';
import '../logic/stats.dart';
import '../logic/twitch.dart';
import 'chart.dart';
import 'numbers.dart' show compactNumbersBreakpoint, formatPercent;

/// The Overall tab: Steam and Twitch totals side by side for the two camps.
class OverallComparison extends StatelessWidget {
  const OverallComparison({
    super.key,
    required this.steam,
    required this.twitch,
  });

  final List<GameStats> steam;
  final List<TwitchStats> twitch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = overallRows(steam, twitch);
    final steamAvailable = steamHasData(steam);
    final twitchAvailable = twitchHasData(twitch);

    final steamSilent = steam.where((g) => g.camp == Camp.silent).length;
    final steamNonSilent = steam.where((g) => g.camp == Camp.nonSilent).length;
    final twitchSilent = twitch.where((g) => g.camp == Camp.silent).length;
    final twitchNonSilent =
        twitch.where((g) => g.camp == Camp.nonSilent).length;

    int denominatorFor(int row, bool silent) {
      if (row < 2) return silent ? steamSilent : steamNonSilent;
      return silent ? twitchSilent : twitchNonSilent;
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Steam players and Twitch viewers are different units, so '
                'they are shown side by side, not added together.',
                style: theme.textTheme.bodyMedium,
              ),
              if (!steamAvailable) ...[
                const SizedBox(height: 8),
                const _SourceNote(source: 'Steam'),
              ],
              if (!twitchAvailable) ...[
                const SizedBox(height: 8),
                const _SourceNote(source: 'Twitch'),
              ],
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < compactNumbersBreakpoint) {
                return _CompactOverall(
                  rows: rows,
                  denominatorFor: denominatorFor,
                );
              }
              return SingleChildScrollView(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columnSpacing: 28,
                    headingTextStyle:
                        const TextStyle(fontWeight: FontWeight.bold),
                    columns: const [
                      DataColumn(label: Text('Measure')),
                      DataColumn(label: Text('Silent'), numeric: true),
                      DataColumn(label: Text('Non-silent'), numeric: true),
                      DataColumn(label: Text('Leader')),
                    ],
                    rows: [
                      for (var i = 0; i < rows.length; i++)
                        _row(context, rows[i], i, denominatorFor),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        _OverallVerdict(rows: rows),
      ],
    );
  }

  DataRow _row(
    BuildContext context,
    Comparison row,
    int index,
    int Function(int, bool) denominatorFor,
  ) {
    final leader = row.leader;
    return DataRow(
      cells: [
        DataCell(Text(_measureLabel(row, index, denominatorFor))),
        DataCell(Text(_total(row, true))),
        DataCell(Text(_total(row, false))),
        DataCell(Text(
          _leaderLabel(row),
          style: leader == null
              ? null
              : TextStyle(
                  color: campColor(leader), fontWeight: FontWeight.bold),
        )),
      ],
    );
  }
}

String _total(Comparison row, bool silent) {
  final count = silent ? row.silentCount : row.nonSilentCount;
  if (count == 0) return '—';
  return formatCount(silent ? row.silentTotal : row.nonSilentTotal);
}

String _leaderLabel(Comparison row) {
  if (row.silentCount == 0 || row.nonSilentCount == 0) return '—';
  final leader = row.leader;
  if (leader == null) return 'Tied';
  return campLabel(leader);
}

String _measureLabel(
  Comparison row,
  int index,
  int Function(int, bool) denominatorFor,
) {
  if (denominatorFor(index, true) == 0 && denominatorFor(index, false) == 0) {
    return row.label;
  }
  final short = <String>[
    if (row.silentCount < denominatorFor(index, true))
      'Silent ${row.silentCount}/${denominatorFor(index, true)}',
    if (row.nonSilentCount < denominatorFor(index, false))
      'Non-silent ${row.nonSilentCount}/${denominatorFor(index, false)}',
  ];
  if (short.isEmpty) return row.label;
  return '${row.label} (${short.join(', ')})';
}

/// The same rows as cards, so a narrow screen never pans sideways.
class _CompactOverall extends StatelessWidget {
  const _CompactOverall({required this.rows, required this.denominatorFor});

  final List<Comparison> rows;
  final int Function(int, bool) denominatorFor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      children: [
        for (var i = 0; i < rows.length; i++)
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: theme.dividerColor)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _measureLabel(rows[i], i, denominatorFor),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                _line(context, 'Silent', _total(rows[i], true)),
                _line(context, 'Non-silent', _total(rows[i], false)),
                _line(context, 'Leader', _leaderLabel(rows[i])),
              ],
            ),
          ),
      ],
    );
  }

  Widget _line(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
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
}

class _OverallVerdict extends StatelessWidget {
  const _OverallVerdict({required this.rows});

  final List<Comparison> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final complete = rows
        .where((row) => row.silentCount > 0 && row.nonSilentCount > 0)
        .length;
    final leader = overallLeader(rows);
    final wins =
        leader == null ? 0 : rows.where((row) => row.leader == leader).length;
    final deciding = decidingRow(rows);

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
          Text("Who's ahead", style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            leader == null
                ? 'Both sides are level across $complete measures'
                : '${campLabel(leader)} games lead on $wins of $complete '
                    'measures',
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

  String _decidingLine(Comparison? deciding) {
    final leader = deciding?.leader;
    if (deciding == null || leader == null) {
      return 'No measure separates the two sides';
    }
    return 'Deciding factor: ${deciding.label} — '
        '${campLabel(leader)} +${formatPercent(deciding.marginPercent)}';
  }
}

class _SourceNote extends StatelessWidget {
  const _SourceNote({required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final message = source == 'Twitch'
        ? 'Twitch data unavailable — set TWITCH_CLIENT_ID and '
            'TWITCH_CLIENT_SECRET on the proxy and refresh.'
        : 'Steam data unavailable — /api/stats returned no players. '
            'Refresh to try again.';
    return Text(
      message,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.error,
      ),
    );
  }
}
