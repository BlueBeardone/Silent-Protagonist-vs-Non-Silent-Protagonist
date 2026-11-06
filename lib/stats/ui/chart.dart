import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../logic/stats.dart';

double barHeight(double value, double maxValue, double maxHeight) {
  if (maxValue <= 0 || value <= 0) return 0;
  return math.sqrt(value / maxValue) * maxHeight;
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

class ComparisonChart extends StatelessWidget {
  const ComparisonChart({
    super.key,
    required this.stats,
    this.maxBarHeight = 220,
  });

  final List<GameStats> stats;
  final double maxBarHeight;

  @override
  Widget build(BuildContext context) {
    final values = [
      for (final game in stats) ...[game.current?.toDouble(), game.avg30d],
    ].whereType<double>();
    final maxValue = values.isEmpty ? 0.0 : values.reduce(math.max);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final game in stats)
            _GameGroup(
              game: game,
              maxValue: maxValue,
              maxBarHeight: maxBarHeight,
            ),
        ],
      ),
    );
  }
}

class _GameGroup extends StatelessWidget {
  const _GameGroup({
    required this.game,
    required this.maxValue,
    required this.maxBarHeight,
  });

  final GameStats game;
  final double maxValue;
  final double maxBarHeight;

  @override
  Widget build(BuildContext context) {
    final color = campColor(game.camp);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _Bar(
                label: formatCount(game.current),
                value: game.current?.toDouble(),
                maxValue: maxValue,
                maxBarHeight: maxBarHeight,
                color: color,
              ),
              const SizedBox(width: 4),
              _Bar(
                label: formatCount(game.avg30d),
                value: game.avg30d,
                maxValue: maxValue,
                maxBarHeight: maxBarHeight,
                color: color.withValues(alpha: 0.42),
              ),
              const SizedBox(width: 4),
              _Bar(
                label: formatCount(game.avg6m),
                value: game.avg6m,
                maxValue: maxValue,
                maxBarHeight: maxBarHeight,
                color: color.withValues(alpha: 0.22),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 90,
            child: Text(
              game.name,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 4),
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
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.label,
    required this.value,
    required this.maxValue,
    required this.maxBarHeight,
    required this.color,
  });

  final String label;
  final double? value;
  final double maxValue;
  final double maxBarHeight;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 10)),
        const SizedBox(height: 4),
        Container(
          width: 22,
          height: barHeight(value ?? 0, maxValue, maxBarHeight),
          decoration: BoxDecoration(
            color: color,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
          ),
        ),
      ],
    );
  }
}
