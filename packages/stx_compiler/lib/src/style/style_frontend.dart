import 'dart:io';
import 'dart:math' as math;

import 'package:yaml/yaml.dart';

import '../diagnostics.dart';
import '../naming.dart';
import 'style_ir.dart';

/// Diagnostic codes of the style stage.
abstract final class StyleCodes {
  /// Unknown or cyclic token reference.
  static const reference = 'STX-S001';

  /// A required slot has no value (neither in the app nor in the defaults), or a value is invalid.
  static const missing = 'STX-S002';

  /// Insufficient contrast (warning).
  static const contrast = 'STX-S003';
}

/// Parses the framework defaults and the app's `stx.tokens.yaml` into a [StyleIR]. The app
/// overrides the defaults key by key; references (`{palette.blue.700}`) are resolved after merging.
final class StyleFrontend {
  StyleFrontend(this.diagnostics);

  final Diagnostics diagnostics;
  late Map<String, Object?> _root;
  late String _source;

  StyleIR? parseFiles({required String defaults, String? app, String? displayApp}) {
    final base = _load(defaults, 'stx_style defaults');
    if (base == null) return null;
    final overrides = app == null ? const <String, Object?>{} : _load(app, displayApp ?? app);
    if (overrides == null) return null;
    return parse(base, overrides, source: displayApp ?? 'stx_style defaults');
  }

  StyleIR parseSource(String defaults, String app, {String source = 'stx.tokens.yaml'}) =>
      parse(_plainMap(loadYaml(defaults)), _plainMap(loadYaml(app)), source: source);

