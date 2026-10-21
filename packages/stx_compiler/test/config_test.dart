import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:stx_compiler/stx_compiler.dart';
import 'package:test/test.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('stx_config'));
  tearDown(() => dir.deleteSync(recursive: true));

  (StxConfig?, Diagnostics) load(String yaml) {
    File(p.join(dir.path, 'stx.yaml')).writeAsStringSync(yaml);
    final diagnostics = Diagnostics();
    return (StxConfig.load(dir.path, diagnostics), diagnostics);
  }

  const security = 'security:\n  oidc: { issuer: http://idp/realms/x, clientId: app }\n';

  test('without backends: one "api" backend, oidc when there is a security section', () {
    final (config, diagnostics) = load('contracts:\n  platformV1: { spec: a.yaml }\n$security');
    expect(diagnostics.all, isEmpty);
    expect(config!.backends.single.name, 'api');
    expect(config.backends.single.oidc, isTrue);
    expect(config.backends.single.envName, 'STX_API_BASE_URL');
    expect(config.backendOf('platformV1').typePrefix, 'Api');
  });

  test('several backends; every contract names one', () {
    final (config, diagnostics) = load('''
backends:
  platform: { baseUrl: http://localhost:9000, auth: oidc }
  gameCatalog: { baseUrl: https://catalog, auth: none }
contracts:
  platformV1: { spec: a.yaml, backend: platform }
  catalogV1: { spec: b.yaml, backend: gameCatalog }
$security''');
    expect(diagnostics.all, isEmpty);
    expect(config!.backendOf('platformV1').oidc, isTrue);
    final catalog = config.backendOf('catalogV1');
    expect(catalog.oidc, isFalse);
    expect(catalog.envName, 'STX_GAME_CATALOG_BASE_URL');
    expect(catalog.typePrefix, 'GameCatalog');
  });

  test('tokens: a file, or a brand layer (base) with an optional app file', () {
    final (plain, _) = load('tokens: stx.tokens.yaml\n');
    expect(plain!.tokens, p.join(dir.path, 'stx.tokens.yaml'));
    expect(plain.tokensBase, isNull);

    final (layered, diagnostics) = load('tokens: { base: brand/tokens.yaml }\n');
    expect(diagnostics.all, isEmpty);
    expect(layered!.tokens, isNull);
    expect(layered.tokensBase, p.join(dir.path, 'brand', 'tokens.yaml'));
    expect(layered.displayTokensBase, 'brand/tokens.yaml');
  });

  test('auth: serviceAccount (issuer from security.oidc by default) and token', () {
    final (config, diagnostics) = load('''
backends:
  platform: { auth: oidc }
  i18n:
    auth: serviceAccount
    serviceAccount: { clientId: app-i18n, scopes: [stx-i18n:bundle-read] }
  cms: { auth: token }
$security''');
    expect(diagnostics.all, isEmpty);
    final i18n = config!.backends.firstWhere((b) => b.name == 'i18n');
    expect(i18n.auth, BackendAuth.serviceAccount);
    expect(i18n.ownTokens, isTrue);
    expect(i18n.serviceAccount!.clientId, 'app-i18n');
    expect(i18n.serviceAccount!.issuer, isNull);
    expect(i18n.serviceAccount!.scopes, ['stx-i18n:bundle-read']);
    expect(i18n.secretEnvName, 'STX_I18N_CLIENT_SECRET');
    final cms = config.backends.firstWhere((b) => b.name == 'cms');
    expect((cms.auth, cms.tokenEnvName), (BackendAuth.token, 'STX_CMS_TOKEN'));

    final (_, noClient) = load('backends: { i18n: { auth: serviceAccount } }\n');
    expect(noClient.all.single.message, contains('serviceAccount: { clientId'));
    final (_, noIssuer) = load('backends: { i18n: { auth: serviceAccount, serviceAccount: { clientId: x } } }\n');
    expect(noIssuer.all.single.message, contains('needs an "issuer"'));
    final (_, unknown) = load('backends: { i18n: { auth: basic } }\n');
    expect(unknown.all.single.message, contains('oidc, serviceAccount, token'));
  });

  test('i18n.remote adds the i18n contract for its backend', () {
    final (config, diagnostics) = load('''
backends:
  i18n: { auth: token }
i18n:
  remote: { backend: i18n, application: match-tracker }
''');
    expect(diagnostics.all, isEmpty);
    expect(config!.i18n.remote!.application, 'match-tracker');
    final contract = config.contracts.single;
    expect(contract.name, I18nRemoteConfig.contractName);
    expect(contract.backend, 'i18n');
    expect(contract.displaySpec, I18nRemoteConfig.defaultSpec);
    expect(config.sources.single.isRemote, isTrue);

    final (_, badApp) = load('backends: { i18n: {} }\ni18n:\n  remote: { application: Match Tracker }\n');
    expect(badApp.all.single.message, contains('lowercase id'));
    final (_, badBackend) = load('backends: { a: {}, b: {} }\ni18n:\n  remote: { application: x1 }\n');
    expect(badBackend.all.single.message, contains('needs "backend: <a|b>"'));
  });

  test('errors: missing or unknown backend, oidc without security, reserved name', () {
    final (_, missing) = load('''
backends: { a: {}, b: {} }
contracts:
  platformV1: { spec: a.yaml }
''');
    expect(missing.all.single.message, contains('needs "backend: <a|b>"'));

    final (_, unknown) = load('backends: { a: {} }\ncontracts:\n  platformV1: { spec: a.yaml, backend: c }\n');
    expect(unknown.all.single.message, contains('unknown backend "c"'));

    final (_, noSecurity) = load('backends: { a: { auth: oidc } }\n');
    expect(noSecurity.all.single.message, contains('no "security" section'));

    final (_, reserved) = load('backends: { session: {} }\n');
    expect(reserved.all.first.message, contains('lowerCamelCase'));
  });
}
