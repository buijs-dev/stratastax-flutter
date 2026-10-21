import 'dart:async';

import 'package:meta/meta.dart';
import 'package:stx_core/stx_core.dart';
import 'package:stx_http/stx_http.dart';

import 'jwt.dart';
import 'token_endpoint.dart';

/// A confidential OIDC client that obtains its own tokens (Client Credentials, RFC 6749 §4.4), e.g.
/// a Keycloak client with a service account. Endpoint paths follow Keycloak's layout under the
/// realm [issuer].
@immutable
final class ServiceAccountConfig {
  const ServiceAccountConfig({
    required this.issuer,
    required this.clientId,
    this.clientSecret,
    this.scopes = const [],
    this.tokenPath = 'protocol/openid-connect/token',
    this.refreshMargin = const Duration(seconds: 30),
  });

  final Uri issuer;
  final String clientId;

  /// Sent in the body (`client_secret_post`); null for a client that authenticates otherwise
  /// (e.g. a proxy that adds it).
  final String? clientSecret;

  /// Requested with `scope`; empty: the client's default scopes.
  final List<String> scopes;
  final String tokenPath;

  /// Obtain a new token this long before the current one expires.
  final Duration refreshMargin;
}

/// The tokens of a service account, independent of the user's [Session]: obtained with the client
/// credentials grant on first use, kept in memory and renewed before they expire. Concurrent
/// callers share one request (single-flight).
///
/// A client secret in an app is not a secret: anyone can extract it from the binary or the
/// JavaScript. Use a service account only for data that is public anyway (published translations),
/// with a client per app that only has read scopes; on the web prefer a token from a backend for
/// frontend ([StaticTokenSource], or your own [TokenSource]).
final class ServiceAccountTokens implements TokenSource {
  ServiceAccountTokens({
    required this.config,
    StxTransport? transport,
    DateTime Function()? clock,
    void Function(String line)? log,
  }) : _clock = clock ?? DateTime.now,
       _client = StxClient(
         baseUrl: config.issuer,
         transport: transport,
         interceptors: [if (log != null) LoggingInterceptor(log: log)],
       );

  final ServiceAccountConfig config;
  final DateTime Function() _clock;
  final StxClient _client;

  String? _accessToken;
  DateTime? _expiresAt;
  Future<String?>? _refreshing;

  /// The current token; a new one first when there is none or it expires within
  /// [ServiceAccountConfig.refreshMargin].
  @override
  Future<String?> accessToken() async {
    final expiresAt = _expiresAt;
    final fresh = expiresAt == null || _clock().add(config.refreshMargin).isBefore(expiresAt);
    return _accessToken != null && fresh ? _accessToken : refreshAccessToken();
  }

  /// Obtains a new token; null when the identity provider refuses. When it cannot be reached, the
  /// current token is kept (it may still be valid).
  @override
  Future<String?> refreshAccessToken() => _refreshing ??= _obtain().whenComplete(() => _refreshing = null);

  Future<String?> _obtain() async {
    final result = await _client.send(
      tokenEndpoint,
      params: config.tokenPath.split('/'),
      body: {
        'grant_type': 'client_credentials',
        'client_id': config.clientId,
        'client_secret': ?config.clientSecret,
        if (config.scopes.isNotEmpty) 'scope': config.scopes.join(' '),
      },
    );
    switch (result) {
      case Ok(:final value):
        _accessToken = value.accessToken;
        _expiresAt = value.expiresIn != null
            ? _clock().add(Duration(seconds: value.expiresIn!))
            : jwtExpiry(jwtClaims(value.accessToken) ?? const {})?.toLocal();
        return _accessToken;
      case Err(error: Problem(type: ProblemType.network)):
        return _accessToken;
      case Err():
        _accessToken = null;
        _expiresAt = null;
        return null;
    }
  }
}

/// A fixed token, e.g. from `--dart-define` or handed out by a backend for frontend. It cannot be
/// renewed; an empty token is no token.
final class StaticTokenSource implements TokenSource {
  const StaticTokenSource(this.token);

  final String? token;

  @override
  Future<String?> accessToken() async => (token?.isEmpty ?? true) ? null : token;

  @override
  Future<String?> refreshAccessToken() async => null;
}
