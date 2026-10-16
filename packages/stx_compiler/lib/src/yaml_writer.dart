/// A minimal YAML emitter for IR dumps (`stx scan`): maps, lists and scalars only.
String toYaml(Object? value) {
  final b = StringBuffer();
  _write(b, value, 0, inList: false);
  return b.toString();
}

void _write(StringBuffer b, Object? value, int indent, {required bool inList}) {
  final pad = '  ' * indent;
  switch (value) {
    case Map() when value.isEmpty:
      b.writeln(' {}');
    case Map():
      var first = true;
      for (final entry in value.entries) {
        final prefix = (inList && first) ? '' : pad;
        first = false;
        b.write('$prefix${_scalar(entry.key)}:');
        _child(b, entry.value, indent + 1);
      }
    case List() when value.isEmpty:
      b.writeln(' []');
    case List():
      for (final item in value) {
        b.write('$pad-');
        if (item is Map && item.isNotEmpty) {
          b.write(' ');
          _write(b, item, indent + 1, inList: true);
        } else {
          _child(b, item, indent + 1);
        }
      }
    default:
      b.writeln(_scalar(value));
  }
}

void _child(StringBuffer b, Object? value, int indent) {
  if ((value is Map && value.isNotEmpty) || (value is List && value.isNotEmpty)) {
    b.writeln();
    _write(b, value, value is List ? indent - 1 : indent, inList: false);
  } else {
    b.write(' ');
    _write(b, value, indent, inList: false);
  }
}

String _scalar(Object? value) {
  if (value == null) return 'null';
  if (value is num || value is bool) return '$value';
  if (value is Map && value.isEmpty) return '{}';
  if (value is List && value.isEmpty) return '[]';
  final text = value.toString();
  final plain =
      RegExp(r'^[A-Za-z_/][A-Za-z0-9_./{}-]*$').hasMatch(text) &&
      !const {'true', 'false', 'null', 'yes', 'no', 'on', 'off'}.contains(text.toLowerCase());
  return plain ? text : "'${text.replaceAll("'", "''")}'";
}
