import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:stx_compiler/stx_compiler.dart';
import 'package:test/test.dart';

String _spec(String version, List<String> operations) =>
    '''
openapi: 3.1.0
info: { title: Test, version: $version }
paths:
${[for (final id in operations) '  /$id:\n    get: { operationId: $id }'].join('\n')}
''';

void main() {
  late Directory dir;
  late HttpServer server;
  late Map<String, String> files;
  late List<String> requests;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('stx_sources');
    files = {
      '/openapi/platform.yaml': _spec('1.0.0', ['listMatches']),
      '/design/tokens.yaml': 'color: {}\n',
    };
    requests = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      requests.add(request.uri.path);
      final body = files[request.uri.path];
      request.response.statusCode = body == null ? HttpStatus.notFound : HttpStatus.ok;
      request.response
        ..write(body ?? 'not found')
        ..close();
    });
  });
  tearDown(() async {
    await server.close(force: true);
    dir.deleteSync(recursive: true);
  });

  String base() => 'http://localhost:${server.port}';

  (StxConfig?, Diagnostics) load(String yaml, {String? local}) {
    File(p.join(dir.path, 'stx.yaml')).writeAsStringSync(yaml);
    if (local != null) File(p.join(dir.path, 'stx.local.yaml')).writeAsStringSync(local);
    final diagnostics = Diagnostics();
    return (StxConfig.load(dir.path, diagnostics), diagnostics);
  }

  String stxYaml() =>
      '''
sources:
  stratastax: ${base()}
contracts:
  platformV1: { spec: 'stratastax:openapi/platform.yaml' }
tokens: { base: 'stratastax:design/tokens.yaml', file: stx.tokens.yaml }
''';

  Future<Diagnostics> resolve(StxConfig config, {bool offline = false}) async {
    final diagnostics = Diagnostics();
    await RemoteSources(dir.path, config.sources, offline: offline).resolve(diagnostics);
    return diagnostics;
  }

  String lock() => File(p.join(dir.path, 'stx.lock')).readAsStringSync();

  test('references: <source>:<path>, a URL or a local path; the display keeps what was written', () {
    final (config, diagnostics) = load(stxYaml());
    expect(diagnostics.all, isEmpty);
    final spec = config!.contracts.single;
    expect(spec.displaySpec, 'stratastax:openapi/platform.yaml');
    expect(
      spec.spec,
      p.join(dir.path, '.dart_tool', 'stx', 'sources', 'localhost_${server.port}', 'openapi', 'platform.yaml'),
    );
    expect(config.displayTokensBase, 'stratastax:design/tokens.yaml');
    expect(config.tokens, p.join(dir.path, 'stx.tokens.yaml'));
    expect(
      [for (final s in config.sources) s.url?.toString()],
      ['${base()}/openapi/platform.yaml', null, '${base()}/design/tokens.yaml'],
    );

    final (direct, _) = load('contracts:\n  platformV1: { spec: "https://example.test/a/b.yaml" }\n');
    expect(
      direct!.contracts.single.spec,
      p.join(dir.path, '.dart_tool', 'stx', 'sources', 'example.test', 'a', 'b.yaml'),
    );
  });

  test('stx.local.yaml points a source at a local checkout', () {
    final (config, diagnostics) = load(stxYaml(), local: 'sources:\n  stratastax: ../horizon/public\n');
    expect(diagnostics.all, isEmpty);
    final spec = config!.contracts.single;
    expect(spec.spec, p.normalize(p.join(dir.path, '..', 'horizon', 'public', 'openapi', 'platform.yaml')));
    expect(spec.displaySpec, 'stratastax:openapi/platform.yaml'); // generated headers do not change
    expect(config.sources.every((s) => !s.isRemote), isTrue);
  });

  test('an unknown source is an error (STX-R003)', () {
    final (_, diagnostics) = load('contracts:\n  platformV1: { spec: "other:a.yaml" }\n');
    expect(diagnostics.all.single.code, SourceCodes.invalid);
    expect(diagnostics.all.single.message, contains('unknown source "other"'));
  });

  test('a new source is fetched and locked; then the cache is used without the network', () async {
    final (config, _) = load(stxYaml());
    expect((await resolve(config!)).all, isEmpty);
    expect(File(config.contracts.single.spec).readAsStringSync(), files['/openapi/platform.yaml']);
    expect(lock(), contains('"${base()}/openapi/platform.yaml": '));
    expect(lock(), contains('"${base()}/design/tokens.yaml": '));
    expect(requests, hasLength(2));

    final locked = lock();
    expect((await resolve(config)).all, isEmpty);
    expect(requests, hasLength(2));
    expect(lock(), locked);
  });

  test('a source that changed since it was locked is an error until `update` (STX-R002)', () async {
    final (config, _) = load(stxYaml());
    await resolve(config!);
    files['/openapi/platform.yaml'] = _spec('1.1.0', ['getMatch']);
    final cached = File(config.contracts.single.spec)..deleteSync(); // e.g. a fresh checkout

    final mismatch = await resolve(config);
    expect(mismatch.all.single.code, SourceCodes.lockMismatch);
    expect(mismatch.all.single.hint, contains('stx sources update'));
    expect(cached.existsSync(), isFalse);

    final diagnostics = Diagnostics();
    final changes = await RemoteSources(dir.path, config.sources).update(diagnostics);
    expect(diagnostics.all, isEmpty);
    expect(changes.single.source.display, 'stratastax:openapi/platform.yaml');
    expect(changes.single.summary, isEmpty); // the old version was no longer cached
    expect((await resolve(config)).all, isEmpty);
  });

  test('update summarizes the change of an OpenAPI document', () async {
    final (config, _) = load(stxYaml());
    await resolve(config!);
    files['/openapi/platform.yaml'] = _spec('1.1.0', ['listMatches', 'getMatch']);
    final changes = await RemoteSources(dir.path, config.sources).update(Diagnostics());
    expect(changes.single.summary, ['version 1.0.0 → 1.1.0', '+ getMatch']);
    expect(File(config.contracts.single.spec).readAsStringSync(), contains('getMatch'));
  });

  test('offline: only the cache; a missing copy is an error (STX-R001)', () async {
    final (config, _) = load(stxYaml());
    final missing = await resolve(config!, offline: true);
    expect(missing.all.map((d) => d.code), everyElement(SourceCodes.unavailable));
    expect(requests, isEmpty);

    await resolve(config);
    expect((await resolve(config, offline: true)).all, isEmpty);
    expect(requests, hasLength(2));
  });

  test('a failed fetch is reported with the reference (STX-R001)', () async {
    final (config, _) = load('contracts:\n  platformV1: { spec: "${base()}/missing.yaml" }\n');
    final diagnostics = await resolve(config!);
    expect(diagnostics.all.single.code, SourceCodes.unavailable);
    expect(diagnostics.all.single.message, contains('HTTP 404'));
    expect(File(p.join(dir.path, 'stx.lock')).existsSync(), isFalse);
  });

  test('sources stx.yaml no longer uses are dropped from the lock', () async {
    final (config, _) = load(stxYaml());
    await resolve(config!);
    final (fewer, _) = load(
      'sources:\n  stratastax: ${base()}\ncontracts:\n  platformV1: { spec: "stratastax:openapi/platform.yaml" }\n',
    );
    await resolve(fewer!);
    expect(lock(), isNot(contains('design/tokens.yaml')));
  });
}
