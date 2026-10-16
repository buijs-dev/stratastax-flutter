import 'dart:math';

/// A UUID, the Dart type for OpenAPI `format: uuid`. Zero-cost: a validated, lower-case [String].
///
/// Use [Uuid.parse] / [Uuid.tryParse] for untrusted input. [Uuid.trusted] skips validation and is
/// meant for generated code and literals in tests.
extension type const Uuid.trusted(String value) implements Object {
  static final _pattern = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');

  factory Uuid.parse(String source) => tryParse(source) ?? (throw FormatException('Invalid UUID', source));

  static Uuid? tryParse(String source) {
    final normalized = source.toLowerCase();
    return _pattern.hasMatch(normalized) ? Uuid.trusted(normalized) : null;
  }

  static final _random = Random.secure();

  /// A time-ordered UUIDv7 (RFC 9562), e.g. for `Idempotency-Key` headers.
  ///
  /// No 64-bit bit operations, so the result is the same on the web.
  factory Uuid.v7({DateTime? now, Random? random}) {
    final rng = random ?? _random;
    final millis = (now ?? DateTime.now()).millisecondsSinceEpoch;
    final timestamp = millis.toRadixString(16).padLeft(12, '0');
    String hex(int value, int width) => value.toRadixString(16).padLeft(width, '0');
    final randA = rng.nextInt(0x1000); // 12 bits
    final randB = 0x8000 | rng.nextInt(0x4000); // variant 10 + 14 bits
    final randC = List.generate(3, (_) => hex(rng.nextInt(0x10000), 4)).join();
    return Uuid.trusted(
      '${timestamp.substring(0, 8)}-${timestamp.substring(8, 12)}-7${hex(randA, 3)}-${hex(randB, 4)}-$randC',
    );
  }
}

/// An e-mail address, the Dart type for OpenAPI `format: email`.
///
/// Validation is deliberately shallow (one `@`, a dot in the domain, no whitespace); the server is
/// the authority.
extension type const Email.trusted(String value) implements Object {
  static final _pattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  factory Email.parse(String source) => tryParse(source) ?? (throw FormatException('Invalid e-mail address', source));

  static Email? tryParse(String source) {
    final trimmed = source.trim();
    return _pattern.hasMatch(trimmed) ? Email.trusted(trimmed) : null;
  }
}
