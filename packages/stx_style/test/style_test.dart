import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stx_style/stx_style.dart';

const _light = StxTokens(
  colors: [Color(0xFF000001), Color(0xFF000002)],
  space: [0, 4, 8, 16, 24, 32, 48, 64],
  radius: [0, 4, 8, 16, 9999],
  breakpoints: [640, 768, 1024, 1280],
  text: [
    Responsive(TextSpec(size: 28, weight: 700), lg: TextSpec(size: 36, weight: 700)),
    Responsive(TextSpec(size: 22)),
    Responsive(TextSpec(size: 18)),
    Responsive(TextSpec(size: 16)),
    Responsive(TextSpec(size: 14)),
    Responsive(TextSpec(size: 12)),
  ],
  buttons: [],
);
const _dark = StxTokens(
  colors: [Color(0xFF0000FF)],
  space: [0, 4, 8, 16, 24, 32, 48, 64],
  radius: [0, 4, 8, 16, 9999],
  breakpoints: [640, 768, 1024, 1280],
  text: [],
  buttons: [],
);

void main() {
  test('responsive values inherit from smaller breakpoints', () {
    const r = Responsive(1, md: 3);
    expect([for (final b in Breakpoint.values) r.resolve(b)], [1, 1, 3, 3, 3]);
  });

  test('breakpointFor', () {
    expect(_light.breakpointFor(320), Breakpoint.base);
    expect(_light.breakpointFor(640), Breakpoint.sm);
    expect(_light.breakpointFor(1100), Breakpoint.lg);
    expect(_light.breakpointFor(2000), Breakpoint.xl);
  });

  test('text styles resolve weight, size and color', () {
    final style = _light.textStyle(TextToken.header1, Breakpoint.lg, color: ColorToken.onPrimary);
    expect(style.fontSize, 36);
    expect(style.fontWeight, FontWeight.w700);
    expect(style.color, const Color(0xFF000002));
    expect(style.inherit, isFalse);
  });

  testWidgets('theme follows the platform brightness in system mode', (tester) async {
    late StxTokens seen;
    Widget app() => StxTheme(
      light: _light,
      dark: _dark,
      child: Builder(
        builder: (context) {
          seen = StxTheme.of(context);
          return const SizedBox();
        },
      ),
    );
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(platformBrightness: Brightness.dark),
        child: app(),
      ),
    );
    expect(identical(seen, _dark), isTrue);
  });

  testWidgets('breakpoint dependents rebuild only when a breakpoint is crossed', (tester) async {
    var builds = 0;
    final child = Builder(
      builder: (context) {
        BreakpointScope.of(context);
        builds++;
        return const SizedBox();
      },
    );
    Widget at(double width) => MediaQuery(
      data: MediaQueryData(size: Size(width, 800)),
      child: StxTheme(light: _light, mode: StxThemeMode.light, child: child),
    );
    await tester.pumpWidget(at(1100));
    await tester.pumpWidget(at(1150));
    await tester.pumpWidget(at(1200));
    expect(builds, 1);
    await tester.pumpWidget(at(1300));
    expect(builds, 2);
  });
}
