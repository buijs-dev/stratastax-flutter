import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'diagnostics.dart';
import 'naming.dart';

/// One `contracts:` entry of stx.yaml.
final class ContractConfig {
  const ContractConfig({
    required this.name,
    required this.spec,
    String? displaySpec,
    this.modelSuffix = '',
    this.apiSuffix = 'Api',
    this.backend = BackendConfig.defaultName,
  }) : displaySpec = displaySpec ?? spec;

  /// The [BackendConfig.name] that serves this contract.
  final String backend;

  /// The key in stx.yaml, e.g. `platformV1`; also the output directory (`platform_v1`).
  final String name;

  /// Absolute path of the bundled OpenAPI document.
  final String spec;

  /// [spec] relative to the project, used in diagnostics and generated headers so output does not
  /// depend on where the project is checked out.
  final String displaySpec;
  final String modelSuffix;
  final String apiSuffix;
}

/// One `backends:` entry of stx.yaml: a server with its own base URL and HTTP client. Every
/// contract belongs to one backend; its endpoints can only be sent with that backend's client.
final class BackendConfig {
  const BackendConfig({required this.name, this.baseUrl = 'http://localhost:8080', this.oidc = false});

  /// Without `backends:` every contract goes to this one, overridable with `STX_API_BASE_URL`.
  static const defaultName = 'api';

  /// The key in stx.yaml; a Dart member name (`platform` → `AppServices.platform`).
  final String name;

  /// Default base URL; overridable at runtime with `--dart-define=<[envName]>=…`.
  final String baseUrl;

  /// `auth: oidc`: calls carry the session's bearer token.
  final bool oidc;

  /// `STX_PLATFORM_BASE_URL` for `platform`.
  String get envName => 'STX_${Naming.snake(name).toUpperCase()}_BASE_URL';

  /// `Platform` → `PlatformEndpoint`, `PlatformClient`.
  String get typePrefix => Naming.pascal(name);
}

/// The `i18n:` section of stx.yaml.
final class I18nConfig {
  const I18nConfig({
    required this.dir,
    this.base = 'en',
    this.locales = const ['en'],
    this.missingIsError = true,
    this.deferred = true,
  });

  /// Absolute directory with `<locale>.yaml` files.
  final String dir;
  final String base;

  /// Includes [base], which comes first.
  final List<String> locales;

  /// `missing: error` (default) or `missing: fallback` (to the base locale) for non-base locales.
  final bool missingIsError;

  /// Load non-base locales as deferred libraries.
  final bool deferred;
}

/// The `security:` section of stx.yaml.
final class SecurityConfig {
  const SecurityConfig({
    required this.issuer,
    required this.clientId,
    this.scopes = const ['openid', 'profile'],
    this.roleClaims,
    this.social = const {},
  });

  /// The OIDC issuer (Keycloak realm URL); overridable at runtime with `--dart-define=STX_OIDC_ISSUER`.
  final String issuer;
  final String clientId;
  final List<String> scopes;

  /// Null: the stx_security defaults (`realm_access.roles`, `resource_access.*.roles`, `scope`, `groups`).
  final List<String>? roleClaims;

  /// Social providers: Keycloak `kc_idp_hint` → name on the button (`google: Google`).
  final Map<String, String> social;
}

/// The parsed stx.yaml of a consumer app.
final class StxConfig {
  const StxConfig({
    required this.projectDir,
    required this.contracts,
    required this.output,
    required this.i18n,
    this.backends = const [BackendConfig(name: BackendConfig.defaultName)],
    this.tokens,
    this.displayTokens,
    this.security,
  });

  /// At least one; without `backends:` in stx.yaml the single [BackendConfig.defaultName].
  final List<BackendConfig> backends;

  /// Null when the app has no login.
  final SecurityConfig? security;

  final String projectDir;
  final List<ContractConfig> contracts;

  /// Absolute path of `stx.tokens.yaml`; null when the app uses the defaults only.
  final String? tokens;
  final String? displayTokens;
  final I18nConfig i18n;

  /// Absolute output directory, `lib/gen` by default.
  final String output;

  static const fileName = 'stx.yaml';

