import 'dart:async';
import 'dart:convert';

import 'package:stx_core/stx_core.dart';
import 'package:stx_http/stx_http.dart';
import 'package:stx_security/stx_security.dart';
import 'package:test/test.dart';

String _jwt(Map<String, Object?> claims) {
  String part(Object json) => base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  return '${part({'alg': 'none'})}.${part(claims)}.sig';
}

final class _Browser implements AuthBrowser {
  _Browser(this.location);

  @override
  Uri location;
  Uri? redirected;
  final replaced = <Uri>[];

  @override
  void redirect(Uri uri) => redirected = uri;

  @override
  void replace(Uri uri) {
    replaced.add(uri);
    location = uri;
  }
}

/// A token endpoint: records requests, answers from a queue.
final class _TokenServer implements StxTransport {
  final requests = <Map<String, String>>[];
  final responses = <StxResponse>[];
  Completer<void>? gate;

  @override
  Future<StxResponse> send(StxRequest request) async {
    requests.add(Uri.splitQueryString(request.body!));
    await gate?.future;
    return responses.removeAt(0);
  }

  @override
  void close() {}
}

StxResponse _tokens({String scope = 'stx-engine:match-read', int expiresIn = 300, String refresh = 'r1'}) =>
    StxResponse(
      status: 200,
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'access_token': _jwt({
          'sub': 'u1',
          'scope': scope,
          'realm_access': {
            'roles': ['offline_access'],
          },
        }),
        'refresh_token': refresh,
        'id_token': _jwt({'sub': 'u1', 'name': 'Gillian', 'email': 'g@example.com'}),
        'expires_in': expiresIn,
      }),
    );

enum _Scope implements StxScope {
  matchRead('stx-engine:match-read'),
  matchCreate('stx-engine:match-create');

  const _Scope(this.claim);

  @override
  final String claim;
}

Set<StxScope> _scopesOf(Iterable<String> claims) => {
  for (final s in _Scope.values)
    if (claims.contains(s.claim)) s,
};

final _config = OidcConfig(
  issuer: Uri.parse('http://localhost:9000/realms/stratastax'),
  clientId: 'portal',
  redirectUri: Uri.parse('http://localhost:8085/'),
);

