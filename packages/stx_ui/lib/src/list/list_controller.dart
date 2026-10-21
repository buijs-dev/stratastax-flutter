import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:stx_core/stx_core.dart';
import 'package:stx_search/stx_search.dart';

import 'filters.dart';

sealed class StxListState<I> {
  const StxListState();
}

/// The first load, or a new one after the criteria changed; [previous] is still shown.
final class ListLoading<I> extends StxListState<I> {
  const ListLoading([this.previous]);

  final StxPage<I>? previous;
}

final class ListLoaded<I> extends StxListState<I> {
  const ListLoaded(this.page);

  final StxPage<I> page;
}

final class ListFailed<I> extends StxListState<I> {
  const ListFailed(this.problem);

  final Problem problem;
}

/// The state of an overview: filters, sort, the current page and the total. Generated pages
/// create one per page with the filters and sorts of their `@SearchFilter` / `@SearchSort`
/// fields; all backend traffic goes through [source].
///
/// A change of a filter (debounced) or of the sort goes back to the first page. The total is only
/// fetched again when the filter changed.
class StxListController<I> extends ChangeNotifier {
  StxListController({
    required this.source,
    this.filters = const [],
    this.search,
    this.sorts = const [],
    SortField? sort,
    this.pageSize = 20,
    this.debounce = const Duration(milliseconds: 300),
  }) : _sort = sort {
    for (final filter in [?search, ...filters]) {
      filter.addListener(_filtersChanged);
    }
  }

  final StxSearchSource<I> source;
  final List<StxFilter> filters;

  /// The free-text search (`@SearchText`), shown above the results.
  final StxTextFilter? search;
  final List<StxSortOption> sorts;
  final int pageSize;
  final Duration debounce;

  SortField? _sort;
  StxListState<I> _state = const ListLoading();
  int? _total;
  var _pageIndex = 0;
  var _generation = 0;
  String? _filter;
  Timer? _timer;
  var _disposed = false;

  StxListState<I> get state => _state;

  SortField? get sort => _sort;

  /// The matching number of items, when the endpoint can count.
  int? get total => _total;

  /// Zero-based.
  int get pageIndex => _pageIndex;

  /// Filters that are set (not the search text).
  int get activeFilters => filters.where((f) => f.active).length;

  StxPage<I>? get page => switch (_state) {
    ListLoaded(:final page) => page,
    ListLoading(:final previous) => previous,
    ListFailed() => null,
  };

  bool get hasNext => page?.hasNext ?? false;

  bool get hasPrev => _pageIndex > 0 && (page?.hasPrev ?? false);

  String? _encodeFilter() => Rsql.and([search?.toRsql(), for (final f in filters) f.toRsql()])?.encode();

  StxSearchQuery _query({String? cursor}) => StxSearchQuery(
    filter: _filter,
    sort: _sort == null ? null : SortSpec([_sort!]).encode(),
    limit: pageSize,
    cursor: cursor,
  );

  /// Loads the first page (and the total); call once when the page opens.
  Future<void> start() => _first(countToo: true);

  /// Loads the current criteria again from the first page.
  Future<void> refresh() => _first(countToo: true);

  void _filtersChanged() {
    _timer?.cancel();
    _timer = Timer(debounce, () => _first(countToo: true));
    notifyListeners(); // active filter count
  }

  /// Sorts on [field]; the same field again flips the direction.
  void sortBy(String field, [SortDirection? direction]) {
    final option = sorts.where((s) => s.field == field).firstOrNull;
    final next =
        direction ?? (_sort?.field == field ? _sort!.direction.flipped : option?.direction ?? SortDirection.asc);
    _sort = SortField(field, next);
    unawaited(_first(countToo: false));
  }

  void clearFilters() {
    for (final f in filters) {
      f.clear();
    }
  }

  Future<void> next() async {
    final cursor = page?.nextCursor;
    if (cursor == null) return;
    await _load(_query(cursor: cursor), _pageIndex + 1);
  }

  Future<void> previous() async {
    final cursor = page?.prevCursor;
    if (cursor == null || _pageIndex == 0) return;
    // The first page has no cursor of its own: load it with the criteria, as at the start.
    await _load(_pageIndex == 1 ? _query() : _query(cursor: cursor), _pageIndex - 1);
  }

  Future<void> _first({required bool countToo}) async {
    _timer?.cancel();
    final filter = _encodeFilter();
    final filterChanged = filter != _filter;
    _filter = filter;
    if (countToo || filterChanged) unawaited(_count(filter));
    await _load(_query(), 0);
  }

  Future<void> _count(String? filter) async {
    final result = await source.total(filter, onRevalidated: (fresh) => _setTotal(filter, fresh));
    if (result case Ok(:final value)) _setTotal(filter, value);
  }

  void _setTotal(String? filter, int? value) {
    if (_disposed || filter != _filter) return;
    _total = value;
    notifyListeners();
  }

  Future<void> _load(StxSearchQuery query, int index) async {
    final generation = ++_generation;
    _state = ListLoading(page);
    notifyListeners();
    final result = await source.page(
      query,
      onRevalidated: (fresh) {
        if (_disposed || generation != _generation) return;
        _state = ListLoaded(fresh);
        notifyListeners();
      },
    );
    if (_disposed || generation != _generation) return; // a newer request won
    _pageIndex = index;
    _state = switch (result) {
      Ok(:final value) => ListLoaded(value),
      Err(:final error) => ListFailed(error),
    };
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    for (final filter in [?search, ...filters]) {
      filter
        ..removeListener(_filtersChanged)
        ..dispose();
    }
    super.dispose();
  }
}