  /// Reads `<projectDir>/stx.yaml`; returns null and reports when it cannot be used.
  static StxConfig? load(String projectDir, Diagnostics diagnostics) {
    final file = File(p.join(projectDir, fileName));
    final location = file.path;
    if (!file.existsSync()) {
      diagnostics.error(ContractCodes.unreadable, 'no $fileName found', location: location);
      return null;
    }
    final Object? root;
    try {
      root = loadYaml(file.readAsStringSync());
    } on YamlException catch (e) {
      diagnostics.error(ContractCodes.unreadable, 'invalid YAML: ${e.message}', location: location);
      return null;
    }
    if (root is! YamlMap) {
      diagnostics.error(ContractCodes.unreadable, 'expected a mapping at the root', location: location);
      return null;
    }

    const known = {'backends', 'contracts', 'tokens', 'i18n', 'security', 'output'};
    for (final key in root.keys) {
      if (!known.contains(key)) {
        diagnostics.warning(ContractCodes.unreadable, 'unknown key "$key" is ignored', location: location);
      }
    }

    final hasSecurity = root['security'] is YamlMap;
    final backends = <BackendConfig>[];
    switch (root['backends']) {
      case null:
        backends.add(BackendConfig(name: BackendConfig.defaultName, oidc: hasSecurity));
      case final YamlMap node:
        for (final entry in node.entries) {
          final name = entry.key.toString();
          final value = entry.value is YamlMap ? entry.value as YamlMap : YamlMap();
          final auth = value['auth']?.toString() ?? (hasSecurity ? 'oidc' : 'none');
          if (Naming.member(name) != name || _reserved.contains(name)) {
            diagnostics.error(
              ContractCodes.unreadable,
              'backend "$name" must be a lowerCamelCase Dart name other than ${_reserved.join(', ')}',
              location: location,
            );
          } else if (auth != 'oidc' && auth != 'none') {
            diagnostics.error(ContractCodes.unreadable, 'backend "$name": auth is oidc or none', location: location);
          } else if (auth == 'oidc' && !hasSecurity) {
            diagnostics.error(
              ContractCodes.unreadable,
              'backend "$name" uses auth: oidc, but stx.yaml has no "security" section',
              location: location,
            );
          } else {
            backends.add(
              BackendConfig(
                name: name,
                baseUrl: value['baseUrl']?.toString() ?? 'http://localhost:8080',
                oidc: auth == 'oidc',
              ),
            );
          }
        }
        if (node.isEmpty) diagnostics.error(ContractCodes.unreadable, '"backends" is empty', location: location);
      default:
        diagnostics.error(ContractCodes.unreadable, '"backends" must be a mapping', location: location);
    }
    final backendNames = {for (final b in backends) b.name};

    final contracts = <ContractConfig>[];
    final contractsNode = root['contracts'];
    if (contractsNode is YamlMap) {
      for (final entry in contractsNode.entries) {
        final name = entry.key.toString();
        final value = entry.value;
        final spec = value is YamlMap ? value['spec'] : null;
        if (spec is! String) {
          diagnostics.error(ContractCodes.unreadable, 'contract "$name" needs a "spec" path', location: location);
          continue;
        }
        final backend =
            (value as YamlMap)['backend']?.toString() ?? (backends.length == 1 ? backends.single.name : null);
        if (backend == null || !backendNames.contains(backend)) {
          diagnostics.error(
            ContractCodes.unreadable,
            backend == null
                ? 'contract "$name" needs "backend: <${backendNames.join('|')}>"'
                : 'contract "$name": unknown backend "$backend" (known: ${backendNames.join(', ')})',
            location: location,
          );
          continue;
        }
        contracts.add(
          ContractConfig(
            name: name,
            spec: p.normalize(p.join(projectDir, spec)),
            displaySpec: p.posix.normalize(spec),
            modelSuffix: value['modelSuffix']?.toString() ?? '',
            apiSuffix: value['apiSuffix']?.toString() ?? 'Api',
            backend: backend,
          ),
        );
      }
    } else if (contractsNode != null) {
      diagnostics.error(ContractCodes.unreadable, '"contracts" must be a mapping', location: location);
    }

    final tokens = root['tokens']?.toString();

    final i18nNode = root['i18n'] is YamlMap ? root['i18n'] as YamlMap : YamlMap();
    final base = i18nNode['base']?.toString() ?? 'en';
    final locales = <String>[
      base,
      for (final l in (i18nNode['locales'] as List?) ?? const []) ?(l.toString() == base ? null : l.toString()),
    ];
    final i18n = I18nConfig(
      dir: p.normalize(p.join(projectDir, i18nNode['dir']?.toString() ?? 'i18n')),
      base: base,
      locales: locales,
      missingIsError: i18nNode['missing']?.toString() != 'fallback',
      deferred: i18nNode['deferred'] != false,
    );

    SecurityConfig? security;
    if (root['security'] case final YamlMap node) {
      final oidc = node['oidc'];
      final issuer = oidc is YamlMap ? oidc['issuer']?.toString() : null;
      final clientId = oidc is YamlMap ? oidc['clientId']?.toString() : null;
      if (issuer == null || clientId == null) {
        diagnostics.error(ContractCodes.unreadable, 'security.oidc needs "issuer" and "clientId"', location: location);
      } else {
        final social = node['social'];
        security = SecurityConfig(
          issuer: issuer,
          clientId: clientId,
          scopes: [
            for (final s in (oidc as YamlMap)['scopes'] as List? ?? const ['openid', 'profile']) s.toString(),
          ],
          roleClaims: (oidc['roleClaims'] as List?)?.map((e) => e.toString()).toList(),
          social: switch (social) {
            YamlMap() => {for (final e in social.entries) e.key.toString(): e.value.toString()},
            YamlList() => {
              for (final name in social)
                name.toString(): name.toString()[0].toUpperCase() + name.toString().substring(1),
            },
            _ => const {},
          },
        );
      }
    }

    final output = root['output']?.toString() ?? 'lib/gen';
    return StxConfig(
      projectDir: projectDir,
      contracts: contracts,
      output: p.normalize(p.join(projectDir, output)),
      tokens: tokens == null ? null : p.normalize(p.join(projectDir, tokens)),
      displayTokens: tokens == null ? null : p.posix.normalize(tokens),
      i18n: i18n,
      backends: backends,
      security: security,
    );
  }

  /// Members of the generated `AppServices` that a backend cannot be named after.
  static const _reserved = {'config', 'session', 'access', 'start', 'loginOptions', 'of'};

  /// The backend of contract [name].
  BackendConfig backendOf(String name) {
    final backend = contracts.firstWhere((c) => c.name == name).backend;
    return backends.firstWhere((b) => b.name == backend);
  }
}
