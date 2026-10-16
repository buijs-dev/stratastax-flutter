import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:stx_compiler/stx_compiler.dart';
import 'package:test/test.dart';

/// Runs the pipeline over examples/match_tracker, which uses the real bundled contracts of
/// stratastax-contract (platform and catalog).
void main() {
  final project = p.normalize(p.join(Directory.current.path, '..', '..', 'examples', 'match_tracker'));
  late BuildResult result;

  setUpAll(() async => result = await StxPipeline(project).run(write: false));

  test('the real contracts produce no diagnostics', () {
    expect(result.diagnostics.all, isEmpty);
  });

  test('every operation of both contracts is generated', () {
    final platform = result.contracts.firstWhere((c) => c.name == 'platformV1');
    final catalog = result.contracts.firstWhere((c) => c.name == 'catalogV1');
    expect(platform.operations, hasLength(69));
    expect(catalog.operations, hasLength(8));
    expect(platform.operations.every((o) => o.security is ScopedSecurity), isTrue);
  });

  test('generated code on disk is up to date (run `stx build` in examples/match_tracker)', () {
    final stale = <String>[];
    for (final file in result.files) {
      final onDisk = File(p.joinAll([project, 'lib', 'gen', ...file.path.split('/')]));
      if (!onDisk.existsSync() || onDisk.readAsStringSync() != file.content) stale.add(file.path);
    }
    expect(stale, isEmpty);
  });

  test('output is deterministic', () async {
    final again = await StxPipeline(project).run(write: false);
    expect([for (final f in again.files) f.content], [for (final f in result.files) f.content]);
  });

  test('stx scan: the merged app IR per form, field and data source', () {
    final config = StxConfig.load(project, Diagnostics())!;
    final yaml = toYaml(scanReport(result, config));
    expect(yaml, contains('platform:\n    baseUrl: \'http://localhost:9000\''));
    final match = (scanReport(result, config)['app']! as Map)['forms'] as List;
    final form = match.cast<Map<String, Object?>>().singleWhere((f) => f['name'] == 'MatchCreateCommand');
    expect(form['submit'], containsPair('backend', 'platform'));
    expect(form['requires'], ['stx-engine:match-create', 'stx-engine:ghost-player-read', 'stx-engine:game-read']);
    final gameId = (form['fields']! as List).cast<Map<String, Object?>>().first;
    expect(gameId, containsPair('kind', 'autocomplete'));
    expect(gameId, containsPair('property', 'gameId (uuid, required)'));
    expect(gameId, containsPair('source', 'GameSearchSource'));
    expect(yaml, isNot(contains('contractIR')));
  });
}
