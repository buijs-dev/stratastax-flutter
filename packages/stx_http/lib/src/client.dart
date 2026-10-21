import 'dart:convert';

import 'package:stx_core/stx_core.dart';

import 'exchange.dart';
import 'transport/transport.dart';

/// Calls contract endpoints. Every call returns a [Result]; failures (network, HTTP errors, a
/// response that does not match the contract) are always a [Problem], never an exception.
///
/// The interceptor chain is built once. Recommended order, outermost first:
///
/// ```dart
/// StxClient(baseUrl: base, interceptors: [
///   LoggingInterceptor(log: print),     // sees the final request, never bodies
///   BearerAuthInterceptor(tokens),      // bearer header, refresh once on 401
///   IdempotencyKeyInterceptor(),        // before retry, so retries reuse the key
///   RetryInterceptor(),                 // only retryable endpoints
/// ]);
/// ```
final class StxClient {
  StxClient({required this.baseUrl, List<StxInterceptor> interceptors = const [], StxTransport? transport})
    : _transport = transport ?? createTransport() {
    StxNext chain = _transport.send;
    for (final interceptor in interceptors.reversed) {
      final next = chain;
      chain = (request) => interceptor.intercept(request, next);
    }
    _chain = chain;
  }

  /// Prefix for every endpoint path, e.g. `https://stratastax.dev/rest`.
  final Uri baseUrl;
  final StxTransport _transport;
  late final StxNext _chain;

  /// Calls [endpoint] and decodes the response body.
  Future<Result<R, Problem>> send<P, B, R>(Endpoint<P, B, R> endpoint, {required P params, required B body}) async =>
      (await exchange(endpoint, params: params, body: body)).map((reply) => reply.value);

  /// Like [send], but keeps status and headers (e.g. `ETag`).
  Future<Result<StxReply<R>, Problem>> exchange<P, B, R>(
    Endpoint<P, B, R> endpoint, {
    required P params,
    required B body,
  }) async => (await _exchange(endpoint, params, body, conditional: false)).map((reply) => reply!);

  /// Like [exchange], for a conditional request (params with `If-None-Match`): `Ok(null)` when the
  /// server answers `304 Not Modified`, so the copy the caller has is still current.
  Future<Result<StxReply<R>?, Problem>> exchangeIfModified<P, B, R>(
    Endpoint<P, B, R> endpoint, {
    required P params,
    required B body,
  }) => _exchange(endpoint, params, body, conditional: true);

  Future<Result<StxReply<R>?, Problem>> _exchange<P, B, R>(
    Endpoint<P, B, R> endpoint,
    P params,
    B body, {
    required bool conditional,
  }) async {
    final request = _request(endpoint, params, body);
    final StxResponse response;
    try {
      response = await _chain(request);
    } on StxTransportException catch (e) {
      return Err(Problem.network(e));
    }

    if (conditional && response.status == 304) return const Ok(null);
    if (!response.isSuccess) {
      return Err(Problem.decode(_tryJson(response.body), fallbackStatus: response.status));
    }

    try {
      final json = response.body.isEmpty ? null : jsonDecode(response.body);
      return Ok(StxReply(endpoint.decode(json), status: response.status, headers: response.headers));
    } on JsonDecodeException catch (e) {
      return Err(Problem.decoding(e, status: response.status));
    } on FormatException catch (e) {
      return Err(Problem.decoding(JsonDecodeException('JSON', e.message), status: response.status));
    }
  }

  StxRequest _request<P, B, R>(Endpoint<P, B, R> endpoint, P params, B body) {
    final query = endpoint.query(params);
    final uri = baseUrl.replace(
      pathSegments: [...baseUrl.pathSegments.where((s) => s.isNotEmpty), ...endpoint.segments(params)],
      queryParameters: query.isEmpty ? null : query,
    );
    String? encoded;
    if (endpoint.encodeBody case final encode?) {
      final value = encode(body);
      encoded = endpoint.isJson ? jsonEncode(value) : value.toString();
    }
    return StxRequest(
      method: endpoint.method,
      uri: uri,
      headers: {
        'Accept': 'application/json, application/problem+json',
        if (encoded != null) 'Content-Type': endpoint.isJson ? 'application/json' : endpoint.requestContentType,
        ...endpoint.headers(params),
      },
      body: encoded,
      endpoint: endpoint,
    );
  }

  static Object? _tryJson(String body) {
    if (body.isEmpty) return null;
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }

  void close() => _transport.close();
}

/// Shorthands for the two common shapes.
extension StxClientCalls on StxClient {
  /// An endpoint without a body: `client.fetch(MatchesApiV1.getMatch, GetMatchParams(matchId: id))`.
  Future<Result<R, Problem>> fetch<P, R>(Endpoint<P, NoBody, R> endpoint, P params) =>
      send(endpoint, params: params, body: ());

  /// An endpoint without parameters: `client.submit(MatchesApiV1.createMatch, CreateMatchV1(...))`.
  Future<Result<R, Problem>> submit<B, R>(Endpoint<NoParams, B, R> endpoint, B body) =>
      send(endpoint, params: (), body: body);
}
