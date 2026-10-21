import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'diagnostics.dart';

/// Diagnostic codes of remote sources (`sources:` in stx.yaml, stx.lock).
abstract final class SourceCodes {
  /// A remote source cannot be fetched, or is not cached with `--offline`.
  static const unavailable = 'STX-R001';

  /// A fetched or cached source does not match its sha256 in stx.lock.
  static const lockMismatch = 'STX-R002';

  /// A reference names an unknown source, or a source or reference is invalid.
  static const invalid = 'STX-R003';
}

/// A file that stx.yaml refers to (a contract spec, the tokens): a local path, an `https://` URL, or
/// `<source>:<path>` with a source from `sources:`. The frontends only read [path]; for a remote file
/// that is its copy in the cache, which [RemoteSources.resolve] fills.
final class SourceRef {
  const SourceRef({required this.path, required this.display, this.url});

  /// Absolute path the frontends read.
  final String path;

  /// The reference as written in stx.yaml (`stratastax:openapi/platform.yaml`), used in
  /// diagnostics and generated headers, so output does not depend on a local override or checkout.
  final String display;

  /// Null for a local file.
  final Uri? url;

  bool get isRemote => url != null;
}

/// Resolves references against `sources:` of stx.yaml, overridden per alias by `sources:` of
/// stx.local.yaml (not committed: point a source at a local checkout).
final class SourceResolver {
  SourceResolver(this.projectDir, this.sources);

  /// Loads `sources:` of stx.yaml ([root]) and stx.local.yaml.
  factory SourceResolver.load(String projectDir, Object? root, Diagnostics diagnostics, {required String location}) {
    final sources = <String, String>{};
    void read(Object? node, String location) {
      if (node == null) return;
      if (node is! YamlMap) {
        diagnostics.error(SourceCodes.invalid, '"sources" must be a mapping', location: location);
        return;
      }
      for (final entry in node.entries) {
        final name = entry.key.toString();
        if (!_alias.hasMatch('$name:')) {
          diagnostics.error(
            SourceCodes.invalid,
            'source "$name": use at least two letters, digits or dashes, starting with a letter',
            location: location,
          );
        } else {
          sources[name] = entry.value.toString();
        }
      }
    }

    read(root is YamlMap ? root['sources'] : null, location);
    final local = File(p.join(projectDir, localFileName));
    if (local.existsSync()) {
      try {
        final yaml = loadYaml(local.readAsStringSync());
        if (yaml is YamlMap) {
          for (final key in yaml.keys) {
            if (key != 'sources') {
              diagnostics.warning(SourceCodes.invalid, 'unknown key "$key" is ignored', location: localFileName);
            }
          }
          read(yaml['sources'], localFileName);
        }
      } on YamlException catch (e) {
        diagnostics.error(SourceCodes.invalid, 'invalid YAML: ${e.message}', location: localFileName);
      }
    }
    return SourceResolver(projectDir, sources);
  }

  static const localFileName = 'stx.local.yaml';

  /// `<alias>:`; two characters at least, so a Windows drive letter is a path.
  static final _alias = RegExp(r'^([a-zA-Z][a-zA-Z0-9-]+):(?!//)');

  final String projectDir;

  /// Alias → base: a URL or a path relative to the project.
  final Map<String, String> sources;

  /// Null (and reported) when [reference] names an unknown source or an unsupported URL.
  SourceRef? resolve(String reference, Diagnostics diagnostics, {required String location}) {
    if (_alias.firstMatch(reference) case final match?) {
      final name = match[1]!;
      final base = sources[name];
      final path = reference.substring(match.end);
      if (base == null) {
        diagnostics.error(
          SourceCodes.invalid,
          'unknown source "$name" in "$reference"',
          location: location,
          hint: sources.isEmpty ? 'add it under "sources:"' : 'known: ${sources.keys.join(', ')}',
        );
        return null;
      }
      if (_isUrl(base)) {
        final url = Uri.parse(base.endsWith('/') ? base : '$base/').resolve(path);
        return _remote(url, reference);
      }
      return SourceRef(path: p.normalize(p.join(projectDir, base, path)), display: reference);
    }
    if (_isUrl(reference)) return _remote(Uri.parse(reference), reference);
    return SourceRef(path: p.normalize(p.join(projectDir, reference)), display: p.posix.normalize(reference));
  }

