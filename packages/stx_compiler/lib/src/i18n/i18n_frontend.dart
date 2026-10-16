import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import '../config.dart';
import '../diagnostics.dart';
import 'cldr.dart';
import 'icu.dart';

/// Diagnostic codes of the i18n stage.
abstract final class I18nCodes {
  /// A required key is missing in the base locale.
  static const missingBase = 'STX-I001';

  /// Placeholders differ between locales.
  static const placeholders = 'STX-I002';

  /// A key is missing in a non-base locale (with `missing: error`).
  static const missingLocale = 'STX-I003';

  /// Invalid ICU message syntax.
  static const syntax = 'STX-I004';

  /// A key exists in a non-base locale only (warning).
  static const unknownKey = 'STX-I005';

  /// Two keys map to the same Dart name.
  static const nameCollision = 'STX-I006';

  /// No bundled CLDR data for a configured locale.
  static const unsupportedLocale = 'STX-I007';
}

final class MessageIR {
  const MessageIR({required this.key, required this.values, this.arguments = const {}, this.nodes = const {}});

  /// Dotted path, e.g. `matchCreateCommand.gameId.label`; the identity of the message at runtime.
  final String key;

  /// Locale → text.
  final Map<String, String> values;

  /// Placeholders with the type they need, in order of first appearance in the base text.
  final Map<String, ArgType> arguments;

  /// Locale → parsed ICU message (empty for plain text without placeholders).
  final Map<String, List<IcuNode>> nodes;

  List<String> get placeholders => [...arguments.keys];

  /// Text only, no placeholders or choices.
  bool get isPlain => nodes.values.every((n) => n.every((node) => node is IcuText));

  /// The text of a plain message in [locale], with ICU quoting resolved (`''` → `'`).
  String plainText(String locale) =>
      nodes[locale] == null ? values[locale]! : nodes[locale]!.map((n) => (n as IcuText).text).join();

  bool get isFramework => key.startsWith('stx.');
}

final class I18nIR {
  const I18nIR({required this.base, required this.locales, required this.messages});

  final String base;
  final List<String> locales;

  /// Framework keys first (in the order of stx.en.yaml), then app keys sorted.
  final List<MessageIR> messages;

  MessageIR? byKey(String key) {
    for (final m in messages) {
      if (m.key == key) return m;
    }
    return null;
  }
}

/// Merges the framework texts (from stx_i18n) and the app's `i18n/<locale>.yaml` files.
final class I18nFrontend {
  I18nFrontend(this.config, this.diagnostics);

  final I18nConfig config;
  final Diagnostics diagnostics;

  /// [frameworkDir] is `package:stx_i18n/i18n/`; [displayDir] the configured dir for messages.
  I18nIR parseFiles({required String frameworkDir, required String displayDir}) {
    Map<String, String> read(String path) {
      final file = File(path);
      if (!file.existsSync()) return const {};
      try {
        return flatten(loadYaml(file.readAsStringSync()));
      } on YamlException catch (e) {
        diagnostics.error(I18nCodes.syntax, 'invalid YAML: ${e.message}', location: path);
        return const {};
      }
    }

    final frameworkBase = read(p.join(frameworkDir, 'stx.en.yaml'));
    return parse(
      framework: {
        for (final locale in config.locales)
          locale: {...frameworkBase, ...read(p.join(frameworkDir, 'stx.$locale.yaml'))},
      },
      frameworkOrder: frameworkBase.keys.toList(),
      app: {for (final locale in config.locales) locale: read(p.join(config.dir, '$locale.yaml'))},
      displayDir: displayDir,
    );
  }

