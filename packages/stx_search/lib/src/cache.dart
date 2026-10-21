import 'dart:async';

import 'package:stx_core/stx_core.dart';

enum StxCacheMode {
  /// Every request goes to the backend.
  none,

  /// A result is reused until its [StxCachePolicy.ttl] has passed.
  memory,

  /// Like [memory]; after the ttl the old result is still shown at once while a fresh one is
  /// fetched in the background (stale-while-revalidate).
  staleWhileRevalidate,
}

/// How long the results of one list are kept. List endpoints send no `ETag` or `Cache-Control`,
/// so this is the client's own choice, per page (`@UiListPage(cache: …)`) or app (stx.yaml
/// `search.cache`).
final class StxCachePolicy {
  const StxCachePolicy({this.mode = StxCacheMode.memory, this.ttl = const Duration(seconds: 60)});

  static const none = StxCachePolicy(mode: StxCacheMode.none, ttl: Duration.zero);

  /// Cursors of stratastax-search expire after 24 hours; a cached page never outlives them.
  static const maxTtl = Duration(hours: 23);

  final StxCacheMode mode;
  final Duration ttl;

  Duration get effectiveTtl => ttl > maxTtl ? maxTtl : ttl;
}

/// The in-memory cache of every list in the app (one per `AppServices`). Entries are grouped by
/// tag, the contract tag of the endpoint (`matches`), so a change can drop what it makes stale:
/// a saved match calls `invalidateTag('matches')`.
///
/// Errors are never cached, and concurrent requests for the same key share one call.
final class StxSearchCache {
  StxSearchCache({this.maxEntries = 200, DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  /// Least recently used entries go first.
  final int maxEntries;
  final DateTime Function() _clock;

  final _entries = <String, _Entry>{}; // insertion order: least recently used first
  final _inFlight = <String, Future<Object?>>{};

  int get length => _entries.length;

  /// The cached value of [key], or [load]'s. With [StxCacheMode.staleWhileRevalidate] an expired
  /// value is returned at once and [onRevalidated] gets the fresh one when it arrives.
  Future<Result<T, Problem>> get<T>(
    String key, {
    required String tag,
    required StxCachePolicy policy,
    required Future<Result<T, Problem>> Function() load,
    void Function(T fresh)? onRevalidated,
  }) async {
    if (policy.mode == StxCacheMode.none) return load();
    final entry = _entries.remove(key);
    if (entry != null) {
      _entries[key] = entry; // most recently used
      final fresh = _clock().difference(entry.stored) < policy.effectiveTtl;
      if (fresh) return Ok(entry.value as T);
      if (policy.mode == StxCacheMode.staleWhileRevalidate) {
        unawaited(
          _load(key, tag, load).then((result) {
            if (result case Ok(:final value)) onRevalidated?.call(value);
          }),
        );
        return Ok(entry.value as T);
      }
    }
    return _load(key, tag, load);
  }

  Future<Result<T, Problem>> _load<T>(String key, String tag, Future<Result<T, Problem>> Function() load) {
    final pending = _inFlight[key];
    if (pending != null) return pending.then((r) => r as Result<T, Problem>);
    final future = load().then((result) {
      _inFlight.remove(key);
      if (result case Ok(:final value)) _store(key, tag, value);
      return result;
    });
    _inFlight[key] = future;
    return future;
  }

  void _store(String key, String tag, Object? value) {
    _entries
      ..remove(key)
      ..[key] = _Entry(tag, value, _clock());
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  /// Drops every entry of [tag], e.g. after a create, update or delete of that resource.
  void invalidateTag(String tag) => _entries.removeWhere((_, e) => e.tag == tag);

  void clear() => _entries.clear();
}

final class _Entry {
  const _Entry(this.tag, this.value, this.stored);

  final String tag;
  final Object? value;
  final DateTime stored;
}
