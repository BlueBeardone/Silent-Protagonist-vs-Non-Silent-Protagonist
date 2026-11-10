import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../logic/stats.dart';
import 'camp_filter.dart';

double barLength(double value, double maxValue, double maxLength) {
  if (maxValue <= 0 || value <= 0) return 0;
  return math.sqrt(value / maxValue) * maxLength;
}

Color campColor(Camp camp) => switch (camp) {
      Camp.silent => const Color(0xFF38BDF8),
      Camp.nonSilent => const Color(0xFFF43F5E),
    };

String formatCount(num? value) {
  if (value == null) return '—';
  final digits = value.round().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

class ComparisonChart extends StatefulWidget {
  const ComparisonChart({
    super.key,
    required this.stats,
    this.maxBarWidth = 220,
  });

  final List<GameStats> stats;
  final double maxBarWidth;

  @override
  State<ComparisonChart> createState() => _ComparisonChartState();
}

class _ComparisonChartState extends State<ComparisonChart> {
  Camp? _camp;

  @override
  Widget build(BuildContext context) {
    final stats = filterByCamp(widget.stats, _camp);
    final values = [
      for (final game in stats) ...[game.current?.toDouble(), game.avg30d],
    ].whereType<double>();
    final maxValue = values.isEmpty ? 0.0 : values.reduce(math.max);

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
                  _GameGroup(
                    game: game,
                    maxValue: maxValue,
                    maxBarWidth: widget.maxBarWidth,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _GameGroup extends StatelessWidget {
  const _GameGroup({
    required this.game,
    required this.maxValue,
    required this.maxBarWidth,
  });

  final GameStats game;
  final double maxValue;
  final double maxBarWidth;

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
          _Bar(
            metricLabel: 'Current',
            valueLabel: formatCount(game.current),
            value: game.current?.toDouble(),
            maxValue: maxValue,
            maxBarWidth: maxBarWidth,
            color: color,
          ),
          _Bar(
            metricLabel: '30-day avg',
            valueLabel: formatCount(game.avg30d),
            value: game.avg30d,
            maxValue: maxValue,
            maxBarWidth: maxBarWidth,
            color: color.withValues(alpha: 0.42),
          ),
          _Bar(
            metricLabel: '6-month avg',
            valueLabel: formatCount(game.avg6m),
            value: game.avg6m,
            maxValue: maxValue,
            maxBarWidth: maxBarWidth,
            color: color.withValues(alpha: 0.22),
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.metricLabel,
    required this.valueLabel,
    required this.value,
    required this.maxValue,
    required this.maxBarWidth,
    required this.color,
  });

  final String metricLabel;
  final String valueLabel;
  final double? value;
  final double maxValue;
  final double maxBarWidth;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              metricLabel,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final maxWidth = math.min(constraints.maxWidth, maxBarWidth);
                final width = barLength(value ?? 0, maxValue, maxWidth);
                return Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    width: width,
                    height: 16,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(3),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 60,
            child: Text(
              valueLabel,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