  StyleIR parse(Map<String, Object?> defaults, Map<String, Object?> app, {required String source}) {
    _root = _merge(defaults, app);
    _source = source;

    final modeList = [
      for (final m in (_root['modes'] as List?) ?? const ['light']) m.toString(),
    ];
    for (final m in modeList) {
      if (!modes.contains(m)) _error(StyleCodes.missing, 'modes', 'unknown mode "$m" (supported: ${modes.join(', ')})');
    }
    if (!modeList.contains('light')) _error(StyleCodes.missing, 'modes', 'the "light" mode is required');
    final activeModes = [
      for (final m in modes)
        if (modeList.contains(m)) m,
    ];

    // Colors
    final colorNode = _map(_root['color']);
    final extensions = _map(colorNode['extend']);
    final colors = <String, Map<String, int>>{};
    for (final name in [...colorSlots, ...extensions.keys]) {
      final value = extensions.containsKey(name) ? extensions[name] : colorNode[name];
      final path = extensions.containsKey(name) ? 'color.extend.$name' : 'color.$name';
      if (value == null) {
        _error(StyleCodes.missing, path, 'no value for color "$name"');
        continue;
      }
      colors[name] = {
        for (final mode in activeModes)
          mode: _color(value is Map ? (value[mode] ?? value['light']) : value, path, mode) ?? 0,
      };
    }

    // Scales
    final unit = _number(_map(_root['primitives'])['unit'] ?? 4, 'primitives.unit') ?? 4;
    final space = _scale('space', spaceTokens, multiplier: unit);
    final radius = _scale('radius', radiusTokens);
    final breakpointScale = _scale('breakpoints', breakpointTokens);
    final breakpoints = [for (final b in breakpointTokens) breakpointScale[b] ?? 0];
    for (var i = 1; i < breakpoints.length; i++) {
      if (breakpoints[i] <= breakpoints[i - 1]) {
        _error(StyleCodes.missing, 'breakpoints', 'breakpoints must increase: ${breakpointTokens.join(' < ')}');
      }
    }

    // Text
    final fonts = _map(_map(_root['primitives'])['font']);
    final text = <String, TextIR>{};
    for (final name in textTokens) {
      final node = _map(_map(_root['text'])[name]);
      final path = 'text.$name';
      if (node.isEmpty) {
        _error(StyleCodes.missing, path, 'no text style "$name"');
        continue;
      }
      final familyKey = node['family']?.toString();
      final family = familyKey == null
          ? null
          : (fonts.containsKey(familyKey) ? fonts[familyKey]?.toString() : familyKey);
      final size = node['size'];
      final sizes = <String, double>{};
      if (size is Map) {
        for (final e in size.entries) {
          final key = e.key.toString();
          if (!responsiveKeys.contains(key)) {
            _error(StyleCodes.missing, '$path.size', 'unknown breakpoint "$key" (use ${responsiveKeys.join(', ')})');
          } else {
            sizes[key] = _number(e.value, '$path.size.$key') ?? 14;
          }
        }
        if (!sizes.containsKey('base')) _error(StyleCodes.missing, '$path.size', 'a responsive size needs "base"');
      } else {
        sizes['base'] = _number(size, '$path.size') ?? 14;
      }
      final weight = (_number(node['weight'] ?? 400, '$path.weight') ?? 400).round();
      if (weight < 100 || weight > 900 || weight % 100 != 0) {
        _error(StyleCodes.missing, '$path.weight', 'weight must be 100, 200, … 900');
      }
      text[name] = TextIR(
        family: family,
        weight: weight,
        height: node['lineHeight'] == null ? null : _number(node['lineHeight'], '$path.lineHeight'),
        letterSpacing: node['letterSpacing'] == null ? null : _number(node['letterSpacing'], '$path.letterSpacing'),
        sizes: sizes,
      );
    }

    // Components
    final components = _map(_root['components']);
    final buttonNode = _map(components['button']);
    final buttonBase = _map(buttonNode['base']);
    final buttonExtensions = _map(buttonNode['extend']);
    final buttons = <String, ButtonIR>{};
    for (final name in [...buttonSlots, ...buttonExtensions.keys]) {
      final own = buttonExtensions.containsKey(name) ? buttonExtensions[name] : buttonNode[name];
      final path = buttonExtensions.containsKey(name) ? 'components.button.extend.$name' : 'components.button.$name';
      if (own == null) {
        _error(StyleCodes.missing, path, 'no button variant "$name"');
        continue;
      }
      final spec = _merge(buttonBase, _map(own));
      final padding = _map(spec['padding']);
      buttons[name] = ButtonIR(
        background: _token(spec['background'], colors.keys, '$path.background', 'color') ?? 'primary',
        foreground: _token(spec['foreground'], colors.keys, '$path.foreground', 'color') ?? 'onPrimary',
        border: spec['border'] == null ? null : _token(spec['border'], colors.keys, '$path.border', 'color'),
        padX: _token(padding['x'] ?? 'md', spaceTokens, '$path.padding.x', 'space') ?? 'md',
        padY: _token(padding['y'] ?? 'sm', spaceTokens, '$path.padding.y', 'space') ?? 'sm',
        radius: _token(spec['radius'] ?? 'md', radiusTokens, '$path.radius', 'radius') ?? 'md',
        text: _token(spec['text'] ?? 'label', textTokens, '$path.text', 'text') ?? 'label',
        minHeight: _number(spec['minHeight'] ?? 40, '$path.minHeight') ?? 40,
      );
    }

    final fieldNode = _map(components['field']);
    final fieldPadding = _map(fieldNode['padding']);
    final field = <String, Object>{
      for (final key in ['background', 'foreground', 'placeholder', 'border', 'borderFocus', 'borderError'])
        if (fieldNode[key] != null)
          key: _token(fieldNode[key], colors.keys, 'components.field.$key', 'color') ?? 'border',
      if (fieldPadding['x'] != null)
        'padX': _token(fieldPadding['x'], spaceTokens, 'components.field.padding.x', 'space') ?? 'md',
      if (fieldPadding['y'] != null)
        'padY': _token(fieldPadding['y'], spaceTokens, 'components.field.padding.y', 'space') ?? 'sm',
      if (fieldNode['radius'] != null)
        'radius': _token(fieldNode['radius'], radiusTokens, 'components.field.radius', 'radius') ?? 'md',
      for (final key in ['text', 'label', 'message'])
        if (fieldNode[key] != null) key: _token(fieldNode[key], textTokens, 'components.field.$key', 'text') ?? 'body',
      if (fieldNode['gap'] != null)
        'gap': _token(fieldNode['gap'], spaceTokens, 'components.field.gap', 'space') ?? 'xs',
      if (fieldNode['borderWidth'] != null)
        'borderWidth': _number(fieldNode['borderWidth'], 'components.field.borderWidth') ?? 1,
    };

    final focusNode = _map(components['focus']);
    final focus = <String, Object>{
      if (focusNode['color'] != null)
        'color': _token(focusNode['color'], colors.keys, 'components.focus.color', 'color') ?? 'focus',
      if (focusNode['width'] != null) 'width': _number(focusNode['width'], 'components.focus.width') ?? 2,
      if (focusNode['offset'] != null) 'offset': _number(focusNode['offset'], 'components.focus.offset') ?? 2,
    };

    final ir = StyleIR(
      modes: activeModes,
      colors: colors,
      colorExtensions: [...extensions.keys],
      space: space,
      radius: radius,
      breakpoints: breakpoints,
      text: text,
      buttons: buttons,
      buttonExtensions: [...buttonExtensions.keys],
      field: field,
      focus: focus,
      source: source,
    );
    _checkContrast(ir);
    _checkNames(ir);
    return ir;
  }

