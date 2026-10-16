import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// A value per breakpoint; unset breakpoints inherit from the next smaller one.
@immutable
final class Responsive<T extends Object> {
  const Responsive(this.base, {this.sm, this.md, this.lg, this.xl});

  final T base;
  final T? sm;
  final T? md;
  final T? lg;
  final T? xl;

  T resolve(Breakpoint breakpoint) => switch (breakpoint) {
    Breakpoint.base => base,
    Breakpoint.sm => sm ?? base,
    Breakpoint.md => md ?? sm ?? base,
    Breakpoint.lg => lg ?? md ?? sm ?? base,
    Breakpoint.xl => xl ?? lg ?? md ?? sm ?? base,
  };
}

@immutable
final class TextSpec {
  const TextSpec({required this.size, this.family, this.weight = 400, this.height, this.letterSpacing});

  final String? family;
  final double size;

  /// 100–900.
  final int weight;
  final double? height;
  final double? letterSpacing;

  TextStyle toStyle(Color color) => TextStyle(
    inherit: false,
    color: color,
    fontFamily: family,
    fontSize: size,
    fontWeight: FontWeight.values[(weight ~/ 100 - 1).clamp(0, 8)],
    height: height,
    letterSpacing: letterSpacing,
    decoration: TextDecoration.none,
    textBaseline: TextBaseline.alphabetic,
  );
}

@immutable
final class ButtonSpec {
  const ButtonSpec({
    required this.background,
    required this.foreground,
    this.border,
    this.padX = SpaceToken.md,
    this.padY = SpaceToken.sm,
    this.radius = RadiusToken.md,
    this.text = TextToken.label,
    this.minHeight = 40,
  });

  final ColorToken background;
  final ColorToken foreground;
  final ColorToken? border;
  final SpaceToken padX;
  final SpaceToken padY;
  final RadiusToken radius;
  final TextToken text;
  final double minHeight;
}

/// Inputs: text fields, selects, pickers.
@immutable
final class FieldSpec {
  const FieldSpec({
    this.background = ColorToken.surface,
    this.foreground = ColorToken.onSurface,
    this.placeholder = ColorToken.muted,
    this.border = ColorToken.border,
    this.borderFocus = ColorToken.focus,
    this.borderError = ColorToken.danger,
    this.padX = SpaceToken.md,
    this.padY = SpaceToken.sm,
    this.radius = RadiusToken.md,
    this.text = TextToken.body,
    this.label = TextToken.label,
    this.message = TextToken.caption,
    this.gap = SpaceToken.xs,
    this.borderWidth = 1,
  });

  final ColorToken background;
  final ColorToken foreground;
  final ColorToken placeholder;
  final ColorToken border;
  final ColorToken borderFocus;
  final ColorToken borderError;
  final SpaceToken padX;
  final SpaceToken padY;
  final RadiusToken radius;
  final TextToken text;
  final TextToken label;
  final TextToken message;

  /// Between label, input and message.
  final SpaceToken gap;
  final double borderWidth;
}

/// The keyboard focus indicator.
@immutable
final class FocusSpec {
  const FocusSpec({this.color = ColorToken.focus, this.width = 2, this.offset = 2});

  final ColorToken color;
  final double width;
  final double offset;
}
