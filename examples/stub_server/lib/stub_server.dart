/// A contract-conformant stub of the stratastax platform API (and the consumer part of the i18n
/// API) for examples/match_tracker.
///
/// Requests are decoded and responses encoded with the code stx_compiler generates from the
/// contract, and bodies are validated with the same `*Validation` constants the app uses, so the
/// stub cannot drift from the contract unnoticed.
library;

import 'dart:async';
import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:stx_core/stx_core.dart';

import 'gen/contract/i18n_v1/i18n_v1.g.dart' as i18n;
import 'gen/contract/platform_v1/platform_v1.g.dart';
import 'gen/contract/scopes.g.dart';
import 'src/oidc.dart';
import 'src/search.dart';
import 'src/store.dart';

export 'src/oidc.dart';
export 'src/store.dart';

/// The complete handler: CORS, logging, the identity provider and the API routes. Every API route
/// checks the bearer token against the security of its contract operation (401 / 403 problems).
Handler stubHandler({StubStore? store, OidcStub? oidc, void Function(String line)? log}) {
  final routes = _Routes(store ?? StubStore(), oidc ?? OidcStub());
  return const Pipeline()
      .addMiddleware(logRequests(logger: (message, isError) => (log ?? print)(message)))
      .addMiddleware(_cors())
      .addHandler(routes.router.call);
}

final class _Routes {
  _Routes(this.store, this.oidc) {
    oidc.bind(router);
    router
      ..get('/api/v1/games/suggestions', _secured(GamesApiV1.getGameSuggestions, _gameSuggestions))
      ..get('/api/v1/games/count', _secured(GamesApiV1.countGames, _countGames))
      ..get('/api/v1/games', _secured(GamesApiV1.listGames, _listGames))
      ..post('/api/v1/games', _secured(GamesApiV1.createGame, _idempotent(_createGame)))
      ..get('/api/v1/games/<id>', _secured(GamesApiV1.getGame, _getGame))
      ..get(
        '/api/v1/ghost-players/suggestions',
        _secured(GhostPlayersApiV1.getGhostPlayerSuggestions, _ghostPlayerSuggestions),
      )
      ..get('/api/v1/matches/count', _secured(MatchesApiV1.countMatches, _countMatches))
      ..get('/api/v1/matches', _secured(MatchesApiV1.listMatches, _listMatches))
      ..post('/api/v1/matches', _secured(MatchesApiV1.createMatch, _idempotent(_createMatch)))
      ..get('/api/v1/matches/<id>', _secured(MatchesApiV1.getMatch, _getMatch))
      ..get('/api/v1/applications/<app>/bundles/<locale>', _secured(i18n.BundlesApiV1.getBundle, _getBundle))
      ..all(
        '/<ignored|.*>',
        (Request r) => _problem(404, ErrorTypeV1.notFound, 'No stub for ${r.method} /${r.url.path}'),
      );
  }

  final StubStore store;
  final OidcStub oidc;
  final router = Router();

  /// What the backend does (Quarkus `@RolesAllowed`): no or invalid token → 401, a token without
  /// one of the operation's scopes → 403. The rule comes from the generated endpoint.
  /// A [Handler], so shelf_router passes the path parameters in `request.params`.
  Handler _secured(Endpoint<Object?, Object?, Object?> endpoint, Function handler) => (Request request) async {
    final claims = oidc.verify(request.headers['authorization']);
    final granted = claims == null ? const <Scope>{} : Scope.fromClaims(jwtRoleClaims(claims));
    if (endpoint.security.allows(authenticated: claims != null, granted: granted)) {
      return await (Function.apply(handler, [request, ...request.params.values]) as FutureOr<Response>);
    }
    return claims == null
        ? _problem(401, ErrorTypeV1.authentication, 'A valid bearer token is required')
        : _problem(403, ErrorTypeV1.authorization, '${endpoint.operationId} requires ${endpoint.security}');
  };

  // -- translations (i18n contract) -----------------------------------------------------------