  // ---------------------------------------------------------------------------------------------

  /// Resolves a color value: `#RGB`, `#RRGGBB`, `#RRGGBBAA` or a `{path.to.value}` reference.
  int? _color(Object? value, String path, String mode, [Set<String> seen = const {}]) {
    if (value == null) {
      _error(StyleCodes.missing, path, 'no value for mode "$mode"');
      return null;
    }
    final text = value.toString().trim();
    final ref = RegExp(r'^\{([^}]+)\}$').firstMatch(text);
    if (ref != null) {
      final target = ref[1]!;
      if (seen.contains(target)) {
        _error(StyleCodes.reference, path, 'cyclic reference via {$target}');
        return null;
      }
      final resolved = _lookup(target);
      if (resolved == _missing) {
        _error(StyleCodes.reference, path, 'unknown reference {$target}');
        return null;
      }
      final next = resolved is Map ? (resolved[mode] ?? resolved['light']) : resolved;
      return _color(next, path, mode, {...seen, target});
    }
    final hex = RegExp(r'^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$').firstMatch(text);
    if (hex == null) {
      _error(StyleCodes.missing, path, 'invalid color "$text" (use #RRGGBB, #RRGGBBAA or {palette.x.y})');
      return null;
    }
    var digits = hex[1]!;
    if (digits.length == 3) digits = digits.split('').map((c) => '$c$c').join();
    final rgb = int.parse(digits.substring(0, 6), radix: 16);
    final alpha = digits.length == 8 ? int.parse(digits.substring(6), radix: 16) : 0xFF;
    return (alpha << 24) | rgb;
  }

  static const _missing = Object();

  /// Looks up `palette.blue.700` in `primitives`, or `color.primary` from the root.
  Object? _lookup(String path) {
    final segments = path.split('.');
    Object? node = segments.first == 'color' ? _root : _map(_root['primitives']);
    for (final segment in segments) {
      if (node is! Map || !node.containsKey(segment)) return _missing;
      node = node[segment];
    }
    return node;
  }

  Map<String, double> _scale(String section, List<String> names, {double multiplier = 1}) {
    final node = _map(_root[section]);
    return {
      for (final name in names)
        name: node.containsKey(name)
            ? (_number(node[name], '$section.$name') ?? 0) * multiplier
            : () {
                _error(StyleCodes.missing, '$section.$name', 'no value for "$name"');
                return 0.0;
              }(),
    };
  }

