// The stx CLI (docs/ARCHITECTURE.md §3).
import 'dart:async';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:stx_compiler/stx_compiler.dart';

Future<void> main(List<String> args) async {
  final runner = CommandRunner<int>('stx', 'stratastax-flutter compiler.')
    ..argParser.addOption('project', abbr: 'p', help: 'Directory with stx.yaml.', defaultsTo: '.')
    ..argParser.addFlag('offline', help: 'Only use the cached remote sources (specs, tokens) of stx.lock.')
    ..addCommand(_Build())
    ..addCommand(_Watch())
    ..addCommand(_Scan())
    ..addCommand(_I18n())
    ..addCommand(_Sources());
  try {
    exitCode = await runner.run(args) ?? 0;
  } on UsageException catch (e) {
    stderr.writeln(e);
    exitCode = 64;
  }
}

String _project(Command<int> command) => Directory(command.globalResults!['project'] as String).absolute.path;

StxPipeline _pipeline(Command<int> command) =>
    StxPipeline(_project(command), offline: command.globalResults!['offline'] as bool);

/// Prints diagnostics; returns the exit code.
int _report(Diagnostics diagnostics) {
  for (final d in diagnostics.all) {
    (d.isError ? stderr : stdout).writeln(d);
  }
  return diagnostics.hasErrors ? 1 : 0;
}

final class _Build extends Command<int> {
  @override
  String get name => 'build';

  @override
  String get description =>
      'Generate lib/gen from stx.yaml: contracts, tokens, translations and the annotated app code.';

  @override
  Future<int> run() async {
    final result = await _pipeline(this).run();
    final code = _report(result.diagnostics);
    if (result.write case final write?) {
      stdout.writeln(
        'stx build: ${result.files.length} files, ${write.written.length} written, '
        '${write.unchanged} unchanged, ${write.deleted.length} deleted',
      );
    }
    return code;
  }
}

final class _Scan extends Command<int> {
  _Scan() {
    argParser.addFlag('contracts', help: 'Also print the full contract IR (schemas and operations).');
  }

  @override
  String get name => 'scan';

  @override
  String get description =>
      'Print the IR as YAML (like stratastaxScan): backends, the merged app IR (forms, fields, '
      'contract mapping, rules, keys, scopes), and summaries of the contract, style and i18n IR.';

  @override
  Future<int> run() async {
    final project = _project(this);
    final result = await _pipeline(this).run(write: false);
    final code = _report(result.diagnostics);
    final config = StxConfig.load(project, Diagnostics());
    if (config != null) {
      stdout.write(toYaml(scanReport(result, config, contracts: argResults!['contracts'] as bool)));
    }
    return code;
  }
}

final class _Sync extends Command<int> {
  @override
  String get name => 'sync';

  @override
  String get description =>
      'Add the translation keys generated pages need to i18n/<locale>.yaml (suggested text in the base '
      'locale, the base text in the others), then build.';

  @override
  Future<int> run() async {
    final project = _project(this);
    final first = await _pipeline(this).run();
    if (first.missingKeys.isEmpty) {
      final code = _report(first.diagnostics);
      stdout.writeln('stx i18n sync: all keys present');
      return code;
    }
    final config = StxConfig.load(project, Diagnostics())!;
    final result = syncTranslations(config.i18n, first.missingKeys);
    for (final entry in result.added.entries) {
      final translate = entry.key == config.i18n.base ? 'check the suggested text' : 'translate (base text inserted)';
      stdout.writeln('${entry.key}.yaml: ${entry.value.length} key(s) added, $translate:');
      for (final key in entry.value) {
        stdout.writeln('  $key: ${first.missingKeys[key]}');
      }
    }
    final second = await _pipeline(this).run();
    return _report(second.diagnostics);
  }
}

final class _Watch extends Command<int> {
  @override
  String get name => 'watch';

  @override
  String get description =>
      'Build, then rebuild when stx.yaml, a contract, the tokens, a translation or app code changes. '
      'Only changed files are written, so hot reload picks up exactly what changed.';

  @override
  Future<int> run() async {
    final project = _project(this);
    StxConfig config() =>
        StxConfig.load(project, Diagnostics()) ??
        StxConfig(
          projectDir: project,
          contracts: const [],
          output: '$project/lib/gen',
          i18n: I18nConfig(dir: '$project/i18n'),
        );
    final stop = Completer<void>();
    ProcessSignal.sigint.watch().first.then((_) => stop.complete());
    await watchProject(config, (changed) async {
      final clock = Stopwatch()..start();
      if (changed.isNotEmpty) stdout.writeln('\nchanged: ${changed.join(', ')}');
      final result = await _pipeline(this).run();
      _report(result.diagnostics);
      final write = result.write;
      stdout.writeln(
        write == null
            ? 'stx watch: build failed (${clock.elapsedMilliseconds} ms), waiting for changes'
            : 'stx watch: ${write.written.length} written, ${write.deleted.length} deleted (${clock.elapsedMilliseconds} ms); '
                  'watching for changes (Ctrl-C stops)',
      );
    }, stop: stop.future);
    return 0;
  }
}

final class _I18n extends Command<int> {
  _I18n() {
    addSubcommand(_Sync());
  }

  @override
  String get name => 'i18n';

  @override
  String get description => 'Manage translation files.';
}

final class _Sources extends Command<int> {
  _Sources() {
    addSubcommand(_SourcesUpdate());
  }

  @override
  String get name => 'sources';

  @override
  String get description => 'Manage the remote sources of stx.yaml (specs, tokens) and stx.lock.';
}

final class _SourcesUpdate extends Command<int> {
  @override
  String get name => 'update';

  @override
  String get description => 'Fetch the latest version of every remote source, show what changed and update stx.lock.';

  @override
  Future<int> run() async {
    final project = _project(this);
    final diagnostics = Diagnostics();
    final config = StxConfig.load(project, diagnostics);
    if (config == null || diagnostics.hasErrors) return _report(diagnostics);
    final changes = await RemoteSources(project, config.sources).update(diagnostics);
    for (final change in changes) {
      stdout.writeln('${change.source.display}: ${change.before == null ? 'locked' : 'updated'}');
      for (final line in change.summary) {
        stdout.writeln('  $line');
      }
    }
    final code = _report(diagnostics);
    if (code == 0) {
      stdout.writeln(
        changes.isEmpty
            ? 'stx sources update: everything up to date'
            : 'stx sources update: ${SourceLock.fileName} updated; run stx build',
      );
    }
    return code;
  }
}