  static bool _isUrl(String value) => value.startsWith('https://') || value.startsWith('http://');

  /// `https://host/a/b.yaml` → `.dart_tool/stx/sources/host/a/b.yaml`.
  SourceRef _remote(Uri url, String display) => SourceRef(
    path: p.joinAll([
      projectDir,
      '.dart_tool',
      'stx',
      'sources',
      url.hasPort ? '${url.host}_${url.port}' : url.host,
      ...url.pathSegments.where((s) => s.isNotEmpty && s != '..'),
    ]),
    display: display,
    url: url,
  );
}

/// stx.lock: the sha256 of every remote source, so a build reads the same files until
/// `stx sources update`. Committed with the project.
final class SourceLock {
  SourceLock(this.hashes);

  static const fileName = 'stx.lock';

  /// URL → sha256 (hex).
  final Map<String, String> hashes;

  static SourceLock load(String projectDir, Diagnostics diagnostics) {
    final file = File(p.join(projectDir, fileName));
    if (!file.existsSync()) return SourceLock({});
    try {
      final yaml = loadYaml(file.readAsStringSync());
      final sources = yaml is YamlMap ? yaml['sources'] : null;
      return SourceLock({
        if (sources is YamlMap)
          for (final e in sources.entries) e.key.toString(): e.value.toString(),
      });
    } on YamlException catch (e) {
      diagnostics.error(SourceCodes.invalid, 'invalid YAML: ${e.message}', location: fileName);
      return SourceLock({});
    }
  }

  void save(String projectDir) {
    final b = StringBuffer()
      ..writeln('# Generated by stx: the sha256 of every remote source in stx.yaml. Commit this file;')
      ..writeln('# `stx sources update` fetches the latest versions.')
      ..writeln(hashes.isEmpty ? 'sources: {}' : 'sources:');
    for (final url in hashes.keys.toList()..sort()) {
      b.writeln('  "$url": ${hashes[url]}');
    }
    File(p.join(projectDir, fileName)).writeAsStringSync(b.toString());
  }
}

/// Fetches the body of [url]; throws on a failure or a status other than 200.
typedef SourceFetch = Future<List<int>> Function(Uri url);

/// A remote source that `stx sources update` changed.
final class SourceChange {
  const SourceChange({required this.source, this.before, required this.after, this.summary = const []});

  final SourceRef source;

  /// Null for a source that was not locked yet.
  final String? before;
  final String after;

  /// What changed, for an OpenAPI document: `info.version` and added or removed operations.
  final List<String> summary;
}

/// Fetches the remote [sources] into their cache and checks them against stx.lock.
final class RemoteSources {
  RemoteSources(this.projectDir, this.sources, {this.offline = false, SourceFetch? fetch})
    : _fetch = fetch ?? httpFetch;

  final String projectDir;
  final List<SourceRef> sources;

  /// Only use the cache.
  final bool offline;
  final SourceFetch _fetch;

  Iterable<SourceRef> get _remote => sources.where((s) => s.isRemote);

  /// Before a build: every locked source is read from the cache, or fetched when it is not cached
  /// and must still match its hash; a new source is fetched and locked. Writes stx.lock when it
  /// changed and [updateLock], without entries for sources stx.yaml no longer uses.
  Future<void> resolve(Diagnostics diagnostics, {bool updateLock = true}) async {
    final lock = SourceLock.load(projectDir, diagnostics);
    final hashes = <String, String>{};
    for (final source in _remote) {
      final url = source.url.toString();
      final locked = lock.hashes[url];
      final cached = _cachedHash(source);
      if (cached != null && (locked == null || cached == locked)) {
        hashes[url] = cached;
        continue;
      }
      if (offline) {
        diagnostics.error(
          cached == null ? SourceCodes.unavailable : SourceCodes.lockMismatch,
          cached == null ? 'not cached ($url)' : 'the cached copy of $url does not match ${SourceLock.fileName}',
          location: source.display,
          hint: cached == null ? 'build once without --offline' : 'build without --offline to fetch the locked version',
        );
        continue;
      }
      final body = await _download(source, diagnostics);
      if (body == null) continue;
      final hash = sha256.convert(body).toString();
      if (locked != null && hash != locked) {
        diagnostics.error(
          SourceCodes.lockMismatch,
          '$url changed since it was locked in ${SourceLock.fileName}',
          location: source.display,
          hint: 'run `stx sources update` to accept the new version',
        );
        continue;
      }
      _store(source, body);
      hashes[url] = hash;
    }
    if (diagnostics.hasErrors) return;
    if (updateLock && !_same(hashes, lock.hashes)) SourceLock(hashes).save(projectDir);
  }

