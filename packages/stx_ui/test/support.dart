import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stx_i18n/stx_i18n.dart';
import 'package:stx_style/stx_style.dart';
import 'package:stx_ui/testing.dart';

/// Distinct colors per slot so tests can tell which token was used.
const testTokens = StxTokens(
  colors: [
    Color(0xFF000000), // primary
    Color(0xFF000001), // onPrimary
    Color(0xFF000002), // secondary
    Color(0xFF000003), // onSecondary
    Color(0xFF000004), // success
    Color(0xFF000005), // onSuccess
    Color(0xFF000006), // warning
    Color(0xFF000007), // onWarning
    Color(0xFF000008), // danger
    Color(0xFF000009), // onDanger
    Color(0xFF00000A), // background
    Color(0xFF00000B), // onBackground
    Color(0xFF00000C), // surface
    Color(0xFF00000D), // onSurface
    Color(0xFF00000E), // muted
    Color(0xFF00000F), // border
    Color(0xFF000010), // focus
    Color(0x00000000), // transparent
  ],
  space: [0, 4, 8, 16, 24, 32, 48, 64],
  radius: [0, 4, 8, 16, 9999],
  breakpoints: [640, 768, 1024, 1280],
  text: [
    Responsive(TextSpec(size: 28, weight: 700), lg: TextSpec(size: 36, weight: 700)),
    Responsive(TextSpec(size: 22, weight: 700)),
    Responsive(TextSpec(size: 18, weight: 600)),
    Responsive(TextSpec(size: 16)),
    Responsive(TextSpec(size: 14, weight: 500)),
    Responsive(TextSpec(size: 12)),
  ],
  buttons: [
    ButtonSpec(background: ColorToken.primary, foreground: ColorToken.onPrimary),
    ButtonSpec(background: ColorToken.surface, foreground: ColorToken.primary, border: ColorToken.border),
    ButtonSpec(background: ColorToken.danger, foreground: ColorToken.onDanger),
    ButtonSpec(background: ColorToken.transparent, foreground: ColorToken.primary),
  ],
);

const label = MsgKey('test.label');
const hint = MsgKey('test.hint');

final testMessages = MapMessages({
  StxKeys.validationRequired.name: 'Required',
  StxKeys.stateLoading.name: 'Loading',
  'stx.validation.minItems': 'Choose at least {min}',
  'test.label': 'Label',
  'test.hint': 'Hint',
});

Future<void> pumpHost(WidgetTester tester, Widget child, {Size size = const Size(800, 600)}) async {
  await tester.pumpWidget(StxTestHost(tokens: testTokens, messages: testMessages, size: size, child: child));
  await tester.pump();
}

/// The color of the nearest [DecoratedBox] above [finder].
Color? decorationColor(WidgetTester tester, Finder finder) {
  final box = tester.widget<DecoratedBox>(find.ancestor(of: finder, matching: find.byType(DecoratedBox)).first);
  return (box.decoration as BoxDecoration).color;
}
