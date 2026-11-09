import 'package:flutter_test/flutter_test.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/shared/utils/rate_limit.dart';

void main() {
  test('allows up to the limit inside the window, then blocks', () async {
    var clock = DateTime.utc(2026, 11, 5, 12);
    final limiter = InMemoryRateLimiter(
      maxRequests: 2,
      window: const Duration(minutes: 10),
      now: () => clock,
    );
    expect(await limiter.allow('ip'), isTrue);
    expect(await limiter.allow('ip'), isTrue);
    expect(await limiter.allow('ip'), isFalse);
    clock = clock.add(const Duration(minutes: 11));
    expect(await limiter.allow('ip'), isTrue);
  });

  test('counts each key separately', () async {
    final limiter = InMemoryRateLimiter(
      maxRequests: 1,
      window: const Duration(minutes: 10),
    );
    expect(await limiter.allow('a'), isTrue);
    expect(await limiter.allow('b'), isTrue);
    expect(await limiter.allow('a'), isFalse);
  });

  test('evicts keys whose newest timestamp has aged out of the window', () async {
    var clock = DateTime.utc(2026, 11, 5, 12);
    final limiter = InMemoryRateLimiter(
      maxRequests: 1,
      window: const Duration(minutes: 10),
      now: () => clock,
    );
    expect(await limiter.allow('a'), isTrue);
    expect(await limiter.allow('b'), isTrue);
    expect(limiter.trackedKeys, 2);

    clock = clock.add(const Duration(minutes: 11));
    expect(await limiter.allow('c'), isTrue);
    // `a` and `b` are older than the window and were swept; only `c` remains.
    expect(limiter.trackedKeys, 1);
    // The aged-out key is allowed again, proving its entry was dropped.
    expect(await limiter.allow('a'), isTrue);
  });
}
