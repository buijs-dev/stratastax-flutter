import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../gen/contract/scopes.g.dart';

/// The roles of a verified token (`realm_access.roles`), as the stub issues them.
List<String> jwtRoleClaims(Map<String, Object?> claims) => switch (claims['realm_access']) {
  {'roles': final List<Object?> roles} => roles.whereType<String>().toList(),
  _ => const [],
};

/// A stub user of the identity provider.
final class StubUser {
  const StubUser(this.id, this.name, this.email, this.roles, this.description);

  final String id;
  final String name;
  final String email;
  final List<String> roles;
  final String description;
}

final _read = [
  for (final s in Scope.values)
    if (s.claim.endsWith('-read')) s.claim,
];

/// Users with different roles, to see the UI adapt.
final stubUsers = <String, StubUser>{
  'admin': StubUser('admin', 'Ada Admin', 'admin@stratastax.test', [
    for (final s in Scope.values) s.claim,
  ], 'every scope of the contract'),
  'player': StubUser('player', 'Pim Player', 'player@stratastax.test', [
    ..._read,
    Scope.matchCreate.claim,
  ], 'reads everything, records matches, cannot create games'),
  'viewer': StubUser('viewer', 'Vera Viewer', 'viewer@stratastax.test', _read, 'read-only'),
};

/// Social logins (`kc_idp_hint`) land on these users without a choice page.
const _social = {'google': 'player', 'github': 'admin'};

final class _Code {
  _Code(this.user, this.challenge, this.redirectUri, this.clientId, this.expires);

  final StubUser user;
  final String challenge;
  final String redirectUri;
  final String clientId;
  final DateTime expires;
}

