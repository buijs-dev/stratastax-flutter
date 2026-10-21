import 'package:stx_icu/stx_icu.dart';

import 'formats.dart';

/// Formats a parsed ICU message at runtime, with the same semantics as the code stx_compiler
/// generates for it (`compileIcu`): `#` and `{n, number}` through [StxLocaleFormats.number], exact
/// plural matches before the CLDR category, `other` as the fallback of plural and select.
///
/// Used for translations from a backend, which are not known at build time. A value of the wrong
/// type (a placeholder that is `any` in the base locale) is shown with `toString()` and selects
/// `other`, instead of failing.
String formatIcu(List<IcuNode> nodes, Map<String, Object?> args, StxLocaleFormats formats) =>
    _message(nodes, args, formats, null);

String _message(List<IcuNode> nodes, Map<String, Object?> args, StxLocaleFormats formats, num? pound) {
  final b = StringBuffer();
  for (final node in nodes) {
    switch (node) {
      case IcuText(:final text):
        b.write(text);
      case IcuPound():
        b.write(pound == null ? '#' : formats.number(pound));
      case IcuArg(:final name, :final type, :final style):
        final value = args[name];
        b.write(switch ((type, value)) {
          ('number', final num n) => switch (style) {
            'integer' => formats.integer(n),
            'percent' => formats.percent(n),
            _ => formats.number(n),
          },
          ('date', final DateTime d) => formats.date(d, DateStyle.values.byName(style ?? 'medium')),
          ('time', final DateTime d) => formats.time(d, TimeStyle.values.byName(style ?? 'short')),
          _ => '$value',
        });
      case IcuChoice(:final name, kind: 'select', :final options):
        final value = args[name];
        final option = value is String && value != 'other' ? options[value] : null;
        b.write(_message(option ?? options['other']!, args, formats, pound));
      case IcuChoice(:final name, :final options):
        final value = args[name];
        if (value is! num) {
          b.write(_message(options['other']!, args, formats, pound));
          break;
        }
        List<IcuNode>? option;
        for (final e in options.entries) {
          if (e.key.startsWith('=') && num.parse(e.key.substring(1)) == value) {
            option = e.value;
            break;
          }
        }
        final category = formats.plural(value).name;
        option ??= category == 'other' ? null : options[category];
        b.write(_message(option ?? options['other']!, args, formats, value));
    }
  }
  return b.toString();
}