  /// The published bundle, with the release as ETag: `If-None-Match` with the current one → 304.
  Response _getBundle(Request request, String app, String locale) {
    final messages = app == 'match-tracker' ? store.bundles[locale] : null;
    if (messages == null) return _problem(404, ErrorTypeV1.notFound, 'Nothing published for $app/$locale');
    final etag = '"${store.bundleRelease}"';
    if (request.headers['if-none-match'] == etag) return Response(304, headers: {'ETag': etag});
    final bundle = i18n.TranslationBundleV1(
      application: app,
      locale: locale,
      version: store.bundleRelease,
      publishedAt: DateTime.utc(2026, 10, 1, 12),
      messages: messages,
    );
    return Response(
      200,
      body: jsonEncode(i18n.TranslationBundleV1.encode(bundle)),
      headers: {..._jsonHeaders, 'ETag': etag},
    );
  }

  // -- games ----------------------------------------------------------------------------------

  Response _gameSuggestions(Request request) {
    final query = request.url.queryParameters['query'];
    if (query == null || query.isEmpty) return _violation('query', 'REQUIRED', 'query is required');
    return _json(200, [
      for (final g in _matching(store.games, query, (g) => g.displayName))
        GameRefV1.encode(GameRefV1(id: g.id, displayName: g.displayName)),
    ]);
  }

  /// The filterable and sortable fields of `listGames` (its description in the contract).
  static final _games = StubSearch<GameV1>(
    filters: {
      'id': (g) => g.id.value,
      'name': (g) => g.displayName,
      'description': (g) => g.description,
      'minPlayers': (g) => g.minPlayers,
      'maxPlayers': (g) => g.maxPlayers,
      'tags': (g) => g.tags,
      'scoreType': (g) => g.scoreType.wire,
      'winCondition': (g) => g.winCondition?.wire,
      'sourceRef': (g) => g.sourceRef,
      'createdAt': (g) => g.createdAt,
      'updatedAt': (g) => g.updatedAt,
    },
    sorts: {
      'id': (g) => g.id.value,
      'name': (g) => g.displayName,
      'createdAt': (g) => g.createdAt,
      'updatedAt': (g) => g.updatedAt,
    },
    id: (g) => g.id.value,
  );

  Response _listGames(Request request) => _page(request, _games, store.games, (items, next, prev, limit) {
    return GameListV1.encode(GameListV1(limit: limit, items: items, nextCursor: next, prevCursor: prev));
  });

  Response _countGames(Request request) => _count(request, _games, store.games);

  Response _getGame(Request request, String id) {
    final game = store.games.where((g) => g.id.value == id).firstOrNull;
    return game == null ? _problem(404, ErrorTypeV1.notFound, 'No game $id') : _json(200, GameV1.encode(game));
  }

  Future<Response> _createGame(Request request) async {
    final body = await _decode(request, CreateGameV1.decode);
    if (body case Err(error: final response)) return response;
    final create = (body as Ok<CreateGameV1, Response>).value;

    // The contract's rules, server-side, with the generated constants.
    final violations = _validate({
      'displayName': CreateGameV1Validation.displayName.check(create.displayName),
      'description': CreateGameV1Validation.description.check(create.description),
      'sourceRef': CreateGameV1Validation.sourceRef.check(create.sourceRef),
    });
    // A business rule the contract cannot express.
    if (create.maxPlayers < create.minPlayers) {
      violations.add(('maxPlayers', 'OUT_OF_RANGE', 'maxPlayers must be at least minPlayers'));
    }
    if (violations.isNotEmpty) return _violations(violations);
    if (store.games.any((g) => g.displayName.toLowerCase() == create.displayName.toLowerCase())) {
      return _problem(409, ErrorTypeV1.conflict, 'A game named "${create.displayName}" already exists');
    }

    final game = GameV1(
      id: store.nextId(),
      displayName: create.displayName,
      description: create.description,
      minPlayers: create.minPlayers,
      maxPlayers: create.maxPlayers,
      imageUrl: create.imageUrl,
      tags: create.tags,
      scoreType: create.scoreType,
      winCondition: create.winCondition,
      sourceRef: create.sourceRef,
      createdAt: DateTime.now().toUtc(),
    );
    store.games.add(game);
    return _json(201, GameV1.encode(game));
  }