  String? _token(Object? value, Iterable<String> allowed, String path, String kind) {
    final name = value?.toString();
    if (name != null && allowed.contains(name)) return name;
    _error(StyleCodes.reference, path, 'unknown $kind token "$name" (one of: ${allowed.join(', ')})');
    return null;
  }

  double? _number(Object? value, String path) {
    if (value is num) return value.toDouble();
    _error(StyleCodes.missing, path, 'expected a number, got "$value"');
    return null;
  }

  void _checkContrast(StyleIR ir) {
    for (final mode in ir.modes) {
      int color(String name) =>
          name == 'transparent' ? ir.colors['background']![mode]! : ir.colors[name]?[mode] ?? 0xFF000000;
      void check(String what, String fg, String bg) {
        final ratio = contrastRatio(color(fg), color(bg));
        if (ratio < 4.5) {
          diagnostics.warning(
            StyleCodes.contrast,
            'contrast ${ratio.toStringAsFixed(2)}:1 between $fg and $bg in $mode mode (WCAG AA needs 4.5:1)',
            location: '$_source#$what',
          );
        }
      }

      for (final e in ir.buttons.entries) {
        check('components.button.${e.key}', e.value.foreground, e.value.background);
      }
      check('components.field', '${ir.field['foreground'] ?? 'onSurface'}', '${ir.field['background'] ?? 'surface'}');
      check('color.onBackground', 'onBackground', 'background');
      check('color.onSurface', 'onSurface', 'surface');
    }
  }

  void _checkNames(StyleIR ir) {
    for (final name in [...ir.colorExtensions, ...ir.buttonExtensions]) {
      if (Naming.member(name) != name) {
        _error(StyleCodes.reference, 'extend.$name', '"$name" is not a valid Dart member name; use lowerCamelCase');
      }
    }
    for (final name in ir.colorExtensions) {
      if (colorSlots.contains(name)) _error(StyleCodes.reference, 'color.extend.$name', '"$name" is a built-in slot');
    }
  }

  void _error(String code, String path, String message) => diagnostics.error(code, message, location: '$_source#$path');

  // ---------------------------------------------------------------------------------------------

  Map<String, Object?>? _load(String path, String display) {
    final file = File(path);
    if (!file.existsSync()) {
      diagnostics.error(StyleCodes.missing, 'tokens file not found', location: display);
      return null;
    }
    try {
      return _plainMap(loadYaml(file.readAsStringSync()));
    } on YamlException catch (e) {
      diagnostics.error(StyleCodes.missing, 'invalid YAML: ${e.message}', location: display);
      return null;
    }
  }

  /// Deep merge; [override] wins, maps merge recursively, everything else is replaced.
  static Map<String, Object?> _merge(Map<String, Object?> base, Map<String, Object?> override) => {
    ...base,
    for (final e in override.entries)
      e.key: (e.value is Map<String, Object?> && base[e.key] is Map<String, Object?>)
          ? _merge(base[e.key]! as Map<String, Object?>, e.value! as Map<String, Object?>)
          : e.value,
  };

  static Map<String, Object?> _map(Object? node) => node is Map<String, Object?> ? node : const {};

  static Map<String, Object?> _plainMap(Object? yaml) {
    final plain = _plain(yaml);
    return plain is Map<String, Object?> ? plain : const {};
  }

  static Object? _plain(Object? node) => switch (node) {
    YamlMap() => <String, Object?>{for (final e in node.entries) e.key.toString(): _plain(e.value)},
    YamlList() => [for (final e in node) _plain(e)],
    YamlScalar() => node.value,
    _ => node,
  };
}

/// WCAG 2 contrast ratio of two opaque ARGB colors.
double contrastRatio(int a, int b) {
  double luminance(int argb) {
    double channel(int v) {
      final c = v / 255;
      return c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
    }

    return 0.2126 * channel((argb >> 16) & 0xFF) + 0.7152 * channel((argb >> 8) & 0xFF) + 0.0722 * channel(argb & 0xFF);
  }

  final la = luminance(a), lb = luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}
