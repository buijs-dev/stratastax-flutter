import 'package:meta/meta.dart';

import 'json.dart';

/// Canonical error types of the stratastax contract (`error_type.yaml`), mirrored from
/// `ProblemType` in stratastax-http problem-core, plus client-side types that never come from the
/// server.
enum ProblemType {
  authentication('https://errors.stratastax.io/authentication'),
  authorization('https://errors.stratastax.io/authorization'),
  validation('https://errors.stratastax.io/validation'),
  notFound('https://errors.stratastax.io/not-found'),
  conflict('https://errors.stratastax.io/conflict'),
  preconditionFailed('https://errors.stratastax.io/precondition-failed'),
  internal('https://errors.stratastax.io/internal'),

  /// Client-side: the request never got a response (offline, DNS, TLS, timeout).
  network('https://errors.stratastax.io/client/network'),

  /// Client-side: the response did not match the contract.
  decoding('https://errors.stratastax.io/client/decoding'),

  /// The server sent a type this client does not know.
  unknown('about:blank');

  const ProblemType(this.uri);

  final String uri;

  bool get isClientSide => this == network || this == decoding;

  static ProblemType fromUri(String? uri) {
    for (final type in values) {
      if (type.uri == uri) return type;
    }
    return unknown;
  }

  /// Same mapping as `ProblemType.forStatus` in problem-core.
  static ProblemType forStatus(int status) => switch (status) {
    401 => authentication,
    403 => authorization,
    404 => notFound,
    409 => conflict,
    412 => preconditionFailed,
    >= 400 && < 500 => validation,
    _ => internal,
  };
}

/// One offending field of a validation [Problem] (`validation_error.yaml`).
@immutable
final class ProblemViolation {
  const ProblemViolation({required this.field, required this.code, required this.message});

  static ProblemViolation decode(Object? json) {
    final j = Json.object(json);
    return ProblemViolation(
      field: Json.string(j, 'field'),
      code: Json.string(j, 'code'),
      message: Json.string(j, 'message'),
    );
  }

  /// Contract property path, e.g. `players[0].playerId`.
  final String field;

  /// Machine-readable code, e.g. `REQUIRED`, `VALUE_TOO_LONG`, `INVALID_FORMAT`, `OUT_OF_RANGE`.
  final String code;

  /// Server-side message; not localized, so not shown as-is (see `FieldError.fromViolation`).
  final String message;

  @override
  bool operator ==(Object other) =>
      other is ProblemViolation && other.field == field && other.code == code && other.message == message;

  @override
  int get hashCode => Object.hash(field, code, message);

  @override
  String toString() => 'ProblemViolation($field, $code)';
}

/// An RFC 9457 problem (`problem_detail.yaml` / `validation_problem_detail.yaml`).
///
/// Every failed call yields a [Problem], including network and decoding failures, so callers
/// handle one error type.
@immutable
final class Problem {
  const Problem({
    required this.type,
    required this.title,
    required this.status,
    this.detail,
    this.instance,
    this.violations = const [],
  });

  /// A problem for an HTTP [status] when the body is not a problem document.
  factory Problem.fromStatus(int status, {String? detail}) =>
      Problem(type: ProblemType.forStatus(status), title: 'HTTP $status', status: status, detail: detail);

  factory Problem.network(Object cause) =>
      Problem(type: ProblemType.network, title: 'Network error', status: 0, detail: cause.toString());

  factory Problem.decoding(JsonDecodeException cause, {int status = 0}) =>
      Problem(type: ProblemType.decoding, title: 'Unexpected response', status: status, detail: cause.toString());

  /// Decodes a problem document. Lenient on purpose: an error response that is not a valid
  /// problem still produces a usable [Problem] for [fallbackStatus].
  static Problem decode(Object? json, {required int fallbackStatus}) {
    try {
      final j = Json.object(json);
      return Problem(
        // A body without a problem `type` (e.g. a proxy or another service) is typed by its status.
        type: switch (Json.stringOrNull(j, 'type')) {
          final uri? => ProblemType.fromUri(uri),
          null => ProblemType.forStatus(Json.integerOrNull(j, 'status') ?? fallbackStatus),
        },
        title: Json.stringOrNull(j, 'title') ?? 'HTTP $fallbackStatus',
        status: Json.integerOrNull(j, 'status') ?? fallbackStatus,
        detail: Json.stringOrNull(j, 'detail'),
        instance: Json.stringOrNull(j, 'instance'),
        violations: Json.listOrNull(j, 'errors', ProblemViolation.decode) ?? const [],
      );
    } on JsonDecodeException {
      return Problem.fromStatus(fallbackStatus);
    }
  }

  final ProblemType type;
  final String title;

  /// HTTP status; 0 for client-side problems without a response.
  final int status;
  final String? detail;
  final String? instance;

  /// Field violations of a validation problem; empty otherwise.
  final List<ProblemViolation> violations;

  @override
  bool operator ==(Object other) =>
      other is Problem &&
      other.type == type &&
      other.title == title &&
      other.status == status &&
      other.detail == detail &&
      other.instance == instance &&
      _listEquals(other.violations, violations);

  @override
  int get hashCode => Object.hash(type, title, status, detail, instance, Object.hashAll(violations));

  @override
  String toString() => 'Problem(${type.name}, $status, $title)';

  static bool _listEquals(List<Object?> a, List<Object?> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
