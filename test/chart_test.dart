import 'package:flutter_test/flutter_test.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/chart.dart';

void main() {
  group('barHeight', () {
    test('gives the largest value the full height', () {
      expect(barHeight(47137, 47137, 200), 200);
    });

    test('uses a square-root curve, not linear', () {
      // sqrt(1/4) = 1/2, so a quarter of the max is half height.
      // A linear scale would wrongly give 50.
      expect(barHeight(2500, 10000, 200), closeTo(100, 0.001));
    });

    test('treats a zero value as zero height', () {
      expect(barHeight(0, 47137, 200), 0);
    });

    test('returns zero when the max is zero (no divide-by-zero)', () {
      expect(barHeight(0, 0, 200), 0);
    });
  });
}
