import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:match_tracker/gen/app/app.g.dart';
import 'package:match_tracker/gen/app/routes.g.dart';
import 'package:match_tracker/gen/contract/scopes.g.dart';
import 'package:match_tracker/gen/style/tokens.g.dart';
import 'package:stx_core/stx_core.dart';
import 'package:stx_http/stx_http.dart';
import 'package:stx_security/stx_security.dart';
import 'package:stx_style/stx_style.dart';
import 'package:stx_ui/stx_ui.dart';

/// End-to-end over the generated app: router, guard, generated pages and forms, validation from
/// the contract, mapping to the contract body and the HTTP call.
final class _Backend implements StxTransport {
  final requests = <StxRequest>[];
  var reject = false;

  @override
  Future<StxResponse> send(StxRequest request) async {
    // Nothing published: the app keeps its YAML texts (see e2e_test.dart for translations).
    if (request.uri.path.contains('/bundles/')) return StxResponse(status: 404);
    requests.add(request);
    final path = request.uri.path;
    if (path.endsWith('/games/suggestions')) {
      return StxResponse(
        status: 200,
        body: jsonEncode([
          {'id': '0192f100-0000-7000-8000-0000000000b1', 'displayName': 'Catan'},
        ]),
      );
    }
    if (path.endsWith('/games') && request.method == HttpMethod.post && reject) {
      return StxResponse(
        status: 400,
        body: jsonEncode({
          'type': 'https://errors.stratastax.io/validation',
          'title': 'Validation failed',
          'status': 400,
          'detail': '1 invalid field(s)',
          'errors': [
            {'field': 'maxPlayers', 'code': 'OUT_OF_RANGE', 'message': 'maxPlayers must be at least minPlayers'},
          ],
        }),
      );
    }
    if (path.endsWith('/games') && request.method == HttpMethod.post) {
      final body = jsonDecode(request.body!) as Map<String, Object?>;
      return StxResponse(
        status: 201,
        body: jsonEncode({
          ...body,
          'id': '0192f100-0000-7000-8000-0000000000b2',
          'createdAt': '2026-10-12T00:00:00.000Z',
        }),
      );
    }
    if (path.endsWith('/games/count')) return StxResponse(status: 200, body: jsonEncode({'count': 25}));
    if (path.endsWith('/games') && request.method == HttpMethod.get) {
      // Two pages of games: the cursor of the second is "p2".
      final second = request.uri.queryParameters['cursor'] == 'p2';
      return StxResponse(
        status: 200,
        body: jsonEncode({
          'limit': second ? 5 : 20,
          'nextCursor': second ? null : 'p2',
          'prevCursor': second ? 'p1' : null,
          'items': [
            for (var i = second ? 20 : 0; i < (second ? 25 : 20); i++)
              {
                'id': '0192f100-0000-7000-8000-${(0xb100 + i).toRadixString(16).padLeft(12, '0')}',
                'displayName': 'Game $i',
                'description': '',
                'minPlayers': 2,
                'maxPlayers': 4,
                'tags': <String>[],
                'scoreType': i.isEven ? 'SCORE' : 'WIN_LOSS',
                'createdAt': '2026-10-01T12:00:00.000Z',
              },
          ],
        }),
      );
    }
    return StxResponse(status: 404);
  }

  @override
  void close() {}
}

Future<_Backend> _pumpApp(
  WidgetTester tester, {
  required String location,
  Iterable<Scope> scopes = Scope.values,
  bool authenticated = true,
  Locale locale = const Locale('en'),
  ThemeModeStore? themeStore,
  Size size = const Size(1200, 1600),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final backend = _Backend();
  final config = AppConfig(
    platform: StxBackend(baseUrl: Uri.parse('https://stratastax.dev/rest')),
    catalog: StxBackend(baseUrl: Uri.parse('https://catalog.stratastax.dev')),
    i18n: StxBackend(baseUrl: Uri.parse('https://i18n.stratastax.dev')),
    i18nTokens: const StaticTokenSource('test'),
    access: StaticAccess(authenticated: authenticated, scopes: scopes.toSet()),
    transport: backend,
    themeStore: themeStore,
  );
  await tester.pumpWidget(AppRoot(services: AppServices(config), initialLocation: location, initialLocale: locale));
  // Non-base locales are deferred libraries: let their load finish outside the fake clock.
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await tester.pumpAndSettle();
  return backend;
}

Finder _input(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(StxFieldFrame)).first,
  matching: find.byType(EditableText),
);