  // -- ghost players --------------------------------------------------------------------------

  Response _ghostPlayerSuggestions(Request request) {
    final query = request.url.queryParameters['query'];
    if (query == null || query.isEmpty) return _violation('query', 'REQUIRED', 'query is required');
    return _json(200, [
      for (final p in _matching(store.ghostPlayers, query, (p) => p.displayName)) GhostPlayerRefV1.encode(p),
    ]);
  }

  // -- matches --------------------------------------------------------------------------------

  /// The filterable and sortable fields of `listMatches` (its description in the contract).
  static final _matches = StubSearch<MatchV1>(
    filters: {
      'id': (m) => m.id.value,
      'gameId': (m) => m.game.id.value,
      'gameName': (m) => m.game.displayName,
      'recorderId': (m) => m.recorder.id.value,
      'recorderName': (m) => m.recorder.displayName,
      'playedAt': (m) => m.playedAt,
      'finalizedAt': (m) => m.finalizedAt,
      'editRequestsEnabled': (m) => m.editRequestsEnabled,
      'lastEditedAt': (m) => m.lastEditedAt,
      'createdAt': (m) => m.createdAt,
    },
    sorts: {
      'id': (m) => m.id.value,
      'playedAt': (m) => m.playedAt,
      'editRequestsEnabled': (m) => m.editRequestsEnabled,
      'createdAt': (m) => m.createdAt,
    },
    id: (m) => m.id.value,
  );

  Response _listMatches(Request request) => _page(request, _matches, store.matches, (items, next, prev, limit) {
    return MatchListV1.encode(MatchListV1(limit: limit, items: items, nextCursor: next, prevCursor: prev));
  });

  Response _countMatches(Request request) => _count(request, _matches, store.matches);

  Response _getMatch(Request request, String id) {
    final match = store.matches.where((m) => m.id.value == id).firstOrNull;
    return match == null ? _problem(404, ErrorTypeV1.notFound, 'No match $id') : _json(200, MatchV1.encode(match));
  }

  Future<Response> _createMatch(Request request) async {
    final body = await _decode(request, CreateMatchV1.decode);
    if (body case Err(error: final response)) return response;
    final create = (body as Ok<CreateMatchV1, Response>).value;

    final violations = _validate({'participants': CreateMatchV1Validation.participants.check(create.participants)});
    final game = store.games.where((g) => g.id == create.gameId).firstOrNull;
    if (game == null) violations.add(('gameId', 'NOT_FOUND', 'unknown game'));
    final players = <MatchParticipantV1>[];
    for (final (i, input) in create.participants.indexed) {
      final ghost = store.ghostPlayers.where((p) => p.id == input.ghostPlayerId).firstOrNull;
      if (ghost == null) {
        violations.add(('participants[$i].ghostPlayerId', 'NOT_FOUND', 'unknown ghost player'));
        continue;
      }
      players.add(
        MatchParticipantV1(
          id: store.nextId(),
          ghostPlayer: ghost,
          score: input.score,
          rank: input.rank,
          outcome: input.outcome,
          createdAt: DateTime.now().toUtc(),
        ),
      );
    }
    if (game != null && create.participants.length > game.maxPlayers) {
      violations.add(('participants', 'OUT_OF_RANGE', '${game.displayName} allows at most ${game.maxPlayers} players'));
    }
    if (violations.isNotEmpty) return _violations(violations);

    final match = MatchV1(
      id: store.nextId(),
      game: GameRefV1(id: game!.id, displayName: game.displayName),
      recorder: store.recorder,
      status: MatchStatusV1.draft,
      playedAt: create.playedAt,
      editRequestsEnabled: create.editRequestsEnabled ?? false,
      createdAt: DateTime.now().toUtc(),
      participants: players,
    );
    store.matches.add(match);
    return _json(201, MatchV1.encode(match));
  }

  // -- helpers --------------------------------------------------------------------------------

