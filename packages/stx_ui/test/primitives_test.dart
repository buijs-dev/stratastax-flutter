import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stx_i18n/stx_i18n.dart';
import 'package:stx_style/stx_style.dart';
import 'package:stx_ui/stx_ui.dart';

import 'support.dart';

void main() {
  group('StxText', () {
    testWidgets('resolves the message and the token style', (tester) async {
      await pumpHost(tester, const StxText(label, style: TextToken.header1, color: ColorToken.primary));
      final text = tester.widget<Text>(find.text('Label'));
      expect(text.style!.fontSize, 28);
      expect(text.style!.color, testTokens.color(ColorToken.primary));
    });

    testWidgets('header1 grows at the lg breakpoint', (tester) async {
      await pumpHost(tester, const StxText(label, style: TextToken.header1), size: const Size(1100, 800));
      expect(tester.widget<Text>(find.text('Label')).style!.fontSize, 36);
    });

    testWidgets('user data is shown as is', (tester) async {
      await pumpHost(tester, const StxText(Msg.data('Catan')));
      expect(find.text('Catan'), findsOneWidget);
    });
  });

  group('layout', () {
    testWidgets('StxColumn spaces children with the gap token', (tester) async {
      await pumpHost(
        tester,
        const SizedBox(
          width: 100,
          child: StxColumn(
            gap: SpaceToken.md,
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: 10, key: Key('a')),
              SizedBox(height: 10, key: Key('b')),
            ],
          ),
        ),
      );
      final a = tester.getBottomLeft(find.byKey(const Key('a')));
      final b = tester.getTopLeft(find.byKey(const Key('b')));
      expect(b.dy - a.dy, 16);
    });

    testWidgets('StxBox paints token background and padding', (tester) async {
      await pumpHost(
        tester,
        const StxBox(
          padding: StxInsets.symmetric(x: SpaceToken.lg, y: SpaceToken.sm),
          background: ColorToken.surface,
          radius: RadiusToken.md,
          child: SizedBox(width: 10, height: 10, key: Key('child')),
        ),
      );
      expect(decorationColor(tester, find.byKey(const Key('child'))), testTokens.color(ColorToken.surface));
      expect(tester.getSize(find.byType(StxBox)), const Size(10 + 48, 10 + 16));
    });
  });

  group('StxButton', () {
    testWidgets('variant colors come from the tokens', (tester) async {
      await pumpHost(tester, StxButton(label, onPressed: () {}, variant: ButtonVariant.danger));
      expect(decorationColor(tester, find.text('Label')), testTokens.color(ColorToken.danger));
      expect(tester.widget<Text>(find.text('Label')).style!.color, testTokens.color(ColorToken.onDanger));
      expect(tester.getSize(find.byType(StxButton)).height, greaterThanOrEqualTo(40));
    });

    testWidgets('tap and keyboard activate it', (tester) async {
      var presses = 0;
      await pumpHost(tester, StxButton(label, onPressed: () => presses++));
      await tester.tap(find.byType(StxButton));
      expect(presses, 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(presses, 2);
    });

    testWidgets('disabled and busy buttons ignore presses', (tester) async {
      await pumpHost(tester, const StxButton(label, onPressed: null));
      expect(tester.widget<Opacity>(find.byType(Opacity).first).opacity, 0.5);

      var presses = 0;
      await pumpHost(tester, StxButton(label, onPressed: () => presses++, busy: true));
      await tester.tap(find.byType(StxButton));
      expect(presses, 0);
      expect(find.text('Loading'), findsOneWidget);
    });

    testWidgets('exposes button semantics with its label', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpHost(tester, StxButton(label, onPressed: () {}));
      expect(
        tester.getSemantics(find.byType(StxButton)),
        matchesSemantics(
          isButton: true,
          label: 'Label',
          hasTapAction: true,
          isEnabled: true,
          hasEnabledState: true,
          isFocusable: true,
          hasFocusAction: true,
        ),
      );
      handle.dispose();
    });
  });

  group('StxTextField', () {
    testWidgets('typing updates the controller; hint hides', (tester) async {
      final controller = TextEditingController();
      final changes = <String>[];
      await pumpHost(
        tester,
        SizedBox(
          width: 300,
          child: StxTextField(controller: controller, label: label, hint: hint, onChanged: changes.add),
        ),
      );
      expect(find.text('Hint'), findsOneWidget);
      await tester.tap(find.byType(StxTextField));
      await tester.enterText(find.byType(EditableText), 'Catan');
      await tester.pump();
      expect(controller.text, 'Catan');
      expect(changes.last, 'Catan');
      expect(find.text('Hint'), findsNothing);
    });

    testWidgets('error replaces help and colors the border', (tester) async {
      await pumpHost(
        tester,
        const SizedBox(
          width: 300,
          child: StxTextField(label: label, error: StxKeys.validationRequired, required: true),
        ),
      );
      expect(find.text('Label *'), findsOneWidget);
      expect(find.text('Required'), findsOneWidget);
      final box = tester.widget<DecoratedBox>(
        find.descendant(of: find.byType(StxInputBox), matching: find.byType(DecoratedBox)).first,
      );
      final border = (box.decoration as BoxDecoration).border! as Border;
      expect(border.top.color, testTokens.color(ColorToken.danger));
    });

    testWidgets('focus thickens the border with the focus color', (tester) async {
      final focus = FocusNode();
      await pumpHost(tester, SizedBox(width: 300, child: StxTextField(focusNode: focus)));
      focus.requestFocus();
      await tester.pump(); // focus change is delivered in a microtask…
      await tester.pump(); // …and the field rebuilds in the next frame
      final box = tester.widget<DecoratedBox>(
        find.descendant(of: find.byType(StxInputBox), matching: find.byType(DecoratedBox)).first,
      );
      final border = (box.decoration as BoxDecoration).border! as Border;
      expect(border.top.color, testTokens.color(ColorToken.focus));
      expect(border.top.width, 2);
      focus.dispose();
    });
  });
}
