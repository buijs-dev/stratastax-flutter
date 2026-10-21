import 'package:flutter/widgets.dart';
import 'package:stx_core/stx_core.dart';
import 'package:stx_i18n/stx_i18n.dart';
import 'package:stx_search/stx_search.dart';
import 'package:stx_style/stx_style.dart';

import '../data/data_source.dart';
import '../fields/choice_fields.dart';
import '../fields/date_fields.dart';
import '../fields/field_frame.dart';
import '../fields/form_fields.dart';
import '../form/field.dart';
import 'chip.dart';

/// One filter of an overview, generated per `@SearchFilter` field: its value(s) as [StxField]s
/// (so the form inputs can edit them) and the RSQL it adds to the `filter` parameter.
///
/// [field] is the filterable field as the endpoint names it (`gameId`, `name`).
sealed class StxFilter extends ChangeNotifier {
  StxFilter({required this.label});

  final Msg label;

  /// The fields that hold this filter's value; a change of any of them is a change of the filter.
  List<StxField<Object?>> get values;

  /// Null when the filter is not set.
  Rsql? toRsql();

  bool get active => toRsql() != null;

  /// Back to "not set".
  void clear();

  /// The input of the filter panel. Built by the filter itself, so its value type stays exact.
  Widget input(BuildContext context);

  var _listening = false;

  @override
  void addListener(VoidCallback listener) {
    if (!_listening) {
      _listening = true;
      for (final v in values) {
        v.addListener(notifyListeners);
      }
    }
    super.addListener(listener);
  }

  @override
  void dispose() {
    for (final v in values) {
      v.dispose();
    }
    super.dispose();
  }
}

/// Text that one of [fields] contains, ignoring case (`=ilike=`). With several fields this is the
/// free-text search of `@SearchText`.
final class StxTextFilter extends StxFilter {
  StxTextFilter({required this.fields, required super.label});

  final List<String> fields;
  final text = StxField<String?>(null);

  @override
  List<StxField<Object?>> get values => [text];

  @override
  Rsql? toRsql() {
    final value = text.value?.trim() ?? '';
    if (value.isEmpty) return null;
    return Rsql.or([for (final f in fields) Rsql.contains(f, value)]);
  }

  @override
  void clear() => text.value = null;

  @override
  Widget input(BuildContext context) => StxFormText(field: text, label: label, hint: StxKeys.searchHint);
}

/// One or more of [options] (`=in=`): enums.
final class StxChoiceFilter<T> extends StxFilter {
  StxChoiceFilter({
    required this.field,
    required super.label,
    required this.options,
    required this.optionLabel,
    required this.wire,
  });

  final String field;
  final List<T> options;
  final Msg Function(T option) optionLabel;

  /// The value on the wire, e.g. `ScoreTypeV1.wire`.
  final String Function(T option) wire;
  final selected = StxField<Set<T>>(const {});

  @override
  List<StxField<Object?>> get values => [selected];

  void toggle(T option) {
    final next = {...selected.value};
    if (!next.remove(option)) next.add(option);
    // Declaration order, so equal selections give equal filters.
    selected.value = {
      for (final o in options)
        if (next.contains(o)) o,
    };
  }

  @override
  Rsql? toRsql() => selected.value.isEmpty ? null : Rsql.isIn(field, selected.value.map(wire));

  @override
  void clear() => selected.value = const {};

  @override
  Widget input(BuildContext context) => StxFieldFrame(
    label: label,
    child: StxFieldBuilder(
      field: selected,
      builder: (context, value) => Wrap(
        spacing: context.tokens.spacing(SpaceToken.xs),
        runSpacing: context.tokens.spacing(SpaceToken.xs),
        children: [
          for (final option in options)
            StxChip(optionLabel(option), selected: value.contains(option), onPressed: () => toggle(option)),
        ],
      ),
    ),
  );
}

/// Yes, no or either (`==`).
final class StxBoolFilter extends StxFilter {
  StxBoolFilter({required this.field, required super.label});

  final String field;
  final value = StxField<bool?>(null);

  @override
  List<StxField<Object?>> get values => [value];