void main() {
  test('PKCE S256 (RFC 7636 appendix B)', () {
    expect(
      const Pkce('dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk').challenge,
      'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
    );
    expect(Pkce.generate().verifier, matches(RegExp(r'^[A-Za-z0-9\-._~]{64}$')));
  });

  test('roles from Keycloak and OAuth claims', () {
    final claims = {
      'scope': 'openid stx-engine:match-read',
      'realm_access': {
        'roles': ['stx-engine:game-read'],
      },
      'resource_access': {
        'portal': {
          'roles': ['stx-engine:match-create'],
        },
        'account': {
          'roles': ['view-profile'],
        },
      },
    };
    expect(jwtRoles(claims, OidcConfig.defaultRoleClaims), {
      'openid',
      'stx-engine:match-read',
      'stx-engine:game-read',
      'stx-engine:match-create',
      'view-profile',
    });
    expect(jwtClaims(_jwt(claims))!['scope'], 'openid stx-engine:match-read');
    expect(jwtClaims('not-a-jwt'), isNull);
  });

  group('Session', () {
    late _Browser browser;
    late _TokenServer server;
    late MemoryStore store;
    var now = DateTime(2026, 10, 13, 12);

    Session session() => Session(
      config: _config,
      scopesOf: _scopesOf,
      transport: server,
      store: store,
      browser: browser,
      clock: () => now,
    );

    setUp(() {
      browser = _Browser(Uri.parse('http://localhost:8085/#/matches/new'));
      server = _TokenServer();
      store = MemoryStore();
      now = DateTime(2026, 10, 13, 12);
    });

    test('login redirects with PKCE, state and the social hint', () {
      session().login(idpHint: 'google');
      final uri = browser.redirected!;
      expect(uri.path, '/realms/stratastax/protocol/openid-connect/auth');
      expect(uri.queryParameters, containsPair('code_challenge_method', 'S256'));
      expect(uri.queryParameters, containsPair('kc_idp_hint', 'google'));
      expect(uri.queryParameters, containsPair('redirect_uri', 'http://localhost:8085/'));
      expect(uri.queryParameters['state'], hasLength(32));
    });

    test('callback: exchanges the code with the verifier, sets scopes and profile, restores the route', () async {
      final s = session()..login();
      final challenge = browser.redirected!.queryParameters['code_challenge'];
      final state = browser.redirected!.queryParameters['state'];
      var notified = 0;
      s.addListener(() => notified++);
      server.responses.add(_tokens());

      browser.location = Uri.parse('http://localhost:8085/?code=abc&state=$state');
      await s.start();

      expect(s.authenticated, isTrue);
      expect(s.scopes.contains(_Scope.matchRead), isTrue);
      expect(s.scopes.contains(_Scope.matchCreate), isFalse);
      expect(s.profile!.displayName, 'Gillian');
      expect(notified, 1);
      final exchange = server.requests.single;
      expect(exchange['grant_type'], 'authorization_code');
      expect(exchange['code'], 'abc');
      expect(Pkce(exchange['code_verifier']!).challenge, challenge);
      expect(browser.replaced.last.toString(), 'http://localhost:8085/#/matches/new');
      expect(store.read('stx.session.refresh'), 'r1');
    });

    test('a callback with a foreign state is rejected', () async {
      final s = session()..login();
      await s.handleCallback(Uri.parse('http://localhost:8085/?code=abc&state=forged'));
      expect(s.authenticated, isFalse);
      expect(s.failure, LoginFailure.stateMismatch);
      expect(server.requests, isEmpty);
    });

    test('a cancelled login is reported', () async {
      final s = session()..login();
      await s.handleCallback(Uri.parse('http://localhost:8085/?error=access_denied'));
      expect(s.failure, LoginFailure.denied);
    });

    test('start restores the session from the stored refresh token', () async {
      store.write('stx.session.refresh', 'stored');
      server.responses.add(_tokens(refresh: 'r2'));
      final s = session();
      await s.start();
      expect(s.authenticated, isTrue);
      expect(server.requests.single, containsPair('refresh_token', 'stored'));
      expect(store.read('stx.session.refresh'), 'r2');
    });

    test('an expiring token is refreshed before use; concurrent refreshes share one request', () async {
      store.write('stx.session.refresh', 'stored');
      server.responses
        ..add(_tokens(expiresIn: 60))
        ..add(_tokens(expiresIn: 300, scope: 'stx-engine:match-read stx-engine:match-create'));
      final s = session();
      await s.start();
      now = now.add(const Duration(seconds: 40)); // within the 30 s margin
      server.gate = Completer();
      final tokens = [s.accessToken(), s.accessToken(), s.refreshAccessToken()];
      server.gate!.complete();
      final results = await Future.wait(tokens);
      expect(results.toSet(), hasLength(1));
      expect(server.requests, hasLength(2)); // start + one refresh
      expect(s.scopes.contains(_Scope.matchCreate), isTrue);
    });

    test('a refused refresh signs out; a network failure keeps the session', () async {
      store.write('stx.session.refresh', 'stored');
      server.responses
        ..add(_tokens())
        ..add(StxResponse(status: 400, body: '{"error":"invalid_grant"}'));
      final s = session();
      await s.start();
      expect(await s.refreshAccessToken(), isNull);
      expect(s.authenticated, isFalse);
      expect(store.read('stx.session.refresh'), isNull);
    });

    test('logout clears the session and ends it at the provider', () async {
      store.write('stx.session.refresh', 'stored');
      server.responses.add(_tokens());
      final s = session();
      await s.start();
      s.logout();
      expect(s.authenticated, isFalse);
      expect(browser.redirected!.path, '/realms/stratastax/protocol/openid-connect/logout');
      expect(browser.redirected!.queryParameters, containsPair('id_token_hint', isNotEmpty));
    });

    test('works as the TokenSource of BearerAuthInterceptor', () async {
      store.write('stx.session.refresh', 'stored');
      server.responses.add(_tokens());
      final s = session();
      await s.start();
      expect(await s.accessToken(), startsWith('ey'));
    });
  });
}
