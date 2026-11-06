import 'package:flutter_test/flutter_test.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/stats/ui/chart.dart';

void main() {
  group('barLength', () {
    test('gives the largest value the full length', () {
      expect(barLength(47137, 47137, 200), 200);
    });

    test('uses a square-root curve, not linear', () {
      // sqrt(1/4) = 1/2, so a quarter of the max is half length.
      // A linear scale would wrongly give 50.
      expect(barLength(2500, 10000, 200), closeTo(100, 0.001));
    });

    test('treats a zero value as zero length', () {
      expect(barLength(0, 47137, 200), 0);
    });

    test('returns zero when the max is zero (no divide-by-zero)', () {
      expect(barLength(0, 0, 200), 0);
    });
  });
}
