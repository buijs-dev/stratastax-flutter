import 'package:meta/meta.dart';

/// What a list endpoint is asked for. With a [cursor] only [cursor] and [limit] are sent: the
/// cursor carries the filter and sort it was issued for (stratastax-search), so they cannot
/// disagree with it.
@immutable
final class StxSearchQuery {
  const StxSearchQuery({this.filter, this.sort, this.limit, this.cursor});

  /// An encoded RSQL expression (`Rsql.encode`), or null for everything.
  final String? filter;

  /// An encoded sort (`SortSpec.encode`), or null for the endpoint's default.
  final String? sort;
  final int? limit;
  final String? cursor;

  /// The same criteria on the page [cursor] points to.
  StxSearchQuery at(String? cursor) => StxSearchQuery(filter: filter, sort: sort, limit: limit, cursor: cursor);

  /// The parameters actually sent.
  ({int? limit, String? cursor, String? filter, String? sort}) get params => cursor == null
      ? (limit: limit, cursor: null, filter: filter, sort: sort)
      : (limit: limit, cursor: cursor, filter: null, sort: null);

  /// Canonical: equal queries give equal keys.
  String get key {
    final p = params;
    return 'l=${p.limit ?? ''}&c=${p.cursor ?? ''}&f=${p.filter ?? ''}&s=${p.sort ?? ''}';
  }

  @override
  bool operator ==(Object other) => other is StxSearchQuery && other.key == key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => 'StxSearchQuery($key)';
}

/// One page of a list endpoint (`paged_metadata` + `items`).
@immutable
final class StxPage<I> {
  const StxPage({required this.items, this.nextCursor, this.prevCursor});

  final List<I> items;

  /// Null on the last page.
  final String? nextCursor;

  /// Null on the first page.
  final String? prevCursor;

  bool get hasNext => nextCursor != null;

  bool get hasPrev => prevCursor != null;
}
