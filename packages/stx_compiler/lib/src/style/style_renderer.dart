import '../naming.dart';
import '../output.dart';
import 'style_ir.dart';

/// Renders `style/tokens.g.dart`: a const `StxTokens` per mode, `AppColor` / `AppButton` for app
/// extensions and the const utilities `Gaps` and `Pad`.
GeneratedFile renderStyle(StyleIR ir) {
  final b = StringBuffer()
    ..writeln(generatedHeader)
    ..writeln('// Source: ${ir.source} + stx_style defaults')
    ..writeln()
    ..writeln("import 'package:flutter/widgets.dart';")
    ..writeln("import 'package:stx_style/stx_style.dart';")
    ..writeln();

  for (final mode in ir.modes) {
    b
      ..writeln('/// ${Naming.pascal(mode)} mode.')
      ..writeln('const stxTokens${Naming.pascal(mode)} = StxTokens(')
      ..writeln('  colors: [');
    final total = ir.colorExtensions.isEmpty ? colorSlots.length : firstColorExtension + ir.colorExtensions.length;
    for (var id = 0; id < total; id++) {
      final name = id < colorSlots.length
          ? colorSlots[id]
          : (id >= firstColorExtension ? ir.colorExtensions[id - firstColorExtension] : null);
      if (name == null) {
        b.writeln('    Color(0x00000000), // $id (unused)');
      } else {
        b.writeln('    Color(${_hex(ir.colors[name]![mode]!)}), // $id $name');
      }
    }
    b
      ..writeln('  ],')
      ..writeln('  space: [${spaceTokens.map((t) => _num(ir.space[t]!)).join(', ')}],')
      ..writeln('  radius: [${radiusTokens.map((t) => _num(ir.radius[t]!)).join(', ')}],')
      ..writeln('  breakpoints: [${ir.breakpoints.map(_num).join(', ')}],')
      ..writeln('  text: [');
    for (final name in textTokens) {
      final t = ir.text[name]!;
      final named = [
        for (final key in responsiveKeys.skip(1))
          if (t.sizes[key] case final size?) '$key: ${_textSpec(t, size)}',
      ];
      b.writeln('    Responsive(${[_textSpec(t, t.sizes['base']!), ...named].join(', ')}), // $name');
    }
    b
      ..writeln('  ],')
      ..writeln('  buttons: [');
    final buttonTotal = ir.buttonExtensions.isEmpty
        ? buttonSlots.length
        : firstButtonExtension + ir.buttonExtensions.length;
    for (var id = 0; id < buttonTotal; id++) {
      final name = id < buttonSlots.length
          ? buttonSlots[id]
          : (id >= firstButtonExtension ? ir.buttonExtensions[id - firstButtonExtension] : buttonSlots.first);
      final unused = id >= buttonSlots.length && id < firstButtonExtension;
      b.writeln('    ${_button(ir.buttons[name]!, ir)}, // $id ${unused ? '(unused)' : name}');
    }
    b
      ..writeln('  ],')
      ..writeln('  field: ${_spec('FieldSpec', ir.field, _fieldKinds, ir)},')
      ..writeln('  focus: ${_spec('FocusSpec', ir.focus, _focusKinds, ir)},')
      ..writeAll([
        for (final e in componentKinds.entries)
          '  ${e.key}: ${_spec(componentSpecType(e.key), ir.components[e.key] ?? const {}, e.value, ir)},\n',
      ])
      ..writeln(');')
      ..writeln();
  }
  if (!ir.modes.contains('dark')) {
    b
      ..writeln('/// No dark mode in stx.tokens.yaml: dark uses the light tokens.')
      ..writeln('const stxTokensDark = stxTokensLight;')
      ..writeln();
  }

  if (ir.colorExtensions.isNotEmpty) {
    b.writeln('/// App colors from `color.extend`; usable wherever a [ColorToken] is accepted.');
    b.writeln('abstract final class AppColor {');
    for (var i = 0; i < ir.colorExtensions.length; i++) {
      b.writeln('  static const ${ir.colorExtensions[i]} = ColorToken.generated(${firstColorExtension + i});');
    }
    b
      ..writeln('}')
      ..writeln();
  }
  if (ir.buttonExtensions.isNotEmpty) {
    b.writeln('/// App button variants from `components.button.extend`.');
    b.writeln('abstract final class AppButton {');
    for (var i = 0; i < ir.buttonExtensions.length; i++) {
      b.writeln('  static const ${ir.buttonExtensions[i]} = ButtonVariant.generated(${firstButtonExtension + i});');
    }
    b
      ..writeln('}')
      ..writeln();
  }

  b.writeln('/// Const gaps of the spacing scale; no theme lookup needed (geometry does not depend on the mode).');
  b.writeln('abstract final class Gaps {');
  for (final t in spaceTokens.skip(1)) {
    b.writeln('  static const $t = SizedBox.square(dimension: ${_num(ir.space[t]!)});');
  }
  b
    ..writeln('}')
    ..writeln()
    ..writeln('/// Const insets of the spacing scale.')
    ..writeln('abstract final class Pad {');
  for (final t in spaceTokens.skip(1)) {
    b.writeln('  static const $t = EdgeInsets.all(${_num(ir.space[t]!)});');
  }
  b.writeln('}');
  return GeneratedFile('style/tokens.g.dart', b.toString());
}

