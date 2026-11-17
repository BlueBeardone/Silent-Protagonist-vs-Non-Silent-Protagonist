import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../logic/comparison.dart';
import '../logic/stats.dart';
import '../logic/twitch.dart';
import 'camp_filter.dart';
import 'chart.dart';
import 'numbers.dart' show formatPercent;

/// The Twitch tab: the same look as the Steam chart, with each category's live
/// channels and live viewers.
class TwitchComparison extends StatefulWidget {
  const TwitchComparison({super.key, required this.stats});

  final List<TwitchStats> stats;

  @override
  State<TwitchComparison> createState() => _TwitchComparisonState();
}

class _TwitchComparisonState extends State<TwitchComparison> {
  Camp? _camp;

  @override
  Widget build(BuildContext context) {
    // Judged by data, not by the list being non-empty: an empty response has
    // zero non-null values, and that counts as unavailable too.
    final everythingFailed = widget.stats
        .every((game) => game.channels == null && game.viewers == null);
    if (everythingFailed) {
      return const _UnavailableNote();
    }

    final stats = _camp == null
        ? widget.stats
        : widget.stats.where((game) => game.camp == _camp).toList();
    final viewerValues = [
      for (final game in stats) ?game.viewers?.toDouble(),
    ];
    final channelValues = [
      for (final game in stats) ?game.channels?.toDouble(),
    ];
    final maxViewers =
        viewerValues.isEmpty ? 0.0 : viewerValues.reduce(math.max);
    final maxChannels =
        channelValues.isEmpty ? 0.0 : channelValues.reduce(math.max);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 16, 32, 0),
          child: CampFilter(
            selected: _camp,
            onChanged: (camp) => setState(() => _camp = camp),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final game in stats)
                  _TwitchGameGroup(
                    game: game,
                    maxViewers: maxViewers,
                    maxChannels: maxChannels,
                  ),
              ],
            ),
          ),
        ),
        if (_camp == null) _TwitchVerdictPanel(rows: summarizeTwitch(stats)),
      ],
    );
  }
}

class _TwitchGameGroup extends StatelessWidget {
  const _TwitchGameGroup({
    required this.game,
    required this.maxViewers,
    required this.maxChannels,
  });

  final TwitchStats game;
  final double maxViewers;
  final double maxChannels;

  @override
  Widget build(BuildContext context) {
    final color = campColor(game.camp);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  game.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                game.camp == Camp.silent ? 'SILENT' : 'NON-SILENT',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          StatBar(
            metricLabel: twitchMetricLabel(TwitchMetric.viewers),
            valueLabel: formatCount(game.viewers?.toDouble()),
            value: game.viewers?.toDouble(),
            maxValue: maxViewers,
            maxBarWidth: 220,
            color: color,
          ),
          StatBar(
            metricLabel: twitchMetricLabel(TwitchMetric.channels),
            valueLabel: formatCount(game.channels?.toDouble()),
            value: game.channels?.toDouble(),
            maxValue: maxChannels,
            maxBarWidth: 220,
            color: color.withValues(alpha: 0.42),
          ),
        ],
      ),
    );
  }
}

/// The pinned summary: one line per Twitch metric, then who is ahead overall
/// and what separates them most.
class _TwitchVerdictPanel extends StatelessWidget {
  const _TwitchVerdictPanel({required this.rows});

  final List<Comparison> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final comparable =
        rows.any((row) => row.silentCount > 0 && row.nonSilentCount > 0);
    final leader = overallLeader(rows);
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
          Text('Live streaming activity', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final row in rows)
            Text(_metricLine(row), style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
          Text(
            !comparable
                ? 'Not enough Twitch data to compare'
                : leader == null
                    ? 'Both sides are equally active'
                    : '${campLabel(leader)} categories are ahead overall',
            style: theme.textTheme.titleMedium!.copyWith(
              fontWeight: FontWeight.bold,
              color: !comparable || leader == null
                  ? null
                  : campColor(leader),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            !comparable
                ? 'Some categories did not resolve on both sides.'
                : _decidingLine(deciding),
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  String _metricLine(Comparison row) {
    if (row.silentCount == 0 || row.nonSilentCount == 0) {
      return '${row.label}: —';
    }
    final leader = row.leader;
    if (leader == null) return '${row.label}: tied';
    return '${row.label}: ${campLabel(leader)} by ${formatCount(row.margin)}';
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

class _UnavailableNote extends StatelessWidget {
  const _UnavailableNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Twitch data unavailable',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Set TWITCH_CLIENT_ID and TWITCH_CLIENT_SECRET on the proxy, '
              'then refresh.',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
