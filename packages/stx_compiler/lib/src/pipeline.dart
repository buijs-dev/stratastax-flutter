import 'dart:io';

import 'package:dart_style/dart_style.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'config.dart';
import 'contract/contract_frontend.dart';
import 'contract/contract_renderer.dart';
import 'contract/ir.dart';
import 'contract/scope_registry.dart';
import 'diagnostics.dart';
import 'naming.dart';
import 'i18n/i18n_frontend.dart';
import 'i18n/i18n_renderer.dart';
import 'output.dart';
import 'package_locator.dart';
import 'remote_source.dart';
import 'style/style_frontend.dart';
import 'style/style_ir.dart';
import 'style/style_renderer.dart';
import 'ui/annotation_frontend.dart';
import 'ui/app_plan.dart';
import 'ui/app_renderer.dart';
import 'ui/ui_ir.dart';

final class BuildResult {
  const BuildResult({
    required this.diagnostics,
    this.contracts = const [],
    this.style,
    this.i18n,
    this.ui,
    this.app,
    this.missingKeys = const {},
    this.files = const [],
    this.write,
  });

  final UiIR? ui;
  final AppPlan? app;

  /// Translation keys generated pages need but the base locale lacks → suggested text.
  final Map<String, String> missingKeys;

  final Diagnostics diagnostics;
  final List<ContractIR> contracts;
  final StyleIR? style;
  final I18nIR? i18n;
  final List<GeneratedFile> files;

  /// Null when nothing was written (errors, or a dry run).
  final WriteResult? write;
}

/// The stx pipeline.
///
/// ```
/// phase 1  contracts → ContractIR ┐
///          tokens    → StyleIR    ├→ render + write lib/gen/{contract,style,i18n}
///          i18n      → I18nIR     ┘
/// phase 2  lib/**.dart (analyzer, resolved against phase 1) → UiIR
///          UiIR × ContractIR × I18nIR → AppPlan → render + write lib/gen/app
/// ```
///
/// Before phase 1 the remote sources (specs, tokens) are fetched into the cache and checked
/// against stx.lock.
final class StxPipeline {
  const StxPipeline(this.projectDir, {this.offline = false, this.fetch});

  final String projectDir;

  /// Only use cached remote sources.
  final bool offline;

  /// Null: [httpFetch].
  final SourceFetch? fetch;

  static const _phase1Dirs = ['contract', 'style', 'i18n'];

