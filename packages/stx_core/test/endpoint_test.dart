import 'package:stx_core/stx_core.dart';
import 'package:test/test.dart';

// Shaped like the code stx_compiler generates.
enum _Scope implements StxScope {
  matchCreate('stx-engine:match-create'),
  matchUpdate('stx-engine:match-update'),
  matchAdmin('stx-engine:match-admin');

  const _Scope(this.claim);

  @override
  final String claim;
}

final class _CreateMatchV1 {
  const _CreateMatchV1(this.gameId);

  final Uuid gameId;

  static Map<String, Object?> encode(_CreateMatchV1 v) => {'gameId': v.gameId.value};
}

final class _MatchV1 {
  const _MatchV1(this.id);

  final Uuid id;

  static _MatchV1 decode(Object? json) => _MatchV1(Json.uuid(Json.object(json), 'id'));
}

final class _UpdateMatchParams {
  const _UpdateMatchParams({required this.matchId, required this.ifMatch});

  final Uuid matchId;
  final String ifMatch;
}

abstract final class _MatchesApiV1 {
  static const createMatch = Endpoint<NoParams, _CreateMatchV1, _MatchV1>(
    operationId: 'createMatch',
    method: HttpMethod.post,
    path: PathTemplate(['api', 'v1', 'matches']),
    security: Secured.scopes({_Scope.matchCreate}),
    idempotent: true,
    encodeBody: _CreateMatchV1.encode,
    decode: _MatchV1.decode,
  );

  static const updateMatch = Endpoint<_UpdateMatchParams, NoBody, NoContent>(
    operationId: 'updateMatch',
    method: HttpMethod.patch,
    path: PathTemplate(['api', 'v1', 'matches', '{matchId}']),
    security: Secured.scopes({_Scope.matchUpdate, _Scope.matchAdmin}), // either of two scopes
    encodePath: _updateMatchPath,
    encodeHeaders: _updateMatchHeaders,
    decode: NoContent.decode,
  );

  static List<String> _updateMatchPath(_UpdateMatchParams p) => ['api', 'v1', 'matches', p.matchId.value];

  static Map<String, String> _updateMatchHeaders(_UpdateMatchParams p) => {'If-Match': p.ifMatch};
}

void main() {
  const id = Uuid.trusted('6f1c2b3a-0d4e-4f5a-9b8c-7d6e5f4a3b2c');

  test('endpoints are const and carry the contract metadata', () {
    const e = _MatchesApiV1.createMatch;
    expect(e.segments(()), ['api', 'v1', 'matches']);
    expect(e.path.pattern, '/api/v1/matches');
    expect(e.retryable, isTrue); // POST, but declares an idempotency key
    expect(e.hasBody, isTrue);
    expect(e.isJson, isTrue);
    expect(e.encodeBody!(const _CreateMatchV1(id)), {'gameId': id.value});
    expect(e.decode({'id': id.value}).id, id);
  });

  test('path and header parameters come from the params class', () {
    const e = _MatchesApiV1.updateMatch;
    const params = _UpdateMatchParams(matchId: id, ifMatch: '"v3"');
    expect(e.segments(params), ['api', 'v1', 'matches', id.value]);
    expect(e.headers(params), {'If-Match': '"v3"'});
    expect(e.query(params), isEmpty);
    expect(e.hasBody, isFalse);
    expect(e.retryable, isFalse);
  });

  group('Secured', () {
    const granted = {_Scope.matchAdmin};

    test('scoped access: any of the scopes is enough (@RolesAllowed)', () {
      expect(_MatchesApiV1.updateMatch.security.allows(authenticated: true, granted: granted), isTrue);
      expect(_MatchesApiV1.createMatch.security.allows(authenticated: true, granted: granted), isFalse);
      expect(_MatchesApiV1.updateMatch.security.allows(authenticated: false, granted: granted), isFalse);
    });

    test('public and authenticated', () {
      expect(const Secured.public().allows(authenticated: false, granted: const {}), isTrue);
      expect(const Secured.public().requiresAuthentication, isFalse);
      expect(const Secured.authenticated().allows(authenticated: true, granted: const {}), isTrue);
      expect(const Secured.authenticated().allows(authenticated: false, granted: const {}), isFalse);
    });
  });

  test('retryable follows RFC 9110 idempotency', () {
    expect(HttpMethod.get.isIdempotent, isTrue);
    expect(HttpMethod.put.isIdempotent, isTrue);
    expect(HttpMethod.delete.isIdempotent, isTrue);
    expect(HttpMethod.post.isIdempotent, isFalse);
    expect(HttpMethod.patch.isIdempotent, isFalse);
  });
}
