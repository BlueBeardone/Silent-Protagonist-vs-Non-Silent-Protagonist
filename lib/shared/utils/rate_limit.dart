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

  /// Sweep once the tracked-key count crosses this, even inside a window.
  static const int _sweepThreshold = 1024;

  DateTime? _lastSweep;

  /// The number of keys currently tracked. Exposed for tests that assert
  /// eviction keeps the map bounded.
  int get trackedKeys => _requests.length;

  /// Returns `true` and records the request when [key] is under its limit
  /// within the current window; otherwise returns `false` without recording.
  bool allow(String key) {
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
