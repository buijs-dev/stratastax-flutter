import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:meta/meta.dart';
import 'package:stx_core/stx_core.dart';
import 'package:stx_http/stx_http.dart';

import 'jwt.dart';
import 'oidc.dart';
import 'platform/platform.dart';
import 'token_endpoint.dart';

/// Who is signed in, from the ID token (or the access token).
@immutable
final class SessionProfile {
  const SessionProfile({required this.subject, this.name, this.email});

  final String subject;
  final String? name;
  final String? email;

  /// What to show for the user: name, e-mail or subject.
  String get displayName => name ?? email ?? subject;
}

/// Why a login did not complete.
enum LoginFailure {
  /// `state` does not match the pending login (or there is none): a stale or forged callback.
  stateMismatch,

  /// The identity provider returned an `error` (e.g. the user cancelled).
  denied,

  /// The code could not be exchanged for tokens.
  exchange,
}

/// The OIDC session of the app: Authorization Code + PKCE login, an in-memory access token,
/// a refresh token in [SecureStore], single-flight refresh and the user's scopes.
///
/// It implements [TokenSource], so `BearerAuthInterceptor(session)` authenticates API calls.
final class Session implements TokenSource {
  Session({
    required this.config,
    required Set<StxScope> Function(Iterable<String> claims) scopesOf,
    StxTransport? transport,
    SecureStore? store,
    AuthBrowser? browser,
    DateTime Function()? clock,
    Random? random,
    void Function(String line)? log,
  }) : _scopesOf = scopesOf,
       _store = store ?? defaultStore(),
       _browser = browser ?? defaultBrowser(),
       _clock = clock ?? DateTime.now,
       _random = random,
       _client = StxClient(
         baseUrl: config.issuer,
         transport: transport,
         interceptors: [if (log != null) LoggingInterceptor(log: log)],
       );

  static const _refreshKey = 'stx.session.refresh';
  static const _pendingKey = 'stx.session.pending';

  final OidcConfig config;
  final Set<StxScope> Function(Iterable<String> claims) _scopesOf;
  final SecureStore _store;
  final AuthBrowser _browser;
  final DateTime Function() _clock;
  final Random? _random;
  final StxClient _client;
  final _listeners = <void Function()>[];

  String? _accessToken;
  String? _idToken;
  DateTime? _expiresAt;
  Set<StxScope> _scopes = const {};
  SessionProfile? _profile;
  LoginFailure? _failure;
  Future<String?>? _refreshing;

  bool get authenticated => _accessToken != null;

  /// The scopes (roles) of the current access token; empty when signed out.
  Set<StxScope> get scopes => _scopes;

  SessionProfile? get profile => _profile;

  /// Set when the last login callback failed.
  LoginFailure? get failure => _failure;

  void addListener(void Function() listener) => _listeners.add(listener);

  void removeListener(void Function() listener) => _listeners.remove(listener);

  void _notify() {
    for (final listener in [..._listeners]) {
      listener();
    }
  }

  /// At startup: completes a login callback in the current location, or restores the session
  /// from a stored refresh token.
  Future<void> start() async {
    final location = _browser.location;
    final query = location.queryParameters;
    if (query.containsKey('code') || query.containsKey('error')) {
      await handleCallback(location);
    } else if (_store.read(_refreshKey) != null) {
      await refreshAccessToken();
    }
  }

  /// Sends the browser to the identity provider. [idpHint] picks a social provider directly
  /// (Keycloak `kc_idp_hint`); [returnTo] is restored after the callback (default: the current
  /// location).
  void login({String? idpHint, Uri? returnTo}) {
    final pkce = Pkce.generate(_random);
    final state = randomToken(32, _random);
    _store.write(
      _pendingKey,
      jsonEncode({'state': state, 'verifier': pkce.verifier, 'returnTo': (returnTo ?? _browser.location).toString()}),
    );
    _browser.redirect(
      config
          .endpoint(config.authorizePath)
          .replace(
            queryParameters: {
              'response_type': 'code',
              'client_id': config.clientId,
              'redirect_uri': config.redirectUri.toString(),
              'scope': config.scopes.join(' '),
              'state': state,
              'code_challenge': pkce.challenge,
              'code_challenge_method': 'S256',
              'kc_idp_hint': ?idpHint,
            },
          ),
    );
  }