  /// Parses everything; renders and writes only when there are no errors and [write] is true.
  /// Without [write], phase 2 analyzes the phase 1 output already on disk.
  Future<BuildResult> run({bool write = true}) async {
    final diagnostics = Diagnostics();
    final config = StxConfig.load(projectDir, diagnostics);
    if (config == null || diagnostics.hasErrors) return BuildResult(diagnostics: diagnostics);
    await RemoteSources(
      projectDir,
      config.sources,
      offline: offline,
      fetch: fetch,
    ).resolve(diagnostics, updateLock: write);
    if (diagnostics.hasErrors) return BuildResult(diagnostics: diagnostics);
    final packages = PackageLocator.forProject(projectDir);
    final dependencies = _dependencies(projectDir);

    // Phase 1: YAML sources.
    final contracts = <ContractIR>[
      for (final contract in config.contracts) ?ContractFrontend(contract, diagnostics).parseFile(),
    ];

    StyleIR? style;
    if (packages.lib('stx_style') case final styleLib? when dependencies.contains('stx_style')) {
      style = StyleFrontend(diagnostics).parseFiles(
        defaults: p.join(styleLib, 'defaults', 'defaults.tokens.yaml'),
        base: config.tokensBase,
        displayBase: config.displayTokensBase,
        app: config.tokens,
        displayApp: config.displayTokens,
      );
    } else if (config.tokens != null || config.tokensBase != null) {
      diagnostics.error(
        StyleCodes.missing,
        'stx.yaml configures tokens but the app does not depend on stx_style',
        location: StxConfig.fileName,
      );
    }

    I18nIR? i18n;
    if (packages.lib('stx_i18n') case final i18nLib? when dependencies.contains('stx_i18n')) {
      i18n = I18nFrontend(config.i18n, diagnostics).parseFiles(
        frameworkDir: p.join(i18nLib, 'i18n'),
        displayDir: p.relative(config.i18n.dir, from: projectDir),
      );
    }

    if (diagnostics.hasErrors) {
      return BuildResult(diagnostics: diagnostics, contracts: contracts, style: style, i18n: i18n);
    }

    final formatter = GeneratedFormatter();
    final files = <GeneratedFile>[];
    try {
      final scopes = ScopeRegistry(contracts);
      for (final contract in contracts) {
        files.addAll(
          ContractRenderer(contract, scopes, backend: config.backendOf(contract.name)).render().map(formatter.format),
        );
      }
      if (scopes.claims.isNotEmpty) {
        files.add(formatter.format(GeneratedFile('contract/scopes.g.dart', renderScopes(scopes))));
      }
      if (contracts.isNotEmpty) {
        final byBackend = <String, List<String>>{};
        for (final c in config.contracts) {
          byBackend.putIfAbsent(c.backend, () => []).add(c.name);
        }
        files.add(
          formatter.format(GeneratedFile('contract/backends.g.dart', renderBackends(config.backends, byBackend))),
        );
      }
      if (style != null) files.add(formatter.format(renderStyle(style)));
      if (i18n != null) {
        files.addAll(renderI18n(i18n, deferred: config.i18n.deferred, diagnostics: diagnostics).map(formatter.format));
      }
    } on FormatterException catch (e) {
      diagnostics.error('STX-X001', 'generated invalid Dart (compiler bug): ${e.message()}', location: projectDir);
    }
    if (diagnostics.hasErrors) {
      return BuildResult(diagnostics: diagnostics, contracts: contracts, style: style, i18n: i18n);
    }

    final phase1 = write ? writeGenerated(config.output, files, ownedDirs: _phase1Dirs) : null;

    // Phase 2: annotated Dart sources, resolved against the phase 1 output.
    final ui = await AnnotationFrontend(projectDir, config.output, diagnostics).parse();
    AppPlan? app;
    var missingKeys = const <String, String>{};
    final appFiles = <GeneratedFile>[];
    if (ui.forms.isNotEmpty || ui.dataSources.isNotEmpty || config.i18n.remote != null) {
      if (style == null || i18n == null) {
        diagnostics.error(
          UiCodes.annotation,
          'generated pages need stx_style and stx_i18n; add them to the app dependencies',
          location: StxConfig.fileName,
        );
      } else if (!diagnostics.hasErrors) {
        final planner = AppPlanner(
          ui: ui,
          contracts: contracts,
          i18n: i18n,
          diagnostics: diagnostics,
          searchConfig: config.search,
        );
        app = planner.plan();
        missingKeys = planner.missingKeys;
        if (!diagnostics.hasErrors) {
          try {
            appFiles.addAll(
              AppRenderer(
                app,
                ScopeRegistry(contracts),
                security: config.security,
                backends: config.backends,
                contractBackends: {for (final c in config.contracts) Naming.snake(c.name): c.backend},
                i18nRemote: config.i18n.remote,
                search: config.search,
              ).render().map(formatter.format),
            );
          } on FormatterException catch (e) {
            diagnostics.error(
              'STX-X001',
              'generated invalid Dart (compiler bug): ${e.message()}',
              location: projectDir,
            );
          }
        }
      }
    }
    final phase2 = (write && !diagnostics.hasErrors)
        ? writeGenerated(config.output, appFiles, ownedDirs: const ['app'])
        : null;

    return BuildResult(
      diagnostics: diagnostics,
      contracts: contracts,
      style: style,
      i18n: i18n,
      ui: ui,
      app: app,
      missingKeys: missingKeys,
      files: [...files, ...appFiles],
      write: phase1 == null
          ? null
          : WriteResult(
              written: [...phase1.written, ...?phase2?.written],
              unchanged: phase1.unchanged + (phase2?.unchanged ?? 0),
              deleted: [...phase1.deleted, ...?phase2?.deleted],
            ),
    );
  }

  /// The direct dependencies in the project's pubspec.yaml; style and i18n are only generated for
  /// apps that depend on stx_style / stx_i18n (a server using only the contract code does not).
  static Set<String> _dependencies(String projectDir) {
    final file = File(p.join(projectDir, 'pubspec.yaml'));
    if (!file.existsSync()) return const {};
    final yaml = loadYaml(file.readAsStringSync());
    final deps = yaml is YamlMap ? yaml['dependencies'] : null;
    return deps is YamlMap ? {for (final k in deps.keys) k.toString()} : const {};
  }
}
