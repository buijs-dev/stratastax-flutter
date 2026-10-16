import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:stub_server/gen/contract/platform_v1/platform_v1.g.dart';
import 'package:stub_server/stub_server.dart';
import 'package:test/test.dart';

void main() {
  late Handler handler;
  late OidcStub oidc;
  setUp(() {
    oidc = OidcStub();
    handler = stubHandler(oidc: oidc, log: (_) {});
  });

  /// Calls the API as [user] (null: without a token).
  Future<(int, Object?, Map<String, String>)> call(
    String method,
    String path, {
    Object? body,
    Map<String, String>? headers,
    String? user = 'admin',
  }) async {
    final response = await handler(
      Request(
        method,
        Uri.parse('http://localhost$path'),
        body: body == null ? null : jsonEncode(body),
        headers: {...?headers, if (user != null) 'Authorization': 'Bearer ${oidc.accessTokenFor(user)}'},
      ),
    );
    final text = await response.readAsString();
    return (response.statusCode, text.isEmpty ? null : jsonDecode(text), response.headers);
  }

  test('ghost player suggestions decode as the contract says', () async {
    final (status, json, headers) = await call('GET', '/api/v1/ghost-players/suggestions?query=cha');
    expect(status, 200);
    expect(headers['access-control-allow-origin'], '*');
    final players = [for (final p in json! as List) GhostPlayerRefV1.decode(p)];
    expect(players.map((p) => p.displayName), ['Charlie', 'Charlotte']);
  });

  test('game suggestions', () async {
    final (_, json, _) = await call('GET', '/api/v1/games/suggestions?query=ca');
    expect([for (final g in json! as List) GameRefV1.decode(g).displayName], ['Catan', 'Carcassonne']);
  });

  test('create game: contract validation and business rules as problem documents', () async {
    final (status, json, _) = await call(
      'POST',
      '/api/v1/games',
      body: {
        'displayName': 'X',
        'description': '',
        'minPlayers': 4,
        'maxPlayers': 2,
        'tags': <Object?>[],
        'scoreType': 'SCORE',
      },
    );
    expect(status, 400);
    final problem = ValidationProblemDetailV1.decode(json);
    expect(problem.errors!.map((e) => e.field), ['description', 'maxPlayers']);
  });

  test('create game, then a duplicate is a conflict', () async {
    final body = {
      'displayName': 'Azul',
      'description': 'Tiles',
      'minPlayers': 2,
      'maxPlayers': 4,
      'tags': <Object?>[],
      'scoreType': 'SCORE',
    };
    final (status, json, _) = await call('POST', '/api/v1/games', body: body);
    expect(status, 201);
    expect(GameV1.decode(json).displayName, 'Azul');
    expect((await call('POST', '/api/v1/games', body: body)).$1, 409);
  });

  test('a malformed body names the offending path', () async {
    final (status, json, _) = await call('POST', '/api/v1/matches', body: {'gameId': 'nope'});
    expect(status, 400);
    expect(ValidationProblemDetailV1.decode(json).errors!.single.field, 'gameId');
  });

  test('create match with an idempotency key replays', () async {
    final (_, games, _) = await call('GET', '/api/v1/games/suggestions?query=catan');
    final (_, players, _) = await call('GET', '/api/v1/ghost-players/suggestions?query=a');
    final body = {
      'gameId': ((games! as List).first as Map)['id'],
      'playedAt': '2026-10-11T19:30:00Z',
      'participants': [
        {'ghostPlayerId': ((players! as List).first as Map)['id'], 'outcome': 'WIN'},
      ],
    };
    final headers = {'Idempotency-Key': '0192f100-0000-7000-8000-00000000aaaa'};
    final first = await call('POST', '/api/v1/matches', body: body, headers: headers);
    final second = await call('POST', '/api/v1/matches', body: body, headers: headers);
    expect(first.$1, 201);
    expect(MatchV1.decode(first.$2).game.displayName, 'Catan');
    expect(second.$3['idempotent-replayed'], 'true');
    expect(second.$2, first.$2);
    final (_, list, _) = await call('GET', '/api/v1/matches');
    expect(MatchListV1.decode(list).items, hasLength(1));
  });

  test('unknown routes are contract problems', () async {
    final (status, json, _) = await call('GET', '/api/v1/nope');
    expect(status, 404);
    expect(ProblemDetailV1.decode(json).type, ErrorTypeV1.notFound);
  });

  group('security', () {
    test('no token → 401, a token without the scope → 403, as problem documents', () async {
      final (status, json, _) = await call('GET', '/api/v1/games/suggestions?query=ca', user: null);
      expect(status, 401);
      expect(ProblemDetailV1.decode(json).type, ErrorTypeV1.authentication);

      final game = {'displayName': 'Azul', 'description': '', 'minPlayers': 2, 'maxPlayers': 4};
      final (forbidden, problem, _) = await call('POST', '/api/v1/games', body: game, user: 'player');
      expect(forbidden, 403);
      expect(ProblemDetailV1.decode(problem).type, ErrorTypeV1.authorization);
      expect((await call('GET', '/api/v1/games/suggestions?query=ca', user: 'viewer')).$1, 200);
    });

    test('a forged token is refused', () async {
      final token = oidc.accessTokenFor('viewer');
      final parts = token.split('.');
      final forged =
          '${parts[0]}.${base64Url.encode(utf8.encode(jsonEncode({
            'sub': 'viewer',
            'realm_access': {
              'roles': ['stx-engine:game-create'],
            },
            'exp': 9999999999,
          }))).replaceAll('=', '')}.${parts[2]}';
      final response = await handler(
        Request('GET', Uri.parse('http://localhost/api/v1/games'), headers: {'Authorization': 'Bearer $forged'}),
      );
      expect(response.statusCode, 401);
    });

    test('authorization code with PKCE, refresh rotation', () async {
      const verifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';
      const challenge = 'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM';
      const base = 'http://localhost/realms/stratastax/protocol/openid-connect';
      final page = await handler(
        Request(
          'GET',
          Uri.parse(
            '$base/auth?response_type=code&client_id=app&redirect_uri=http://app/&state=s1'
            '&code_challenge=$challenge&code_challenge_method=S256',
          ),
        ),
      );
      expect(await page.readAsString(), contains('Pim Player'));

      final authorize = await handler(
        Request(
          'GET',
          Uri.parse(
            '$base/auth?response_type=code&client_id=app&redirect_uri=http://app/&state=s1'
            '&code_challenge=$challenge&code_challenge_method=S256&kc_idp_hint=google',
          ),
        ),
      );
      expect(authorize.statusCode, 302);
      final back = Uri.parse(authorize.headers['location']!);
      expect(back.queryParameters['state'], 's1');

      Future<Response> token(Map<String, String> form) async => handler(
        Request(
          'POST',
          Uri.parse('$base/token'),
          body: Uri(queryParameters: form).query,
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        ),
      );
      final code = back.queryParameters['code']!;
      final wrong = await token({
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': 'http://app/',
        'client_id': 'app',
        'code_verifier': 'x' * 43,
      });
      expect(wrong.statusCode, 400); // a failed exchange also burns the code

      final again = await handler(
        Request(
          'GET',
          Uri.parse(
            '$base/auth?response_type=code&client_id=app&redirect_uri=http://app/&state=s2'
            '&code_challenge=$challenge&code_challenge_method=S256&user=player',
          ),
        ),
      );
      final code2 = Uri.parse(again.headers['location']!).queryParameters['code']!;
      final ok = await token({
        'grant_type': 'authorization_code',
        'code': code2,
        'redirect_uri': 'http://app/',
        'client_id': 'app',
        'code_verifier': verifier,
      });
      expect(ok.statusCode, 200);
      final tokens = jsonDecode(await ok.readAsString()) as Map<String, Object?>;
      expect(oidc.verify('Bearer ${tokens['access_token']}'), containsPair('sub', 'player'));

      final refresh = {'grant_type': 'refresh_token', 'refresh_token': tokens['refresh_token']! as String};
      expect((await token(refresh)).statusCode, 200);
      expect((await token(refresh)).statusCode, 400); // rotated
    });
  });
}
