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
