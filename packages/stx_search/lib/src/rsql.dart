import 'package:meta/meta.dart';

/// An RSQL filter expression (the `filter` query parameter of every list endpoint), as in
/// stratastax-search: `;` is AND, `,` is OR, AND binds tighter.
///
/// Values are wire values (`WIN_LOSS`, a UUID, an ISO 8601 instant); [encode] quotes them where
/// RSQL needs it. The output is deterministic, so equal filters give equal cache keys.
@immutable
sealed class Rsql {
  const Rsql();

  factory Rsql.eq(String field, String value) => RsqlComparison(field, RsqlOperator.eq, [value]);

  factory Rsql.ne(String field, String value) => RsqlComparison(field, RsqlOperator.ne, [value]);

  factory Rsql.gt(String field, String value) => RsqlComparison(field, RsqlOperator.gt, [value]);

  factory Rsql.ge(String field, String value) => RsqlComparison(field, RsqlOperator.ge, [value]);

  factory Rsql.lt(String field, String value) => RsqlComparison(field, RsqlOperator.lt, [value]);

  factory Rsql.le(String field, String value) => RsqlComparison(field, RsqlOperator.le, [value]);

  /// Case-insensitive pattern match: `%` is any text, `_` one character.
  factory Rsql.ilike(String field, String pattern) => RsqlComparison(field, RsqlOperator.ilike, [pattern]);

  factory Rsql.isIn(String field, Iterable<String> values) => RsqlComparison(field, RsqlOperator.isIn, [...values]);

  factory Rsql.out(String field, Iterable<String> values) => RsqlComparison(field, RsqlOperator.out, [...values]);

  /// [field] contains [text], ignoring case: `field=ilike="%text%"`, with `%`, `_` and `\` in
  /// [text] escaped so they match themselves.
  factory Rsql.contains(String field, String text) => Rsql.ilike(field, '%${escapeLike(text)}%');

  /// All of [parts]; null parts are left out. Null when nothing is left, the part itself when one is.
  static Rsql? and(Iterable<Rsql?> parts) => _combine(parts, (list) => RsqlAnd(list));

  /// Any of [parts]; null parts are left out.
  static Rsql? or(Iterable<Rsql?> parts) => _combine(parts, (list) => RsqlOr(list));

  static Rsql? _combine(Iterable<Rsql?> parts, Rsql Function(List<Rsql>) build) {
    final list = [...parts.nonNulls];
    return switch (list.length) {
      0 => null,
      1 => list.single,
      _ => build(list),
    };
  }

  /// Escapes `%`, `_` and `\` for a literal match in an `=ilike=` pattern.
  static String escapeLike(String text) => text.replaceAllMapped(RegExp(r'[%_\\]'), (m) => '\\${m[0]}');

  String encode();

  @override
  String toString() => encode();
}

enum RsqlOperator {
  eq('=='),
  ne('!='),
  gt('=gt='),
  ge('=ge='),
  lt('=lt='),
  le('=le='),
  ilike('=ilike='),
  isIn('=in='),
  out('=out=');

  const RsqlOperator(this.wire);

  final String wire;

  bool get isList => this == isIn || this == out;
}

final class RsqlComparison extends Rsql {
  const RsqlComparison(this.field, this.operator, this.values);

  /// The filterable field as the endpoint names it (`gameId`, not `game.id`).
  final String field;
  final RsqlOperator operator;

  /// One value, or the alternatives of `=in=` / `=out=`.
  final List<String> values;

  @override
  String encode() {
    // Patterns are always quoted, as in the stratastax-search README (`name=ilike="%john%"`).
    final encoded = values.map((v) => _quote(v, always: operator == RsqlOperator.ilike));
    return operator.isList ? '$field${operator.wire}(${encoded.join(',')})' : '$field${operator.wire}${encoded.single}';
  }

  @override
  bool operator ==(Object other) => other is RsqlComparison && other.encode() == encode();

  @override
  int get hashCode => encode().hashCode;
}

final class RsqlAnd extends Rsql {
  const RsqlAnd(this.parts);

  final List<Rsql> parts;

  @override
  String encode() => parts.map((p) => p is RsqlOr ? '(${p.encode()})' : p.encode()).join(';');

  @override
  bool operator ==(Object other) => other is RsqlAnd && other.encode() == encode();

  @override
  int get hashCode => encode().hashCode;
}

final class RsqlOr extends Rsql {
  const RsqlOr(this.parts);

  final List<Rsql> parts;

  @override
  String encode() => parts.map((p) => p.encode()).join(',');

  @override
  bool operator ==(Object other) => other is RsqlOr && other.encode() == encode();

  @override
  int get hashCode => encode().hashCode;
}

/// Characters that end an unquoted RSQL argument.
final _reserved = RegExp(r'''[\s"'();,=!<>~\\]''');

/// Quotes [value] with `"` when it is empty or holds a reserved character; inside the quotes `"`
/// and `\` are escaped with a backslash (so `100\%` becomes `"100\\%"`).
String _quote(String value, {bool always = false}) {
  if (!always && value.isNotEmpty && !_reserved.hasMatch(value)) return value;
  return '"${value.replaceAllMapped(RegExp(r'["\\]'), (m) => '\\${m[0]}')}"';
}