const _fieldKinds = {
  'background': 'color',
  'foreground': 'color',
  'placeholder': 'color',
  'border': 'color',
  'borderFocus': 'color',
  'borderError': 'color',
  'padX': 'space',
  'padY': 'space',
  'radius': 'radius',
  'text': 'text',
  'label': 'text',
  'message': 'text',
  'gap': 'space',
  'borderWidth': 'number',
};

const _focusKinds = {'color': 'color', 'width': 'number', 'offset': 'number'};

String _spec(String type, Map<String, Object> values, Map<String, String> kinds, StyleIR ir) {
  final args = [
    for (final e in kinds.entries)
      if (values[e.key] case final value?) '${e.key}: ${_value(e.value, value, ir)}',
  ];
  return '$type(${args.join(', ')})';
}

String _value(String kind, Object value, StyleIR ir) => switch (kind) {
  'color' => _colorRef(value.toString(), ir),
  'space' => 'SpaceToken.$value',
  'radius' => 'RadiusToken.$value',
  'text' => 'TextToken.$value',
  _ => _num(value as num),
};

String _colorRef(String name, StyleIR ir) => colorSlots.contains(name)
    ? 'ColorToken.$name'
    : 'ColorToken.generated(${firstColorExtension + ir.colorExtensions.indexOf(name)})';

String _button(ButtonIR spec, StyleIR ir) => [
  'ButtonSpec(background: ${_colorRef(spec.background, ir)}',
  'foreground: ${_colorRef(spec.foreground, ir)}',
  if (spec.border case final border?) 'border: ${_colorRef(border, ir)}',
  'padX: SpaceToken.${spec.padX}',
  'padY: SpaceToken.${spec.padY}',
  'radius: RadiusToken.${spec.radius}',
  'text: TextToken.${spec.text}',
  'minHeight: ${_num(spec.minHeight)})',
].join(', ');

String _textSpec(TextIR t, double size) => [
  'TextSpec(size: ${_num(size)}',
  if (t.family case final family?) 'family: ${Naming.stringLiteral(family)}',
  if (t.weight != 400) 'weight: ${t.weight}',
  if (t.height case final height?) 'height: ${_num(height)}',
  if (t.letterSpacing case final spacing?) 'letterSpacing: ${_num(spacing)}',
].join(', ').replaceFirst(RegExp(r'$'), ')');

String _hex(int argb) => '0x${argb.toRadixString(16).padLeft(8, '0').toUpperCase()}';

String _num(num value) => value == value.roundToDouble() ? '${value.round()}' : '$value';
