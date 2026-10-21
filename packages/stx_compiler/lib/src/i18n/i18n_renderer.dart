import '../diagnostics.dart';
import '../naming.dart';
import '../output.dart';
import 'cldr.dart';
import 'i18n_frontend.dart';
import 'icu.dart';

/// The Dart constant for an app key: `matchCreateCommand.gameId.label` →
/// (`MsgMatchCreateCommand`, `gameIdLabel`); keys without a namespace go to `MsgRoot`.
({String className, String member}) msgName(String key) {
  final segments = key.split('.');
  if (segments.length == 1) return (className: 'MsgRoot', member: Naming.member(key));
  final rest = segments.skip(1).map((s) => Naming.pascal(s)).join();
  return (className: 'Msg${Naming.pascal(segments.first)}', member: Naming.member(rest));
}

/// Renders `i18n/keys.g.dart`, `i18n/arguments.g.dart`, `i18n/messages_<locale>.g.dart` and
/// `i18n/locales.g.dart`.
List<GeneratedFile> renderI18n(I18nIR ir, {required bool deferred, required Diagnostics diagnostics}) {
  // keys.g.dart: app keys only; framework keys are StxKeys in stx_i18n.
  final classes = <String, List<String>>{};
  final seen = <String, String>{};
  for (final m in ir.messages.where((m) => !m.isFramework)) {
    final name = msgName(m.key);
    final qualified = '${name.className}.${name.member}';
    if (seen[qualified] case final other?) {
      diagnostics.error(
        I18nCodes.nameCollision,
        'keys "$other" and "${m.key}" both map to $qualified',
        location: m.key,
      );
      continue;
    }
    seen[qualified] = m.key;
    final doc = '  /// `${m.key}`: ${m.values[ir.base]!.replaceAll('\n', ' ')}';
    final member = m.arguments.isEmpty
        ? '  static const ${name.member} = MsgKey(${Naming.stringLiteral(m.key)});'
        : '  static Msg ${name.member}({${m.arguments.entries.map((a) => 'required ${a.value.dart} ${Naming.member(a.key)}').join(', ')}}) =>\n'
              '      MsgArgs(const MsgKey(${Naming.stringLiteral(m.key)}), [${m.placeholders.map(Naming.member).join(', ')}]);';
    classes.putIfAbsent(name.className, () => []).add('$doc\n$member');
  }
  final keys = StringBuffer()
    ..writeln(generatedHeader)
    ..writeln('// Source: the base locale (${ir.base}) of the app translations.')
    ..writeln()
    ..writeln("import 'package:stx_i18n/stx_i18n.dart';")
    ..writeln();
  for (final entry in classes.entries) {
    keys
      ..writeln('abstract final class ${entry.key} {')
      ..writeln(entry.value.join('\n\n'))
      ..writeln('}')
      ..writeln();
  }

  final files = [GeneratedFile('i18n/keys.g.dart', keys.toString())];

  // arguments.g.dart: the placeholders per key, shared by every locale, so a translation from a
  // backend (OverlayMessages) can use them by name.
  final arguments = StringBuffer()
    ..writeln(generatedHeader)
    ..writeln('// Source: the base locale (${ir.base}) of the app translations and the stx_i18n framework texts.')
    ..writeln()
    ..writeln("import 'package:stx_i18n/stx_i18n.dart';")
    ..writeln()
    ..writeln('/// The placeholders of every message that has them, in the order of `MsgArgs.args`.')
    ..writeln('const messageArguments = <String, List<(String, ArgType)>>{');
  for (final m in ir.messages.where((m) => m.placeholders.isNotEmpty)) {
    final list = [
      for (final name in m.placeholders) '(${Naming.stringLiteral(name)}, ArgType.${m.arguments[name]!.name})',
    ];
    arguments.writeln('  ${Naming.stringLiteral(m.key)}: [${list.join(', ')}],');
  }
  arguments.writeln('};');
  files.add(GeneratedFile('i18n/arguments.g.dart', arguments.toString()));

  // messages_<locale>.g.dart
  for (final locale in ir.locales) {
    final className = 'Messages${Naming.pascal(locale)}';
    final formatsClass = '_Formats${Naming.pascal(locale)}';
    final data = cldrFor(locale)!;
    final b = StringBuffer()
      ..writeln(generatedHeader)
      ..writeln(
        '// Source: stx_i18n framework texts + the app translations ($locale) + CLDR (${locale.split(RegExp('[-_]')).first}).',
      )
      ..writeln()
      ..writeln("import 'package:flutter/widgets.dart';")
      ..writeln("import 'package:stx_i18n/stx_i18n.dart';")
      ..writeln()
      ..writeln("import 'arguments.g.dart';")
      ..writeln()
      ..writeln('final class $className extends StxMessages {')
      ..writeln('  const $className() : super(const ${_locale(locale)}, _plain);')
      ..writeln()
      ..writeln('  /// By key; messages with placeholders keep their ICU source (they go through [format]).')
      ..writeln('  static const _plain = <String, String>{');
    for (final m in ir.messages) {
      final text = m.isPlain ? m.plainText(locale) : m.values[locale]!;
      b.writeln('    ${Naming.stringLiteral(m.key)}: ${Naming.stringLiteral(text)},');
    }
    b
      ..writeln('  };')
      ..writeln()
      ..writeln('  @override')
      ..writeln('  StxLocaleFormats get formats => const $formatsClass();')
      ..writeln()
      ..writeln('  @override')
      ..writeln('  Map<String, List<(String, ArgType)>> get arguments => messageArguments;')
      ..writeln()
      ..writeln('  @override')
      ..writeln('  String format(String key, List<Object?> args) {')
      ..writeln('    return switch (key) {');
    for (final m in ir.messages.where((m) => !m.isPlain)) {
      b.writeln('      ${Naming.stringLiteral(m.key)} => ${compileIcu(m.nodes[locale]!, m.placeholders)},');
    }
    b
      ..writeln('      _ => plain[key] ?? key,')
      ..writeln('    };')
      ..writeln('  }')
      ..writeln('}')
      ..writeln()
      ..write(renderFormats(formatsClass, data));
    files.add(GeneratedFile('i18n/messages_${Naming.snake(locale)}.g.dart', b.toString()));
  }

  // locales.g.dart
  final l = StringBuffer()
    ..writeln(generatedHeader)
    ..writeln()
    ..writeln("import 'dart:async';")
    ..writeln()
    ..writeln("import 'package:flutter/widgets.dart';")
    ..writeln("import 'package:stx_i18n/stx_i18n.dart';")
    ..writeln();
  for (final locale in ir.locales) {
    final file = 'messages_${Naming.snake(locale)}.g.dart';
    l.writeln(
      deferred && locale != ir.base ? "import '$file' deferred as ${Naming.member(locale)};" : "import '$file';",
    );
  }
  l
    ..writeln()
    ..writeln('const supportedLocales = [${ir.locales.map(_locale).join(', ')}];')
    ..writeln()
    ..writeln('/// The base locale loads synchronously; other locales${deferred ? ' are deferred libraries' : ''}.')
    ..writeln('FutureOr<StxMessages> loadMessages(Locale locale) => switch (locale.toLanguageTag()) {');
  for (final locale in ir.locales.skip(1)) {
    final className = 'Messages${Naming.pascal(locale)}';
    final tag = locale.replaceAll('_', '-');
    l.writeln(
      deferred
          ? "  '$tag' => ${Naming.member(locale)}.loadLibrary().then((_) => ${Naming.member(locale)}.$className()),"
          : "  '$tag' => const $className(),",
    );
  }
  l
    ..writeln('  _ => const Messages${Naming.pascal(ir.base)}(),')
    ..writeln('};');
  files.add(GeneratedFile('i18n/locales.g.dart', l.toString()));
  return files;
}

String _locale(String locale) {
  final parts = locale.split(RegExp('[-_]'));
  return parts.length > 1 ? "Locale('${parts[0]}', '${parts[1]}')" : "Locale('${parts[0]}')";
}
