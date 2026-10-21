import 'package:flutter/widgets.dart';

import 'stx_tokens.dart';
import 'tokens.dart';

enum StxThemeMode { system, light, dark }

/// Remembers the user's theme choice; e.g. backed by shared preferences or local storage.
abstract interface class ThemeModeStore {
  StxThemeMode? read();

  void write(StxThemeMode mode);
}

/// Provides the tokens of the active mode. Dependents rebuild only when the mode (and thus the
/// token set) changes; reading a value is an index into a const list.
///
/// The mode starts as the one in [store], else [mode]; [setMode] switches it and remembers it.
class StxTheme extends StatefulWidget {
  const StxTheme({
    super.key,
    required this.light,
    StxTokens? dark,
    this.mode = StxThemeMode.system,
    this.store,
    required this.child,
  }) : dark = dark ?? light;

  final StxTokens light;
  final StxTokens dark;
  final StxThemeMode mode;
  final ThemeModeStore? store;
  final Widget child;

  static StxTokens of(BuildContext context) => _scope(context).tokens;

  /// The selected mode (may be [StxThemeMode.system]).
  static StxThemeMode modeOf(BuildContext context) => _scope(context).mode;

  /// Whether the dark tokens are active, also when the mode follows the system.
  static bool isDarkOf(BuildContext context) => _scope(context).dark;

  /// Switches the mode of the app and remembers it.
  static void setMode(BuildContext context, StxThemeMode mode) =>
      context.findAncestorStateOfType<_StxThemeState>()!._select(mode);

  static _ThemeInherited _scope(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_ThemeInherited>();
    assert(scope != null, 'No StxTheme above this widget; StxApp adds one.');
    return scope!;
  }

  @override
  State<StxTheme> createState() => _StxThemeState();
}

class _StxThemeState extends State<StxTheme> {
  late StxThemeMode _mode = widget.store?.read() ?? widget.mode;

  @override
  void didUpdateWidget(StxTheme oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode) _mode = widget.mode;
  }

  void _select(StxThemeMode mode) {
    widget.store?.write(mode);
    if (mode != _mode) setState(() => _mode = mode);
  }

  @override
  Widget build(BuildContext context) {
    final dark = switch (_mode) {
      StxThemeMode.light => false,
      StxThemeMode.dark => true,
      StxThemeMode.system => MediaQuery.platformBrightnessOf(context) == Brightness.dark,
    };
    final tokens = dark ? widget.dark : widget.light;
    return _ThemeInherited(
      tokens: tokens,
      mode: _mode,
      dark: dark,
      child: BreakpointScope(tokens: tokens, child: widget.child),
    );
  }
}

class _ThemeInherited extends InheritedWidget {
  const _ThemeInherited({required this.tokens, required this.mode, required this.dark, required super.child});

  final StxTokens tokens;
  final StxThemeMode mode;
  final bool dark;

  @override
  bool updateShouldNotify(_ThemeInherited oldWidget) =>
      !identical(oldWidget.tokens, tokens) || oldWidget.mode != mode || oldWidget.dark != dark;
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
