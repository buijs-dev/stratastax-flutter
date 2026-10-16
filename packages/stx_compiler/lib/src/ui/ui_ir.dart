/// The UI IR: what the annotations in the app's Dart sources declare (phase 2), before it is
/// merged with the contract and the translations.
library;

enum TypeKind {
  string,
  int,
  double,
  bool,
  dateTime,
  localDate,
  uuid,
  email,
  list,

  /// A Dart enum (contract enums are generated in lib/gen/contract).
  enumType,

  /// A type annotated with `@BuildTypeConverter`.
  converter,

  /// A class annotated with `@DomainEntity` (mapped field by field).
  entity,

  /// A generated contract model (lib/gen/contract).
  contractModel,
  other,
}

/// A Dart type as the generator needs it: its source code, its library (for imports) and what it
/// is.
final class DartTypeRef {
  const DartTypeRef({
    required this.name,
    required this.kind,
    this.library,
    this.args = const [],
    this.nullable = false,
    this.converterTarget,
    this.representation,
    this.enumValues = const [],
  });

  final String name;
  final TypeKind kind;

  /// `package:…` or `dart:core`; null for type parameters.
  final String? library;
  final List<DartTypeRef> args;
  final bool nullable;

  /// For [TypeKind.converter]: the contract-side type and the field that holds it.
  final DartTypeRef? converterTarget;
  final String? representation;

  /// For [TypeKind.enumType]: value names in declaration order.
  final List<String> enumValues;

  DartTypeRef get nonNull => nullable ? withNullable(false) : this;

  DartTypeRef withNullable(bool value) => DartTypeRef(
    name: name,
    kind: kind,
    library: library,
    args: args,
    nullable: value,
    converterTarget: converterTarget,
    representation: representation,
    enumValues: enumValues,
  );

  /// The type in Dart source, e.g. `List<Participant>` or `GameId?`.
  String get code => '$name${args.isEmpty ? '' : '<${args.map((a) => a.code).join(', ')}>'}${nullable ? '?' : ''}';

  /// Libraries to import for this type and its arguments.
  Iterable<String> get libraries sync* {
    if (library != null && library != 'dart:core') yield library!;
    for (final a in args) {
      yield* a.libraries;
    }
  }

  bool get isContract => library != null && library!.contains('/gen/contract/');

  @override
  String toString() => code;
}

/// A reference to a generated contract endpoint constant (`MatchesApiV1.createMatch`).
final class EndpointRef {
  const EndpointRef({required this.operationId, required this.apiClass, required this.member, required this.library});

  final String operationId;
  final String apiClass;
  final String member;

  /// The generated api library, e.g. `package:app/gen/contract/platform_v1/api/matches_api_v1.g.dart`.
  final String library;

  /// `platform_v1` from the library path.
  String get contractDir => RegExp(r'/gen/contract/([^/]+)/').firstMatch(library)?[1] ?? '';
}

final class UiValidateIR {
  const UiValidateIR({
    this.required,
    this.minLength,
    this.maxLength,
    this.minItems,
    this.maxItems,
    this.minimum,
    this.maximum,
    this.pattern,
  });

  final bool? required;
  final int? minLength;
  final int? maxLength;
  final int? minItems;
  final int? maxItems;
  final num? minimum;
  final num? maximum;
  final String? pattern;
}

final class FieldIR {
  const FieldIR({
    required this.name,
    required this.type,
    required this.location,
    this.order,
    this.kind,
    this.labelKeyId,
    this.hint = false,
    this.help = false,
    this.dataSource,
    this.widget,
    this.contractProperty,
    this.ignore = false,
    this.validate = const UiValidateIR(),
    this.hasDefault = false,
  });

  final String name;
  final DartTypeRef type;
  final String location;
  final int? order;

  /// From `@UiFieldType`, by `UiFieldKind` name.
  final String? kind;

  /// `@UiFieldLabel(MsgCommon.players)`: the MsgKey id.
  final int? labelKeyId;
  final bool hint;
  final bool help;

  /// Class name of the `@UiDataSource` class.
  final String? dataSource;

  /// `@UiFieldWidget(Type)`: class name.
  final String? widget;
  final String? contractProperty;
  final bool ignore;
  final UiValidateIR validate;

  /// The constructor parameter has a default value.
  final bool hasDefault;
}

final class RouteIR {
  const RouteIR({required this.path, required this.nav});

  final String path;

  /// `primary`, `secondary` or `none`.
  final String nav;
}

final class FormIR {
  const FormIR({
    required this.name,
    required this.library,
    required this.location,
    required this.submit,
    required this.onSuccess,
    required this.fields,
    this.route,
    this.requires = const [],
  });

  final String name;
  final String library;
  final String location;
  final EndpointRef submit;

  /// `back`, `reset` or `stay`.
  final String onSuccess;
  final List<FieldIR> fields;
  final RouteIR? route;

  /// `@UiRequires`: extra scope claims (from the generated `Scope` enum).
  final List<String> requires;
}

/// A `@DomainEntity` class used inside a form field (mapped to a contract schema).
final class EntityIR {
  const EntityIR({required this.name, required this.library, required this.location, required this.fields});

  final String name;
  final String library;
  final String location;
  final List<FieldIR> fields;
}

final class DataSourceIR {
  const DataSourceIR({
    required this.name,
    required this.library,
    required this.location,
    required this.endpoint,
    required this.value,
    required this.label,
    this.query,
  });

  final String name;
  final String library;
  final String location;
  final EndpointRef endpoint;
  final String? query;
  final String value;
  final String label;
}

final class FieldWidgetIR {
  const FieldWidgetIR({required this.name, required this.library, required this.location, required this.valueType});

  final String name;
  final String library;
  final String location;

  /// `T` of `StxFieldWidget<T>`.
  final DartTypeRef? valueType;
}

final class UiIR {
  const UiIR({
    required this.package,
    required this.forms,
    required this.entities,
    required this.dataSources,
    required this.fieldWidgets,
  });

  /// The app's package name (for `package:` imports of generated code).
  final String package;
  final List<FormIR> forms;
  final Map<String, EntityIR> entities;
  final Map<String, DataSourceIR> dataSources;
  final Map<String, FieldWidgetIR> fieldWidgets;
}