  /// Replays the stored response for a repeated `Idempotency-Key` (stratastax-http semantics).
  Handler _idempotent(Future<Response> Function(Request) handler) => (request) async {
    final key = request.headers['idempotency-key'];
    if (key == null) return handler(request);
    if (store.idempotent[key] case (final status, final body)) {
      return Response(status, body: body, headers: {..._jsonHeaders, 'Idempotent-Replayed': 'true'});
    }
    final response = await handler(request);
    final body = await response.readAsString();
    store.idempotent[key] = (response.statusCode, body);
    return response.change(body: body);
  };

  Future<Result<T, Response>> _decode<T>(Request request, T Function(Object? json) decode) async {
    try {
      return Ok(decode(jsonDecode(await request.readAsString())));
    } on JsonDecodeException catch (e) {
      return Err(_violation(e.path, 'INVALID_FORMAT', 'expected ${e.expected}'));
    } on FormatException catch (e) {
      return Err(_problem(400, ErrorTypeV1.validation, 'Body is not JSON: ${e.message}'));
    }
  }

  static List<(String, String, String)> _validate(Map<String, FieldError?> results) => [
    for (final e in results.entries)
      if (e.value case final error?) (e.key, _code(error), error.toString()),
  ];

  /// The codes of the stratastax backend (`validation_error.yaml`).
  static String _code(FieldError error) => switch (error) {
    RequiredError() => 'REQUIRED',
    MinLengthError() || MaxLengthError() => 'VALUE_TOO_LONG',
    PatternError() || FormatError() => 'INVALID_FORMAT',
    _ => 'OUT_OF_RANGE',
  };

  static int _limit(Request request) => int.tryParse(request.url.queryParameters['limit'] ?? '') ?? 20;

  /// A page of [all]; `limit` is the number of items returned, as in the engine.
  static Response _page<T>(
    Request request,
    StubSearch<T> search,
    List<T> all,
    Object? Function(List<T> items, String? next, String? prev, int limit) encode,
  ) {
    final q = request.url.queryParameters;
    try {
      final page = search.page(all, limit: _limit(request), cursor: q['cursor'], filter: q['filter'], sort: q['sort']);
      return _json(200, encode(page.items, page.next, page.prev, page.items.length));
    } on SearchException catch (e) {
      return _violation('query', 'INVALID_SEARCH', e.message);
    }
  }

  static Response _count<T>(Request request, StubSearch<T> search, List<T> all) {
    try {
      final count = search.filter(all, request.url.queryParameters['filter']).length;
      return _json(200, CountV1.encode(CountV1(count: count)));
    } on SearchException catch (e) {
      return _violation('query', 'INVALID_SEARCH', e.message);
    }
  }

  static Iterable<T> _matching<T>(List<T> items, String query, String Function(T) name) =>
      items.where((i) => name(i).toLowerCase().contains(query.toLowerCase())).take(10);
}

const _jsonHeaders = {'Content-Type': 'application/json'};

Response _json(int status, Object? body) => Response(status, body: jsonEncode(body), headers: _jsonHeaders);

Response _problem(int status, ErrorTypeV1 type, String detail) => Response(
  status,
  body: jsonEncode(
    ProblemDetailV1.encode(ProblemDetailV1(type: type, title: type.name, status: status, detail: detail)),
  ),
  headers: {'Content-Type': 'application/problem+json'},
);

Response _violation(String field, String code, String message) => _violations([(field, code, message)]);

Response _violations(List<(String, String, String)> violations) => Response(
  400,
  body: jsonEncode(
    ValidationProblemDetailV1.encode(
      ValidationProblemDetailV1(
        type: ErrorTypeV1.validation,
        title: 'Validation failed',
        status: 400,
        detail: '${violations.length} invalid field(s)',
        errors: [
          for (final (field, code, message) in violations)
            ValidationErrorV1(field: field, code: code, message: message),
        ],
      ),
    ),
  ),
  headers: {'Content-Type': 'application/problem+json'},
);

Middleware _cors() =>
    (handler) => (request) async {
      const headers = {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
        'Access-Control-Allow-Headers': 'Accept, Authorization, Content-Type, Idempotency-Key, If-Match, If-None-Match',
        'Access-Control-Expose-Headers': 'ETag, Idempotent-Replayed',
      };
      if (request.method == 'OPTIONS') return Response(204, headers: headers);
      return (await handler(request)).change(headers: headers);
    };
