/// Compiles ICU messages ([parseIcu] from stx_icu) to Dart string interpolation.
library;

import 'package:stx_icu/stx_icu.dart';

import '../naming.dart';

export 'package:stx_icu/stx_icu.dart';

extension ArgTypeDart on ArgType {
  /// The Dart type of a placeholder in a generated factory.
  String get dart => switch (this) {
    ArgType.any => 'Object?',
    ArgType.number => 'num',
    ArgType.date => 'DateTime',
    ArgType.string => 'String',
  };
}

/// Compiles [nodes] to a Dart string expression. Arguments come from `args[i]` (index from
/// [arguments]); formatting goes through `formats` (the locale's generated `StxLocaleFormats`).
String compileIcu(List<IcuNode> nodes, List<String> arguments) => _Compiler(arguments).message(nodes, null, 0);

final class _Compiler {
  _Compiler(this.arguments);

  final List<String> arguments;

  String arg(String name, ArgType type) {
    final i = arguments.indexOf(name);
    return switch (type) {
      ArgType.any => 'args[$i]',
      _ => '(args[$i] as ${type.dart})',
    };
  }

  /// [pound] is the variable `#` refers to inside a plural.
  String message(List<IcuNode> nodes, String? pound, int depth) {
    // A message that is only a String-valued expression needs no interpolation around it.
    final single = nodes.length == 1 ? nodes.single : null;
    final stringValued = switch (single) {
      IcuChoice() || IcuPound() => true,
      IcuArg(:final type) => type != null,
      _ => false,
    };
    if (stringValued) {
      final wrapped = message([const IcuText(''), single!], pound, depth);
      return wrapped.substring(3, wrapped.length - 2); // '${…}' → …
    }
    final b = StringBuffer("'");
    for (final node in nodes) {
      switch (node) {
        case IcuText(:final text):
          b.write(_escape(text));
        case IcuPound():
          b.write('\${formats.number($pound)}');
        case IcuArg(:final name, type: null):
          b.write('\${${arg(name, ArgType.any)}}');
        case IcuArg(:final name, type: 'number', :final style):
          final value = arg(name, ArgType.number);
          b.write(switch (style) {
            'integer' => '\${formats.integer($value)}',
            'percent' => '\${formats.percent($value)}',
            _ => '\${formats.number($value)}',
          });
        case IcuArg(:final name, type: 'date', :final style):
          b.write('\${formats.date(${arg(name, ArgType.date)}, DateStyle.${style ?? 'medium'})}');
        case IcuArg(:final name, type: 'time', :final style):
          b.write('\${formats.time(${arg(name, ArgType.date)}, TimeStyle.${style ?? 'short'})}');
        case IcuArg():
          throw StateError('unreachable');
        case IcuChoice(:final name, :final kind, :final options):
          b.write('\${${choice(name, kind, options, pound, depth)}}');
      }
    }
    b.write("'");
    return b.toString();
  }

  String choice(String name, String kind, Map<String, List<IcuNode>> options, String? pound, int depth) {
    final v = 'v$depth';
    if (kind == 'select') {
      final cases = [
        for (final e in options.entries)
          if (e.key != 'other') '${Naming.stringLiteral(e.key)} => ${message(e.value, pound, depth + 1)}',
        '_ => ${message(options['other']!, pound, depth + 1)}',
      ];
      return 'switch (${arg(name, ArgType.string)}) { ${cases.join(', ')} }';
    }
    final exact = [
      for (final e in options.entries)
        if (e.key.startsWith('=')) 'final $v when $v == ${e.key.substring(1)} => ${message(e.value, v, depth + 1)}',
    ];
    final categories = [
      for (final e in options.entries)
        if (!e.key.startsWith('=') && e.key != 'other') 'Plural.${e.key} => ${message(e.value, v, depth + 1)}',
      '_ => ${message(options['other']!, v, depth + 1)}',
    ];
    final byCategory = 'switch (formats.plural($v)) { ${categories.join(', ')} }';
    return 'switch (${arg(name, ArgType.number)}) { ${[...exact, 'final $v => $byCategory'].join(', ')} }';
  }

  static String _escape(String text) => text
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'")
      .replaceAll(r'$', r'\$')
      .replaceAll('\n', r'\n')
      .replaceAll('\r', r'\r');
}
