import 'package:flutter/widgets.dart';
import 'package:stx_i18n/stx_i18n.dart';
import 'package:stx_search/stx_search.dart';
import 'package:stx_style/stx_style.dart';

import '../form/field.dart';
import '../primitives/button.dart';
import '../primitives/layout.dart';
import '../primitives/pressable.dart';
import 'chip.dart';
import 'list_controller.dart';

/// The shape of an overview's filter panel (`@UiListPage(panel: UiSearchPanel(…))`).
enum StxPanelLayout {
  /// A side panel from `lg`, a bar above the results from [StxListScaffold.collapseBelow], a
  /// "Filters" button with a sheet below it.
  auto,

  /// Always a side panel, down to [StxListScaffold.collapseBelow].
  side,

  /// Always a bar above the results, down to [StxListScaffold.collapseBelow].
  top,
}

/// The side of a side panel; `start` is left in left-to-right languages.
enum StxPanelPosition { start, end }

/// One column of an overview: a table column on wide screens, a line of a card on narrow ones.
@immutable
final class StxListColumn<I> {
  const StxListColumn({required this.label, required this.value, this.sortField, this.flex = 1, this.primary = false});

  final Msg label;

  /// The cell's text. User data comes in as `Msg.data`, enums through their translations.
  final Msg Function(BuildContext context, I item) value;

  /// The sortable field behind this column; its header then sorts.
  final String? sortField;
  final int flex;

  /// The card title on narrow screens.
  final bool primary;

  /// The cell of an absent value.
  static const none = Msg.data('–');
}

/// The page body of a generated overview: title, search, filter panel, results and pager. The
/// panel follows [layout] and the current [Breakpoint]; results are a table from `md`, cards
/// below.
class StxListScaffold<I> extends StatefulWidget {
  const StxListScaffold({
    super.key,
    required this.title,
    required this.controller,
    required this.columns,
    this.layout = StxPanelLayout.auto,
    this.position = StxPanelPosition.start,
    this.collapseBelow = Breakpoint.md,
    this.actions = const [],
  });

  final Msg title;
  final StxListController<I> controller;
  final List<StxListColumn<I>> columns;
  final StxPanelLayout layout;
  final StxPanelPosition position;

  /// Below this breakpoint the panel becomes a "Filters" button with a sheet.
  final Breakpoint collapseBelow;

  /// Next to the title, e.g. a `StxRouteButton` to the create form.
  final List<Widget> actions;

  @override
  State<StxListScaffold<I>> createState() => _StxListScaffoldState<I>();
}

enum _Panel { side, top, sheet }

class _StxListScaffoldState<I> extends State<StxListScaffold<I>> {
  final _sheet = OverlayPortalController();

  StxListController<I> get _list => widget.controller;

  @override
  void initState() {
    super.initState();
    _list.start();
  }

  /// Whether the page was the top page; null: not on a route.
  bool? _current;

