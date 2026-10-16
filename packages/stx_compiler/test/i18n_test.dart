import 'package:stx_compiler/src/i18n/icu.dart';
import 'package:stx_compiler/stx_compiler.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

Map<String, String> _flat(String yaml) => I18nFrontend.flatten(loadYaml(yaml));

({I18nIR ir, Diagnostics diagnostics}) _parse({required String en, String nl = '{}', bool missingIsError = true}) {
  final diagnostics = Diagnostics();
  final frontend = I18nFrontend(
    I18nConfig(dir: 'i18n', locales: const ['en', 'nl'], missingIsError: missingIsError),
    diagnostics,
  );
  final framework = {
    'en': _flat('stx: { action: { save: Save }, validation: { minItems: "At least {min}" } }'),
    'nl': _flat('stx: { action: { save: Opslaan }, validation: { minItems: "Minimaal {min}" } }'),
  };
  final ir = frontend.parse(
    framework: framework,
    frameworkOrder: framework['en']!.keys.toList(),
    app: {'en': _flat(en), 'nl': _flat(nl)},
  );
  return (ir: ir, diagnostics: diagnostics);
}

void main() {
  test('framework keys come first with fixed ids, app keys sorted after', () {
    final parsed = _parse(
      en: 'match: { title: Match }\napp: { title: App }',
      nl: 'match: { title: Wedstrijd }\napp: { title: App }',
    );
    expect(parsed.diagnostics.all, isEmpty);
    expect(parsed.ir.messages.map((m) => m.key), [
      'stx.action.save',
      'stx.validation.minItems',
      'app.title',
      'match.title',
    ]);
    expect(parsed.ir.byKey('match.title')!.values, {'en': 'Match', 'nl': 'Wedstrijd'});
  });

  test('apps override framework texts', () {
    final parsed = _parse(en: 'stx: { action: { save: Store } }', nl: 'stx: { action: { save: Bewaren } }');
    expect(parsed.ir.byKey('stx.action.save')!.values, {'en': 'Store', 'nl': 'Bewaren'});
  });

  test('a missing translation is an error, or falls back to the base', () {
    expect(_parse(en: 'a: A').diagnostics.all.single.code, I18nCodes.missingLocale);
    final fallback = _parse(en: 'a: A', missingIsError: false);
    expect(fallback.diagnostics.all, isEmpty);
    expect(fallback.ir.byKey('a')!.values['nl'], 'A');
  });

  test('placeholders must match across locales', () {
    final parsed = _parse(en: 'a: "Hi {name}"', nl: 'a: "Hoi {naam}"');
    expect(parsed.diagnostics.all.single.code, I18nCodes.placeholders);
    expect(_parse(en: 'a: "Hi {name}"', nl: 'a: "Hoi {name}"').ir.byKey('a')!.placeholders, ['name']);
  });

  test('ICU messages are parsed; invalid syntax is STX-I004', () {
    final ok = _parse(en: 'a: "{count, plural, one {# x} other {# xs}}"', nl: 'a: "{count, plural, other {#}}"');
    expect(ok.diagnostics.all, isEmpty);
    expect(ok.ir.byKey('a')!.arguments, {'count': ArgType.number});
    final bad = _parse(en: 'a: "{count, plural, one {# x}}"', nl: 'a: "{count, plural, other {#}}"');
    expect(bad.diagnostics.all.single.code, I18nCodes.syntax);
  });

  test('placeholder types must agree across locales', () {
    final parsed = _parse(en: 'a: "{when, date}"', nl: 'a: "{when, number}"');
    expect(parsed.diagnostics.all.single.code, I18nCodes.placeholders);
  });

  test('typed factories', () {
    final parsed = _parse(
      en: 'a: "{n, plural, other {#}} on {d, date}"',
      nl: 'a: "{n, plural, other {#}} op {d, date}"',
    );
    final keys = renderI18n(parsed.ir, deferred: false, diagnostics: parsed.diagnostics).first.content;
    expect(keys, contains('static Msg a({required num n, required DateTime d})'));
  });

  test('keys only in a non-base locale are warned about', () {
    final parsed = _parse(en: 'a: A', nl: 'a: A\nb: B');
    expect(parsed.diagnostics.all.single.code, I18nCodes.unknownKey);
    expect(parsed.diagnostics.all.single.isError, isFalse);
  });

  test('rendering: keys, tables with compiled placeholders, deferred loading', () {
    final parsed = _parse(
      en: 'matchCreateCommand: { gameId: { label: Game } }\ngreeting: "Hi {name}"',
      nl: 'matchCreateCommand: { gameId: { label: Spel } }\ngreeting: "Hoi {name}"',
    );
    final formatter = GeneratedFormatter();
    final files = {
      for (final f in renderI18n(parsed.ir, deferred: true, diagnostics: parsed.diagnostics))
        f.path: formatter.format(f).content,
    };
    expect(files['i18n/keys.g.dart'], contains('abstract final class MsgMatchCreateCommand {'));
    expect(
      files['i18n/keys.g.dart'],
      contains("static const gameIdLabel = MsgKey('matchCreateCommand.gameId.label');"),
    );
    expect(files['i18n/keys.g.dart'], contains('static Msg greeting({required Object? name}) =>'));
    expect(files['i18n/messages_nl.g.dart'], contains(r"'stx.validation.minItems' => 'Minimaal ${args[0]}',"));
    expect(files['i18n/messages_nl.g.dart'], contains(r"'greeting' => 'Hoi ${args[0]}',"));
    expect(files['i18n/messages_nl.g.dart'], contains("'matchCreateCommand.gameId.label': 'Spel',"));
    expect(files['i18n/locales.g.dart'], contains("import 'messages_nl.g.dart' deferred as nl;"));
    expect(parsed.diagnostics.all, isEmpty);
  });

  test('msgName', () {
    expect(msgName('matchCreateCommand.gameId.label'), (className: 'MsgMatchCreateCommand', member: 'gameIdLabel'));
    expect(msgName('enum.OutcomeV1.win'), (className: 'MsgEnum', member: 'outcomeV1Win'));
    expect(msgName('title'), (className: 'MsgRoot', member: 'title'));
  });
}