  /// `stx sources update`: fetches every remote source and locks the new versions.
  Future<List<SourceChange>> update(Diagnostics diagnostics) async {
    final lock = SourceLock.load(projectDir, diagnostics);
    final hashes = <String, String>{};
    final changes = <SourceChange>[];
    for (final source in _remote) {
      final url = source.url.toString();
      final body = await _download(source, diagnostics);
      if (body == null) continue;
      final hash = sha256.convert(body).toString();
      hashes[url] = hash;
      final locked = lock.hashes[url];
      if (hash == locked) {
        if (_cachedHash(source) != hash) _store(source, body);
        continue;
      }
      final file = File(source.path);
      final before = locked != null && _cachedHash(source) == locked ? file.readAsStringSync() : null;
      _store(source, body);
      changes.add(
        SourceChange(
          source: source,
          before: locked,
          after: hash,
          summary: describeChange(before, file.readAsStringSync()),
        ),
      );
    }
    if (!diagnostics.hasErrors && !_same(hashes, lock.hashes)) SourceLock(hashes).save(projectDir);
    return changes;
  }

  String? _cachedHash(SourceRef source) {
    final file = File(source.path);
    return file.existsSync() ? sha256.convert(file.readAsBytesSync()).toString() : null;
  }

  Future<List<int>?> _download(SourceRef source, Diagnostics diagnostics) async {
    try {
      return await _fetch(source.url!);
    } on Object catch (e) {
      diagnostics.error(
        SourceCodes.unavailable,
        'cannot fetch ${source.url}: $e',
        location: source.display,
        hint: 'check the URL, or point the source at a local copy in ${SourceResolver.localFileName}',
      );
      return null;
    }
  }

  void _store(SourceRef source, List<int> body) {
    final file = File(source.path);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(body);
  }

  static bool _same(Map<String, String> a, Map<String, String> b) =>
      a.length == b.length && a.entries.every((e) => b[e.key] == e.value);
}

/// [SourceFetch] with `dart:io`.
Future<List<int>> httpFetch(Uri url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
  try {
    final response = await (await client.getUrl(url)).close().timeout(const Duration(seconds: 30));
    final body = await response.fold<List<int>>([], (all, chunk) => all..addAll(chunk));
    if (response.statusCode != HttpStatus.ok) throw HttpException('HTTP ${response.statusCode}', uri: url);
    return body;
  } finally {
    client.close();
  }
}

/// For two versions of an OpenAPI document: the change of `info.version` and the operations that
/// were added or removed. Empty for other documents, or when [before] is unknown.
List<String> describeChange(String? before, String after) {
  if (before == null) return const [];
  final (oldVersion, oldOperations) = _openApi(before);
  final (newVersion, newOperations) = _openApi(after);
  if (oldOperations == null || newOperations == null) return const [];
  return [
    if (oldVersion != newVersion) 'version $oldVersion → $newVersion',
    for (final id in newOperations.difference(oldOperations).toList()..sort()) '+ $id',
    for (final id in oldOperations.difference(newOperations).toList()..sort()) '- $id',
  ];
}

(String?, Set<String>?) _openApi(String text) {
  try {
    final yaml = loadYaml(text);
    if (yaml is! YamlMap || !yaml.containsKey('openapi')) return (null, null);
    final info = yaml['info'];
    final paths = yaml['paths'];
    return (
      info is YamlMap ? info['version']?.toString() : null,
      {
        if (paths is YamlMap)
          for (final item in paths.values)
            if (item is YamlMap)
              for (final operation in item.values)
                if (operation is YamlMap && operation['operationId'] != null) operation['operationId'].toString(),
      },
    );
  } on YamlException {
    return (null, null);
  }
}
