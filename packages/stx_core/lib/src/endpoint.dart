import 'scope.dart';

enum HttpMethod {
  get,
  head,
  post,
  put,
  patch,
  delete;

  /// Safe to retry without an idempotency key (RFC 9110 §9.2.2).
  bool get isIdempotent => this != post && this != patch;

  String get wire => name.toUpperCase();
}

/// Parameters of an endpoint without path, query or header parameters.
typedef NoParams = ();

/// Request body of an endpoint without a body.
typedef NoBody = ();

/// Response type of an endpoint without a response body (e.g. 204).
final class NoContent {
  const NoContent._();

  static const instance = NoContent._();

  static NoContent decode(Object? _) => instance;

  @override
  String toString() => 'NoContent';
}

/// The path of an operation as declared in the contract, e.g. `['api', 'v1', 'matches', '{matchId}']`.
/// Used for diagnostics and as the request path of endpoints without path parameters.
extension type const PathTemplate(List<String> segments) {
  String get pattern => '/${segments.join('/')}';
}

/// Who may call an operation, from the operation's own `security` block in the contract. Mirrors
/// `OperationSecurity` in stratastax-codegen; the root-level `security` is ignored there too.
sealed class Secured {
  const Secured();

  const factory Secured.public() = PublicAccess;
  const factory Secured.authenticated() = AuthenticatedAccess;

  /// Any of [scopes] grants access (`@RolesAllowed` semantics).
  const factory Secured.scopes(Set<StxScope> scopes) = ScopedAccess;

  bool get requiresAuthentication => true;

  /// Whether a caller with [granted] scopes may call the operation.
  bool allows({required bool authenticated, required Set<StxScope> granted});
}

final class PublicAccess extends Secured {
  const PublicAccess();

  @override
  bool get requiresAuthentication => false;

  @override
  bool allows({required bool authenticated, required Set<StxScope> granted}) => true;

  @override
  String toString() => 'Secured.public()';
}

final class AuthenticatedAccess extends Secured {
  const AuthenticatedAccess();

  @override
  bool allows({required bool authenticated, required Set<StxScope> granted}) => authenticated;

  @override
  String toString() => 'Secured.authenticated()';
}

final class ScopedAccess extends Secured {
  const ScopedAccess(this.scopes);

  /// Alternatives: holding one of them is enough.
  final Set<StxScope> scopes;

  @override
  bool allows({required bool authenticated, required Set<StxScope> granted}) =>
      authenticated && scopes.any(granted.contains);

  @override
  String toString() => 'Secured.scopes(${scopes.map((s) => s.claim).join(', ')})';
}

/// A contract operation, generated as a `static const` per operation, e.g. `MatchesApiV1.createMatch`.
/// Generated code uses a subclass per backend (`PlatformEndpoint`), so the backend's client
/// (`PlatformClient`) only accepts its own operations.
///
/// [P] is the generated params class of the operation (or [NoParams]), [B] the request body (or
/// [NoBody]) and [R] the decoded response (or [NoContent]).
base class Endpoint<P, B, R> {
  const Endpoint({
    required this.operationId,
    required this.method,
    required this.path,
    required this.security,
    required this.decode,
    this.idempotent = false,
    this.requestContentType = 'application/json',
    this.encodePath,
    this.encodeQuery,
    this.encodeHeaders,
    this.encodeBody,
  });

  final String operationId;
  final HttpMethod method;
  final PathTemplate path;
  final Secured security;

  /// Whether the operation declares an `Idempotency-Key` header. The header is not part of [P]: the
  /// idempotency interceptor sets it, so a retry reuses the same key.
  final bool idempotent;

  /// `application/json` (body encoded as JSON) or another type whose body is sent as a string,
  /// e.g. `text/csv`.
  final String requestContentType;

  /// Builds the request path segments from [P]; null when the path has no parameters.
  final List<String> Function(P params)? encodePath;

  /// Builds the query parameters from [P]; null when there are none. Absent values are left out.
  final Map<String, List<String>> Function(P params)? encodeQuery;

  /// Builds the header parameters from [P]; null when there are none.
  final Map<String, String> Function(P params)? encodeHeaders;

  /// Encodes the body to a JSON-compatible value (or a string for non-JSON content); null when the
  /// operation has no body.
  final Object? Function(B body)? encodeBody;

  /// Decodes the response JSON; throws `JsonDecodeException` on a contract mismatch.
  final R Function(Object? json) decode;

  bool get hasBody => encodeBody != null;

  bool get isJson => requestContentType == 'application/json';

  /// Whether a failed request may be retried automatically.
  bool get retryable => method.isIdempotent || idempotent;

  List<String> segments(P params) => encodePath?.call(params) ?? path.segments;

  Map<String, List<String>> query(P params) => encodeQuery?.call(params) ?? const {};

  Map<String, String> headers(P params) => encodeHeaders?.call(params) ?? const {};

  @override
  String toString() => 'Endpoint($operationId ${method.wire} ${path.pattern})';
}
