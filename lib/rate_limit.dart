/// A per-key sliding-window rate limiter.
///
/// Each key is counted separately. On every [allow] call, timestamps older
/// than the configured [window] are dropped, then the request is allowed when
/// the number of remaining timestamps is below [maxRequests].
class RateLimiter {
  RateLimiter({
    required this.maxRequests,
    required this.window,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final int maxRequests;
  final Duration window;
  final DateTime Function() _now;

  final Map<String, List<DateTime>> _requests = {};

  /// Returns `true` and records the request when [key] is under its limit
  /// within the current window; otherwise returns `false` without recording.
  bool allow(String key) {
    final current = _now();
    final cutoff = current.subtract(window);
    final timestamps = _requests.putIfAbsent(key, () => <DateTime>[]);

    timestamps.removeWhere((timestamp) => timestamp.isBefore(cutoff));

    if (timestamps.length < maxRequests) {
      timestamps.add(current);
      return true;
    }
    return false;
  }
}
