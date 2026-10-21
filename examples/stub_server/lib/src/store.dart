import 'package:stx_core/stx_core.dart';

import '../gen/contract/platform_v1/platform_v1.g.dart';

Uuid _id(int n) => Uuid.trusted('0192f100-0000-7000-8000-${n.toRadixString(16).padLeft(12, '0')}');

/// In-memory state, seeded with a few games, ghost players and one user. With [demo] there are
/// more games and 45 recorded matches, enough for several pages in the overviews.
final class StubStore {
  StubStore({bool demo = false}) {
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
    if (demo) _seedDemo(now);
  }

  void _seedDemo(DateTime now) {
    const more = [
      ('Azul', 2, 4, ScoreTypeV1.score),
      ('Brass: Birmingham', 2, 4, ScoreTypeV1.score),
      ('Cascadia', 1, 4, ScoreTypeV1.score),
      ('Dominion', 2, 4, ScoreTypeV1.score),
      ('Everdell', 1, 4, ScoreTypeV1.score),
      ('Gloomhaven', 1, 4, ScoreTypeV1.winLoss),
      ('Hanabi', 2, 5, ScoreTypeV1.score),
      ('Kingdomino', 2, 4, ScoreTypeV1.score),
      ('Love Letter', 2, 6, ScoreTypeV1.winLoss),
      ('Mysterium', 2, 7, ScoreTypeV1.winLoss),
      ('Pandemic', 2, 4, ScoreTypeV1.winLoss),
      ('Patchwork', 2, 2, ScoreTypeV1.score),
      ('Quacks of Quedlinburg', 2, 4, ScoreTypeV1.score),
      ('Root', 2, 4, ScoreTypeV1.score),
      ('Sagrada', 1, 4, ScoreTypeV1.score),
      ('Scythe', 1, 5, ScoreTypeV1.score),
      ('Splendor', 2, 4, ScoreTypeV1.score),
      ('Spirit Island', 1, 4, ScoreTypeV1.winLoss),
      ('The Crew', 2, 5, ScoreTypeV1.winLoss),
      ('Ticket to Ride', 2, 5, ScoreTypeV1.score),
      ('Twilight Struggle', 2, 2, ScoreTypeV1.winLoss),
      ('7 Wonders', 3, 7, ScoreTypeV1.score),
      ('Agricola', 1, 4, ScoreTypeV1.score),
      ('Viticulture', 1, 6, ScoreTypeV1.score),
    ];
    for (final (i, (name, min, max, type)) in more.indexed) {
      games.add(
        GameV1(
          id: _id(0xb100 + i),
          displayName: name,
          description: '$name, seeded by the stub.',
          minPlayers: min,
          maxPlayers: max,
          tags: const [],
          scoreType: type,
          winCondition: type == ScoreTypeV1.score ? WinConditionV1.higherWins : null,
          createdAt: now.subtract(Duration(days: 30 + i * 7)),
        ),
      );
    }
    final recorders = [
      recorder,
      UserRefV1(id: _id(0xd001), displayName: 'Pim'),
      UserRefV1(id: _id(0xd002), displayName: 'Sara'),
    ];
    for (var i = 0; i < 45; i++) {
      final game = games[(i * 7) % games.length];
      final players = [ghostPlayers[i % 6], ghostPlayers[(i + 1) % 6]];
      final playedAt = now.subtract(Duration(days: i * 3, hours: i % 5));
      matches.add(
        MatchV1(
          id: _id(0xa000 + i),
          game: GameRefV1(id: game.id, displayName: game.displayName),
          recorder: recorders[i % recorders.length],
          status: i % 4 == 0 ? MatchStatusV1.draft : MatchStatusV1.finalized,
          playedAt: playedAt,
          editRequestsEnabled: i.isEven,
          createdAt: playedAt.add(const Duration(hours: 2)),
          participants: [
            for (final (j, p) in players.indexed)
              MatchParticipantV1(
                id: _id(0xa100 + i * 2 + j),
                ghostPlayer: p,
                outcome: j == 0 ? OutcomeV1.win : OutcomeV1.loss,
                createdAt: playedAt,
              ),
          ],
        ),
      );
    }
  }

  final games = <GameV1>[];
  final ghostPlayers = <GhostPlayerRefV1>[];
  final matches = <MatchV1>[];

  /// The signed-in user of the stub.
  final recorder = UserRefV1(id: _id(0xd000), displayName: 'Stub user');

  /// The published translations of app `match-tracker` per locale (the i18n CMS): a plain text
  /// and an ICU plural, laid over the app's own Dutch texts. Nothing is published for `en`.
  final bundles = <String, Map<String, String>>{
    'nl': {
      'app.title': 'Partijen',
      'matchCreateCommand.players.count': '{count, plural, =0 {Nog niemand} one {# deelnemer} other {# deelnemers}}',
    },
  };

  /// The release that published [bundles]; the ETag of a bundle.
  var bundleRelease = 1;

  /// Idempotency-Key → stored response (status, JSON body).
  final idempotent = <String, (int, String)>{};

  var _sequence = 0;

  Uuid nextId() => _id(0xe000 + _sequence++);
}
