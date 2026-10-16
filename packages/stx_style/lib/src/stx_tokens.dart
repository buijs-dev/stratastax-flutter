import 'package:flutter/widgets.dart';

import 'specs.dart';
import 'tokens.dart';

/// All resolved token values of one theme mode; generated from `stx.tokens.yaml` as
/// `const stxTokensLight` / `stxTokensDark`. Every lookup is an index into a const list.
@immutable
final class StxTokens {
  const StxTokens({
    required this.colors,
    required this.space,
    required this.radius,
    required this.breakpoints,
    required this.text,
    required this.buttons,
    this.field = const FieldSpec(),
    this.focus = const FocusSpec(),
  });

  /// By [ColorToken] id; gaps between the fixed slots and extensions are unused.
  final List<Color> colors;

  /// By [SpaceToken.index], in logical pixels.
  final List<double> space;

  /// By [RadiusToken.index].
  final List<double> radius;

  /// Lower bounds of `sm`, `md`, `lg`, `xl` in logical pixels.
  final List<double> breakpoints;

  /// By [TextToken.index].
  final List<Responsive<TextSpec>> text;

  /// By [ButtonVariant] id.
  final List<ButtonSpec> buttons;
  final FieldSpec field;
  final FocusSpec focus;

  Color color(ColorToken token) => colors[token.id];

  double spacing(SpaceToken token) => space[token.index];

  double corner(RadiusToken token) => radius[token.index];

  ButtonSpec button(ButtonVariant variant) => buttons[variant.id];

  TextStyle textStyle(TextToken token, Breakpoint breakpoint, {ColorToken color = ColorToken.onBackground}) =>
      text[token.index].resolve(breakpoint).toStyle(colors[color.id]);

  Breakpoint breakpointFor(double width) {
    for (var i = breakpoints.length - 1; i >= 0; i--) {
      if (width >= breakpoints[i]) return Breakpoint.values[i + 1];
    }
    return Breakpoint.base;
  }
}
