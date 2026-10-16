/// The style IR: resolved token values per mode, before rendering `lib/gen/style/tokens.g.dart`.
library;

/// The fixed color slots of stx_style, in `ColorToken` id order.
const colorSlots = [
  'primary', 'onPrimary', 'secondary', 'onSecondary', 'success', 'onSuccess', 'warning', 'onWarning', //
  'danger', 'onDanger', 'background', 'onBackground', 'surface', 'onSurface', 'muted', 'border', 'focus',
  'transparent',
];
const firstColorExtension = 32;

const spaceTokens = ['none', 'xs', 'sm', 'md', 'lg', 'xl', 'x2l', 'x3l'];
const radiusTokens = ['none', 'sm', 'md', 'lg', 'full'];
const textTokens = ['header1', 'header2', 'header3', 'body', 'label', 'caption'];
const breakpointTokens = ['sm', 'md', 'lg', 'xl'];
const responsiveKeys = ['base', 'sm', 'md', 'lg', 'xl'];

/// The fixed button variants, in `ButtonVariant` id order.
const buttonSlots = ['primary', 'secondary', 'danger', 'ghost'];
const firstButtonExtension = 8;

const modes = ['light', 'dark'];

final class TextIR {
  const TextIR({required this.sizes, this.family, this.weight = 400, this.height, this.letterSpacing});

  final String? family;
  final int weight;
  final double? height;
  final double? letterSpacing;

  /// By responsive key (`base` always present).
  final Map<String, double> sizes;
}

final class ButtonIR {
  const ButtonIR({
    required this.background,
    required this.foreground,
    this.border,
    required this.padX,
    required this.padY,
    required this.radius,
    required this.text,
    required this.minHeight,
  });

  /// Color token names (a slot or an extension).
  final String background;
  final String foreground;
  final String? border;
  final String padX;
  final String padY;
  final String radius;
  final String text;
  final double minHeight;
}

final class StyleIR {
  const StyleIR({
    required this.modes,
    required this.colors,
    required this.colorExtensions,
    required this.space,
    required this.radius,
    required this.breakpoints,
    required this.text,
    required this.buttons,
    required this.buttonExtensions,
    required this.field,
    required this.focus,
    required this.source,
  });

  /// `light`, optionally `dark`.
  final List<String> modes;

  /// Color name (slot or extension) → mode → ARGB.
  final Map<String, Map<String, int>> colors;

  /// Extension color names in declaration order (id = 32 + index).
  final List<String> colorExtensions;
  final Map<String, double> space;
  final Map<String, double> radius;

  /// sm, md, lg, xl lower bounds.
  final List<double> breakpoints;
  final Map<String, TextIR> text;

  /// Variant name (slot or extension) → spec.
  final Map<String, ButtonIR> buttons;
  final List<String> buttonExtensions;

  /// FieldSpec property → token name or number.
  final Map<String, Object> field;

  /// FocusSpec property → token name or number.
  final Map<String, Object> focus;
  final String source;

  Map<String, Object?> toJson() => {
    'modes': modes,
    'colors': {
      for (final e in colors.entries)
        e.key: {for (final m in e.value.entries) m.key: '#${m.value.toRadixString(16).padLeft(8, '0')}'},
    },
    'space': space,
    'radius': radius,
    'breakpoints': breakpoints,
    'buttons': [...buttons.keys],
  };
}
