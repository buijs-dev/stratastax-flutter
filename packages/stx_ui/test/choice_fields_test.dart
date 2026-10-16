import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stx_core/stx_core.dart';
import 'package:stx_ui/stx_ui.dart';

import 'support.dart';

final class _Source implements StxDataSource<int> {
  @override
  Future<Result<List<StxOption<int>>, Problem>> search(String query) async =>
      Ok([const StxOption(1, 'Catan'), const StxOption(2, 'Carcassonne')]);
}

/// A mouse click with a frame between down and up, as in a browser: the overlay must not close
/// on pointer down (it lives in the Overlay, outside the field's own tap region).
Future<void> _slowClick(WidgetTester tester, Finder finder) async {
  final gesture = await tester.startGesture(tester.getCenter(finder), kind: PointerDeviceKind.mouse);
  await tester.pump();
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('autocomplete: a mouse click on an option selects it', (tester) async {
    final field = StxField<int?>(null);
    await pumpHost(
      tester,
      SizedBox(
        width: 300,
        child: StxAutocomplete<int>(field: field, label: label, source: _Source()),
      ),
    );
    await _slowClick(tester, find.byType(EditableText));
    await tester.enterText(find.byType(EditableText), 'ca');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    await _slowClick(tester, find.text('Carcassonne'));
    expect(field.value, 2);
    expect(find.text('Catan'), findsNothing); // list closed
    expect(tester.widget<EditableText>(find.byType(EditableText)).controller.text, 'Carcassonne');
  });

  testWidgets('select: a mouse click on an option selects it', (tester) async {
    final field = StxField<String?>(null);
    await pumpHost(
      tester,
      SizedBox(
        width: 300,
        child: StxFormSelect<String>(
          field: field,
          label: label,
          options: const ['a', 'b'],
          optionLabel: (o) => o == 'a' ? label : hint,
        ),
      ),
    );
    await _slowClick(tester, find.byType(StxPressable).first);
    await _slowClick(tester, find.text('Hint'));
    expect(field.value, 'b');
  });

  testWidgets('a click outside closes the list', (tester) async {
    final field = StxField<String?>(null);
    await pumpHost(
      tester,
      Column(
        children: [
          SizedBox(
            width: 300,
            child: StxFormSelect<String>(field: field, label: label, options: const ['a'], optionLabel: (_) => hint),
          ),
          const ColoredBox(color: Color(0xFFFFFFFF), key: Key('outside'), child: SizedBox(height: 200, width: 300)),
        ],
      ),
    );
    await _slowClick(tester, find.byType(StxPressable).first);
    expect(find.text('Hint'), findsOneWidget);
    await _slowClick(tester, find.byKey(const Key('outside')));
    expect(find.text('Hint'), findsNothing);
    expect(field.value, isNull);
  });
}
