import 'package:meta/meta_meta.dart';

/// The kind of input rendered for a form field.
enum UiFieldKind {
  text,
  textArea,
  password,
  number,
  checkbox,
  select,
  autocomplete,
  multiAutocomplete,
  date,
  dateTime,

  /// Rendered by a widget registered with [UiFieldWidget].
  custom,
}

/// Overrides the field kind the compiler infers from the Dart type.
///
/// Inferred defaults: `String` → text, `int`/`double` → number, `bool` → checkbox,
/// `DateTime` → dateTime, enum → select, with [UiFieldDataSource] → autocomplete,
/// `List<T>` with a data source → multiAutocomplete.
///
/// ```dart
/// @UiFieldType(UiFieldType.autocomplete)
/// ```
@Target({TargetKind.field})
final class UiFieldType {
  const UiFieldType(this.kind);

  final UiFieldKind kind;

  static const text = UiFieldKind.text;
  static const textArea = UiFieldKind.textArea;
  static const password = UiFieldKind.password;
  static const number = UiFieldKind.number;
  static const checkbox = UiFieldKind.checkbox;
  static const select = UiFieldKind.select;
  static const autocomplete = UiFieldKind.autocomplete;
  static const multiAutocomplete = UiFieldKind.multiAutocomplete;
  static const date = UiFieldKind.date;
  static const dateTime = UiFieldKind.dateTime;
}

/// Position of the field in the form. Values must be unique within a form; leave gaps (10, 20,
/// 30) so fields can be inserted later.
@Target({TargetKind.field})
final class UiFormOrder {
  const UiFormOrder(this.order);

  final int order;
}

/// Reuses an existing i18n key as label instead of the convention key `<model>.<field>.label`.
@Target({TargetKind.field})
final class UiFieldLabel {
  const UiFieldLabel(this.key);

  /// A generated `MsgKey` constant, e.g. `MsgCommon.players`.
  final Object key;
}

/// Renders a hint; requires the i18n key `<model>.<field>.hint`.
@Target({TargetKind.field})
final class UiFieldHint {
  const UiFieldHint();
}

/// Renders help text; requires the i18n key `<model>.<field>.help`.
@Target({TargetKind.field})
final class UiFieldHelp {
  const UiFieldHelp();
}

/// Tightens the validation that comes from the contract. Loosening it (e.g. a larger
/// `maxLength` than the contract allows) is a build error.
@Target({TargetKind.field})
final class UiFieldValidate {
  const UiFieldValidate({
    this.required,
    this.minLength,
    this.maxLength,
    this.minItems,
    this.maxItems,
    this.minimum,
    this.maximum,
    this.pattern,
  });

  /// Only `true` is meaningful: a field can be made required, not optional.
  final bool? required;
  final int? minLength;
  final int? maxLength;
  final int? minItems;
  final int? maxItems;
  final num? minimum;
  final num? maximum;
  final String? pattern;
}

/// Feeds an autocomplete / select field from a class annotated with `@UiDataSource`.
@Target({TargetKind.field})
final class UiFieldDataSource {
  const UiFieldDataSource(this.source);

  final Type source;
}

/// On a widget class: registers it as a custom field widget. The class must extend
/// `StxFieldWidget<T>`.
///
/// On a field: renders the field with that widget. `T` must match the field type.
@Target({TargetKind.classType, TargetKind.field})
final class UiFieldWidget {
  const UiFieldWidget([this.widget]);

  /// Null on the widget class itself; the widget type when used on a field.
  final Type? widget;
}

/// Leaves a field out of the form. The command gets the constructor default (so the field needs
/// one, or must be nullable), which is still sent when the contract has a property with that name.
/// A field without a contract property must be ignored, like UI-only data in a nested entity.
@Target({TargetKind.field})
final class UiIgnore {
  const UiIgnore();
}

/// Declares a data source backed by a contract operation.
///
/// The compiler validates [query] against the operation's query parameters and [value] / [label]
/// against the item schema, and adds the operation's scopes to every page that uses the source.
@Target({TargetKind.classType})
final class UiDataSource {
  const UiDataSource({required this.endpoint, required this.value, required this.label, this.query});

  /// A const `Endpoint` from the generated contract code.
  final Object endpoint;

  /// The query parameter that receives the search text; null for non-searchable sources.
  final String? query;

  /// The item property used as field value.
  final String value;

  /// The item property shown to the user (rendered as user data, not translated).
  final String label;
}
