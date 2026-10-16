import 'dart:math';

import 'package:stx_core/stx_core.dart';
import 'package:test/test.dart';

void main() {
  group('Patch', () {
    test('unset keeps, value replaces, value(null) clears', () {
      expect(const Patch<int>.unset().orKeep(1), 1);
      expect(const Patch<int>.value(2).orKeep(1), 2);
      expect(const Patch<int>.value(null).orKeep(1), isNull);
    });

    test('value equality', () {
      expect(const Patch<int>.value(1), const Patch<int>.value(1));
      expect(const Patch<int>.unset(), const Patch<int>.unset());
      expect(const Patch<int>.unset() == const Patch<int>.value(null), isFalse);
    });
  });

  group('DeepEquality', () {
    test('lists and maps compare structurally', () {
      expect(
        DeepEquality.equals(
          [
            {
              'a': [1, 2],
            },
          ],
          [
            {
              'a': [1, 2],
            },
          ],
        ),
        isTrue,
      );
      expect(DeepEquality.equals([1, 2], [2, 1]), isFalse);
      expect(DeepEquality.equals({'a': 1, 'b': 2}, {'b': 2, 'a': 1}), isTrue);
    });

    test('equal values hash equally', () {
      expect(DeepEquality.hash({'a': 1, 'b': 2}), DeepEquality.hash({'b': 2, 'a': 1}));
      expect(DeepEquality.hash([1, 2]), DeepEquality.hash([1, 2]));
    });
  });

  group('Uuid.v7', () {
    test('has version 7, variant 10 and the timestamp prefix', () {
      final now = DateTime.utc(2026, 10, 11, 12);
      final uuid = Uuid.v7(now: now, random: Random(1));
      expect(Uuid.tryParse(uuid.value), isNotNull);
      expect(uuid.value[14], '7');
      expect('89ab'.contains(uuid.value[19]), isTrue);
      final hex = uuid.value.replaceAll('-', '').substring(0, 12);
      expect(int.parse(hex, radix: 16), now.millisecondsSinceEpoch);
    });

    test('is time-ordered', () {
      final a = Uuid.v7(now: DateTime.utc(2026, 1, 1));
      final b = Uuid.v7(now: DateTime.utc(2026, 1, 2));
      expect(a.value.compareTo(b.value), lessThan(0));
    });
  });

  group('ScopeRequirement', () {
    test('every group needs one of its scopes', () {
      const requires = ScopeRequirement([
        {_Scope.a, _Scope.b},
        {_Scope.c},
      ]);
      expect(requires.satisfiedBy({_Scope.b, _Scope.c}), isTrue);
      expect(requires.satisfiedBy({_Scope.a, _Scope.b}), isFalse);
      expect(ScopeRequirement.none.satisfiedBy(const {}), isTrue);
    });
  });

  group('Json value decoders', () {
    test('decode list items and maps', () {
      expect(
        Json.list(
          {
            'ids': ['6F1C2B3A-0D4E-4F5A-9B8C-7D6E5F4A3B2C'],
          },
          'ids',
          Json.uuidValue,
        ).single.value,
        '6f1c2b3a-0d4e-4f5a-9b8c-7d6e5f4a3b2c',
      );
      expect(Json.mapOf({'a': 1, 'b': 2.0}, Json.integerValue), {'a': 1, 'b': 2});
      expect(
        () => Json.list(
          {
            'n': [1, 'x'],
          },
          'n',
          Json.integerValue,
        ),
        throwsA(isA<JsonDecodeException>().having((e) => e.path, 'path', 'n[1]')),
      );
    });
  });
}

enum _Scope implements StxScope {
  a,
  b,
  c;

  @override
  String get claim => 'test:$name';
}
