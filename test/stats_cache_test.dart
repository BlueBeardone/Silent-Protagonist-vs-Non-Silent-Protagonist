import 'package:flutter_test/flutter_test.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/shared/utils/server.dart';
import 'package:silent_protagonist_vs_non_silent_protagonist/stats/logic/stats.dart';

const _game = GameStats(
  name: 'Elden Ring',
  camp: Camp.silent,
  appid: 1245620,
  current: 1,
  avg30d: 2,
  avg6m: 3,
  peakAllTime: 4,
);

void main() {
  test('caches the fetch for the TTL', () async {
    var clock = DateTime.utc(2026, 11, 9, 12);
    var calls = 0;
    final cache = StatsCache(
      ttl: const Duration(seconds: 60),
      now: () => clock,
    );
    Future<List<GameStats>> fetch() async {
      calls++;
      return const [_game];
    }

    expect(await cache.get(fetch), const [_game]);
    expect(await cache.get(fetch), const [_game]);
    expect(calls, 1);

    clock = clock.add(const Duration(seconds: 61));
    expect(await cache.get(fetch), const [_game]);
    expect(calls, 2);
  });

  test('shares one in-flight fetch between concurrent callers', () async {
    var calls = 0;
    final cache = StatsCache(ttl: const Duration(seconds: 60));
    Future<List<GameStats>> fetch() async {
      calls++;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      return const [_game];
    }

    final results = await Future.wait([
      cache.get(fetch),
      cache.get(fetch),
      cache.get(fetch),
    ]);
    expect(results, everyElement(const [_game]));
    expect(calls, 1);
  });

  test('does not cache a failed fetch', () async {
    var calls = 0;
    final cache = StatsCache(ttl: const Duration(seconds: 60));
    Future<List<GameStats>> fetch() async {
      calls++;
      if (calls == 1) throw StateError('boom');
      return const [_game];
    }

    await expectLater(cache.get(fetch), throwsStateError);
    expect(await cache.get(fetch), const [_game]);
    expect(calls, 2);
  });
}
