import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:match_tracker/gen/app/app.g.dart';
import 'package:match_tracker/gen/contract/scopes.g.dart';
import 'package:stx_core/stx_core.dart';
import 'package:stx_http/stx_http.dart';
import 'package:stx_ui/stx_ui.dart';

/// End-to-end over the generated app: router, guard, generated pages and forms, validation from
/// the contract, mapping to the contract body and the HTTP call.
final class _Backend implements StxTransport {
  final requests = <StxRequest>[];
  var reject = false;

  @override
  Future<StxResponse> send(StxRequest request) async {
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
      return StxResponse(status: 201, body: jsonEncode({...body, 'id': '0192f100-0000-7000-8000-0000000000b2'}));
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
}) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final backend = _Backend();
  final config = AppConfig(
    platform: StxBackend(baseUrl: Uri.parse('https://stratastax.dev/rest')),
    catalog: StxBackend(baseUrl: Uri.parse('https://catalog.stratastax.dev')),
    access: StaticAccess(authenticated: authenticated, scopes: scopes.toSet()),
    transport: backend,
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
    expect(find.text('New game'), findsWidgets); // page title and nav item

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

    final request = backend.requests.single;
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

    // Opened directly (no previous page): a confirmation, and the form is empty for the next game.
    expect(find.text('Saved'), findsOneWidget);
    expect(tester.widget<EditableText>(_input('Name *')).controller.text, isEmpty);
    expect(find.text('Choose…'), findsWidgets);
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
    // The navigation only offers what the user may use.
    expect(find.text('New game'), findsOneWidget);
    expect(find.text('New match'), findsNothing);
  });

  testWidgets('signed out', (tester) async {
    await _pumpApp(tester, location: '/games/new', authenticated: false);
    expect(find.text('Sign in'), findsOneWidget);
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
}
