/// A semantic color. Widgets accept a [ColorToken], never a `Color`; the value comes from the
/// app's `stx.tokens.yaml` and depends on the theme mode.
///
/// Ids 0–31 are the fixed slots below; app tokens from `color.extend` are generated from 32
/// (`AppColor.win`).
extension type const ColorToken._(int id) implements Object {
  static const primary = ColorToken._(0);
  static const onPrimary = ColorToken._(1);
  static const secondary = ColorToken._(2);
  static const onSecondary = ColorToken._(3);
  static const success = ColorToken._(4);
  static const onSuccess = ColorToken._(5);
  static const warning = ColorToken._(6);
  static const onWarning = ColorToken._(7);
  static const danger = ColorToken._(8);
  static const onDanger = ColorToken._(9);
  static const background = ColorToken._(10);
  static const onBackground = ColorToken._(11);
  static const surface = ColorToken._(12);
  static const onSurface = ColorToken._(13);
  static const muted = ColorToken._(14);
  static const border = ColorToken._(15);
  static const focus = ColorToken._(16);
  static const transparent = ColorToken._(17);

  /// Number of fixed slots in use; the compiler fills exactly these.
  static const slots = 18;

  /// First id of app-specific tokens.
  static const firstExtension = 32;

  /// For generated code only (`AppColor` in lib/gen/style); the stx lints reject it elsewhere.
  const ColorToken.generated(int id) : this._(id);
}

/// Spacing scale (padding, margins, gaps).
enum SpaceToken { none, xs, sm, md, lg, xl, x2l, x3l }

/// Corner radius scale.
enum RadiusToken { none, sm, md, lg, full }

/// Text styles.
enum TextToken { header1, header2, header3, body, label, caption }

/// Responsive breakpoints; [base] applies below `sm`.
enum Breakpoint { base, sm, md, lg, xl }

/// Button styles. Ids 0–7 are fixed; app variants from `components.button.extend` start at 8.
extension type const ButtonVariant._(int id) implements Object {
  static const primary = ButtonVariant._(0);
  static const secondary = ButtonVariant._(1);
  static const danger = ButtonVariant._(2);
  static const ghost = ButtonVariant._(3);

  static const slots = 4;
  static const firstExtension = 8;

  /// For generated code only (`AppButton` in lib/gen/style).
  const ButtonVariant.generated(int id) : this._(id);
}
