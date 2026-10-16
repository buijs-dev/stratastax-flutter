import 'ids.dart';
import 'local_date.dart';

/// A JSON document does not match the shape the contract promises.
///
/// [path] points at the offending value, e.g. `players[1].playerId`.
final class JsonDecodeException implements Exception {
  JsonDecodeException(this.expected, this.actual, [List<String> path = const []]) : _path = List.unmodifiable(path);

  final String expected;
  final Object? actual;
  final List<String> _path;

  String get path => _path.isEmpty ? r'$' : _path.join('.').replaceAll('.[', '[');

  /// Returns a copy with [segment] prepended to the path.
  JsonDecodeException at(String segment) => JsonDecodeException(expected, actual, [segment, ..._path]);

  @override
  String toString() => 'JsonDecodeException at $path: expected $expected, got ${_describe(actual)}';

  static String _describe(Object? value) => switch (value) {
    null => 'null',
    String() => 'string "$value"',
    _ => '${value.runtimeType} $value',
  };
}

/// Decoding helpers used by generated contract codecs.
///
/// Every helper either returns the typed value or throws a [JsonDecodeException] with the path of
/// the offending value. Generated code is straight-line calls to these helpers; there is no
/// reflection.
abstract final class Json {
  static Map<String, Object?> object(Object? json) => switch (json) {
    Map<String, Object?>() => json,
    Map() => json.map((k, v) => MapEntry(k.toString(), v)),
    _ => throw JsonDecodeException('object', json),
  };

  static List<Object?> array(Object? json) => switch (json) {
    List<Object?>() => json,
    _ => throw JsonDecodeException('array', json),
  };

  static String string(Map<String, Object?> json, String key) =>
      _required(json, key, 'string', (v) => v is String ? v : null);

  static String? stringOrNull(Map<String, Object?> json, String key) =>
      _optional(json, key, 'string', (v) => v is String ? v : null);

  static int integer(Map<String, Object?> json, String key) => _required(json, key, 'integer', _asInt);

  static int? integerOrNull(Map<String, Object?> json, String key) => _optional(json, key, 'integer', _asInt);

  static double number(Map<String, Object?> json, String key) =>
      _required(json, key, 'number', (v) => v is num ? v.toDouble() : null);

  static double? numberOrNull(Map<String, Object?> json, String key) =>
      _optional(json, key, 'number', (v) => v is num ? v.toDouble() : null);

  static bool boolean(Map<String, Object?> json, String key) =>
      _required(json, key, 'boolean', (v) => v is bool ? v : null);

  static bool? booleanOrNull(Map<String, Object?> json, String key) =>
      _optional(json, key, 'boolean', (v) => v is bool ? v : null);

  static Uuid uuid(Map<String, Object?> json, String key) => _required(json, key, 'uuid', _asUuid);

  static Uuid? uuidOrNull(Map<String, Object?> json, String key) => _optional(json, key, 'uuid', _asUuid);

  static DateTime dateTime(Map<String, Object?> json, String key) => _required(json, key, 'date-time', _asDateTime);

  static DateTime? dateTimeOrNull(Map<String, Object?> json, String key) =>
      _optional(json, key, 'date-time', _asDateTime);

  static LocalDate date(Map<String, Object?> json, String key) => _required(json, key, 'date', _asDate);

  static LocalDate? dateOrNull(Map<String, Object?> json, String key) => _optional(json, key, 'date', _asDate);

  /// A free-form object (`type: object` with `additionalProperties: true`).
  static Map<String, Object?> map(Map<String, Object?> json, String key) => nested(json, key, object);

  static Map<String, Object?>? mapOrNull(Map<String, Object?> json, String key) => nestedOrNull(json, key, object);

  /// An object whose values all decode with [decode] (`additionalProperties: <schema>`).
  static Map<String, T> mapOf<T>(Object? json, T Function(Object? json) decode) {
    final source = object(json);
    return Map.unmodifiable({for (final e in source.entries) e.key: _guard(e.key, () => decode(e.value))});
  }

  // Value-level decoders, for list items and map values.

