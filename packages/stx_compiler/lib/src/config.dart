import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

import 'diagnostics.dart';
import 'naming.dart';
import 'remote_source.dart';

/// `search:` of stx.yaml: the defaults of every overview (`@UiListPage` overrides them per page).
final class SearchConfig {
  const SearchConfig({this.pageSize = 20, this.cacheMode = 'memory', this.cacheTtl = 60, this.cacheMaxEntries = 200});

  /// `limit` of every page; the contract allows 1–100.
  final int pageSize;

  /// `none`, `memory` or `staleWhileRevalidate` (`StxCacheMode`).
  final String cacheMode;

  /// Seconds.
  final int cacheTtl;

  /// Of the one cache all overviews share.
  final int cacheMaxEntries;
}

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

  /// Absolute path of the bundled OpenAPI document; for a remote spec its copy in the cache.
  final String spec;

  /// [spec] as written in stx.yaml (relative to the project, a URL or `<source>:<path>`), used in
  /// diagnostics and generated headers so output does not depend on where the project is checked out.
  final String displaySpec;
  final String modelSuffix;
  final String apiSuffix;
}

/// How the client of a backend authenticates.
enum BackendAuth {
  /// No token.
  none,

  /// The user's session (stx.yaml `security`).
  oidc,

  /// Its own service account (client credentials), independent of the user.
  serviceAccount,

  /// A fixed token from `--dart-define=STX_<BACKEND>_TOKEN` (or `AppConfig.<backend>Tokens`).
  token,
}

/// `serviceAccount:` of a backend with `auth: serviceAccount`.
final class ServiceAccountSettings {
  const ServiceAccountSettings({required this.clientId, this.issuer, this.scopes = const []});

  final String clientId;

  /// Null: the issuer of `security.oidc`.
  final String? issuer;
  final List<String> scopes;
}

/// One `backends:` entry of stx.yaml: a server with its own base URL and HTTP client. Every
/// contract belongs to one backend; its endpoints can only be sent with that backend's client.
final class BackendConfig {
  const BackendConfig({
    required this.name,
    this.baseUrl = 'http://localhost:8080',
    this.auth = BackendAuth.none,
    this.serviceAccount,
  });

  /// Without `backends:` every contract goes to this one, overridable with `STX_API_BASE_URL`.
  static const defaultName = 'api';

  /// The key in stx.yaml; a Dart member name (`platform` → `AppServices.platform`).
  final String name;

  /// Default base URL; overridable at runtime with `--dart-define=<[envName]>=…`.
  final String baseUrl;

  final BackendAuth auth;

  /// Set for [BackendAuth.serviceAccount].
  final ServiceAccountSettings? serviceAccount;

  /// `auth: oidc`: calls carry the session's bearer token.
  bool get oidc => auth == BackendAuth.oidc;

  /// Whether the backend has tokens of its own ([BackendAuth.serviceAccount], [BackendAuth.token]).
  bool get ownTokens => auth == BackendAuth.serviceAccount || auth == BackendAuth.token;

  /// `STX_PLATFORM_BASE_URL` for `platform`.
  String get envName => '${_envPrefix}_BASE_URL';

  /// `STX_I18N_CLIENT_SECRET`, `STX_I18N_TOKEN`, `STX_I18N_ISSUER` for `i18n`.
  String get secretEnvName => '${_envPrefix}_CLIENT_SECRET';
  String get tokenEnvName => '${_envPrefix}_TOKEN';
  String get issuerEnvName => '${_envPrefix}_ISSUER';

  String get _envPrefix => 'STX_${Naming.snake(name).toUpperCase()}';

  /// `Platform` → `PlatformEndpoint`, `PlatformClient`.
  String get typePrefix => Naming.pascal(name);
}

/// `i18n.remote:`: published translations from the i18n backend (CMS), laid over the YAML texts.
final class I18nRemoteConfig {
  const I18nRemoteConfig({required this.backend, required this.application});

  /// The backend that serves the i18n contract.
  final String backend;

  /// The application id in the CMS (`match-tracker`).
  final String application;

  /// The contract added for [backend]; its output directory is `stx_i18n_v1`.
  static const contractName = 'stxI18nV1';

  /// The default `spec` of the contract.
  static const defaultSpec = 'https://docs.stratastax.dev/openapi/stratastax.i18n.api-v1.yaml';
}

/// The `i18n:` section of stx.yaml.
final class I18nConfig {
  const I18nConfig({
    required this.dir,
    this.base = 'en',
    this.locales = const ['en'],
    this.missingIsError = true,
    this.deferred = true,
    this.remote,
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

  /// Null: only the YAML texts.
  final I18nRemoteConfig? remote;
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
    this.tokensBase,
    this.displayTokensBase,
    this.security,
    this.sources = const [],
    this.search = const SearchConfig(),
  });

