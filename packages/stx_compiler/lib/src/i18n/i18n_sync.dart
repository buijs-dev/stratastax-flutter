import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

import '../config.dart';

final class SyncResult {
  const SyncResult({required this.added});

  /// Locale → keys added to its file.
  final Map<String, List<String>> added;

  bool get changed => added.values.any((keys) => keys.isNotEmpty);
}

/// Adds [missing] keys (key → suggested text) to every locale file, preserving the existing
/// formatting and comments. The base locale gets the suggestion; other locales get the base text
/// so the build passes, and are reported so they can be translated.
SyncResult syncTranslations(I18nConfig config, Map<String, String> missing) {
  final added = <String, List<String>>{};
  for (final locale in config.locales) {
    final file = File(p.join(config.dir, '$locale.yaml'));
    final source = file.existsSync() ? file.readAsStringSync() : '';
    final editor = YamlEditor(source.trim().isEmpty ? '{}' : source);
    final keys = <String>[];
    for (final entry in missing.entries) {
      final path = entry.key.split('.');
      if (_exists(editor, path)) continue;
      _insert(editor, path, entry.value);
      keys.add(entry.key);
    }
    if (keys.isEmpty) continue;
    file.parent.createSync(recursive: true);
    var text = editor.toString();
    if (source.trim().isEmpty) text = text.replaceFirst(RegExp(r'^\{\}\s*'), '');
    file.writeAsStringSync(text.endsWith('\n') ? text : '$text\n');
    added[locale] = keys;
  }
  return SyncResult(added: added);
}

bool _exists(YamlEditor editor, List<String> path) {
  try {
    editor.parseAt(path);
    return true;
  } on Object {
    return false;
  }
}

/// Creates missing parents: the deepest existing map gets the rest of the path as a nested map.
void _insert(YamlEditor editor, List<String> path, String value) {
  var depth = 0;
  while (depth < path.length - 1 && _isMap(editor, path.sublist(0, depth + 1))) {
    depth++;
  }
  Object nested = value;
  for (final segment in path.sublist(depth + 1).reversed) {
    nested = {segment: nested};
  }
  editor.update(path.sublist(0, depth + 1), nested);
}

bool _isMap(YamlEditor editor, List<String> path) {
  try {
    return editor.parseAt(path) is YamlMap;
  } on Object {
    return false;
  }
}
