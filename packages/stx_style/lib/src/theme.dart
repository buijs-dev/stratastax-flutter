import 'package:flutter/widgets.dart';

import 'stx_tokens.dart';
import 'tokens.dart';

enum StxThemeMode { system, light, dark }

/// Provides the tokens of the active mode. Dependents rebuild only when the mode (and thus the
/// token set) changes; reading a value is an index into a const list.
class StxTheme extends StatelessWidget {
  const StxTheme({
    super.key,
    required this.light,
    StxTokens? dark,
    this.mode = StxThemeMode.system,
    required this.child,
  }) : dark = dark ?? light;

  final StxTokens light;
  final StxTokens dark;
  final StxThemeMode mode;
  final Widget child;

  static StxTokens of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_ThemeInherited>();
    assert(scope != null, 'No StxTheme above this widget; StxApp adds one.');
    return scope!.tokens;
  }

  @override
  Widget build(BuildContext context) {
    final dark = switch (mode) {
      StxThemeMode.light => false,
      StxThemeMode.dark => true,
      StxThemeMode.system => MediaQuery.platformBrightnessOf(context) == Brightness.dark,
    };
    final tokens = dark ? this.dark : light;
    return _ThemeInherited(
      tokens: tokens,
      child: BreakpointScope(tokens: tokens, child: child),
    );
  }
}

class _ThemeInherited extends InheritedWidget {
  const _ThemeInherited({required this.tokens, required super.child});

  final StxTokens tokens;

  @override
  bool updateShouldNotify(_ThemeInherited oldWidget) => !identical(oldWidget.tokens, tokens);
}

/// Publishes the current [Breakpoint]. It listens to the screen width itself, but its dependents
/// only rebuild when the width crosses a breakpoint, not on every resize.
class BreakpointScope extends StatelessWidget {
  const BreakpointScope({super.key, required this.tokens, required this.child});

  final StxTokens tokens;
  final Widget child;

  static Breakpoint of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_BreakpointInherited>()?.breakpoint ?? Breakpoint.base;

  @override
  Widget build(BuildContext context) =>
      _BreakpointInherited(breakpoint: tokens.breakpointFor(MediaQuery.sizeOf(context).width), child: child);
}

class _BreakpointInherited extends InheritedWidget {
  const _BreakpointInherited({required this.breakpoint, required super.child});

  final Breakpoint breakpoint;

  @override
  bool updateShouldNotify(_BreakpointInherited oldWidget) => oldWidget.breakpoint != breakpoint;
}

extension StxThemeContext on BuildContext {
  StxTokens get tokens => StxTheme.of(this);

  Breakpoint get breakpoint => BreakpointScope.of(this);

  /// The [TextStyle] of [token] at the current breakpoint.
  TextStyle textStyle(TextToken token, {ColorToken color = ColorToken.onBackground}) =>
      tokens.textStyle(token, breakpoint, color: color);
}
