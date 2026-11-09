import 'package:flutter_test/flutter_test.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/shared/utils/rate_limit.dart';

void main() {
  test('falls back to the in-memory limiter when Mongo is unavailable', () async {
    final limiter = MongoRateLimiter(
      collection: () async => throw Exception('down'),
      maxRequests: 2,
      window: const Duration(minutes: 10),
    );
    expect(await limiter.allow('a'), isTrue);
    expect(await limiter.allow('a'), isTrue);
    expect(await limiter.allow('a'), isFalse);
  });
}