  /// Completes a login: checks `state`, exchanges the code (with the PKCE verifier) and restores
  /// the location the login started from.
  Future<bool> handleCallback(Uri uri) async {
    final query = uri.queryParameters;
    final pending = switch (_store.read(_pendingKey)) {
      final String json => jsonDecode(json) as Map<String, Object?>,
      null => null,
    };
    _store.write(_pendingKey, null);
    final returnTo = Uri.parse(pending?['returnTo'] as String? ?? config.redirectUri.toString());
    _browser.replace(returnTo.replace(queryParameters: _withoutAuth(returnTo.queryParameters)));

    if (query.containsKey('error')) return _fail(LoginFailure.denied);
    if (pending == null || pending['state'] != query['state']) return _fail(LoginFailure.stateMismatch);

    final result = await _client.send(
      tokenEndpoint,
      params: config.tokenPath.split('/'),
      body: {
        'grant_type': 'authorization_code',
        'code': query['code'] ?? '',
        'redirect_uri': config.redirectUri.toString(),
        'client_id': config.clientId,
        'code_verifier': pending['verifier']! as String,
      },
    );
    return switch (result) {
      Ok(:final value) => _apply(value),
      Err() => _fail(LoginFailure.exchange),
    };
  }

  static Map<String, String>? _withoutAuth(Map<String, String> query) {
    final rest = {
      for (final e in query.entries)
        if (!const {'code', 'state', 'session_state', 'iss', 'error', 'error_description'}.contains(e.key))
          e.key: e.value,
    };
    return rest.isEmpty ? null : rest;
  }

  bool _fail(LoginFailure failure) {
    _failure = failure;
    _clear();
    return false;
  }

  bool _apply(TokenResponse tokens) {
    final claims = jwtClaims(tokens.accessToken) ?? const {};
    _accessToken = tokens.accessToken;
    _idToken = tokens.idToken ?? _idToken;
    _expiresAt = tokens.expiresIn != null
        ? _clock().add(Duration(seconds: tokens.expiresIn!))
        : jwtExpiry(claims)?.toLocal();
    _scopes = _scopesOf(jwtRoles(claims, config.roleClaims));
    final identity = (_idToken == null ? null : jwtClaims(_idToken!)) ?? claims;
    _profile = SessionProfile(
      subject: identity['sub'] as String? ?? '',
      name: identity['name'] as String? ?? identity['preferred_username'] as String?,
      email: identity['email'] as String?,
    );
    if (tokens.refreshToken case final refresh?) _store.write(_refreshKey, refresh);
    _failure = null;
    _notify();
    return true;
  }

  void _clear() {
    final was = authenticated;
    _accessToken = null;
    _idToken = null;
    _expiresAt = null;
    _scopes = const {};
    _profile = null;
    _store.write(_refreshKey, null);
    if (was || _failure != null) _notify();
  }

  /// The current access token; refreshed first when it expires within [OidcConfig.refreshMargin].
  @override
  Future<String?> accessToken() async {
    final expiresAt = _expiresAt;
    if (_accessToken != null && expiresAt != null && _clock().add(config.refreshMargin).isAfter(expiresAt)) {
      return refreshAccessToken();
    }
    return _accessToken;
  }

  /// Exchanges the refresh token for new tokens. Concurrent calls share one request; a refused
  /// refresh signs the user out.
  @override
  Future<String?> refreshAccessToken() => _refreshing ??= _refresh().whenComplete(() => _refreshing = null);

  Future<String?> _refresh() async {
    final refresh = _store.read(_refreshKey);
    if (refresh == null) return null;
    final result = await _client.send(
      tokenEndpoint,
      params: config.tokenPath.split('/'),
      body: {'grant_type': 'refresh_token', 'refresh_token': refresh, 'client_id': config.clientId},
    );
    switch (result) {
      case Ok(:final value):
        _apply(value);
        return _accessToken;
      case Err(error: Problem(type: ProblemType.network)):
        return _accessToken; // offline: keep the session, retry later
      case Err():
        _clear();
        return null;
    }
  }

  /// Signs out locally and ends the session at the identity provider.
  void logout() {
    final idToken = _idToken;
    _clear();
    _browser.redirect(
      config
          .endpoint(config.logoutPath)
          .replace(
            queryParameters: {
              'client_id': config.clientId,
              'post_logout_redirect_uri': (config.postLogoutRedirectUri ?? config.redirectUri).toString(),
              'id_token_hint': ?idToken,
            },
          ),
    );
  }
}
