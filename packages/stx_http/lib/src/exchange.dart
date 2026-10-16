import 'package:meta/meta.dart';
import 'package:stx_core/stx_core.dart';

/// A request on the wire, as interceptors see it: the body is already encoded.
@immutable
final class StxRequest {
  StxRequest({
    required this.method,
    required this.uri,
    required Map<String, String> headers,
    required this.endpoint,
    this.body,
    this.attempt = 1,
  }) : headers = Map.unmodifiable(headers);

  final HttpMethod method;
  final Uri uri;

  /// Header names as set; use [header] for case-insensitive lookup.
  final Map<String, String> headers;
  final String? body;

  /// The contract operation, for interceptors that act on its metadata (security, idempotency).
  final Endpoint<Object?, Object?, Object?> endpoint;

  /// 1 for the first attempt; incremented by the retry interceptor.
  final int attempt;

  String? header(String name) {
    final lower = name.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == lower) return entry.value;
    }
    return null;
  }

  /// A copy with [set] added or replacing headers with the same (case-insensitive) name.
  StxRequest withHeaders(Map<String, String> set) {
    final lower = {for (final k in set.keys) k.toLowerCase()};
    return copyWith(
      headers: {
        for (final e in headers.entries)
          if (!lower.contains(e.key.toLowerCase())) e.key: e.value,
        ...set,
      },
    );
  }

  StxRequest copyWith({Map<String, String>? headers, int? attempt}) => StxRequest(
    method: method,
    uri: uri,
    headers: headers ?? this.headers,
    endpoint: endpoint,
    body: body,
    attempt: attempt ?? this.attempt,
  );

  @override
  String toString() => 'StxRequest(${method.wire} $uri, ${endpoint.operationId}, attempt $attempt)';
}

/// A response on the wire. Header names are lower case.
@immutable
final class StxResponse {
  StxResponse({required this.status, Map<String, String> headers = const {}, this.body = ''})
    : headers = Map.unmodifiable({for (final e in headers.entries) e.key.toLowerCase(): e.value});

  final int status;
  final Map<String, String> headers;
  final String body;

  bool get isSuccess => status >= 200 && status < 300;

  String? header(String name) => headers[name.toLowerCase()];

  @override
  String toString() => 'StxResponse($status)';
}

/// The request never got a response: offline, DNS, TLS, connection reset or timeout.
final class StxTransportException implements Exception {
  const StxTransportException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => 'StxTransportException: $message${cause == null ? '' : ' ($cause)'}';
}

/// A decoded response with its status and headers, e.g. to read the `ETag` for a later `If-Match`.
@immutable
final class StxReply<R> {
  const StxReply(this.value, {required this.status, required this.headers});

  final R value;
  final int status;

  /// Lower-case names.
  final Map<String, String> headers;

  String? header(String name) => headers[name.toLowerCase()];
}

/// Calls the next interceptor, or the transport for the last one.
typedef StxNext = Future<StxResponse> Function(StxRequest request);

/// Wraps every request. Interceptors may change the request, short-circuit, retry by calling
/// [next] again, or inspect the response. They never see decoded bodies.
abstract interface class StxInterceptor {
  Future<StxResponse> intercept(StxRequest request, StxNext next);
}

/// Sends a request over the network. Throws [StxTransportException] when there is no response.
abstract interface class StxTransport {
  Future<StxResponse> send(StxRequest request);

  void close();
}
