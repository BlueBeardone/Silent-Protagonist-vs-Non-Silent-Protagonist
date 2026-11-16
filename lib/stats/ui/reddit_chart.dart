import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../logic/comparison.dart';
import '../logic/reddit.dart';
import '../logic/stats.dart';
import 'camp_filter.dart';
import 'chart.dart';
import 'numbers.dart' show formatPercent;

/// The Reddit tab: the same look as the Steam chart, with each subreddit's
/// online-now and total-member numbers.
class RedditComparison extends StatefulWidget {
  const RedditComparison({super.key, required this.stats});

  final List<RedditStats> stats;

  @override
  State<RedditComparison> createState() => _RedditComparisonState();
}

class _RedditComparisonState extends State<RedditComparison> {
  Camp? _camp;

  @override
  Widget build(BuildContext context) {
    final everythingFailed = widget.stats.isNotEmpty &&
        widget.stats.every((game) => game.online == null && game.members == null);
    if (everythingFailed) {
      return const _UnavailableNote();
    }

    final stats = _camp == null
        ? widget.stats
        : widget.stats.where((game) => game.camp == _camp).toList();
    final onlineValues = [
      for (final game in stats) ?game.online?.toDouble(),
    ];
    final memberValues = [
      for (final game in stats) ?game.members?.toDouble(),
    ];
    final maxOnline =
        onlineValues.isEmpty ? 0.0 : onlineValues.reduce(math.max);
    final maxMembers =
        memberValues.isEmpty ? 0.0 : memberValues.reduce(math.max);

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
                  _RedditGameGroup(
                    game: game,
                    maxOnline: maxOnline,
                    maxMembers: maxMembers,
                  ),
              ],
            ),
          ),
        ),
        if (_camp == null) _RedditVerdictPanel(rows: summarizeReddit(stats)),
      ],
    );
  }
}

class _RedditGameGroup extends StatelessWidget {
  const _RedditGameGroup({
    required this.game,
    required this.maxOnline,
    required this.maxMembers,
  });

  final RedditStats game;
  final double maxOnline;
  final double maxMembers;

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
            metricLabel: 'Online now',
            valueLabel: formatCount(game.online?.toDouble()),
            value: game.online?.toDouble(),
            maxValue: maxOnline,
            maxBarWidth: 220,
            color: color,
          ),
          StatBar(
            metricLabel: 'Total members',
            valueLabel: formatCount(game.members?.toDouble()),
            value: game.members?.toDouble(),
            maxValue: maxMembers,
            maxBarWidth: 220,
            color: color.withValues(alpha: 0.42),
          ),
        ],
      ),
    );
  }
}

/// The pinned summary: one line per Reddit metric, then who is ahead overall
/// and what separates them most.
class _RedditVerdictPanel extends StatelessWidget {
  const _RedditVerdictPanel({required this.rows});

  final List<Comparison> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
          Text('Subreddit activity', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final row in rows)
            Text(_metricLine(row), style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
          Text(
            leader == null
                ? 'Both sides are equally active'
                : '${campLabel(leader)} subreddits are ahead overall',
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
              'Reddit data unavailable',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Set REDDIT_CLIENT_ID and REDDIT_CLIENT_SECRET on the proxy, '
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
