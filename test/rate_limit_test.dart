import 'package:flutter_test/flutter_test.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/shared/utils/rate_limit.dart';

void main() {
  test('allows up to the limit inside the window, then blocks', () {
    var clock = DateTime.utc(2026, 11, 5, 12);
    final limiter = RateLimiter(
      maxRequests: 2,
      window: const Duration(minutes: 10),
      now: () => clock,
    );
    expect(limiter.allow('ip'), isTrue);
    expect(limiter.allow('ip'), isTrue);
    expect(limiter.allow('ip'), isFalse);
    clock = clock.add(const Duration(minutes: 11));
    expect(limiter.allow('ip'), isTrue);
  });

  test('counts each key separately', () {
    final limiter = RateLimiter(maxRequests: 1, window: const Duration(minutes: 10));
    expect(limiter.allow('a'), isTrue);
    expect(limiter.allow('b'), isTrue);
    expect(limiter.allow('a'), isFalse);
  });

  test('evicts keys whose newest timestamp has aged out of the window', () {
    var clock = DateTime.utc(2026, 11, 5, 12);
    final limiter = RateLimiter(
      maxRequests: 1,
      window: const Duration(minutes: 10),
      now: () => clock,
    );
    expect(limiter.allow('a'), isTrue);
    expect(limiter.allow('b'), isTrue);
    expect(limiter.trackedKeys, 2);

    clock = clock.add(const Duration(minutes: 11));
    expect(limiter.allow('c'), isTrue);
    // `a` and `b` are older than the window and were swept; only `c` remains.
    expect(limiter.trackedKeys, 1);
    // The aged-out key is allowed again, proving its entry was dropped.
    expect(limiter.allow('a'), isTrue);
  });
}
