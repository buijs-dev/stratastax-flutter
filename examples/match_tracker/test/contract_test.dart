import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:match_tracker/gen/contract/platform_v1/platform_v1.g.dart';
import 'package:match_tracker/gen/contract/scopes.g.dart';
import 'package:stx_core/stx_core.dart';
import 'package:stx_http/stx_http.dart';

/// Exercises the code stx_compiler generated from the real platform contract.
void main() {
  const matchId = '0192f100-0000-7000-8000-0000000000a5';
  const gameId = '0192f100-0000-7000-8000-0000000000b1';
  const ghostId = '0192f100-0000-7000-8000-0000000000c1';

  final matchJson = {
    'id': matchId,
    'game': {'id': gameId, 'displayName': 'Catan'},
    'recorder': {'id': '0192f100-0000-7000-8000-0000000000d1', 'displayName': 'Gillian'},
    'status': 'FINALIZED',
    'playedAt': '2026-10-11T19:30:00Z',
    'editRequestsEnabled': true,
    'createdAt': '2026-10-11T21:00:00Z',
    'participants': [
      {
        'id': '0192f100-0000-7000-8000-0000000000e1',
        'ghostPlayer': {'id': ghostId, 'displayName': 'Sam'},
        'score': 10,
        'rank': 1,
        'outcome': 'WIN',
        'createdAt': '2026-10-11T21:00:00Z',
      },
    ],
  };

  group('models', () {
    test('decode a match response', () {
      final match = MatchV1.decode(matchJson);
      expect(match.id, Uuid.trusted(matchId));
      expect(match.game.displayName, 'Catan');
      expect(match.status, MatchStatusV1.finalized);
      expect(match.playedAt, DateTime.utc(2026, 10, 11, 19, 30));
      expect(match.playset, isNull);
      expect(match.participants.single.outcome, OutcomeV1.win);
      expect(match.participants.single.score, 10.0); // number → double, also from an int
    });

    test('round trip keeps value equality', () {
      final match = MatchV1.decode(matchJson);
      final again = MatchV1.decode(jsonDecode(jsonEncode(MatchV1.encode(match))));
      expect(again, match);
      expect(again.hashCode, match.hashCode);
    });

    test('a contract violation names the offending path', () {
      final broken = {
        ...matchJson,
        'participants': [
          {...(matchJson['participants']! as List).single as Map<String, Object?>, 'outcome': 'DRAW'},
        ],
      };
      expect(
        () => MatchV1.decode(broken),
        throwsA(isA<JsonDecodeException>().having((e) => e.path, 'path', 'participants[0].outcome')),
      );
    });

    test('create body leaves out absent optional fields', () {
      final body = CreateMatchV1(
        gameId: Uuid.trusted(gameId),
        playedAt: DateTime.utc(2026, 10, 11, 19, 30),
        participants: [MatchParticipantInputV1(ghostPlayerId: Uuid.trusted(ghostId), outcome: OutcomeV1.win)],
      );
      expect(CreateMatchV1.encode(body), {
        'gameId': gameId,
        'playedAt': '2026-10-11T19:30:00.000Z',
        'participants': [
          {'ghostPlayerId': ghostId, 'outcome': 'WIN'},
        ],
      });
    });

    test('PATCH bodies distinguish unchanged, set and cleared', () {
      // playedAt is not nullable: set or left out. playsetId can also be cleared.
      final body = UpdateMatchV1(playedAt: DateTime.utc(2026, 10, 12), playsetId: const Patch.value(null));
      expect(UpdateMatchV1.encode(body), {'playedAt': '2026-10-12T00:00:00.000Z', 'playsetId': null});
      expect(UpdateMatchV1.encode(const UpdateMatchV1()), isEmpty);
    });
  });

  group('validation', () {
    test('rules come from the contract', () {
      expect(CreateMatchV1Validation.gameId, const UiFieldValidation(required: true, format: UiFormat.uuid));
      expect(CreateMatchV1Validation.participants.required, isTrue);
      expect(CreateMatchV1Validation.playsetId.required, isFalse);
      expect(CreateMatchV1Validation.participants.check(const []), const FieldError.required());
    });
  });

  group('endpoints', () {
    test('security and paths from the contract', () {
      const endpoint = MatchesApiV1.getMatch;
      expect(endpoint.path.pattern, '/api/v1/matches/{matchId}');
      expect(endpoint.segments(GetMatchParams(matchId: Uuid.trusted(matchId))), ['api', 'v1', 'matches', matchId]);
      const reader = {Scope.matchRead};
      expect(endpoint.security.allows(authenticated: true, granted: reader), isTrue);
      expect(MatchesApiV1.createMatch.security.allows(authenticated: true, granted: reader), isFalse);
    });

    test('scopes from token claims', () {
      final granted = Scope.fromClaims(['stx-engine:match-read', 'openid', 'stx-engine:match-create']);
      expect(granted, {Scope.matchRead, Scope.matchCreate});
    });

    test('a full call through StxClient', () async {
      final transport = _Transport();
      final client = StxClient(
        baseUrl: Uri.parse('https://stratastax.dev/rest'),
        transport: transport,
        interceptors: [IdempotencyKeyInterceptor()],
      );
      final result = await client.fetch(
        MatchesApiV1.listMatches,
        const ListMatchesParams(limit: 20, filter: 'status==FINALIZED'),
      );
      final page = result.valueOrNull!;
      expect(page.items.single.game.displayName, 'Catan');
      expect(page.nextCursor, 'abc');
      expect(
        transport.request.uri.toString(),
        'https://stratastax.dev/rest/api/v1/matches?limit=20&filter=status%3D%3DFINALIZED',
      );
    });
  });
}

final class _Transport implements StxTransport {
  late StxRequest request;

  @override
  Future<StxResponse> send(StxRequest request) async {
    this.request = request;
    return StxResponse(
      status: 200,
      body: jsonEncode({
        'limit': 20,
        'nextCursor': 'abc',
        'items': [
          {
            'id': '0192f100-0000-7000-8000-0000000000a5',
            'game': {'id': '0192f100-0000-7000-8000-0000000000b1', 'displayName': 'Catan'},
            'recorder': {'id': '0192f100-0000-7000-8000-0000000000d1', 'displayName': 'Gillian'},
            'status': 'DRAFT',
            'playedAt': '2026-10-11T19:30:00Z',
            'editRequestsEnabled': false,
            'createdAt': '2026-10-11T21:00:00Z',
            'participants': <Object?>[],
          },
        ],
      }),
    );
  }

  @override
  void close() {}
}
