import 'dart:async';

import 'package:stx_core/stx_core.dart';
import 'package:stx_search/stx_search.dart';
import 'package:test/test.dart';

void main() {
  var now = DateTime.utc(2026, 10, 21, 12);
  late StxSearchCache cache;
  var loads = 0;

  setUp(() {
    now = DateTime.utc(2026, 10, 21, 12);
    loads = 0;
    cache = StxSearchCache(maxEntries: 3, clock: () => now);
  });

  Future<Result<int, Problem>> load() async => Ok(++loads);

  Future<int?> get(String key, StxCachePolicy policy, {String tag = 'games', void Function(int)? fresh}) async =>
      (await cache.get(key, tag: tag, policy: policy, load: load, onRevalidated: fresh)).valueOrNull;

  const memory = StxCachePolicy(ttl: Duration(seconds: 30));
  const swr = StxCachePolicy(mode: StxCacheMode.staleWhileRevalidate, ttl: Duration(seconds: 30));

  test('none always loads', () async {
    expect(await get('a', StxCachePolicy.none), 1);
    expect(await get('a', StxCachePolicy.none), 2);
  });

  test('memory reuses a value until its ttl has passed', () async {
    expect(await get('a', memory), 1);
    now = now.add(const Duration(seconds: 29));
    expect(await get('a', memory), 1);
    now = now.add(const Duration(seconds: 2));
    expect(await get('a', memory), 2);
  });

  test('stale-while-revalidate answers with the stale value and reports the fresh one', () async {
    expect(await get('a', swr), 1);
    now = now.add(const Duration(minutes: 1));
    final fresh = Completer<int>();
    expect(await get('a', swr, fresh: fresh.complete), 1);
    expect(await fresh.future, 2);
    expect(await get('a', swr), 2);
  });

  test('errors are not cached', () async {
    var fail = true;
    Future<Result<int, Problem>> flaky() async => fail ? Err(Problem.network('offline')) : const Ok(7);
    expect((await cache.get('a', tag: 't', policy: memory, load: flaky)).isErr, isTrue);
    fail = false;
    expect((await cache.get('a', tag: 't', policy: memory, load: flaky)).valueOrNull, 7);
  });

  test('concurrent requests for one key share one load', () async {
    final results = await Future.wait([get('a', memory), get('a', memory)]);
    expect(results, [1, 1]);
    expect(loads, 1);
  });

  test('invalidateTag drops only that tag', () async {
    await get('g', memory);
    await get('m', memory, tag: 'matches');
    cache.invalidateTag('matches');
    expect(await get('g', memory), 1);
    expect(await get('m', memory, tag: 'matches'), 3);
  });

  test('least recently used entries are evicted first', () async {
    await get('a', memory); // 1
    await get('b', memory); // 2
    await get('c', memory); // 3
    await get('a', memory); // hit: a is now most recent
    await get('d', memory); // 4, evicts b
    expect(cache.length, 3);
    expect(await get('a', memory), 1);
    expect(await get('b', memory), 5);
  });

  test('the ttl never outlives the cursors of stratastax-search', () {
    expect(const StxCachePolicy(ttl: Duration(days: 2)).effectiveTtl, StxCachePolicy.maxTtl);
  });
}