void main() {
  testWidgets('create a game: validation, select, mapping and submit', (tester) async {
    final backend = await _pumpApp(tester, location: '/games/new');
    expect(find.text('New game'), findsOneWidget); // page title; embedded in Games, not in the navigation

    // Submitting empty shows the contract's rules, without a request.
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Required'), findsWidgets);
    expect(backend.requests, isEmpty);

    await tester.enterText(_input('Name *'), 'C'); // @UiFieldValidate(minLength: 2)
    await tester.pumpAndSettle();
    expect(find.text('At least 2 characters'), findsOneWidget);

    await tester.enterText(_input('Name *'), 'Catan');
    await tester.enterText(_input('Description *'), 'Trade and build');
    await tester.enterText(_input('Minimum players *'), '3');
    await tester.enterText(_input('Maximum players *'), '42'); // maximum: 20
    await tester.enterText(_input('Image URL'), 'not a url'); // format: uri
    await tester.pumpAndSettle();
    expect(find.text('Must be at most 20'), findsOneWidget);
    expect(find.text('Invalid value'), findsOneWidget);
    await tester.enterText(_input('Maximum players *'), '4');
    await tester.enterText(_input('Image URL'), '');

    // Enum select: options are the translated contract enum values.
    await tester.tap(find.text('Choose…').first);
    await tester.pumpAndSettle();
    expect(find.text('Win / loss'), findsOneWidget);
    await tester.tap(find.text('Points'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final request = backend.requests.first;
    expect(request.method, HttpMethod.post);
    expect(request.uri.path, '/rest/api/v1/games');
    expect(jsonDecode(request.body!), {
      'displayName': 'Catan',
      'description': 'Trade and build',
      'minPlayers': 3,
      'maxPlayers': 4,
      'tags': <Object?>[], // @UiIgnore field: the constructor default is sent
      'scoreType': 'SCORE',
    });

    // Opened directly: back to the page it is embedded in, which loads the games.
    expect(find.text('Save'), findsNothing);
    expect(find.text('Games'), findsWidgets);
    expect(backend.requests.skip(1).map((r) => r.endpoint.operationId), containsAll(['listGames', 'countGames']));
  });

  testWidgets('server violations show on the field they belong to', (tester) async {
    final backend = await _pumpApp(tester, location: '/games/new');
    backend.reject = true;
    await tester.enterText(_input('Name *'), 'Catan');
    await tester.enterText(_input('Description *'), 'Trade and build');
    await tester.enterText(_input('Minimum players *'), '4');
    await tester.enterText(_input('Maximum players *'), '2');
    await tester.tap(find.text('Choose…').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Points'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Please correct the highlighted fields'), findsOneWidget);
    expect(find.text('Value is out of range'), findsOneWidget);
    // Editing clears the banner.
    await tester.enterText(_input('Maximum players *'), '5');
    await tester.pumpAndSettle();
    expect(find.text('Please correct the highlighted fields'), findsNothing);
  });

  testWidgets('create a match: autocomplete from a data source', (tester) async {
    final backend = await _pumpApp(tester, location: '/matches/new');
    expect(find.text('New match'), findsWidgets);

    await tester.enterText(_input('Game *'), 'cat');
    await tester.pump(const Duration(milliseconds: 300)); // debounce
    await tester.pumpAndSettle();
    expect(backend.requests.single.uri.queryParameters, {'query': 'cat'});
    await tester.tap(find.text('Catan').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    // The game is set; playedAt and the players are still missing.
    expect(find.text('Required'), findsOneWidget);
    expect(find.text('Choose at least 1 item'), findsOneWidget);
    expect(backend.requests, hasLength(1)); // only the search
  });

  testWidgets('pages are guarded by the scopes of the operations they use', (tester) async {
    // Can create games, but the match page also needs match-create and ghost-player-read.
    await _pumpApp(tester, location: '/matches/new', scopes: [Scope.gameCreate, Scope.gameRead]);
    expect(find.text("You don't have access to this page"), findsOneWidget);
    expect(find.text('Save'), findsNothing); // the form is never built
    // The navigation only offers what the user may use; the forms are embedded in their overviews.
    expect(find.text('Games'), findsOneWidget);
    expect(find.text('Matches'), findsNothing);
    expect(find.text('New game'), findsNothing);
  });

  testWidgets('an overview opens its embedded form; back returns to it', (tester) async {
    await _pumpApp(tester, location: '/matches');
    expect(find.text('New match'), findsOneWidget); // the action, not a navigation item
    await tester.tap(find.text('New match'));
    await tester.pumpAndSettle();
    expect(find.text('Save'), findsOneWidget);
    // The navigation keeps the overview the form is embedded in active.
    final matches = tester.widget<StxButton>(find.ancestor(of: find.text('Matches'), matching: find.byType(StxButton)));
    expect(matches.variant, ButtonVariant.secondary);
    final navigator = StxRouter.of<AppRoute>(tester.element(find.text('Save')));
    navigator.back();
    await tester.pumpAndSettle();
    expect(find.text('Save'), findsNothing);
    expect(find.text('New match'), findsOneWidget);
  });

  testWidgets('the action is hidden without the scopes of the embedded page', (tester) async {
    await _pumpApp(tester, location: '/matches', scopes: [Scope.matchRead, Scope.gameRead]);
    expect(find.text('Matches'), findsWidgets);
    expect(find.text('New match'), findsNothing);
  });

  testWidgets('a deep link to an embedded page goes back to the page it is embedded in', (tester) async {
    final backend = await _pumpApp(tester, location: '/games/new');
    expect(backend.requests, isEmpty); // the overview is not built underneath
    StxRouter.of<AppRoute>(tester.element(find.text('Save'))).back();
    await tester.pumpAndSettle();
    expect(find.text('New game'), findsOneWidget); // the action on Games
    expect(find.text('Save'), findsNothing);
  });

  testWidgets('signed out', (tester) async {
    await _pumpApp(tester, location: '/games/new', authenticated: false);
    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('the sidebar switches between light and dark and remembers it', (tester) async {
    final store = _MemoryThemeStore();
    await _pumpApp(tester, location: '/games/new', themeStore: store);
    Color background() => tester.widget<ColoredBox>(find.byType(ColoredBox).first).color;
    expect(background(), stxTokensLight.color(ColorToken.background));
    expect(find.bySemanticsLabel('Dark mode'), findsOneWidget);
    expect(find.bySemanticsLabel('Matches'), findsOneWidget); // the side rail is visible to screen readers
    await tester.tap(find.text('☾'));
    await tester.pumpAndSettle();
    expect(background(), stxTokensDark.color(ColorToken.background));
    expect(find.text('☀'), findsOneWidget);
    expect(find.bySemanticsLabel('Light mode'), findsOneWidget);
    expect(store.mode, StxThemeMode.dark);
  });

  testWidgets('on a phone the bottom bar switches between light and dark', (tester) async {
    final store = _MemoryThemeStore();
    await _pumpApp(tester, location: '/games/new', themeStore: store, size: const Size(400, 800));
    Color background() => tester.widget<ColoredBox>(find.byType(ColoredBox).first).color;
    await tester.tap(find.text('☾'));
    await tester.pumpAndSettle();
    expect(background(), stxTokensDark.color(ColorToken.background));
    expect(find.text('☀'), findsOneWidget);
    expect(find.bySemanticsLabel('Light mode'), findsOneWidget);
    expect(store.mode, StxThemeMode.dark);
  });

  testWidgets('unknown paths', (tester) async {
    await _pumpApp(tester, location: '/nope');
    expect(find.text('Page not found'), findsOneWidget);
  });

  testWidgets('Dutch', (tester) async {
    await _pumpApp(tester, location: '/games/new', locale: const Locale('nl'));
    expect(find.text('Nieuw spel'), findsWidgets);
    expect(find.text('Opslaan'), findsOneWidget);
    await tester.tap(find.text('Opslaan'));
    await tester.pumpAndSettle();
    expect(find.text('Verplicht'), findsWidgets);
  });

  testWidgets('games overview: filter chips, header sort and cursor paging send the contract parameters', (
    tester,
  ) async {
    final backend = await _pumpApp(tester, location: '/games');
    Map<String, String> lastList() =>
        backend.requests.lastWhere((r) => r.uri.path.endsWith('/games')).uri.queryParameters;
    expect(find.text('Games'), findsWidgets);
    expect(find.text('Game 0'), findsOneWidget);
    expect(find.text('1–20 of 25'), findsOneWidget);
    expect(lastList(), {'limit': '20', 'sort': 'name:ASC'}); // @SearchSort(initial: true)

    // The side panel (lg): chips of the enum, labels from enum.ScoreTypeV1.*.
    await tester.tap(find.text('Win / loss').first);
    await tester.pump(const Duration(milliseconds: 400)); // debounce
    await tester.pumpAndSettle();
    expect(lastList(), {'limit': '20', 'filter': 'scoreType=in=(WIN_LOSS)', 'sort': 'name:ASC'});
    expect(
      backend.requests.lastWhere((r) => r.uri.path.endsWith('/count')).uri.queryParameters['filter'],
      'scoreType=in=(WIN_LOSS)',
    );

    await tester.tap(find.text('Name ↑').last); // the table header (the sort chip in the panel reads the same)
    await tester.pumpAndSettle();
    expect(lastList()['sort'], 'name:DESC');

    await tester.ensureVisible(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(lastList(), {'limit': '20', 'cursor': 'p2'}); // the cursor carries filter and sort
    expect(find.text('Game 20'), findsOneWidget);
    expect(find.text('21–25 of 25'), findsOneWidget);
  });
}

class _MemoryThemeStore implements ThemeModeStore {
  StxThemeMode? mode;

  @override
  StxThemeMode? read() => mode;

  @override
  void write(StxThemeMode mode) => this.mode = mode;
}
