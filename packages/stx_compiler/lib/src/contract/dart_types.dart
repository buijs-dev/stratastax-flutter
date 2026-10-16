import '../naming.dart';
import 'ir.dart';

/// Maps IR types to Dart type names and to the encode / decode expressions generated code uses.
final class DartTypes {
  DartTypes(this.contract);

  final ContractIR contract;

  /// Schema keys referenced while rendering one file; decides whether the models barrel is imported.
  final Set<String> referenced = {};

  SchemaIR schema(String key) => contract.schemas[key]!;

  String type(TypeIR t) => switch (t) {
    PrimitiveTypeIR(:final kind) => switch (kind) {
      PrimitiveKind.string => 'String',
      PrimitiveKind.integer => 'int',
      PrimitiveKind.number => 'double',
      PrimitiveKind.boolean => 'bool',
      PrimitiveKind.uuid => 'Uuid',
      PrimitiveKind.dateTime => 'DateTime',
      PrimitiveKind.date => 'LocalDate',
      PrimitiveKind.email => 'Email',
      PrimitiveKind.any => 'Object?',
    },
    RefTypeIR(schema: final key) => _ref(key).dartName,
    ListTypeIR(:final item) => 'List<${type(item)}>',
    MapTypeIR(:final value) => 'Map<String, ${value == null ? 'Object?' : type(value)}>',
  };

  String nullableType(TypeIR t) => isAny(t) ? 'Object?' : '${type(t)}?';

  bool isAny(TypeIR t) => t is PrimitiveTypeIR && t.kind == PrimitiveKind.any;

  bool isCollection(TypeIR t) => t is ListTypeIR || t is MapTypeIR;

  /// The Dart type of a model property.
  String propertyType(PropertyIR p) {
    if (p.patch) return 'Patch<${type(p.type)}>';
    return (p.required && !p.nullable) ? type(p.type) : nullableType(p.type);
  }

  /// Whether the JSON representation equals the Dart value (no conversion needed).
  bool isIdentity(TypeIR t) => switch (t) {
    PrimitiveTypeIR(:final kind) => switch (kind) {
      PrimitiveKind.string || PrimitiveKind.integer || PrimitiveKind.number => true,
      PrimitiveKind.boolean || PrimitiveKind.any => true,
      _ => false,
    },
    RefTypeIR() => false,
    ListTypeIR(:final item) => isIdentity(item),
    MapTypeIR(:final value) => value == null || isIdentity(value),
  };

  /// Encodes the non-null Dart value [expr] of type [t] to a JSON-compatible value.
  String encode(TypeIR t, String expr, [int depth = 0]) {
    if (isIdentity(t)) return expr;
    final e = 'e$depth';
    return switch (t) {
      PrimitiveTypeIR(kind: PrimitiveKind.uuid || PrimitiveKind.email) => '$expr.value',
      PrimitiveTypeIR(kind: PrimitiveKind.dateTime) => '$expr.toUtc().toIso8601String()',
      PrimitiveTypeIR() => '$expr.toString()',
      RefTypeIR(schema: final key) => switch (_ref(key)) {
        EnumSchemaIR() => '$expr.wire',
        final s => '${s.dartName}.encode($expr)',
      },
      ListTypeIR(:final item) => '[for (final $e in $expr) ${encode(item, e, depth + 1)}]',
      MapTypeIR(:final value) => '{for (final $e in $expr.entries) $e.key: ${encode(value!, '$e.value', depth + 1)}}',
    };
  }

  /// A `T Function(Object? json)` expression that decodes one value of type [t].
  String decoder(TypeIR t) => switch (t) {
    PrimitiveTypeIR(:final kind) => switch (kind) {
      PrimitiveKind.string => 'Json.stringValue',
      PrimitiveKind.integer => 'Json.integerValue',
      PrimitiveKind.number => 'Json.numberValue',
      PrimitiveKind.boolean => 'Json.booleanValue',
      PrimitiveKind.uuid => 'Json.uuidValue',
      PrimitiveKind.dateTime => 'Json.dateTimeValue',
      PrimitiveKind.date => 'Json.dateValue',
      PrimitiveKind.email => 'Json.emailValue',
      PrimitiveKind.any => 'Json.anyValue',
    },
    RefTypeIR(schema: final key) => '${_ref(key).dartName}.decode',
    ListTypeIR(:final item) => '(Object? json) => Json.listValue(json, ${decoder(item)})',
    MapTypeIR(value: null) => 'Json.object',
    MapTypeIR(:final value) => '(Object? json) => Json.mapOf(json, ${decoder(value!)})',
  };

  /// Decodes the JSON value [expr] as a value of type [t] (list and map responses).
  String decodeValue(TypeIR t, String expr) => switch (t) {
    ListTypeIR(:final item) => 'Json.listValue($expr, ${decoder(item)})',
    MapTypeIR(value: null) => 'Json.object($expr)',
    MapTypeIR(:final value) => 'Json.mapOf($expr, ${decoder(value!)})',
    _ => '${decoder(t)}($expr)',
  };

  static const _keyHelpers = {
    PrimitiveKind.string: 'string',
    PrimitiveKind.integer: 'integer',
    PrimitiveKind.number: 'number',
    PrimitiveKind.boolean: 'boolean',
    PrimitiveKind.uuid: 'uuid',
    PrimitiveKind.dateTime: 'dateTime',
    PrimitiveKind.date: 'date',
  };

  /// Decodes property [wire] of the JSON object in variable `j`.
  String decodeProperty(PropertyIR p) {
    final optional = !p.required || p.nullable || p.patch;
    final value = _decodeKey(p.type, Naming.stringLiteral(p.wireName), optional: optional);
    if (!p.patch) return value;
    return 'j.containsKey(${Naming.stringLiteral(p.wireName)}) ? Patch.value($value) : const Patch.unset()';
  }

  String _decodeKey(TypeIR t, String key, {required bool optional}) {
    final orNull = optional ? 'OrNull' : '';
    return switch (t) {
      PrimitiveTypeIR(kind: PrimitiveKind.any) => 'j[$key]',
      PrimitiveTypeIR(:final kind) when _keyHelpers.containsKey(kind) => 'Json.${_keyHelpers[kind]}$orNull(j, $key)',
      ListTypeIR(:final item) => 'Json.list$orNull(j, $key, ${decoder(item)})',
      MapTypeIR(value: null) => 'Json.map$orNull(j, $key)',
      _ => 'Json.nested$orNull(j, $key, ${decoder(t)})',
    };
  }

  /// Converts the non-null parameter value [expr] to its string form in a path, query or header.
  String paramString(TypeIR t, String expr) => switch (t) {
    PrimitiveTypeIR(kind: PrimitiveKind.string) => expr,
    PrimitiveTypeIR(kind: PrimitiveKind.uuid || PrimitiveKind.email) => '$expr.value',
    PrimitiveTypeIR(kind: PrimitiveKind.dateTime) => '$expr.toUtc().toIso8601String()',
    RefTypeIR(schema: final key) when _ref(key) is EnumSchemaIR => '$expr.wire',
    _ => '$expr.toString()',
  };

  SchemaIR _ref(String key) {
    referenced.add(key);
    return schema(key);
  }
}