  final SearchConfig search;

  /// At least one; without `backends:` in stx.yaml the single [BackendConfig.defaultName].
  final List<BackendConfig> backends;

  /// Null when the app has no login.
  final SecurityConfig? security;

  final String projectDir;
  final List<ContractConfig> contracts;

  /// Absolute path of `stx.tokens.yaml`; null when the app uses the defaults (and [tokensBase]) only.
  final String? tokens;
  final String? displayTokens;

  /// `tokens.base`: a brand layer between the stx_style defaults and [tokens] (e.g. the tokens of
  /// stratastax-design); absolute path, for a remote file its copy in the cache.
  final String? tokensBase;
  final String? displayTokensBase;

  /// Every file stx.yaml refers to; the remote ones are fetched and locked before a build.
  final List<SourceRef> sources;
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

    const known = {'sources', 'backends', 'contracts', 'tokens', 'i18n', 'security', 'search', 'output'};
    for (final key in root.keys) {
      if (!known.contains(key)) {
        diagnostics.warning(ContractCodes.unreadable, 'unknown key "$key" is ignored', location: location);
      }
    }

    final resolver = SourceResolver.load(projectDir, root, diagnostics, location: location);
    final sources = <SourceRef>[];
    SourceRef? source(String reference) {
      final ref = resolver.resolve(reference, diagnostics, location: location);
      if (ref != null) sources.add(ref);
      return ref;
    }

