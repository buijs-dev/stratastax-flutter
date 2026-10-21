import 'package:stx_core/stx_core.dart';
import 'package:stx_http/stx_http.dart';

import 'cache.dart';
import 'page.dart';

/// What an overview reads from: pages and totals. [StxSearchService] is the implementation;
/// tests can provide their own.
abstract interface class StxSearchSource<I> {
  Future<Result<StxPage<I>, Problem>> page(StxSearchQuery query, {void Function(StxPage<I> fresh)? onRevalidated});

  /// `Ok(null)` when the endpoint cannot count.
  Future<Result<int?, Problem>> total(String? filter, {void Function(int fresh)? onRevalidated});

  /// Drops cached pages and totals.
  void invalidate();
}

/// Talks to one list endpoint (and its `/count` endpoint, when the contract has one): pages,
/// totals and the cache. Generated per `@UiListPage` into `AppServices`; pages and controllers
/// never call the client themselves.
///
/// [P] is the generated params class of the list operation, [R] its response (`MatchListV1`) and
/// [I] the item type (`MatchV1`).
final class StxSearchService<P, R, I> implements StxSearchSource<I> {
  StxSearchService({
    required this.client,
    required this.endpoint,
    required this.params,
    required this.items,
    required this.nextCursor,
    required this.prevCursor,
    required this.tag,
    required this.cache,
    this.policy = const StxCachePolicy(),
    this.count,
  });

  final StxClient client;
  final Endpoint<P, NoBody, R> endpoint;

  /// Builds the operation's params from what is sent (see [StxSearchQuery.params]).
  final P Function(({int? limit, String? cursor, String? filter, String? sort}) query) params;
  final List<I> Function(R response) items;
  final String? Function(R response) nextCursor;
  final String? Function(R response) prevCursor;

  /// The contract tag of the endpoint; [StxSearchCache.invalidateTag] uses it.
  final String tag;
  final StxSearchCache cache;
  final StxCachePolicy policy;

  /// Counts the items matching an encoded filter; null when the contract has no count endpoint.
  final Future<Result<int, Problem>> Function(String? filter)? count;

  bool get counts => count != null;

  /// One page; [onRevalidated] gets a fresher copy of a stale cached page.
  @override
  Future<Result<StxPage<I>, Problem>> page(StxSearchQuery query, {void Function(StxPage<I> fresh)? onRevalidated}) =>
      cache.get(
        '${endpoint.operationId}?${query.key}',
        tag: tag,
        policy: policy,
        load: () async => (await client.fetch(
          endpoint,
          params(query.params),
        )).map((r) => StxPage(items: items(r), nextCursor: nextCursor(r), prevCursor: prevCursor(r))),
        onRevalidated: onRevalidated,
      );

  /// The number of items matching [filter]; `Ok(null)` without a count endpoint.
  @override
  Future<Result<int?, Problem>> total(String? filter, {void Function(int fresh)? onRevalidated}) async {
    final count = this.count;
    if (count == null) return const Ok(null);
    return cache.get<int>(
      '${endpoint.operationId}#count?f=${filter ?? ''}',
      tag: tag,
      policy: policy,
      load: () => count(filter),
      onRevalidated: onRevalidated,
    );
  }

  @override
  void invalidate() => cache.invalidateTag(tag);
}
