enum Severity { error, warning }

/// A finding of the compiler, reported with a stable code (docs/ARCHITECTURE.md §12).
final class Diagnostic {
  const Diagnostic(this.severity, this.code, this.message, {required this.location, this.hint});

  const Diagnostic.error(this.code, this.message, {required this.location, this.hint}) : severity = Severity.error;

  const Diagnostic.warning(this.code, this.message, {required this.location, this.hint}) : severity = Severity.warning;

  final Severity severity;

  /// E.g. `STX-C001`.
  final String code;
  final String message;

  /// A file, optionally with a JSON pointer: `openapi/platform-v1.yaml#/paths/~1api~1v1~1matches/get`.
  final String location;
  final String? hint;

  bool get isError => severity == Severity.error;

  @override
  String toString() => '${severity.name}[$code] $location: $message${hint == null ? '' : '\n  hint: $hint'}';
}

/// Collects diagnostics of one compiler run.
final class Diagnostics {
  final List<Diagnostic> _all = [];

  List<Diagnostic> get all => List.unmodifiable(_all);

  bool get hasErrors => _all.any((d) => d.isError);

  void add(Diagnostic diagnostic) => _all.add(diagnostic);

  void error(String code, String message, {required String location, String? hint}) =>
      add(Diagnostic.error(code, message, location: location, hint: hint));

  void warning(String code, String message, {required String location, String? hint}) =>
      add(Diagnostic.warning(code, message, location: location, hint: hint));
}

/// Diagnostic codes of the contract stage.
abstract final class ContractCodes {
  /// Operation without its own `security` block.
  static const undeclaredSecurity = 'STX-C001';

  /// Schema construct the generator does not support.
  static const unsupported = 'STX-C002';

  /// `$ref` that cannot be resolved.
  static const unresolvedRef = 'STX-C003';

  /// Two schemas or operations map to the same Dart name.
  static const nameCollision = 'STX-C004';

  /// Operation without `operationId`.
  static const missingOperationId = 'STX-C005';

  /// The spec or configuration cannot be read.
  static const unreadable = 'STX-C006';
}
