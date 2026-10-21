import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stx_i18n/stx_i18n.dart';
import 'package:stx_icu/stx_icu.dart' show parseIcu;

/// Stands in for a generated `MessagesNl`.
final class _Compiled extends StxMessages {
  const _Compiled([Locale locale = const Locale('nl')])
    : super(locale, const {
        'app.title': 'Wedstrijden',
        'players.count': '{count, plural, one {# speler} other {# spelers}}',
        'greeting': 'Hallo {name}',
      });

  @override
  Map<String, List<(String, ArgType)>> get arguments => const {
    'players.count': [('count', ArgType.number)],
    'greeting': [('name', ArgType.any)],
  };

  @override
  String format(String key, List<Object?> args) => switch (key) {
    'players.count' => 'compiled ${args[0]}',
    'greeting' => 'Hallo ${args[0]}',
    _ => key,
  };
}

const _count = MsgKey('players.count');

void main() {
  group('formatIcu', () {
    const formats = IsoFormats();
    String run(String text, Map<String, Object?> args) => formatIcu(parseIcu(text), args, formats);

    test('plural: exact match first, then the CLDR category, then other', () {
      const text = '{n, plural, =0 {geen} one {# speler} other {# spelers}}';
      expect(run(text, {'n': 0}), 'geen');
      expect(run(text, {'n': 1}), '1 speler');
      expect(run(text, {'n': 1234}), '1,234 spelers');
    });

    test('select, nested arguments and formats', () {
      expect(run('{g, select, f {zij} other {hen}} speelt', {'g': 'f'}), 'zij speelt');
      expect(run('{g, select, f {zij} other {hen}}', {'g': 'x'}), 'hen');
      expect(run('{p, number, percent} op {d, date}', {'p': 0.5, 'd': DateTime(2026, 10, 20)}), '50% op 2026-10-20');
    });

    test('a value of the wrong type is shown, never thrown', () {
      expect(run('{n, number}', {'n': 'veel'}), 'veel');
      expect(run('{n, plural, one {een} other {meer}}', {'n': 'x'}), 'meer');
    });
  });

  group('OverlayMessages', () {
    test('overrides plain and ICU texts; other keys keep the compiled text', () {
      final messages = OverlayMessages(const _Compiled(), {
        'app.title': "Partijen van 't seizoen",
        'players.count': '{count, plural, =0 {Nog niemand} one {# deelnemer} other {# deelnemers}}',
      });
      expect(messages.resolve(const MsgKey('app.title')), "Partijen van 't seizoen");
      expect(messages.resolve(const MsgArgs(_count, [0])), 'Nog niemand');
      expect(messages.resolve(const MsgArgs(_count, [3])), '3 deelnemers');
      expect(messages.resolve(const MsgArgs(MsgKey('greeting'), ['Ada'])), 'Hallo Ada');
      expect(messages.overridden, {'app.title', 'players.count'});
      expect(messages.locale, const Locale('nl'));
    });

    test('unknown keys, invalid ICU and wrong placeholders are left out and reported', () {
      final issues = <TranslationIssue>[];
      final messages = OverlayMessages(const _Compiled(), {
        'not.a.key': 'x',
        'app.title': 'Partijen {broken',
        'greeting': 'Hoi {user}',
        'players.count': '{count, date}',
      }, onIssue: issues.add);
      expect(issues.map((i) => (i.kind, i.key)), [
        (TranslationIssueKind.unknownKey, 'not.a.key'),
        (TranslationIssueKind.syntax, 'app.title'),
        (TranslationIssueKind.arguments, 'greeting'),
        (TranslationIssueKind.arguments, 'players.count'),
      ]);
      expect(messages.overridden, isEmpty);
      expect(messages.resolve(const MsgKey('app.title')), 'Wedstrijden');
      expect(messages.resolve(const MsgArgs(_count, [2])), 'compiled 2');
    });

    test('a placeholder in a plain key is wrong too', () {
      final issues = <TranslationIssue>[];
      OverlayMessages(const _Compiled(), {'app.title': 'Hallo {name}'}, onIssue: issues.add);
      expect(issues.single.message, contains('expected: none'));
    });
  });

  group('StxLocaleScope with translations', () {
    Widget host(_Source source, {TranslationCache? cache, void Function(TranslationIssue)? onIssue}) => Directionality(
      textDirection: TextDirection.ltr,
      child: StxLocaleScope(
        supported: const [Locale('nl'), Locale('en')],
        load: _Compiled.new,
        initial: const Locale('nl'),
        translations: source,
        cache: cache,
        onIssue: onIssue,
        child: Builder(builder: (context) => Text(context.msg(const MsgKey('app.title')))),
      ),
    );

    testWidgets('the compiled text first, then the bundle once it arrives; it is cached', (tester) async {
      final source = _Source();
      final cache = MemoryTranslationCache();
      await tester.pumpWidget(host(source, cache: cache));
      expect(find.text('Wedstrijden'), findsOneWidget); // never waits for the backend

      source.reply(const TranslationBundle(locale: Locale('nl'), messages: {'app.title': 'Partijen'}, etag: '"7"'));
      await tester.pumpAndSettle();
      expect(find.text('Partijen'), findsOneWidget);
      expect(cache.read(const Locale('nl'))!.etag, '"7"');
    });

    testWidgets('a cached bundle shows in the first frame; its ETag makes the next fetch conditional', (tester) async {
      final source = _Source();
      final cache = MemoryTranslationCache()
        ..write(const TranslationBundle(locale: Locale('nl'), messages: {'app.title': 'Uit de cache'}, etag: '"6"'));
      await tester.pumpWidget(host(source, cache: cache));
      expect(find.text('Uit de cache'), findsOneWidget);
      expect(source.requests.single, ('nl', '"6"'));

      source.reply(null); // 304 Not Modified
      await tester.pump();
      expect(find.text('Uit de cache'), findsOneWidget);
    });

    testWidgets('a failed fetch keeps the texts and is reported', (tester) async {
      final source = _Source();
      final issues = <TranslationIssue>[];
      await tester.pumpWidget(host(source, onIssue: issues.add));
      source.fail(StateError('offline'));
      await tester.pumpAndSettle();
      expect(find.text('Wedstrijden'), findsOneWidget);
      expect(issues.single.kind, TranslationIssueKind.fetch);
    });

    testWidgets('a bundle that arrives after a locale switch is not applied', (tester) async {
      final source = _Source();
      await tester.pumpWidget(host(source));
      await StxLocaleScope.setLocale(tester.element(find.text('Wedstrijden')), const Locale('en'));
      source.reply(const TranslationBundle(locale: Locale('nl'), messages: {'app.title': 'Partijen'}), at: 0);
      await tester.pumpAndSettle();
      expect(find.text('Partijen'), findsNothing);
      expect(source.requests.map((r) => r.$1), ['nl', 'en']);
    });

    testWidgets('refresh fetches again', (tester) async {
      final source = _Source();
      await tester.pumpWidget(host(source));
      source.reply(null);
      await tester.pump();
      final refreshed = StxLocaleScope.refresh(tester.element(find.text('Wedstrijden')));
      source.reply(const TranslationBundle(locale: Locale('nl'), messages: {'app.title': 'Nieuw'}));
      await refreshed;
      await tester.pump();
      expect(find.text('Nieuw'), findsOneWidget);
    });
  });
}

/// A backend whose answers the test releases one by one.
final class _Source implements TranslationSource {
  final requests = <(String, String?)>[];
  final _pending = <Completer<TranslationBundle?>>[];

  @override
  Future<TranslationBundle?> fetch(Locale locale, {String? etag}) {
    requests.add((locale.toLanguageTag(), etag));
    final completer = Completer<TranslationBundle?>();
    _pending.add(completer);
    return completer.future;
  }

  void reply(TranslationBundle? bundle, {int at = -1}) => _take(at).complete(bundle);

  void fail(Object error) => _take(-1).completeError(error);

  Completer<TranslationBundle?> _take(int at) => _pending.removeAt(at < 0 ? _pending.length - 1 : at);
}
