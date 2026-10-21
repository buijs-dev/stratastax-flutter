import 'package:stx_icu/stx_icu.dart';
import 'package:test/test.dart';

void main() {
  group('parse', () {
    test('text, arguments and quoting', () {
      final nodes = parseIcu("It''s '{literal}' for {name}");
      expect(nodes.whereType<IcuText>().map((t) => t.text).join(), "It's {literal} for ");
      expect((nodes.last as IcuArg).name, 'name');
    });

    test('plural with exact matches, categories and #', () {
      final choice = parseIcu('{count, plural, =0 {none} one {# player} other {# players}}').single as IcuChoice;
      expect(choice.kind, 'plural');
      expect(choice.options.keys, ['=0', 'one', 'other']);
      expect(choice.options['one']!.first, isA<IcuPound>());
    });

    test('nested select inside plural', () {
      final choice =
          parseIcu('{n, plural, other {{who, select, me {I have #} other {{who} has #}}}}').single as IcuChoice;
      expect(choice.options['other']!.single, isA<IcuChoice>());
    });

    test('formatted arguments', () {
      final nodes = parseIcu('{d, date, long} at {d, time} for {p, number, percent}');
      expect(
        [for (final n in nodes.whereType<IcuArg>()) '${n.type}:${n.style}'],
        ['date:long', 'time:null', 'number:percent'],
      );
    });

    test('errors', () {
      for (final bad in [
        '{n, plural, one {x}}', // no other
        '{n, plural, eleven {x} other {y}}', // unknown category
        '{d, date, tiny}', // unknown style
        '{n, currency}', // unknown type
        '{open',
        'close}',
      ]) {
        expect(() => parseIcu(bad), throwsA(isA<IcuException>()), reason: bad);
      }
    });
  });

  group('arguments', () {
    test('types follow usage', () {
      expect(icuArguments(parseIcu('{name} played {n, plural, other {#}} on {d, date}, {s, select, a {} other {}}')), {
        'name': ArgType.any,
        'n': ArgType.number,
        'd': ArgType.date,
        's': ArgType.string,
      });
    });

    test('conflicting usage is an error', () {
      expect(() => icuArguments(parseIcu('{x, number} {x, date}')), throwsA(isA<IcuException>()));
    });
  });

  test('compatible types: equal, or one of them is any', () {
    expect(ArgType.number.compatibleWith(ArgType.number), isTrue);
    expect(ArgType.any.compatibleWith(ArgType.date), isTrue);
    expect(ArgType.string.compatibleWith(ArgType.any), isTrue);
    expect(ArgType.number.compatibleWith(ArgType.date), isFalse);
  });
}