    final hasSecurity = root['security'] is YamlMap;
    final backends = <BackendConfig>[];
    switch (root['backends']) {
      case null:
        backends.add(
          BackendConfig(name: BackendConfig.defaultName, auth: hasSecurity ? BackendAuth.oidc : BackendAuth.none),
        );
      case final YamlMap node:
        for (final entry in node.entries) {
          final name = entry.key.toString();
          final value = entry.value is YamlMap ? entry.value as YamlMap : YamlMap();
          final auth = value['auth']?.toString() ?? (hasSecurity ? 'oidc' : 'none');
          final account = value['serviceAccount'];
          if (Naming.member(name) != name || _reserved.contains(name)) {
            diagnostics.error(
              ContractCodes.unreadable,
              'backend "$name" must be a lowerCamelCase Dart name other than ${_reserved.join(', ')}',
              location: location,
            );
          } else if (!BackendAuth.values.any((a) => a.name == auth)) {
            diagnostics.error(
              ContractCodes.unreadable,
              'backend "$name": auth is ${BackendAuth.values.map((a) => a.name).join(', ')}',
              location: location,
            );
          } else if (auth == 'serviceAccount' && (account is! YamlMap || account['clientId'] == null)) {
            diagnostics.error(
              ContractCodes.unreadable,
              'backend "$name" uses auth: serviceAccount, but has no "serviceAccount: { clientId: … }"',
              location: location,
            );
          } else if (auth == 'serviceAccount' && (account as YamlMap)['issuer'] == null && !hasSecurity) {
            diagnostics.error(
              ContractCodes.unreadable,
              'backend "$name": serviceAccount needs an "issuer" (there is no security.oidc to take it from)',
              location: location,
            );
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
                auth: BackendAuth.values.byName(auth),
                serviceAccount: account is YamlMap && auth == 'serviceAccount'
                    ? ServiceAccountSettings(
                        clientId: account['clientId'].toString(),
                        issuer: account['issuer']?.toString(),
                        scopes: [for (final s in account['scopes'] as List? ?? const []) s.toString()],
                      )
                    : null,
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
        final ref = source(spec);
        if (ref == null) continue;
        contracts.add(
          ContractConfig(
            name: name,
            spec: ref.path,
            displaySpec: ref.display,
            modelSuffix: value['modelSuffix']?.toString() ?? '',
            apiSuffix: value['apiSuffix']?.toString() ?? 'Api',
            backend: backend,
          ),
        );
      }
    } else if (contractsNode != null) {
      diagnostics.error(ContractCodes.unreadable, '"contracts" must be a mapping', location: location);
    }

    // `tokens: stx.tokens.yaml`, or `tokens: { base: <brand layer>, file: stx.tokens.yaml }`.
    SourceRef? tokens, tokensBase;
    switch (root['tokens']) {
      case null:
        break;
      case final YamlMap node:
        for (final key in node.keys) {
          if (key != 'base' && key != 'file') {
            diagnostics.warning(ContractCodes.unreadable, 'tokens: unknown key "$key" is ignored', location: location);
          }
        }
        if (node['file'] case final Object file) tokens = source(file.toString());
        if (node['base'] case final Object base) tokensBase = source(base.toString());
      case final Object file:
        tokens = source(file.toString());
    }

    final i18nNode = root['i18n'] is YamlMap ? root['i18n'] as YamlMap : YamlMap();
    final base = i18nNode['base']?.toString() ?? 'en';
    final locales = <String>[
      base,
      for (final l in (i18nNode['locales'] as List?) ?? const []) ?(l.toString() == base ? null : l.toString()),
    ];
    I18nRemoteConfig? remote;
    if (i18nNode['remote'] case final YamlMap node) {
      final backend = node['backend']?.toString() ?? (backends.length == 1 ? backends.single.name : null);
      final application = node['application']?.toString();
      if (backend == null || !backendNames.contains(backend)) {
        diagnostics.error(
          ContractCodes.unreadable,
          'i18n.remote needs "backend: <${backendNames.join('|')}>"',
          location: location,
        );
      } else if (application == null || !RegExp(r'^[a-z][a-z0-9-]{1,62}$').hasMatch(application)) {
        diagnostics.error(
          ContractCodes.unreadable,
          'i18n.remote needs "application": the lowercase id of the app in the i18n backend (match-tracker)',
          location: location,
        );
      } else if (contracts.any((c) => c.name == I18nRemoteConfig.contractName)) {
        diagnostics.error(
          ContractCodes.unreadable,
          'contract "${I18nRemoteConfig.contractName}" is reserved for i18n.remote',
          location: location,
        );
      } else if (source(node['spec']?.toString() ?? I18nRemoteConfig.defaultSpec) case final ref?) {
        remote = I18nRemoteConfig(backend: backend, application: application);
        contracts.add(
          ContractConfig(
            name: I18nRemoteConfig.contractName,
            spec: ref.path,
            displaySpec: ref.display,
            modelSuffix: 'V1',
            apiSuffix: 'ApiV1',
            backend: backend,
          ),
        );
      }
    } else if (i18nNode['remote'] != null) {
      diagnostics.error(ContractCodes.unreadable, 'i18n.remote must be a mapping', location: location);
    }

    final i18n = I18nConfig(
      dir: p.normalize(p.join(projectDir, i18nNode['dir']?.toString() ?? 'i18n')),
      base: base,
      locales: locales,
      missingIsError: i18nNode['missing']?.toString() != 'fallback',
      deferred: i18nNode['deferred'] != false,
      remote: remote,
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

    var search = const SearchConfig();
    switch (root['search']) {
      case null:
        break;
      case final YamlMap node:
        final cache = node['cache'] is YamlMap ? node['cache'] as YamlMap : YamlMap();
        final pageSize = node['pageSize'] ?? 20;
        final mode = cache['mode']?.toString() ?? 'memory';
        final ttl = cache['ttl'] ?? 60;
        final maxEntries = cache['maxEntries'] ?? 200;
        if (pageSize is! int || pageSize < 1 || pageSize > 100) {
          diagnostics.error(ContractCodes.unreadable, 'search.pageSize must be 1–100', location: location);
        } else if (!const {'none', 'memory', 'staleWhileRevalidate'}.contains(mode)) {
          diagnostics.error(
            ContractCodes.unreadable,
            'search.cache.mode is none, memory or staleWhileRevalidate',
            location: location,
          );
        } else if (ttl is! int || ttl < 0 || maxEntries is! int || maxEntries < 1) {
          diagnostics.error(
            ContractCodes.unreadable,
            'search.cache.ttl (seconds) and maxEntries must be whole numbers',
            location: location,
          );
        } else {
          search = SearchConfig(pageSize: pageSize, cacheMode: mode, cacheTtl: ttl, cacheMaxEntries: maxEntries);
        }
      default:
        diagnostics.error(ContractCodes.unreadable, 'search must be a mapping', location: location);
    }

    final output = root['output']?.toString() ?? 'lib/gen';
    return StxConfig(
      projectDir: projectDir,
      contracts: contracts,
      output: p.normalize(p.join(projectDir, output)),
      tokens: tokens?.path,
      displayTokens: tokens?.display,
      tokensBase: tokensBase?.path,
      displayTokensBase: tokensBase?.display,
      sources: sources,
      i18n: i18n,
      backends: backends,
      security: security,
      search: search,
    );
  }

  /// Members of the generated `AppServices` that a backend cannot be named after.
  static const _reserved = {'config', 'session', 'access', 'start', 'loginOptions', 'of', 'translations'};

  /// The backend of contract [name].
  BackendConfig backendOf(String name) {
    final backend = contracts.firstWhere((c) => c.name == name).backend;
    return backends.firstWhere((b) => b.name == backend);
  }
}
