import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:stx_compiler/stx_compiler.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  late StxConfig config;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('stx_watch');
    final root = dir.resolveSymbolicLinksSync();
    File(
      p.join(root, 'stx.yaml'),
    ).writeAsStringSync('contracts:\n  platformV1: { spec: openapi/platform.yaml }\ntokens: stx.tokens.yaml\n');
    Directory(p.join(root, 'lib', 'gen')).createSync(recursive: true);
    Directory(p.join(root, 'i18n')).createSync();
    config = StxConfig.load(root, Diagnostics())!;
  });
  tearDown(() => dir.deleteSync(recursive: true));

  String at(String relative) => p.join(config.projectDir, relative);

  test('what affects the build', () {
    expect(affectsBuild(config, at('stx.yaml')), isTrue);
    expect(affectsBuild(config, at('openapi/platform.yaml')), isTrue);
    expect(affectsBuild(config, at('stx.tokens.yaml')), isTrue);
    expect(affectsBuild(config, at('i18n/nl.yaml')), isTrue);
    expect(affectsBuild(config, at('lib/features/matches/match.dart')), isTrue);

    expect(affectsBuild(config, at('lib/gen/app/app.g.dart')), isFalse); // our own output
    expect(affectsBuild(config, at('openapi/other.yaml')), isFalse);
    expect(affectsBuild(config, at('test/app_test.dart')), isFalse);
    expect(affectsBuild(config, at('build/web/main.dart.js')), isFalse);
  });

  test('builds once, then once per burst of relevant changes', () async {
    final builds = <List<String>>[];
    final built = StreamController<void>.broadcast();
    final stop = Completer<void>();
    final initial = built.stream.first;
    final watching = watchProject(
      () => config,
      (changed) async {
        builds.add(changed);
        built.add(null);
      },
      stop: stop.future,
      debounce: const Duration(milliseconds: 50),
    );
    await initial; // the initial build
    await Future<void>.delayed(const Duration(milliseconds: 300)); // let the watcher start

    final next = built.stream.first;
    File(at('i18n/en.yaml')).writeAsStringSync('a: A');
    File(at('lib/gen/x.g.dart')).writeAsStringSync('// ignored');
    File(at('lib/feature.dart')).writeAsStringSync('// app code');
    await next.timeout(const Duration(seconds: 5));

    stop.complete();
    await watching;
    expect(builds, [
      <String>[],
      [p.join('i18n', 'en.yaml'), p.join('lib', 'feature.dart')],
    ]);
  });
}
