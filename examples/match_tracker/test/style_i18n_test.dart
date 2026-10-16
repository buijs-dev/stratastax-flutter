import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:match_tracker/gen/i18n/keys.g.dart';
import 'package:match_tracker/gen/i18n/locales.g.dart';
import 'package:match_tracker/gen/i18n/messages_en.g.dart';
import 'package:match_tracker/gen/style/tokens.g.dart';
import 'package:stx_i18n/stx_i18n.dart';
import 'package:stx_style/stx_style.dart';
import 'package:stx_ui/stx_ui.dart';
import 'package:stx_ui/testing.dart';

/// Renders with the tokens and messages stx_compiler generated from stx.tokens.yaml and i18n/.
void main() {
  testWidgets('generated tokens style an app button variant', (tester) async {
    await tester.pumpWidget(
      StxTestHost(
        tokens: stxTokensLight,
        messages: const MessagesEn(),
        child: StxButton(MsgApp.title, onPressed: () {}, variant: AppButton.win),
      ),
    );
    await tester.pump();
    final text = tester.widget<Text>(find.text('Match tracker'));
    expect(text.style!.color, const Color(0xFFFFFFFF)); // onWin
    expect(stxTokensLight.color(AppColor.win), const Color(0xFF15803D));
  });

  test('dark mode resolves references per mode', () {
    expect(stxTokensLight.color(ColorToken.primary), const Color(0xFF7C3AED)); // violet.600
    expect(stxTokensDark.color(ColorToken.primary), const Color(0xFF7C3AED)); // violet.600, both modes
    expect(stxTokensLight.color(ColorToken.border), const Color(0xFFE4E4E7)); // zinc.200 (default)
  });

  test('framework texts and app texts share one table; non-base locales load deferred', () async {
    const en = MessagesEn();
    expect(en.resolve(StxKeys.actionSave), 'Save');
    expect(en.resolve(StxKeys.validationMinItems(2)), 'Choose at least 2 items');
    expect(en.resolve(StxKeys.validationMinItems(1)), 'Choose at least 1 item');
    final nl = await loadMessages(const Locale('nl'));
    expect(nl.resolve(MsgApp.title), 'Wedstrijden');
    expect(nl.resolve(StxKeys.validationMinItems(2)), 'Kies minimaal 2 items');
  });

  test('ICU plural with exact match, compiled per locale', () async {
    const en = MessagesEn();
    final nl = await loadMessages(const Locale('nl'));
    expect(en.resolve(MsgMatchCreateCommand.playersCount(count: 0)), 'No players yet');
    expect(en.resolve(MsgMatchCreateCommand.playersCount(count: 1)), '1 player');
    expect(nl.resolve(MsgMatchCreateCommand.playersCount(count: 3)), '3 spelers');
  });

  test('CLDR dates, numbers and input formats per locale', () async {
    const en = MessagesEn();
    final nl = await loadMessages(const Locale('nl'));
    final d = DateTime(2026, 10, 11, 18, 5);
    expect(en.formats.date(d, DateStyle.long), 'October 11, 2026');
    expect(en.formats.dateTime(d), 'Oct 11, 2026, 6:05 PM');
    expect(nl.formats.date(d, DateStyle.full), 'zondag 11 oktober 2026');
    expect(nl.formats.dateTime(d), '11 okt 2026 18:05');
    expect(en.formats.number(1234.5), '1,234.5');
    expect(nl.formats.number(1234.5), '1.234,5');
    expect(nl.formats.percent(0.25), '25%');
    expect(en.formats.inputDateTime(d), '10/11/2026 18:05');
    expect(nl.formats.inputDateTime(d), '11-10-2026 18:05');
    expect(nl.formats.parseInputDate('31-12-2026'), DateTime(2026, 12, 31));
    expect(en.formats.parseInputDate('12/31/2026'), DateTime(2026, 12, 31));
    expect(en.formats.parseInputDate('31/12/2026'), isNull);
    expect(en.formats.firstDayOfWeek, DateTime.sunday);
    expect(nl.formats.firstDayOfWeek, DateTime.monday);
  });
}