  static String stringValue(Object? json) => json is String ? json : throw JsonDecodeException('string', json);

  static int integerValue(Object? json) =>
      (json == null ? null : _asInt(json)) ?? (throw JsonDecodeException('integer', json));

  static double numberValue(Object? json) => json is num ? json.toDouble() : throw JsonDecodeException('number', json);

  static bool booleanValue(Object? json) => json is bool ? json : throw JsonDecodeException('boolean', json);

  static Uuid uuidValue(Object? json) =>
      (json == null ? null : _asUuid(json)) ?? (throw JsonDecodeException('uuid', json));

  static DateTime dateTimeValue(Object? json) =>
      (json == null ? null : _asDateTime(json)) ?? (throw JsonDecodeException('date-time', json));

  static LocalDate dateValue(Object? json) =>
      (json == null ? null : _asDate(json)) ?? (throw JsonDecodeException('date', json));

  static Email emailValue(Object? json) =>
      (json is String ? Email.tryParse(json) : null) ?? (throw JsonDecodeException('email', json));

  /// An unmodifiable list, for nested lists and list responses.
  static List<T> listValue<T>(Object? json, T Function(Object? json) decode) =>
      _decodeItems('', array(json), decode, indexOnly: true);

  /// Any JSON value, unchecked (schemas without a type).
  static Object? anyValue(Object? json) => json;

  /// A nested value decoded by [decode], e.g. a `$ref` to another schema.
  static T nested<T>(Map<String, Object?> json, String key, T Function(Object? json) decode) {
    if (!json.containsKey(key)) throw JsonDecodeException('value', null, [key]);
    return _guard(key, () => decode(json[key]));
  }

  static T? nestedOrNull<T extends Object>(Map<String, Object?> json, String key, T Function(Object? json) decode) {
    final value = json[key];
    return value == null ? null : _guard(key, () => decode(value));
  }

  /// An unmodifiable list whose items are decoded by [decode].
  static List<T> list<T>(Map<String, Object?> json, String key, T Function(Object? json) decode) {
    final value = json[key];
    if (value is! List<Object?>) throw JsonDecodeException('array', value, [key]);
    return _decodeItems(key, value, decode);
  }

  static List<T>? listOrNull<T>(Map<String, Object?> json, String key, T Function(Object? json) decode) {
    final value = json[key];
    if (value == null) return null;
    if (value is! List<Object?>) throw JsonDecodeException('array', value, [key]);
    return _decodeItems(key, value, decode);
  }

  static List<T> _decodeItems<T>(
    String key,
    List<Object?> items,
    T Function(Object? json) decode, {
    bool indexOnly = false,
  }) => List.unmodifiable([
    for (var i = 0; i < items.length; i++) _guard(indexOnly ? '[$i]' : '$key[$i]', () => decode(items[i])),
  ]);

  static T _guard<T>(String segment, T Function() decode) {
    try {
      return decode();
    } on JsonDecodeException catch (e) {
      throw e.at(segment);
    }
  }

  static T _required<T extends Object>(
    Map<String, Object?> json,
    String key,
    String expected,
    T? Function(Object value) convert,
  ) {
    final value = json[key];
    final converted = value == null ? null : convert(value);
    if (converted == null) throw JsonDecodeException(expected, value, [key]);
    return converted;
  }

  static T? _optional<T extends Object>(
    Map<String, Object?> json,
    String key,
    String expected,
    T? Function(Object value) convert,
  ) {
    final value = json[key];
    if (value == null) return null;
    return convert(value) ?? (throw JsonDecodeException(expected, value, [key]));
  }

  // On the web every number is a double; accept integral values.
  static int? _asInt(Object value) => switch (value) {
    int() => value,
    double() when value == value.truncateToDouble() && value.isFinite => value.toInt(),
    _ => null,
  };

  static Uuid? _asUuid(Object value) => value is String ? Uuid.tryParse(value) : null;

  static DateTime? _asDateTime(Object value) => value is String ? DateTime.tryParse(value) : null;

  static LocalDate? _asDate(Object value) => value is String ? LocalDate.tryParse(value) : null;
}