  @override
  Rsql? toRsql() => switch (value.value) {
    null => null,
    final v => Rsql.eq(field, '$v'),
  };

  @override
  void clear() => value.value = null;

  @override
  Widget input(BuildContext context) => StxFieldFrame(
    label: label,
    child: StxFieldBuilder(
      field: value,
      builder: (context, current) => Wrap(
        spacing: context.tokens.spacing(SpaceToken.xs),
        children: [
          for (final (choice, text) in [
            (null, StxKeys.searchAny),
            (true, StxKeys.searchYes),
            (false, StxKeys.searchNo),
          ])
            StxChip(text, selected: current == choice, onPressed: () => value.value = choice),
        ],
      ),
    ),
  );
}

/// A minimum and/or maximum, both inclusive (`=ge=` / `=le=`).
final class StxRangeFilter<T extends num> extends StxFilter {
  StxRangeFilter({required this.field, required super.label});

  final String field;
  final min = StxField<T?>(null);
  final max = StxField<T?>(null);

  @override
  List<StxField<Object?>> get values => [min, max];

  @override
  Rsql? toRsql() =>
      Rsql.and([if (min.value case final v?) Rsql.ge(field, '$v'), if (max.value case final v?) Rsql.le(field, '$v')]);

  @override
  void clear() {
    min.value = null;
    max.value = null;
  }

  @override
  Widget input(BuildContext context) => StxFieldFrame(
    label: label,
    child: Row(
      spacing: context.tokens.spacing(SpaceToken.sm),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: StxFormNumber<T>(field: min, label: StxKeys.searchFrom),
        ),
        Expanded(
          child: StxFormNumber<T>(field: max, label: StxKeys.searchTo),
        ),
      ],
    ),
  );
}

/// A period of whole days, both inclusive. For a date-time field the days are the user's local
/// days: from local midnight to the next local midnight, sent as UTC instants.
final class StxDateRangeFilter extends StxFilter {
  StxDateRangeFilter({required this.field, required super.label, this.dateTime = true});

  final String field;

  /// The field is a date-time (`playedAt`); false for a date.
  final bool dateTime;
  final from = StxField<LocalDate?>(null);
  final to = StxField<LocalDate?>(null);

  @override
  List<StxField<Object?>> get values => [from, to];

  static String _instant(LocalDate day) => DateTime(day.year, day.month, day.day).toUtc().toIso8601String();

  @override
  Rsql? toRsql() => Rsql.and([
    if (from.value case final d?) Rsql.ge(field, dateTime ? _instant(d) : '$d'),
    if (to.value case final d?)
      dateTime
          ? Rsql.lt(field, _instant(LocalDate.fromDateTime(DateTime(d.year, d.month, d.day + 1))))
          : Rsql.le(field, '$d'),
  ]);

  @override
  void clear() {
    from.value = null;
    to.value = null;
  }

  @override
  Widget input(BuildContext context) => StxFieldFrame(
    label: label,
    child: Column(
      spacing: context.tokens.spacing(SpaceToken.sm),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        StxFormDate(field: from, label: StxKeys.searchFrom),
        StxFormDate(field: to, label: StxKeys.searchTo),
      ],
    ),
  );
}

/// One value picked from a data source (`==`), e.g. a game for `gameId`.
final class StxSourceFilter<T> extends StxFilter {
  StxSourceFilter({required this.field, required super.label, required this.source, required this.wire});

  final String field;
  final StxDataSource<T> source;
  final String Function(T value) wire;
  final value = StxField<T?>(null);

  @override
  List<StxField<Object?>> get values => [value];

  @override
  Rsql? toRsql() => switch (value.value) {
    null => null,
    final v => Rsql.eq(field, wire(v)),
  };

  @override
  void clear() => value.value = null;

  @override
  Widget input(BuildContext context) => StxAutocomplete<T>(source: source, field: value, label: label);
}

/// A sort an overview offers: a sortable field, its label and the direction it starts in.
@immutable
final class StxSortOption {
  const StxSortOption({required this.field, required this.label, this.direction = SortDirection.asc});

  final String field;
  final Msg label;
  final SortDirection direction;
}
