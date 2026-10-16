/// The contract IR: what the generator knows about one OpenAPI document after parsing, before
/// rendering. Mirrors the role of `EntityMetadata` in stratastax-codegen.
library;

/// The Dart-level type of a property, parameter, body or response.
sealed class TypeIR {
  const TypeIR();

  Map<String, Object?> toJson();
}

enum PrimitiveKind { string, integer, number, boolean, uuid, dateTime, date, email, any }

final class PrimitiveTypeIR extends TypeIR {
  const PrimitiveTypeIR(this.kind);

  final PrimitiveKind kind;

  @override
  Map<String, Object?> toJson() => {'primitive': kind.name};
}

/// A generated model or enum, by its key in [ContractIR.schemas].
final class RefTypeIR extends TypeIR {
  const RefTypeIR(this.schema);

  final String schema;

  @override
  Map<String, Object?> toJson() => {'ref': schema};
}

final class ListTypeIR extends TypeIR {
  const ListTypeIR(this.item);

  final TypeIR item;

  @override
  Map<String, Object?> toJson() => {'list': item.toJson()};
}

/// A JSON object used as a map; [value] is null for free-form objects
/// (`additionalProperties: true`).
final class MapTypeIR extends TypeIR {
  const MapTypeIR(this.value);

  final TypeIR? value;

  @override
  Map<String, Object?> toJson() => {'map': value?.toJson() ?? 'any'};
}

/// Validation keywords of a schema. Constraints of a `$ref`'d alias (e.g. `display_name`) are merged
/// into the property that uses it.
final class ConstraintIR {
  const ConstraintIR({
    this.minLength,
    this.maxLength,
    this.minItems,
    this.maxItems,
    this.minimum,
    this.maximum,
    this.exclusiveMinimum = false,
    this.exclusiveMaximum = false,
    this.pattern,
    this.format,
  });

  static const none = ConstraintIR();

  final int? minLength;
  final int? maxLength;
  final int? minItems;
  final int? maxItems;
  final num? minimum;
  final num? maximum;
  final bool exclusiveMinimum;
  final bool exclusiveMaximum;
  final String? pattern;

  /// The raw OpenAPI format, e.g. `uuid`, `date-time`, `int32`, `uri`.
  final String? format;

  /// [override] wins where it sets a value (property-level over alias-level).
  ConstraintIR mergedWith(ConstraintIR override) => ConstraintIR(
    minLength: override.minLength ?? minLength,
    maxLength: override.maxLength ?? maxLength,
    minItems: override.minItems ?? minItems,
    maxItems: override.maxItems ?? maxItems,
    minimum: override.minimum ?? minimum,
    maximum: override.maximum ?? maximum,
    exclusiveMinimum: override.minimum != null ? override.exclusiveMinimum : exclusiveMinimum,
    exclusiveMaximum: override.maximum != null ? override.exclusiveMaximum : exclusiveMaximum,
    pattern: override.pattern ?? pattern,
    format: override.format ?? format,
  );

  Map<String, Object?> toJson() => {
    'minLength': ?minLength,
    'maxLength': ?maxLength,
    'minItems': ?minItems,
    'maxItems': ?maxItems,
    'minimum': ?minimum,
    'maximum': ?maximum,
    if (exclusiveMinimum) 'exclusiveMinimum': true,
    if (exclusiveMaximum) 'exclusiveMaximum': true,
    'pattern': ?pattern,
    'format': ?format,
  };
}

final class PropertyIR {
  const PropertyIR({
    required this.wireName,
    required this.dartName,
    required this.type,
    required this.required,
    required this.nullable,
    this.patch = false,
    this.constraints = ConstraintIR.none,
    this.description,
  });

  final String wireName;
  final String dartName;
  final TypeIR type;

  /// Listed in the schema's `required`.
  final bool required;

  /// `null` is a valid value (`type: [x, 'null']` or `anyOf: [x, {type: 'null'}]`).
  final bool nullable;

  /// Optional and nullable in a PATCH body: absent and null differ, generated as `Patch<T>`.
  final bool patch;
  final ConstraintIR constraints;
  final String? description;

  PropertyIR asPatch() => PropertyIR(
    wireName: wireName,
    dartName: dartName,
    type: type,
    required: required,
    nullable: nullable,
    patch: true,
    constraints: constraints,
    description: description,
  );

  Map<String, Object?> toJson() => {
    'name': wireName,
    'type': type.toJson(),
    'required': required,
    'nullable': nullable,
    if (patch) 'patch': true,
    if (constraints.toJson().isNotEmpty) 'constraints': constraints.toJson(),
  };
}

sealed class SchemaIR {
  const SchemaIR({required this.key, required this.dartName, required this.location, this.description});

  /// `create_match` for components, `CreateMatchParticipants` style for inline schemas.
  final String key;
  final String dartName;

  /// Where the schema is declared, for diagnostics and the `// Source:` header.
  final String location;
  final String? description;

  Map<String, Object?> toJson();
}

final class ObjectSchemaIR extends SchemaIR {
  const ObjectSchemaIR({
    required super.key,
    required super.dartName,
    required super.location,
    required this.properties,
    super.description,
  });

  final List<PropertyIR> properties;

