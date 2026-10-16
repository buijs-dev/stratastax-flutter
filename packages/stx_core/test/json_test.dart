import 'package:stx_core/stx_core.dart';
import 'package:test/test.dart';

final class _Player {
  const _Player(this.id, this.seat);

  static _Player decode(Object? json) {
    final j = Json.object(json);
    return _Player(Json.uuid(j, 'playerId'), Json.integerOrNull(j, 'seat'));
  }

  final Uuid id;
  final int? seat;
}

void main() {
  const id = '6f1c2b3a-0d4e-4f5a-9b8c-7d6e5f4a3b2c';

  group('primitives', () {
    final json = <String, Object?>{
      'name': 'Catan',
      'count': 3,
      'countFromWeb': 3.0,
      'ratio': 1,
      'active': true,
      'id': id.toUpperCase(),
      'at': '2026-10-11T19:30:00Z',
      'on': '2026-10-11',
    };

    test('decode typed values', () {
      expect(Json.string(json, 'name'), 'Catan');
      expect(Json.integer(json, 'count'), 3);
      expect(Json.integer(json, 'countFromWeb'), 3);
      expect(Json.number(json, 'ratio'), 1.0);
      expect(Json.boolean(json, 'active'), isTrue);
      expect(Json.uuid(json, 'id'), Uuid.trusted(id));
      expect(Json.dateTime(json, 'at'), DateTime.utc(2026, 10, 11, 19, 30));
      expect(Json.date(json, 'on'), LocalDate(2026, 10, 11));
    });

    test('OrNull variants return null for absent or null values', () {
      expect(Json.stringOrNull(json, 'missing'), isNull);
      expect(Json.stringOrNull({'x': null}, 'x'), isNull);
      expect(Json.uuidOrNull(json, 'missing'), isNull);
    });

    test('OrNull variants still reject a wrong type', () {
      expect(() => Json.stringOrNull({'x': 1}, 'x'), throwsA(isA<JsonDecodeException>()));
    });

    test('required values reject absence and wrong types with the key as path', () {
      expect(
        () => Json.string(json, 'missing'),
        throwsA(isA<JsonDecodeException>().having((e) => e.path, 'path', 'missing')),
      );
      expect(() => Json.integer({'x': 1.5}, 'x'), throwsA(isA<JsonDecodeException>()));
      expect(() => Json.uuid({'x': 'not-a-uuid'}, 'x'), throwsA(isA<JsonDecodeException>()));
      expect(() => Json.date({'x': '2026-02-30'}, 'x'), throwsA(isA<JsonDecodeException>()));
    });
  });

  group('nested', () {
    test('lists decode items and are unmodifiable', () {
      final players = Json.list(
        {
          'players': [
            {'playerId': id, 'seat': 1},
            {'playerId': id},
          ],
        },
        'players',
        _Player.decode,
      );
      expect(players.map((p) => p.seat), [1, null]);
      expect(() => players.add(const _Player(Uuid.trusted(id), 3)), throwsUnsupportedError);
    });

    test('errors in list items carry the full path', () {
      expect(
        () => Json.list(
          {
            'players': [
              {'playerId': id},
              {'playerId': 'x'},
            ],
          },
          'players',
          _Player.decode,
        ),
        throwsA(isA<JsonDecodeException>().having((e) => e.path, 'path', 'players[1].playerId')),
      );
    });

    test('nested objects carry the full path', () {
      expect(
        () => Json.nested({'winner': <String, Object?>{}}, 'winner', _Player.decode),
        throwsA(isA<JsonDecodeException>().having((e) => e.path, 'path', 'winner.playerId')),
      );
    });

    test('object rejects non-objects', () {
      expect(() => Json.object([1]), throwsA(isA<JsonDecodeException>()));
      expect(Json.object(<Object?, Object?>{'a': 1}), {'a': 1});
    });
  });
}
