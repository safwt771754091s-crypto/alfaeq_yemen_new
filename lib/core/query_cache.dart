/// Short-lived memo for read-only catalog queries.
///
/// Every query costs roughly half a second against the live project, and the
/// storefront rebuilds often (tab switches, `setState`, pull-to-refresh). Two
/// rules keep that from turning into a request storm:
///
/// * identical reads inside the TTL share one in-flight future, so a rebuild
///   cannot queue a second round trip;
/// * the cached value is dropped on an explicit refresh, which is the only path
///   that is allowed to bypass the TTL.
class QueryCache {
  QueryCache._();

  static final QueryCache instance = QueryCache._();

  final Map<String, _Entry> _entries = {};

  static const Duration defaultTtl = Duration(seconds: 60);

  /// Storefront content (catalog, offers, updates) changes rarely, so it can
  /// survive a tab switch without a round trip.
  static const Duration contentTtl = Duration(minutes: 5);

  Future<T> remember<T>(
    String key,
    Future<T> Function() load, {
    Duration ttl = defaultTtl,
  }) {
    final now = DateTime.now();
    final existing = _entries[key];
    if (existing != null && existing.expiresAt.isAfter(now)) {
      return existing.value as Future<T>;
    }
    final future = load();
    _entries[key] = _Entry(future, now.add(ttl));
    // A failed read must not be cached, otherwise a transient network error
    // would keep every caller failing for the rest of the TTL. The derived
    // future swallows the error so the caller still receives it from [future].
    future.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {
        if (identical(_entries[key]?.value, future)) _entries.remove(key);
      },
    );
    return future;
  }

  /// Drops entries whose key starts with [prefix]; empty drops everything.
  void invalidate([String prefix = '']) {
    if (prefix.isEmpty) {
      _entries.clear();
      return;
    }
    _entries.removeWhere((key, _) => key.startsWith(prefix));
  }
}

class _Entry {
  _Entry(this.value, this.expiresAt);
  final Future<Object?> value;
  final DateTime expiresAt;
}
