import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:match_tracker/gen/app/app.g.dart';
import 'package:stx_http/stx_http.dart';
import 'package:stx_security/stx_security.dart';
import 'package:stx_ui/stx_ui.dart';

void main() {
  testWidgets('signed out: the page offers the login options from stx.yaml', (tester) async {
    final app = await _start(tester);
    expect(find.text('Sign in to continue'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Sign in with Google'), findsOneWidget);
    expect(find.text('Sign in with GitHub'), findsOneWidget);
    expect(find.text('Save'), findsNothing);

    await tester.tap(find.text('Sign in with Google'));
    final redirect = app.browser.redirected!;
    expect(redirect.toString(), startsWith('http://idp.test/realms/stratastax/protocol/openid-connect/auth'));
    expect(redirect.queryParameters, containsPair('kc_idp_hint', 'google'));
    expect(redirect.queryParameters, containsPair('client_id', 'match-tracker'));
    expect(redirect.queryParameters, containsPair('code_challenge_method', 'S256'));
  });

  testWidgets('after the callback: the form, the user, and bearer tokens on API calls', (tester) async {
    final app = await _start(tester);
    await tester.tap(find.text('Sign in'));
    await _callback(tester, app);

    expect(app.services.access.authenticated, isTrue);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Gillian'), findsOneWidget);
    expect(find.text('Sign out'), findsOneWidget);
    expect(find.text('Games'), findsOneWidget); // nav: game-read granted

    final search = find.descendant(
      of: find.ancestor(of: find.text('Game *'), matching: find.byType(StxFieldFrame)).first,
      matching: find.byType(EditableText),
    );
    await tester.enterText(search, 'cat');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pumpAndSettle();
    expect(app.backend.apiAuthorization.single, startsWith('Bearer ey'));
  });

  testWidgets('the token decides what is shown', (tester) async {
    final app = await _start(tester, roles: ['stx-engine:game-read', 'stx-engine:game-create']);
    await tester.tap(find.text('Sign in'));
    await _callback(tester, app);
    expect(find.text("You don't have access to this page"), findsOneWidget); // no match-create
    expect(find.text('Matches'), findsNothing); // no match-read
    expect(find.text('Games'), findsOneWidget);
  });

  testWidgets('sign out ends the session at the provider', (tester) async {
    final app = await _start(tester);
    await tester.tap(find.text('Sign in'));
    await _callback(tester, app);
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
    expect(app.services.access.authenticated, isFalse);
    expect(app.browser.redirected!.path, '/realms/stratastax/protocol/openid-connect/logout');
    expect(find.text('Sign in to continue'), findsOneWidget);
  });

  testWidgets('a forged callback is refused and explained', (tester) async {
    final app = await _start(tester);
    await tester.tap(find.text('Sign in'));
    app.browser.location = Uri.parse('http://app.test/?code=c1&state=forged');
    await tester.runAsync(app.services.start);
    await tester.pumpAndSettle();
    expect(app.services.access.authenticated, isFalse);
    expect(find.text('Signing in did not work; please try again'), findsOneWidget);
  });
}

/// The OIDC login through the generated app: sign-in view, redirect with PKCE, callback, bearer
/// tokens on API calls, scopes from the token, sign-out.
String _jwt(Map<String, Object?> claims) {
  String part(Object json) => base64Url.encode(utf8.encode(jsonEncode(json))).replaceAll('=', '');
  return '${part({'alg': 'none'})}.${part(claims)}.sig';
}

final class _Browser implements AuthBrowser {
  @override
  Uri location = Uri.parse('http://app.test/');
  Uri? redirected;

  @override
  void redirect(Uri uri) => redirected = uri;

  @override
  void replace(Uri uri) => location = uri;
}

/// Identity provider and API in one fake.
final class _Backend implements StxTransport {
  _Backend(this.roles);

  List<String> roles;
  final apiAuthorization = <String?>[];

  @override
  Future<StxResponse> send(StxRequest request) async {
    if (request.uri.path.contains('/bundles/')) return StxResponse(status: 404); // nothing published
    if (request.uri.path.endsWith('/protocol/openid-connect/token')) {
      return StxResponse(
        status: 200,
        body: jsonEncode({
          'access_token': _jwt({
            'sub': 'u1',
            'realm_access': {'roles': roles},
          }),
          'id_token': _jwt({'sub': 'u1', 'name': 'Gillian'}),
          'refresh_token': 'refresh',
          'expires_in': 300,
        }),
      );
    }
    apiAuthorization.add(request.header('authorization'));
    return StxResponse(status: 200, body: '[]');
  }

  @override
  void close() {}
}

const _all = [
  'stx-engine:match-create',
  'stx-engine:game-read',
  'stx-engine:game-create',
  'stx-engine:ghost-player-read',
];

Future<({AppServices services, _Browser browser, _Backend backend})> _start(
  WidgetTester tester, {
  List<String> roles = _all,
}) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final browser = _Browser();
  final backend = _Backend(roles);
  final services = AppServices(
    AppConfig(
      platform: StxBackend(baseUrl: Uri.parse('http://api.test')),
      catalog: StxBackend(baseUrl: Uri.parse('http://catalog.test')),
      i18n: StxBackend(baseUrl: Uri.parse('http://i18n.test')),
      i18nTokens: const StaticTokenSource('test'),
      oidc: OidcConfig(
        issuer: Uri.parse('http://idp.test/realms/stratastax'),
        clientId: 'match-tracker',
        redirectUri: Uri.parse('http://app.test/'),
      ),
      transport: backend,
      secureStore: MemoryStore(),
      browser: browser,
    ),
  );
  await tester.runAsync(services.start);
  await tester.pumpWidget(
    AppRoot(services: services, initialLocation: '/matches/new', initialLocale: const Locale('en')),
  );
  await tester.pumpAndSettle();
  return (services: services, browser: browser, backend: backend);
}

/// What the identity provider does after a successful login: back to the app with code and state.
Future<void> _callback(WidgetTester tester, ({AppServices services, _Browser browser, _Backend backend}) app) async {
  final state = app.browser.redirected!.queryParameters['state'];
  app.browser.location = Uri.parse('http://app.test/?code=c1&state=$state');
  await tester.runAsync(app.services.start);
  await tester.pumpAndSettle();
}