/// Keycloak-compatible endpoints under `/realms/<realm>/protocol/openid-connect/`: Authorization
/// Code with PKCE (S256 only), refresh-token rotation, logout. Tokens are HS256 JWTs signed with a
/// stub secret; [verify] checks them for the API.
final class OidcStub {
  OidcStub({this.realm = 'stratastax', this.accessTtl = const Duration(minutes: 5), DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final String realm;
  final Duration accessTtl;
  final DateTime Function() _clock;
  final _secret = utf8.encode('stratastax-stub-${Random.secure().nextInt(1 << 32)}');
  final _codes = <String, _Code>{};
  final _refresh = <String, StubUser>{};
  final _random = Random.secure();

  String get _base => '/realms/$realm/protocol/openid-connect';

  void bind(Router router) {
    router
      ..get('$_base/auth', _authorize)
      ..post('$_base/token', _token)
      ..get('$_base/logout', _logout);
  }

  /// The claims of a valid, unexpired access token; null otherwise.
  Map<String, Object?>? verify(String? authorization) {
    if (authorization == null || !authorization.startsWith('Bearer ')) return null;
    final parts = authorization.substring(7).split('.');
    if (parts.length != 3 || _sign('${parts[0]}.${parts[1]}') != parts[2]) return null;
    final claims = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1])))) as Map<String, Object?>;
    final exp = claims['exp'] as int?;
    return exp != null && exp * 1000 > _clock().millisecondsSinceEpoch ? claims : null;
  }

  /// A token for [user], for tests and scripts.
  String accessTokenFor(String user) => _accessToken(stubUsers[user]!);

  Response _authorize(Request request) {
    final q = request.url.queryParameters;
    final missing = [
      for (final key in const ['client_id', 'redirect_uri', 'state', 'code_challenge'])
        if (q[key] == null) key,
    ];
    if (missing.isNotEmpty || q['response_type'] != 'code' || q['code_challenge_method'] != 'S256') {
      return Response(400, body: 'Invalid authorization request (missing: ${missing.join(', ')}; S256 PKCE required)');
    }
    // The choice of a user, or a social provider straight through.
    final chosen = q['user'] ?? _social[q['kc_idp_hint']];
    if (chosen != null && stubUsers[chosen] != null) {
      final code = _token32();
      _codes[code] = _Code(
        stubUsers[chosen]!,
        q['code_challenge']!,
        q['redirect_uri']!,
        q['client_id']!,
        _clock().add(const Duration(minutes: 1)),
      );
      final back = Uri.parse(q['redirect_uri']!);
      return Response.found(
        back.replace(queryParameters: {...back.queryParameters, 'code': code, 'state': q['state']!}),
      );
    }
    final links = [
      for (final user in stubUsers.values)
        '<li><a href="${request.requestedUri.replace(queryParameters: {...q, 'user': user.id})}">'
            '${const HtmlEscape().convert(user.name)}</a> <small>${user.description}</small></li>',
    ].join();
    return Response.ok(
      '<!doctype html><meta charset="utf-8"><title>Stub login</title>'
      '<body style="font-family:system-ui;max-width:32rem;margin:4rem auto;color:#18181b">'
      '<h1>Stub identity provider</h1><p>Realm <code>$realm</code>, client <code>${const HtmlEscape().convert(q['client_id']!)}</code>. Sign in as:</p>'
      '<ul style="line-height:2">$links</ul></body>',
      headers: {'Content-Type': 'text/html; charset=utf-8'},
    );
  }

  Future<Response> _token(Request request) async {
    final form = Uri.splitQueryString(await request.readAsString());
    StubUser? user;
    switch (form['grant_type']) {
      case 'authorization_code':
        final code = _codes.remove(form['code']);
        final verifier = form['code_verifier'] ?? '';
        final challenge = base64Url.encode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');
        if (code == null || code.expires.isBefore(_clock())) {
          return _oauthError('invalid_grant', 'unknown or expired code');
        }
        if (code.redirectUri != form['redirect_uri'] || code.clientId != form['client_id']) {
          return _oauthError('invalid_grant', 'redirect_uri or client_id differs from the authorization request');
        }
        if (code.challenge != challenge) return _oauthError('invalid_grant', 'PKCE verification failed');
        user = code.user;
      case 'refresh_token':
        user = _refresh.remove(form['refresh_token']); // rotation: a refresh token works once
        if (user == null) return _oauthError('invalid_grant', 'unknown refresh token');
      default:
        return _oauthError('unsupported_grant_type', 'use authorization_code or refresh_token');
    }
    final refresh = _token32();
    _refresh[refresh] = user;
    return Response.ok(
      jsonEncode({
        'access_token': _accessToken(user),
        'id_token': _jwt({'sub': user.id, 'name': user.name, 'email': user.email, ..._times()}),
        'refresh_token': refresh,
        'token_type': 'Bearer',
        'expires_in': accessTtl.inSeconds,
      }),
      headers: {'Content-Type': 'application/json', 'Cache-Control': 'no-store'},
    );
  }

  Response _logout(Request request) {
    final back = request.url.queryParameters['post_logout_redirect_uri'];
    return back == null ? Response.ok('Signed out') : Response.found(back);
  }

  String _accessToken(StubUser user) => _jwt({
    'sub': user.id,
    'preferred_username': user.id,
    'scope': 'openid profile',
    'realm_access': {'roles': user.roles},
    ..._times(),
  });

  Map<String, Object?> _times() {
    final now = _clock().millisecondsSinceEpoch ~/ 1000;
    return {'iss': 'stub/realms/$realm', 'iat': now, 'exp': now + accessTtl.inSeconds};
  }

  String _jwt(Map<String, Object?> claims) {
    String part(Object json) => base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
    final unsigned = '${part({'alg': 'HS256', 'typ': 'JWT'})}.${part(claims)}';
    return '$unsigned.${_sign(unsigned)}';
  }

  String _sign(String input) =>
      base64Url.encode(Hmac(sha256, _secret).convert(utf8.encode(input)).bytes).replaceAll('=', '');

  String _token32() => base64Url.encode(List.generate(24, (_) => _random.nextInt(256))).replaceAll('=', '');

  static Response _oauthError(String error, String description) => Response(
    400,
    body: jsonEncode({'error': error, 'error_description': description}),
    headers: {'Content-Type': 'application/json'},
  );
}
