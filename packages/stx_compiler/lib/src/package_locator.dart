import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Finds the `lib/` directory of packages the consumer app depends on, through the
/// `.dart_tool/package_config.json` that `pub get` wrote (in a workspace: at the workspace root).
/// Used to read framework defaults shipped with stx_style and stx_i18n.
final class PackageLocator {
  PackageLocator._(this._libs);

  factory PackageLocator.forProject(String projectDir) {
    var dir = Directory(p.normalize(p.absolute(projectDir)));
    while (true) {
      final config = File(p.join(dir.path, '.dart_tool', 'package_config.json'));
      if (config.existsSync()) return PackageLocator._(_read(config));
      final parent = dir.parent;
      if (parent.path == dir.path) return PackageLocator._(const {});
      dir = parent;
    }
  }

  final Map<String, String> _libs;

  /// Absolute path of `package:<name>/`, or null when the app does not depend on it.
  String? lib(String name) => _libs[name];

  static Map<String, String> _read(File config) {
    final json = jsonDecode(config.readAsStringSync()) as Map<String, Object?>;
    final base = config.parent.uri;
    return {
      for (final package in (json['packages'] as List).cast<Map<String, Object?>>())
        package['name']! as String: p.normalize(
          p.fromUri(
            base.resolve(_dir(package['rootUri']! as String)).resolve(_dir(package['packageUri'] as String? ?? 'lib/')),
          ),
        ),
    };
  }

  static String _dir(String uri) => uri.endsWith('/') ? uri : '$uri/';
}
