import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stx_core/stx_core.dart';
import 'package:stx_i18n/stx_i18n.dart';
import 'package:stx_ui/stx_ui.dart';
import 'package:stx_ui/testing.dart';

import 'support.dart';

/// Day-month-year input and Sunday as first day, like a generated `en`/`nl` formats class.
final class _DmyFormats extends IsoFormats {
  const _DmyFormats();

  static final _input = RegExp(r'^\s*(\d{1,2})-(\d{1,2})-(\d{4})\s*$');

  @override
  int get firstDayOfWeek => DateTime.sunday;

  @override
  List<String> get weekdaysShort => const ['ma', 'di', 'wo', 'do', 'vr', 'za', 'zo'];

  @override
  String inputDate(DateTime v) => '${pad2(v.day)}-${pad2(v.month)}-${v.year}';

  @override
  DateTime? parseInputDate(String text) => parseNumericDate(text, _input, 3, 2, 1);
}

final _now = DateTime(2026, 10, 11, 19, 30);

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    StxTestHost(
      tokens: testTokens,
      messages: MapMessages({
        StxKeys.calendarOpen.name: 'Calendar',
        StxKeys.fieldNow.name: 'Now',
        StxKeys.validationFormat.name: 'Invalid',
      }, formats: const _DmyFormats()),
      size: const Size(800, 900),
      child: SizedBox(width: 400, child: child),
    ),
  );
  await tester.pump();
}

Future<void> _click(WidgetTester tester, Finder finder) async {
  final gesture = await tester.startGesture(tester.getCenter(finder), kind: PointerDeviceKind.mouse);
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('typing in the locale format sets the value; the hint is an example', (tester) async {
    final field = StxField<DateTime?>(null);
    await _pump(tester, StxFormDateTime(field: field, label: label, clock: () => _now));
    expect(find.text('31-12-2026 18:30'), findsOneWidget); // hint
    await tester.enterText(find.byType(EditableText), '5-11-2026 9:05');
    await tester.pump();
    expect(field.value, DateTime(2026, 11, 5, 9, 5));
  });

  testWidgets('invalid text shows a format error and clears the value', (tester) async {
    final field = StxField<DateTime?>(DateTime(2026, 1, 1));
    await _pump(tester, StxFormDateTime(field: field, label: label, clock: () => _now));
    expect(find.text('01-01-2026 00:00'), findsOneWidget);
    await tester.enterText(find.byType(EditableText), '31-02-2026 10:00');
    await tester.pump();
    expect(field.value, isNull);
    expect(find.text('Invalid'), findsOneWidget);
    // The invalid text stays while the user fixes it.
    expect(tester.widget<EditableText>(find.byType(EditableText)).controller.text, '31-02-2026 10:00');
  });

  testWidgets('the calendar picks a day and keeps the time; weeks start on the locale day', (tester) async {
    final field = StxField<DateTime?>(DateTime(2026, 10, 3, 14, 15));
    await _pump(tester, StxFormDateTime(field: field, label: label, clock: () => _now));
    await _click(tester, find.text('Calendar'));
    final headers = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList();
    expect(headers.sublist(headers.indexOf('zo'), headers.indexOf('zo') + 7), [
      'zo',
      'ma',
      'di',
      'wo',
      'do',
      'vr',
      'za',
    ]);
    await _click(tester, find.text('15'));
    expect(field.value, DateTime(2026, 10, 15, 14, 15));
    expect(find.text('15-10-2026 14:15'), findsOneWidget);
    expect(find.text('zo'), findsNothing); // closed
  });

  testWidgets('a reset from outside clears the text', (tester) async {
    final field = StxField<DateTime?>(DateTime(2026, 1, 1));
    await _pump(tester, StxFormDateTime(field: field, label: label, clock: () => _now));
    field.reset(null);
    await tester.pump();
    expect(tester.widget<EditableText>(find.byType(EditableText)).controller.text, isEmpty);
  });

  testWidgets('date fields hold a LocalDate', (tester) async {
    final field = StxField<LocalDate?>(null);
    await _pump(tester, StxFormDate(field: field, label: label, clock: () => _now));
    await tester.enterText(find.byType(EditableText), '29-02-2028');
    await tester.pump();
    expect(field.value, LocalDate(2028, 2, 29));
  });
}
