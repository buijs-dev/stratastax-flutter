import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:stx_compiler/stx_compiler.dart';
import 'package:test/test.dart';

final _defaults = File(
  p.join(Directory.current.path, '..', 'stx_style', 'lib', 'defaults', 'defaults.tokens.yaml'),
).readAsStringSync();

({StyleIR ir, Diagnostics diagnostics}) _parse(String app) {
  final diagnostics = Diagnostics();
  final ir = StyleFrontend(diagnostics).parseSource(_defaults, app);
  return (ir: ir, diagnostics: diagnostics);
}

void main() {
  test('the defaults alone are complete, valid and accessible', () {
    final parsed = _parse('{}');
    expect(parsed.diagnostics.all, isEmpty);
    expect(parsed.ir.modes, ['light', 'dark']);
    expect(parsed.ir.colors.keys, containsAll(colorSlots));
    expect(parsed.ir.buttons.keys, buttonSlots);
  });

  test('app values override defaults; refs resolve per mode', () {
    final parsed = _parse('''
primitives:
  palette:
    brand: { 500: '#6366F1', 600: '#4F46E5' }
color:
  primary: { light: '{palette.brand.600}', dark: '{palette.brand.500}' }
''');
    expect(parsed.ir.colors['primary'], {'light': 0xFF4F46E5, 'dark': 0xFF6366F1});
    // Untouched slots keep their default.
    expect(parsed.ir.colors['danger']!['light'], 0xFFDC2626);
  });

  test('hex forms: #RGB, #RRGGBB, #RRGGBBAA (alpha last, CSS order)', () {
    final parsed = _parse('''
color:
  extend:
    a: '#F00'
    b: '#00FF00'
    c: '#0000FF80'
''');
    expect(parsed.ir.colors['a']!['light'], 0xFFFF0000);
    expect(parsed.ir.colors['b']!['light'], 0xFF00FF00);
    expect(parsed.ir.colors['c']!['light'], 0x800000FF);
    expect(parsed.ir.colorExtensions, ['a', 'b', 'c']);
  });

  test('semantic colors can reference other semantic colors', () {
    final parsed = _parse('''
color:
  focus: '{color.primary}'
''');
    expect(parsed.ir.colors['focus'], parsed.ir.colors['primary']);
  });

  test('space is multiplied by the unit; responsive text sizes', () {
    final parsed = _parse('''
primitives:
  unit: 8
text:
  body: { size: { base: 15, md: 17 }, weight: 400 }
''');
    expect(parsed.ir.space['md'], 32);
    expect(parsed.ir.text['body']!.sizes, {'base': 15, 'md': 17});
  });

  test('unknown and cyclic references are errors (STX-S001)', () {
    expect(_parse("color: { primary: '{palette.nope.1}' }").diagnostics.all.map((d) => d.code), contains('STX-S001'));
    final cyclic = _parse('''
color:
  primary: '{color.secondary}'
  secondary: '{color.primary}'
''');
    expect(cyclic.diagnostics.all.where((d) => d.message.contains('cyclic')), isNotEmpty);
  });

  test('component tokens must exist', () {
    final parsed = _parse('''
components:
  button:
    primary: { background: brand }
''');
    expect(parsed.diagnostics.all.single.message, contains('unknown color token "brand"'));
  });

  test('invalid values are reported with their path', () {
    final parsed = _parse('''
color: { primary: 'blue' }
text: { body: { size: 16, weight: 450 } }
breakpoints: { sm: 800, md: 700 }
''');
    final messages = parsed.diagnostics.all.map((d) => '${d.location} ${d.message}').join('\n');
    expect(messages, contains('#color.primary invalid color "blue"'));
    expect(messages, contains('#text.body.weight weight must be'));
    expect(messages, contains('breakpoints must increase'));
  });

  test('low contrast is a warning (STX-S003)', () {
    final parsed = _parse('''
components:
  button:
    extend:
      faint: { background: background, foreground: border }
''');
    final warning = parsed.diagnostics.all.firstWhere((d) => d.code == 'STX-S003');
    expect(warning.isError, isFalse);
    expect(warning.location, contains('components.button.faint'));
  });

  test('renders const tokens, extensions and utilities', () {
    final parsed = _parse('''
modes: [light]
color:
  extend:
    win: '#15803D'
components:
  button:
    extend:
      win: { background: win, foreground: onPrimary }
''');
    final file = GeneratedFormatter().format(renderStyle(parsed.ir));
    expect(file.content, contains('const stxTokensLight = StxTokens('));
    expect(file.content, contains('const stxTokensDark = stxTokensLight;'));
    expect(file.content, contains('static const win = ColorToken.generated(32);'));
    expect(file.content, contains('static const win = ButtonVariant.generated(8);'));
    expect(file.content, contains('Color(0xFF15803D), // 32 win'));
    expect(file.content, contains('static const md = SizedBox.square(dimension: 16);'));
  });
}