  ObjectSchemaIR withProperties(List<PropertyIR> properties) => ObjectSchemaIR(
    key: key,
    dartName: dartName,
    location: location,
    properties: properties,
    description: description,
  );

  @override
  Map<String, Object?> toJson() => {
    'kind': 'object',
    'dart': dartName,
    'properties': [for (final p in properties) p.toJson()],
  };
}

final class EnumValueIR {
  const EnumValueIR(this.wire, this.dartName);

  final String wire;
  final String dartName;
}

final class EnumSchemaIR extends SchemaIR {
  const EnumSchemaIR({
    required super.key,
    required super.dartName,
    required super.location,
    required this.values,
    super.description,
  });

  final List<EnumValueIR> values;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'enum',
    'dart': dartName,
    'values': [for (final v in values) v.wire],
  };
}

enum ParamLocation { path, query, header }

final class ParamIR {
  const ParamIR({
    required this.wireName,
    required this.dartName,
    required this.location,
    required this.type,
    required this.required,
    this.constraints = ConstraintIR.none,
    this.description,
  });

  final String wireName;
  final String dartName;
  final ParamLocation location;
  final TypeIR type;
  final bool required;
  final ConstraintIR constraints;
  final String? description;

  Map<String, Object?> toJson() => {'name': wireName, 'in': location.name, 'type': type.toJson(), 'required': required};
}

final class BodyIR {
  const BodyIR({required this.type, required this.contentType});

  final TypeIR type;
  final String contentType;

  bool get isJson => contentType == 'application/json';

  Map<String, Object?> toJson() => {'type': type.toJson(), 'contentType': contentType};
}

/// Who may call an operation; mirrors `OperationSecurity` in stratastax-codegen.
sealed class SecurityIR {
  const SecurityIR();

  Object toJson();
}

/// No `security` on the operation itself; the root-level `security` is deliberately ignored.
final class UndeclaredSecurity extends SecurityIR {
  const UndeclaredSecurity();

  @override
  Object toJson() => 'undeclared';
}

final class PublicSecurity extends SecurityIR {
  const PublicSecurity();

  @override
  Object toJson() => 'public';
}

final class AuthenticatedSecurity extends SecurityIR {
  const AuthenticatedSecurity();

  @override
  Object toJson() => 'authenticated';
}

/// Any of [scopes] grants access.
final class ScopedSecurity extends SecurityIR {
  const ScopedSecurity(this.scopes);

  final List<String> scopes;

  @override
  Object toJson() => {'anyOf': scopes};
}

enum HttpMethodIR { get, head, post, put, patch, delete }

final class OperationIR {
  const OperationIR({
    required this.operationId,
    required this.dartName,
    required this.tag,
    required this.method,
    required this.path,
    required this.params,
    required this.security,
    required this.location,
    this.body,
    this.response,
    this.idempotent = false,
    this.summary,
    this.description,
  });

  final String operationId;

  /// The static member name on the API class, e.g. `createMatch`.
  final String dartName;

  /// First tag, e.g. `matches` (→ `MatchesApiV1`).
  final String tag;
  final HttpMethodIR method;

  /// As declared, e.g. `/api/v1/matches/{matchId}`.
  final String path;
  final List<ParamIR> params;
  final BodyIR? body;

  /// The JSON body of the first 2xx response; null for responses without content.
  final TypeIR? response;
  final SecurityIR security;

  /// Declares an `Idempotency-Key` header (not part of [params]).
  final bool idempotent;
  final String location;
  final String? summary;
  final String? description;

  List<String> get segments => path.split('/').where((s) => s.isNotEmpty).toList();

  Map<String, Object?> toJson() => {
    'operationId': operationId,
    'method': method.name.toUpperCase(),
    'path': path,
    'tag': tag,
    'security': security.toJson(),
    if (idempotent) 'idempotent': true,
    if (params.isNotEmpty) 'params': [for (final p in params) p.toJson()],
    if (body != null) 'body': body!.toJson(),
    'response': response?.toJson() ?? 'none',
  };
}

/// One parsed OpenAPI document.
final class ContractIR {
  const ContractIR({
    required this.name,
    required this.source,
    required this.modelSuffix,
    required this.apiSuffix,
    required this.schemas,
    required this.operations,
  });

  /// The stx.yaml key, e.g. `platformV1`.
  final String name;
  final String source;
  final String modelSuffix;
  final String apiSuffix;

  /// Sorted by key.
  final Map<String, SchemaIR> schemas;

  /// Sorted by tag, then operationId.
  final List<OperationIR> operations;

  Iterable<String> get scopes sync* {
    for (final operation in operations) {
      if (operation.security case ScopedSecurity(:final scopes)) yield* scopes;
    }
  }

  Map<String, List<OperationIR>> get operationsByTag {
    final result = <String, List<OperationIR>>{};
    for (final operation in operations) {
      result.putIfAbsent(operation.tag, () => []).add(operation);
    }
    return result;
  }

  Map<String, Object?> toJson() => {
    'contract': name,
    'source': source,
    'schemas': {for (final e in schemas.entries) e.key: e.value.toJson()},
    'operations': [for (final o in operations) o.toJson()],
  };
}
