import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:match_tracker/gen/app/app.g.dart';
import 'package:match_tracker/gen/contract/platform_v1/platform_v1.g.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:stx_core/stx_core.dart';
import 'package:stx_http/stx_http.dart';
import 'package:stx_i18n/stx_i18n.dart';
import 'package:stx_security/stx_security.dart';
import 'package:stx_ui/stx_ui.dart';
import 'package:stub_server/gen/contract/platform_v1/platform_v1.g.dart' as stub;
import 'package:stub_server/stub_server.dart';

/// End to end, without mocks of our own code: the generated app against examples/stub_server (its
/// OIDC endpoints and its contract-conformant API), in process. Only the network and the browser
/// redirect are replaced: [_StubTransport] hands requests to the stub's shelf handler.
final class _StubTransport implements StxTransport {
  _StubTransport(this.handler);

  final shelf.Handler handler;
  final api = <StxRequest>[];

  @override
  Future<StxResponse> send(StxRequest request) async {
    if (request.uri.path.startsWith('/api/')) api.add(request);
    final response = await handler(
      shelf.Request(request.method.wire, request.uri, headers: request.headers, body: request.body),
    );
    return StxResponse(status: response.statusCode, headers: response.headers, body: await response.readAsString());
  }

  @override
  void close() {}
}

/// The browser: the app redirects to the identity provider; the "user" picks an account there.
final class _Browser implements AuthBrowser {
  @override
  Uri location = Uri.parse('http://app.test/');
  Uri? redirected;

  @override
  void redirect(Uri uri) => redirected = uri;

  @override
  void replace(Uri uri) => location = uri;
}

Finder _input(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(StxFieldFrame)).first,
  matching: find.byType(EditableText),
);

Future<void> _settle(WidgetTester tester) async {
  // Let the stub's handler (real async work) finish, then the debounce and rebuilds.
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 300));
  }
  await tester.pumpAndSettle();
}

