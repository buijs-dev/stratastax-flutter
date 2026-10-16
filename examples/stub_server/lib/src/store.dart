import 'package:stx_core/stx_core.dart';

import '../gen/contract/platform_v1/platform_v1.g.dart';

Uuid _id(int n) => Uuid.trusted('0192f100-0000-7000-8000-${n.toRadixString(16).padLeft(12, '0')}');

/// In-memory state, seeded with a few games, ghost players and one user.
final class StubStore {
  StubStore() {
    final now = DateTime.utc(2026, 10, 1, 12);
    for (final (i, (name, min, max, type)) in const [
      ('Catan', 3, 4, ScoreTypeV1.score),
      ('Carcassonne', 2, 5, ScoreTypeV1.score),
      ('Wingspan', 1, 5, ScoreTypeV1.score),
      ('Terraforming Mars', 1, 5, ScoreTypeV1.score),
      ('Codenames', 4, 8, ScoreTypeV1.winLoss),
      ('Chess', 2, 2, ScoreTypeV1.winLoss),
    ].indexed) {
      games.add(
        GameV1(
          id: _id(0xb000 + i),
          displayName: name,
          description: '$name, seeded by the stub.',
          minPlayers: min,
          maxPlayers: max,
          tags: const [],
          scoreType: type,
          winCondition: type == ScoreTypeV1.score ? WinConditionV1.higherWins : null,
          createdAt: now,
        ),
      );
    }
    for (final (i, name) in const ['Alice', 'Bob', 'Charlie', 'Charlotte', 'Diana', 'Eve'].indexed) {
      ghostPlayers.add(GhostPlayerRefV1(id: _id(0xc000 + i), displayName: name));
    }
  }

  final games = <GameV1>[];
  final ghostPlayers = <GhostPlayerRefV1>[];
  final matches = <MatchV1>[];

  /// The signed-in user of the stub.
  final recorder = UserRefV1(id: _id(0xd000), displayName: 'Stub user');

  /// Idempotency-Key → stored response (status, JSON body).
  final idempotent = <String, (int, String)>{};

  var _sequence = 0;

  Uuid nextId() => _id(0xe000 + _sequence++);
}
