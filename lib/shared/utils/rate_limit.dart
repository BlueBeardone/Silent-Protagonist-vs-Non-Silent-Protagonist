import 'dart:async';

import 'package:mongo_dart/mongo_dart.dart';

/// A rate limiter that answers whether [key] may make another request.
///
/// Implementations may be synchronous or asynchronous; the interface is
/// asynchronous so a shared store (for example MongoDB) can be used in
/// production without changing the handler.
abstract class RateLimiter {
  /// Returns `true` and records the request when [key] is under its limit
  /// within the current window; otherwise returns `false` without recording.
  Future<bool> allow(String key);
}

/// A sliding-window rate limiter kept in memory. Intended for tests and as a
/// fallback when the shared store is unavailable.
class InMemoryRateLimiter implements RateLimiter {
  InMemoryRateLimiter({
    required this.maxRequests,
    required this.window,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final int maxRequests;
  final Duration window;
  final DateTime Function() _now;

  final Map<String, List<DateTime>> _requests = {};

  /// Sweep once the tracked-key count crosses this, even inside a window.
  static const int _sweepThreshold = 1024;

  DateTime? _lastSweep;

  /// The number of keys currently tracked. Exposed for tests that assert
  /// eviction keeps the map bounded.
  int get trackedKeys => _requests.length;

  @override
  Future<bool> allow(String key) async {
    final current = _now();
    final cutoff = current.subtract(window);
    _sweep(current, cutoff);

    final timestamps = _requests.putIfAbsent(key, () => <DateTime>[]);
    timestamps.removeWhere((timestamp) => timestamp.isBefore(cutoff));

    if (timestamps.length < maxRequests) {
      timestamps.add(current);
      return true;
    }
    // Defensive: never keep an empty entry around (reachable when
    // maxRequests is zero).
    if (timestamps.isEmpty) _requests.remove(key);
    return false;
  }

  /// Removes keys whose newest timestamp is older than [cutoff] (and any empty
  /// lists). Runs at most once per [window] unless the map is large.
  void _sweep(DateTime current, DateTime cutoff) {
    final last = _lastSweep;
    if (last != null &&
        current.difference(last) < window &&
        _requests.length < _sweepThreshold) {
      return;
    }
    _lastSweep = current;
    _requests.removeWhere(
      (_, timestamps) =>
          timestamps.isEmpty || timestamps.last.isBefore(cutoff),
    );
  }
}

/// A fixed-window rate limiter backed by MongoDB. It is shared across restarts
/// and instances, so the same client cannot bypass the limit by hitting a
/// different process.
///
/// Each window is a separate document keyed by `key + ":" + windowStart`. A
/// TTL index on `expiresAt` removes old buckets. If the Mongo call fails, the
/// limiter falls back to [fallback] so a database outage does not take the
/// whole API down.
class MongoRateLimiter implements RateLimiter {
  MongoRateLimiter({
    required this.collection,
    required this.maxRequests,
    required this.window,
    DateTime Function()? now,
    RateLimiter? fallback,
  })  : _now = now ?? DateTime.now,
        _fallback = fallback ??
            InMemoryRateLimiter(
              maxRequests: maxRequests,
              window: window,
              now: now,
            );

  final Future<DbCollection> Function() collection;
  final int maxRequests;
  final Duration window;
  final DateTime Function() _now;
  final RateLimiter _fallback;

  @override
  Future<bool> allow(String key) async {
    final current = _now();
    final windowStart = _windowStart(current);
    final bucket = '$key:${windowStart.millisecondsSinceEpoch}';
    try {
      final db = await collection();
      final doc = await db.findAndModify(
        query: {'_id': bucket},
        update: {
          r'$inc': {'count': 1},
          r'$setOnInsert': {'expiresAt': windowStart.add(window)},
        },
        upsert: true,
        returnNew: true,
      );
      if (doc == null) return await _fallback.allow(key);
      final count = (doc['count'] as num?)?.toInt() ?? 1;
      return count <= maxRequests;
    } catch (_) {
      // A database outage must not turn into a 500 for every request. The
      // in-memory fallback still protects the process, just not across
      // instances.
      return await _fallback.allow(key);
    }
  }

  /// The start of the fixed window containing [now].
  DateTime _windowStart(DateTime now) {
    final windowMs = window.inMilliseconds;
    if (windowMs <= 0) return now;
    final ms = now.millisecondsSinceEpoch;
    final start = (ms ~/ windowMs) * windowMs;
    return DateTime.fromMillisecondsSinceEpoch(start, isUtc: now.isUtc);
  }
}