void main() {
  late StubStore store;
  late _StubTransport transport;
  late _Browser browser;
  late AppServices services;

  Future<void> start(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
    TranslationCache? cache,
    String location = '/matches/new',
    bool demo = false,
  }) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    store = StubStore(demo: demo);
    transport = _StubTransport(stubHandler(store: store, log: (_) {}));
    browser = _Browser();
    services = AppServices(
      AppConfig(
        platform: StxBackend(baseUrl: Uri.parse('http://stub.test')),
        catalog: StxBackend(baseUrl: Uri.parse('http://catalog.test')),
        // The stub serves the published translations too, to its service account. The app gets
        // the secret with --dart-define; the test passes the same tokens explicitly.
        i18n: StxBackend(baseUrl: Uri.parse('http://stub.test')),
        i18nTokens: ServiceAccountTokens(
          config: ServiceAccountConfig(
            issuer: Uri.parse('http://stub.test/realms/stratastax'),
            clientId: 'match-tracker-i18n',
            clientSecret: 'stub-secret',
            scopes: const ['stx-i18n:bundle-read'],
          ),
          transport: transport,
        ),
        translationCache: cache,
        oidc: OidcConfig(
          issuer: Uri.parse('http://stub.test/realms/stratastax'),
          clientId: 'match-tracker',
          redirectUri: Uri.parse('http://app.test/'),
        ),
        transport: transport,
        secureStore: MemoryStore(),
        browser: browser,
      ),
    );
    await tester.runAsync(services.start);
    await tester.pumpWidget(AppRoot(services: services, initialLocation: location, initialLocale: locale));
    await tester.pumpAndSettle();
  }

  /// Sign in at the stub's identity provider as [user] and come back with the code.
  Future<void> signIn(WidgetTester tester, String user) async {
    await tester.tap(find.text('Sign in'));
    final authorize = browser.redirected!.replace(
      queryParameters: {...browser.redirected!.queryParameters, 'user': user},
    );
    final response = (await tester.runAsync(() async => transport.handler(shelf.Request('GET', authorize))))!;
    expect(response.statusCode, 302);
    browser.location = Uri.parse(response.headers['location']!);
    await tester.runAsync(services.start);
    await tester.pumpAndSettle();
  }

  Future<void> pick(WidgetTester tester, String field, String query, String option) async {
    await tester.enterText(_input(field), query);
    await _settle(tester);
    await tester.tap(find.text(option).last);
    await tester.pumpAndSettle();
  }

  testWidgets('sign in, record a match, and the stub has it', (tester) async {
    await start(tester);
    expect(find.text('Sign in to continue'), findsOneWidget);
    await signIn(tester, 'player');
    expect(find.text('Pim Player'), findsOneWidget);

    await pick(tester, 'Game *', 'cat', 'Catan');
    await tester.tap(find.text('Now'));
    await tester.pumpAndSettle();
    await pick(tester, 'Players *', 'cha', 'Charlie');
    await pick(tester, 'Players *', 'bo', 'Bob');
    expect(find.text('2 players'), findsOneWidget);
    await tester.tap(find.text('Mark as winner').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await _settle(tester);

    expect(find.text('Save'), findsNothing); // back on the overview the form is embedded in
    final match = store.matches.single;
    expect(match.game.displayName, 'Catan');
    expect(
      {for (final p in match.participants) p.ghostPlayer.displayName: p.outcome},
      {'Charlie': stub.OutcomeV1.win, 'Bob': stub.OutcomeV1.loss},
    );
    // Every API call carried the session's token. The contract declares an Idempotency-Key for
    // createMatch, so one is sent.
    expect(transport.api.map((r) => r.header('authorization')), everyElement(startsWith('Bearer ')));
    final create = transport.api.singleWhere((r) => r.method == HttpMethod.post);
    expect(create.uri.path, '/api/v1/matches');
    expect(create.header('idempotency-key'), isNotNull);
  });

  testWidgets('published translations replace the YAML texts, with the service account; they are cached', (
    tester,
  ) async {
    final cache = MemoryTranslationCache();
    await start(tester, cache: cache);
    await signIn(tester, 'player');
    // Nothing is published for en (404): the YAML texts stay.
    expect(find.text('Match tracker'), findsWidgets);
    expect(find.text('No players yet'), findsOneWidget);

    await tester.runAsync(
      () => StxLocaleScope.setLocale(tester.element(find.text('Match tracker').first), const Locale('nl')),
    );
    await _settle(tester);
    expect(find.text('Partijen'), findsWidgets); // app.title of the stub's release 1
    expect(find.text('Wedstrijden'), findsNothing); // the YAML text it replaces
    expect(find.text('Nog niemand'), findsOneWidget); // an ICU plural from the backend, interpreted
    expect(find.text('Spelers *'), findsOneWidget); // keys without a translation keep the YAML text
    expect(cache.read(const Locale('nl'))!.etag, '"1"');

    // Both bundles went with the service account's token, not the user's.
    final bundles = transport.api.where((r) => r.uri.path.contains('/bundles/')).toList();
    expect(bundles.map((r) => r.uri.path.split('/').last), ['en', 'nl']);
    for (final request in bundles) {
      final claims = jwtClaims(request.header('authorization')!.substring(7))!;
      expect(claims['sub'], 'service-account-match-tracker-i18n');
    }
  });

  testWidgets('a viewer only reads: the page is forbidden and the API agrees', (tester) async {
    await start(tester);
    await signIn(tester, 'viewer');
    expect(find.text("You don't have access to this page"), findsOneWidget);

    final result = await tester.runAsync(
      () => services.platform.submit<CreateMatchV1, MatchV1>(
        MatchesApiV1.createMatch,
        CreateMatchV1(
          gameId: store.games.first.id,
          playedAt: DateTime.utc(2026, 10, 1),
          participants: const <MatchParticipantInputV1>[],
          editRequestsEnabled: false,
        ),
      ),
    );
    expect(result!, isA<Err<MatchV1, Problem>>().having((e) => e.error.status, 'status', 403));
  });

  testWidgets('matches overview against the stub: search, filter by game, total, and a new match shows up', (
    tester,
  ) async {
    await start(tester, location: '/matches', demo: true);
    await signIn(tester, 'player');
    await _settle(tester);
    expect(find.text('1–20 of 45'), findsOneWidget);
    final first = transport.api.lastWhere((r) => r.uri.path == '/api/v1/matches');
    expect(first.uri.queryParameters['sort'], 'playedAt:DESC');

    // A game from the data source (`@SearchFilter(source: GameSearchSource)`): gameId==…
    // The table shows Catan too: tap the option in the list under the field.
    await tester.enterText(_input('Game'), 'cat');
    await _settle(tester);
    await tester.tap(
      find.descendant(
        of: find.byWidgetPredicate((w) => w.runtimeType.toString() == '_OptionsOverlay'),
        matching: find.text('Catan'),
      ),
    );
    await _settle(tester);
    final filtered = transport.api.lastWhere((r) => r.uri.path == '/api/v1/matches');
    expect(filtered.uri.queryParameters['filter'], 'gameId==${store.games.first.id.value}');
    expect(find.text('1–2 of 2'), findsOneWidget);

    // Record a match; the overview of the same contract tag no longer shows its cached pages.
    await tester.tap(find.text('New match'));
    await tester.pumpAndSettle();
    await pick(tester, 'Game *', 'cat', 'Catan');
    await tester.tap(find.text('Now'));
    await tester.pumpAndSettle();
    await pick(tester, 'Players *', 'cha', 'Charlie');
    await tester.tap(find.text('Save'));
    await _settle(tester);
    expect(store.matches, hasLength(46));

    // Back on the overview it is embedded in, still filtered on Catan: loaded again, not cached.
    expect(find.text('Save'), findsNothing);
    expect(find.text('1–3 of 3'), findsOneWidget);
  });
}
