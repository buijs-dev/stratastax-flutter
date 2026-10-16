import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stx_i18n/stx_i18n.dart';

final class _Messages extends StxMessages {
  const _Messages(Locale locale, String text) : super(locale, const {});

  @override
  String format(String key, List<Object?> args) => '';

  @override
  String resolve(Msg msg) => locale.languageCode;
}

void main() {
  Widget host(MessagesLoader load, {Locale? initial}) => Directionality(
    textDirection: TextDirection.ltr,
    child: StxLocaleScope(
      supported: const [Locale('en'), Locale('nl')],
      load: load,
      initial: initial,
      child: Builder(builder: (context) => Text(context.msg(const MsgKey('any')))),
    ),
  );

  testWidgets('synchronous base locale renders in the first frame', (tester) async {
    await tester.pumpWidget(host((l) => _Messages(l, ''), initial: const Locale('en')));
    expect(find.text('en'), findsOneWidget);
  });

  testWidgets('an asynchronously loaded locale renders once loaded', (tester) async {
    await tester.pumpWidget(host((l) async => _Messages(l, ''), initial: const Locale('nl')));
    expect(find.text('nl'), findsNothing);
    await tester.pump();
    expect(find.text('nl'), findsOneWidget);
  });

  testWidgets('region locales match their language', (tester) async {
    await tester.pumpWidget(host((l) => _Messages(l, ''), initial: const Locale('nl', 'BE')));
    expect(find.text('nl'), findsOneWidget);
  });

  testWidgets('setLocale switches and remembers', (tester) async {
    await tester.pumpWidget(host((l) => _Messages(l, ''), initial: const Locale('en')));
    await StxLocaleScope.setLocale(tester.element(find.text('en')), const Locale('nl'));
    await tester.pump();
    expect(find.text('nl'), findsOneWidget);
  });
}
