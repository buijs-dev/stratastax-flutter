import 'package:stx_compiler/src/i18n/cldr.dart';
import 'package:stx_compiler/src/i18n/icu.dart';
import 'package:stx_compiler/stx_compiler.dart';
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

  group('compile', () {
    test('plain arguments interpolate; quotes and dollars are escaped', () {
      expect(compileIcu(parseIcu(r"Bob's {item} costs $5"), ['item']), r"'Bob\'s ${args[0]} costs \$5'");
    });

    test('plural compiles to switches over exact values and CLDR categories', () {
      final code = compileIcu(parseIcu('{n, plural, =0 {none} one {# item} other {# items}}'), ['n']);
      expect(code, contains('final v0 when v0 == 0 =>'));
      expect(code, contains('switch (formats.plural(v0))'));
      expect(code, contains(r"Plural.one => '${formats.number(v0)} item'"));
    });

    test('select compiles to a string switch', () {
      final code = compileIcu(parseIcu('{g, select, f {she} other {they}}'), ['g']);
      // A message that is only a choice is the switch itself, not '${…}'.
      expect(code, r"switch ((args[0] as String)) { 'f' => 'she', _ => 'they' }");
    });
  });

  group('CLDR', () {
    test('locales map to their language', () {
      expect(cldrFor('nl_BE'), same(cldr['nl']));
      expect(cldrFor('en-GB'), same(cldr['en']));
      expect(cldrFor('xx'), isNull);
    });

    test('date patterns compile to interpolation', () {
      final nl = cldr['nl']!;
      expect(
        compileDatePattern('EEEE d MMMM y', nl),
        r"'${weekdays[v.weekday - 1]} ${v.day} ${months[v.month - 1]} ${v.year}'",
      );
      expect(compileDatePattern("d 'de' MMMM", cldr['es']!), r"'${v.day} de ${months[v.month - 1]}'");
      expect(
        compileDatePattern('h:mm a', cldr['en']!),
        r"'${(v.hour + 11) % 12 + 1}:${pad2(v.minute)} ${v.hour < 12 ? 'AM' : 'PM'}'",
      );
    });

    test('every bundled locale renders valid Dart', () {
      final formatter = GeneratedFormatter();
      for (final entry in cldr.entries) {
        expect(entry.value.months, hasLength(12), reason: entry.key);
        expect(entry.value.weekdays, hasLength(7), reason: entry.key);
        final source = "import 'package:stx_i18n/stx_i18n.dart';\n\n${renderFormats('_F', entry.value)}";
        expect(() => formatter.format(GeneratedFile('f.dart', source)), returnsNormally, reason: entry.key);
      }
    });
  });

  test('the frontend rejects locales without CLDR data (STX-I007)', () {
    final diagnostics = Diagnostics();
    I18nFrontend(
      const I18nConfig(dir: 'i18n', base: 'en', locales: ['en', 'xx']),
      diagnostics,
    ).parse(framework: const {'en': {}, 'xx': {}}, frameworkOrder: const [], app: const {'en': {}, 'xx': {}});
    expect(diagnostics.all.single.code, I18nCodes.unsupportedLocale);
  });
}