  I18nIR parse({
    required Map<String, Map<String, String>> framework,
    required List<String> frameworkOrder,
    required Map<String, Map<String, String>> app,
    String displayDir = 'i18n',
  }) {
    final base = config.base;
    for (final locale in config.locales) {
      if (cldrFor(locale) == null) {
        diagnostics.error(
          I18nCodes.unsupportedLocale,
          'no bundled CLDR data for "$locale"',
          location: 'stx.yaml#i18n.locales',
          hint: 'supported languages: ${cldr.keys.join(', ')}',
        );
      }
    }
    final appKeys = [
      for (final k in (app[base] ?? const {}).keys)
        if (!k.startsWith('stx.')) k,
    ]..sort();
    final messages = <MessageIR>[];

    for (final key in [...frameworkOrder, ...appKeys]) {
      final isFramework = key.startsWith('stx.');
      final values = <String, String>{};
      for (final locale in config.locales) {
        final fromFramework = isFramework ? framework[locale] : null;
        final value = app[locale]?[key] ?? fromFramework?[key];
        if (value != null) {
          values[locale] = value;
        } else if (locale == base || !config.missingIsError) {
          values[locale] = values[base] ?? key;
        } else {
          diagnostics.error(
            I18nCodes.missingLocale,
            'key "$key" has no $locale translation',
            location: p.posix.join(displayDir, '$locale.yaml'),
            hint: "add it, or set `missing: fallback` in stx.yaml to fall back to '$base'",
          );
          values[locale] = values[base] ?? key;
        }
      }

      final nodes = <String, List<IcuNode>>{};
      final types = <String, Map<String, ArgType>>{};
      for (final entry in values.entries) {
        try {
          nodes[entry.key] = parseIcu(entry.value);
          types[entry.key] = icuArguments(nodes[entry.key]!);
        } on IcuException catch (e) {
          diagnostics.error(
            I18nCodes.syntax,
            'key "$key" ($e): ${entry.value}',
            location: p.posix.join(displayDir, '${entry.key}.yaml'),
          );
        }
      }
      final arguments = types[base] ?? const <String, ArgType>{};
      // Compare with the base only when the base itself parsed (no follow-up errors).
      for (final entry in types[base] == null ? const <MapEntry<String, Map<String, ArgType>>>[] : types.entries) {
        final own = entry.value;
        final same =
            own.length == arguments.length &&
            own.keys.every((k) => arguments.containsKey(k) && _compatible(arguments[k]!, own[k]!));
        if (!same) {
          diagnostics.error(
            I18nCodes.placeholders,
            'key "$key" has placeholders ${_describe(own)} in ${entry.key} but ${_describe(arguments)} in $base',
            location: p.posix.join(displayDir, '${entry.key}.yaml'),
          );
        }
      }
      messages.add(MessageIR(key: key, values: values, arguments: arguments, nodes: nodes));
    }

    for (final locale in config.locales.skip(1)) {
      for (final key in (app[locale] ?? const {}).keys) {
        if (!key.startsWith('stx.') && !appKeys.contains(key)) {
          diagnostics.warning(
            I18nCodes.unknownKey,
            'key "$key" is not in the base locale ($base) and is ignored',
            location: p.posix.join(displayDir, '$locale.yaml'),
          );
        }
      }
    }

    return I18nIR(base: base, locales: config.locales, messages: messages);
  }

  // A locale may use a placeholder plainly where the base formats it (or the reverse).
  static bool _compatible(ArgType a, ArgType b) => a == b || a == ArgType.any || b == ArgType.any;

  static String _describe(Map<String, ArgType> args) =>
      '{${args.entries.map((e) => e.value == ArgType.any ? e.key : '${e.key}: ${e.value.name}').join(', ')}}';

  /// Nested YAML maps → dotted keys, in file order.
  static Map<String, String> flatten(Object? node, [String prefix = '']) {
    final result = <String, String>{};
    if (node is YamlMap) {
      for (final e in node.entries) {
        final key = prefix.isEmpty ? '${e.key}' : '$prefix.${e.key}';
        result.addAll(flatten(e.value, key));
      }
    } else if (node != null && prefix.isNotEmpty) {
      result[prefix] = node.toString();
    }
    return result;
  }
}
