import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

List<String> _leafKeys(Object? node, [String prefix = '']) => switch (node) {
  YamlMap() => [for (final e in node.entries) ..._leafKeys(e.value, prefix.isEmpty ? '${e.key}' : '$prefix.${e.key}')],
  _ => [prefix],
};

String _camel(String key) {
  final parts = key.split('.').skip(1).toList(); // drop `stx`
  return parts.first + parts.skip(1).map((p) => p[0].toUpperCase() + p.substring(1)).join();
}

void main() {
  final en = _leafKeys(loadYaml(File('lib/i18n/stx.en.yaml').readAsStringSync()));

  test('every key of stx.en.yaml has its StxKeys constant, and nothing else', () {
    final source = File('lib/src/keys.dart').readAsStringSync();
    final declared = [for (final m in RegExp(r"MsgKey\('([^']+)'\)").allMatches(source)) m[1]!];
    expect(declared.toSet(), en.toSet());
    for (final key in en) {
      expect(source, contains(RegExp('${_camel(key)}[ =(].*MsgKey\\(\'${RegExp.escape(key)}\'\\)')), reason: key);
    }
  });

  test('every locale has exactly the keys of en', () {
    for (final file in Directory('lib/i18n').listSync().whereType<File>()) {
      expect(_leafKeys(loadYaml(file.readAsStringSync())), en, reason: file.path);
    }
  });
}