  /// Back on top after a page above it is closed (e.g. its create form saved): load again, so a
  /// cache entry that page invalidated is not shown; a valid one answers without a request.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final current = ModalRoute.of(context)?.isCurrent;
    if (current == true && _current == false) _list.refresh();
    _current = current;
  }

  _Panel _panel(Breakpoint bp) {
    if (bp.index < widget.collapseBelow.index) return _Panel.sheet;
    return switch (widget.layout) {
      StxPanelLayout.side => _Panel.side,
      StxPanelLayout.top => _Panel.top,
      StxPanelLayout.auto => bp.index >= Breakpoint.lg.index ? _Panel.side : _Panel.top,
    };
  }

  bool get _hasPanel => _list.filters.isNotEmpty || _list.sorts.length > 1;

  /// The breakpoint of the width the overview gets, not of the screen: next to the navigation
  /// rail of the app shell a 900 px window leaves a phone-sized table.
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => _build(
      context,
      constraints.hasBoundedWidth ? context.tokens.breakpointFor(constraints.maxWidth) : context.breakpoint,
    ),
  );

  Widget _build(BuildContext context, Breakpoint bp) {
    final tokens = context.tokens;
    final panel = _hasPanel ? _panel(bp) : null;
    return ListenableBuilder(
      listenable: _list,
      builder: (context, _) {
        final results = StxColumn(
          gap: SpaceToken.md,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_list.search != null || panel == _Panel.sheet)
              Row(
                spacing: tokens.spacing(SpaceToken.sm),
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (_list.search case final search?) Expanded(child: search.input(context)),
                  if (_list.search == null) const Spacer(),
                  if (panel == _Panel.sheet)
                    StxButton(
                      _list.activeFilters == 0
                          ? StxKeys.searchFilters
                          : StxKeys.searchFiltersActive(_list.activeFilters),
                      variant: ButtonVariant.secondary,
                      onPressed: _sheet.show,
                    ),
                ],
              ),
            if (panel == _Panel.top) _FilterBar<I>(list: _list),
            _ActiveFilters<I>(list: _list),
            _Results<I>(list: _list, columns: widget.columns, table: bp.index >= Breakpoint.md.index),
            _Pager<I>(list: _list),
          ],
        );
        final side = panel == _Panel.side;
        final body = side
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: tokens.spacing(SpaceToken.lg),
                children: [
                  if (widget.position == StxPanelPosition.start) _SidePanel<I>(list: _list),
                  Expanded(child: results),
                  if (widget.position == StxPanelPosition.end) _SidePanel<I>(list: _list),
                ],
              )
            : results;
        return OverlayPortal(
          controller: _sheet,
          overlayChildBuilder: (context) => _Sheet<I>(list: _list, title: widget.title, onClose: _sheet.hide),
          child: SingleChildScrollView(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1280),
                child: StxBox(
                  padding: const StxInsets.all(SpaceToken.lg),
                  child: FocusTraversalGroup(
                    child: StxColumn(
                      gap: SpaceToken.lg,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (widget.actions.isEmpty)
                          StxText(widget.title, style: TextToken.header1)
                        else
                          StxRow(
                            gap: SpaceToken.md,
                            children: [
                              Expanded(child: StxText(widget.title, style: TextToken.header1)),
                              ...widget.actions,
                            ],
                          ),
                        body,
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Sort options and filter inputs, as a column (side panel, sheet) or wrapped (top bar).
List<Widget> _panelChildren<I>(BuildContext context, StxListController<I> list) => [
  if (list.sorts.length > 1) _SortChoice<I>(list: list),
  for (final filter in list.filters) filter.input(context),
];

class _SidePanel<I> extends StatelessWidget {
  const _SidePanel({required this.list});

  final StxListController<I> list;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final spec = tokens.panel;
    return SizedBox(
      width: spec.width,
      child: StxBox(
        padding: StxInsets.all(spec.padding),
        background: spec.background,
        border: spec.border,
        radius: spec.radius,
        child: StxColumn(
          gap: spec.gap,
          mainAxisSize: MainAxisSize.min,
          children: [
            StxText(StxKeys.searchFilters, style: TextToken.header3, color: spec.foreground),
            ..._panelChildren(context, list),
            if (list.activeFilters > 0)
              StxButton(StxKeys.searchReset, variant: ButtonVariant.ghost, onPressed: list.clearFilters),
          ],
        ),
      ),
    );
  }
}

class _FilterBar<I> extends StatelessWidget {
  const _FilterBar({required this.list});

  final StxListController<I> list;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final spec = tokens.panel;
    return StxBox(
      padding: StxInsets.all(spec.padding),
      background: spec.background,
      border: spec.border,
      radius: spec.radius,
      child: Wrap(
        spacing: tokens.spacing(spec.gap),
        runSpacing: tokens.spacing(spec.gap),
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [for (final child in _panelChildren(context, list)) SizedBox(width: spec.width - 40, child: child)],
      ),
    );
  }
}

/// Full screen over the page on narrow screens; the results update while filtering.
class _Sheet<I> extends StatelessWidget {
  const _Sheet({required this.list, required this.title, required this.onClose});

  final StxListController<I> list;
  final Msg title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Positioned.fill(
      child: Semantics(
        scopesRoute: true,
        explicitChildNodes: true,
        label: context.msg(StxKeys.searchFilters),
        child: ColoredBox(
          color: tokens.color(ColorToken.background),
          child: SafeArea(
            child: ListenableBuilder(
              listenable: list,
              builder: (context, _) => StxColumn(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: StxBox(
                        padding: const StxInsets.all(SpaceToken.lg),
                        child: StxColumn(
                          gap: SpaceToken.md,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            StxText(StxKeys.searchFilters, style: TextToken.header2),
                            ..._panelChildren(context, list),
                          ],
                        ),
                      ),
                    ),
                  ),
                  StxBox(
                    padding: const StxInsets.all(SpaceToken.md),
                    border: ColorToken.border,
                    child: Wrap(
                      spacing: tokens.spacing(SpaceToken.sm),
                      runSpacing: tokens.spacing(SpaceToken.sm),
                      alignment: WrapAlignment.end,
                      children: [
                        if (list.activeFilters > 0)
                          StxButton(StxKeys.searchReset, variant: ButtonVariant.ghost, onPressed: list.clearFilters),
                        StxButton(StxKeys.searchShowResults, onPressed: onClose),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const _up = Msg.data('↑');
const _down = Msg.data('↓');

Msg _arrow(SortDirection direction) => direction == SortDirection.asc ? _up : _down;

Msg _directionName(SortDirection direction) =>
    direction == SortDirection.asc ? StxKeys.searchAscending : StxKeys.searchDescending;

class _SortChoice<I> extends StatelessWidget {
  const _SortChoice({required this.list});

  final StxListController<I> list;

  @override
  Widget build(BuildContext context) {
    final current = list.sort;
    return StxColumn(
      gap: SpaceToken.xs,
      mainAxisSize: MainAxisSize.min,
      children: [
        StxText(StxKeys.searchSortBy, style: TextToken.label),
        Wrap(
          spacing: context.tokens.spacing(SpaceToken.xs),
          runSpacing: context.tokens.spacing(SpaceToken.xs),
          children: [
            for (final option in list.sorts)
              StxChip(
                option.label,
                selected: current?.field == option.field,
                trailing: current?.field == option.field ? _arrow(current!.direction) : null,
                semanticLabel: current?.field == option.field ? _directionName(current!.direction) : null,
                onPressed: () => list.sortBy(option.field),
              ),
          ],
        ),
      ],
    );
  }
}

class _ActiveFilters<I> extends StatelessWidget {
  const _ActiveFilters({required this.list});

  final StxListController<I> list;

  @override
  Widget build(BuildContext context) {
    final active = list.filters.where((f) => f.active).toList();
    if (active.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: context.tokens.spacing(SpaceToken.xs),
      runSpacing: context.tokens.spacing(SpaceToken.xs),
      children: [
        for (final filter in active)
          StxChip(
            filter.label,
            selected: true,
            trailing: const Msg.data('×'),
            semanticLabel: StxKeys.searchRemove,
            onPressed: filter.clear,
          ),
      ],
    );
  }
}

class _Results<I> extends StatelessWidget {
  const _Results({required this.list, required this.columns, required this.table});

  final StxListController<I> list;
  final List<StxListColumn<I>> columns;
  final bool table;

  @override
  Widget build(BuildContext context) {
    final state = list.state;
    if (state case ListFailed(:final problem)) {
      return StxColumn(
        gap: SpaceToken.sm,
        cross: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(liveRegion: true, child: StxText(problemMsg(problem), color: ColorToken.danger)),
          StxButton(StxKeys.actionRetry, variant: ButtonVariant.secondary, onPressed: list.refresh),
        ],
      );
    }
    final page = list.page;
    if (page == null) return const StxText(StxKeys.stateLoading, color: ColorToken.muted);
    final loading = state is ListLoading;
    Widget content;
    if (page.items.isEmpty) {
      content = const StxText(StxKeys.stateEmpty, color: ColorToken.muted);
    } else {
      content = table
          ? _Table<I>(list: list, columns: columns, items: page.items)
          : _Cards<I>(columns: columns, items: page.items);
    }
    return Semantics(
      liveRegion: true,
      child: AnimatedOpacity(opacity: loading ? 0.6 : 1, duration: const Duration(milliseconds: 120), child: content),
    );
  }
}

class _Table<I> extends StatelessWidget {
  const _Table({required this.list, required this.columns, required this.items});

  final StxListController<I> list;
  final List<StxListColumn<I>> columns;
  final List<I> items;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final spec = tokens.table;
    final padding = EdgeInsets.symmetric(horizontal: tokens.spacing(spec.padX), vertical: tokens.spacing(spec.padY));
    final divider = BorderSide(color: tokens.color(spec.divider));
    final sort = list.sort;

    Widget header(StxListColumn<I> column) {
      final field = column.sortField;
      final sorted = field != null && sort?.field == field;
      final text = Text(
        [context.msg(column.label), if (sorted) context.msg(_arrow(sort!.direction))].join(' '),
        style: context.textStyle(spec.header, color: spec.headerForeground),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
      final cell = Padding(padding: padding, child: text);
      if (field == null) return cell;
      return StxPressable(
        onPressed: () => list.sortBy(field),
        radius: RadiusToken.none,
        semanticLabel: sorted
            ? '${context.msg(column.label)}, ${context.msg(_directionName(sort!.direction))}'
            : context.msg(column.label),
        builder: (context, state) => ColoredBox(
          color: state.hovered ? tokens.color(spec.divider).withValues(alpha: 0.4) : const Color(0x00000000),
          child: cell,
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.fromBorderSide(divider),
        borderRadius: BorderRadius.circular(tokens.corner(RadiusToken.md)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(tokens.corner(RadiusToken.md)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            ColoredBox(
              color: tokens.color(spec.headerBackground),
              child: Row(
                children: [for (final c in columns) Expanded(flex: c.flex, child: header(c))],
              ),
            ),
            for (var i = 0; i < items.length; i++)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: tokens.color(i.isOdd ? spec.backgroundAlt : spec.background),
                  border: Border(top: divider),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final c in columns)
                      Expanded(
                        flex: c.flex,
                        child: Padding(
                          padding: padding,
                          child: Text(
                            context.msg(c.value(context, items[i])),
                            style: context.textStyle(spec.text, color: spec.foreground),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Cards<I> extends StatelessWidget {
  const _Cards({required this.columns, required this.items});

  final List<StxListColumn<I>> columns;
  final List<I> items;

  @override
  Widget build(BuildContext context) {
    final spec = context.tokens.table;
    final primary = columns.where((c) => c.primary).firstOrNull ?? columns.first;
    return StxColumn(
      gap: SpaceToken.sm,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final item in items)
          StxBox(
            padding: StxInsets.symmetric(x: spec.padX, y: spec.padY),
            border: spec.divider,
            radius: RadiusToken.md,
            child: StxColumn(
              gap: SpaceToken.xs,
              mainAxisSize: MainAxisSize.min,
              children: [
                StxText(primary.value(context, item), style: TextToken.header3, color: spec.foreground),
                for (final c in columns)
                  if (c != primary)
                    StxRow(
                      gap: SpaceToken.sm,
                      cross: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: StxText(c.label, style: TextToken.caption, color: spec.headerForeground),
                        ),
                        Expanded(
                          flex: 2,
                          child: StxText(c.value(context, item), style: spec.text, color: spec.foreground),
                        ),
                      ],
                    ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Pager<I> extends StatelessWidget {
  const _Pager({required this.list});

  final StxListController<I> list;

  @override
  Widget build(BuildContext context) {
    final page = list.page;
    if (page == null || (page.items.isEmpty && list.pageIndex == 0)) return const SizedBox.shrink();
    final from = list.pageIndex * list.pageSize + 1;
    final to = from + page.items.length - 1;
    final total = list.total;
    final position = total == null ? StxKeys.pagerPage(list.pageIndex + 1) : StxKeys.pagerRange(from, to, total);
    if (!list.hasPrev && !list.hasNext && total == null) return const SizedBox.shrink();
    return StxRow(
      gap: SpaceToken.sm,
      main: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: StxButton(
            StxKeys.pagerPrevious,
            variant: ButtonVariant.ghost,
            onPressed: list.hasPrev ? list.previous : null,
          ),
        ),
        Flexible(
          flex: 2,
          child: StxText(position, color: ColorToken.muted, align: TextAlign.center, maxLines: 1),
        ),
        Flexible(
          child: StxButton(StxKeys.pagerNext, variant: ButtonVariant.ghost, onPressed: list.hasNext ? list.next : null),
        ),
      ],
    );
  }
}
