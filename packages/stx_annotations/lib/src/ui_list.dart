import 'package:meta/meta_meta.dart';

/// Generates an overview of the annotated model: search, filters, sort, a responsive table and
/// a pager, on a list operation of the contract.
///
/// [list] is a generated list endpoint (`GamesApiV1.listGames`): GET with the `limit`, `cursor`,
/// `filter` and `sort` parameters of stratastax-contract, returning `items` with `nextCursor` and
/// `prevCursor`. [count] is its `/count` endpoint, for "1–20 of 134"; without it the pager shows
/// the page number.
///
/// The fields of the model are paths into the item schema (`@ContractProperty('game.displayName')`
/// for nested ones). `@UiColumn` shows a field, `@SearchFilter` / `@SearchSort` / `@SearchText`
/// make it filterable, sortable or part of the free-text search, like the `@Search*` annotations
/// of stratastax-entity on the server.
@Target({TargetKind.classType})
final class UiListPage {
  const UiListPage({
    required this.list,
    this.count,
    this.pageSize,
    this.panel = const UiSearchPanel(),
    this.cache,
    this.actions = const [],
  });

  /// A const `Endpoint` from the generated contract code; typed as [Object] because this package
  /// has no dependency on stx_core.
  final Object list;
  final Object? count;

  /// `limit` of a page (1–100); null: stx.yaml `search.pageSize` (default 20).
  final int? pageSize;
  final UiSearchPanel panel;

  /// Null: stx.yaml `search.cache` (default: memory, 60 seconds).
  final UiCache? cache;

  /// Buttons next to the title, e.g. to the create form of the model.
  final List<UiAction> actions;
}

/// A button in the header of an overview that opens another page on top of it (e.g. its create
/// form). The label is the title of that page; users without its scopes don't see the button.
final class UiAction {
  const UiAction(this.page);

  /// A class with `@UiRoute` (without route parameters).
  final Type page;
}

/// The shape of the filter panel.
enum UiPanelLayout {
  /// A side panel from `lg`, a bar above the results from [UiSearchPanel.collapseBelow], a
  /// "Filters" button with a sheet below that.
  auto,

  /// A side panel down to [UiSearchPanel.collapseBelow].
  side,

  /// A bar above the results down to [UiSearchPanel.collapseBelow].
  top,
}

enum UiPanelPosition { start, end }

/// Breakpoints of stx_style, for [UiSearchPanel.collapseBelow].
enum UiBreakpoint { sm, md, lg, xl }

final class UiSearchPanel {
  const UiSearchPanel({
    this.layout = UiPanelLayout.auto,
    this.position = UiPanelPosition.start,
    this.collapseBelow = UiBreakpoint.md,
  });

  final UiPanelLayout layout;

  /// The side of a side panel.
  final UiPanelPosition position;

  /// Below this breakpoint the filters move into a sheet behind a "Filters" button.
  final UiBreakpoint collapseBelow;
}

enum UiCacheMode {
  /// Every page comes from the backend.
  none,

  /// A page is reused until [UiCache.ttlSeconds] have passed.
  memory,

  /// After the ttl the old page is shown at once while a fresh one loads.
  staleWhileRevalidate,
}

/// How long pages and totals of this overview are kept. A successful form on an operation with
/// the same contract tag (`createMatch` → `matches`) drops them.
final class UiCache {
  const UiCache({this.mode = UiCacheMode.memory, this.ttlSeconds = 60});

  final UiCacheMode mode;
  final int ttlSeconds;
}

/// Shows the field as a column (table) or a line (cards). Fields without it can still filter.
@Target({TargetKind.field})
final class UiColumn {
  const UiColumn({this.order, this.primary = false, this.flex = 1});

  final int? order;

  /// The title of a card on narrow screens; the first column when none is marked.
  final bool primary;

  /// Relative width in the table.
  final int flex;
}

/// The field is filterable, like `@SearchFilter` of stratastax-entity. The input follows from the
/// type: text contains (string), choice chips (enum), yes/no (bool), from–to (number, date,
/// date-time), or an autocomplete with [source].
@Target({TargetKind.field})
final class SearchFilter {
  const SearchFilter({this.alias = '', this.source});

  /// The filterable field as the endpoint names it; default: the flattened path (`game.id` →
  /// `gameId`), the convention of stratastax-contract.
  final String alias;

  /// A `@UiDataSource` class: pick one value (`==`), e.g. a game for `gameId`.
  final Type? source;
}

enum SearchDirection { asc, desc }

/// The field is sortable, like `@SearchSort` of stratastax-entity.
@Target({TargetKind.field})
final class SearchSort {
  const SearchSort({this.alias = '', this.direction = SearchDirection.asc, this.initial = false});

  /// As [SearchFilter.alias].
  final String alias;

  /// The direction a first click sorts in.
  final SearchDirection direction;

  /// The sort the page opens with; at most one field.
  final bool initial;
}

/// The field is part of the free-text search above the results (`=ilike=` on every such field,
/// combined with OR). Strings only.
@Target({TargetKind.field})
final class SearchText {
  const SearchText({this.alias = ''});

  /// As [SearchFilter.alias].
  final String alias;
}
