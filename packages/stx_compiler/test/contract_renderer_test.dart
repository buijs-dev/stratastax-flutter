import 'package:stx_compiler/stx_compiler.dart';
import 'package:test/test.dart';

const _config = ContractConfig(name: 'platformV1', spec: 'spec.yaml', modelSuffix: 'V1', apiSuffix: 'ApiV1');

Map<String, String> _render(String yaml) {
  final diagnostics = Diagnostics();
  final ir = ContractFrontend(_config, diagnostics).parseSource(yaml);
  if (diagnostics.all.isNotEmpty) throw StateError(diagnostics.all.join("\n"));
  final formatter = GeneratedFormatter();
  return {
    for (final f in ContractRenderer(ir, ScopeRegistry([ir])).render()) f.path: formatter.format(f).content,
    'contract/scopes.g.dart': formatter.format(GeneratedFile('s', renderScopes(ScopeRegistry([ir])))).content,
  };
}

void main() {
  final files = _render('''
openapi: 3.1.0
paths:
  /api/v1/matches:
    post:
      operationId: createMatch
      tags: [matches]
      security:
        - bearerAuth: [stx-engine:match-create]
      requestBody:
        content:
          application/json:
            schema:
              \$ref: '#/components/schemas/match_create'
      responses:
        '201':
          content:
            application/json:
              schema:
                \$ref: '#/components/schemas/match_create'
components:
  schemas:
    match_create:
      type: object
      required: [gameId, playedAt, players]
      properties:
        gameId:
          type: string
          format: uuid
          description: The game being played
        playedAt:
          type: string
          format: date-time
        players:
          type: array
          minItems: 2
          maxItems: 8
          items:
            type: string
            format: uuid
        notes:
          type: string
          maxLength: 500
''');

  test('file layout', () {
    expect(files.keys, [
      'contract/platform_v1/models/match_create.g.dart',
      'contract/platform_v1/validation/match_create.g.dart',
      'contract/platform_v1/api/matches_api_v1.g.dart',
      'contract/platform_v1/models.g.dart',
      'contract/platform_v1/platform_v1.g.dart',
      'contract/scopes.g.dart',
    ]);
  });

  test('every file starts with the generated header', () {
    for (final content in files.values) {
      expect(content, startsWith(generatedHeader));
    }
  });

  test('validation constants from the contract (the example from the architecture)', () {
    final validation = files['contract/platform_v1/validation/match_create.g.dart']!;
    expect(validation, contains('abstract final class MatchCreateV1Validation {'));
    expect(validation, contains('static const gameId = UiFieldValidation(required: true, format: UiFormat.uuid);'));
    expect(
      validation,
      contains('static const playedAt = UiFieldValidation(required: true, format: UiFormat.dateTime);'),
    );
    expect(validation, contains('static const players = UiFieldValidation(required: true, minItems: 2, maxItems: 8);'));
    expect(validation, contains('static const notes = UiFieldValidation(maxLength: 500);'));
  });

  test('model codecs are straight-line', () {
    final model = files['contract/platform_v1/models/match_create.g.dart']!;
    expect(model, contains('/// The game being played\n  final Uuid gameId;'));
    expect(model, contains("'players': [for (final e0 in v.players) e0.value],"));
    expect(model, contains("'notes': ?v.notes,"));
    expect(model, contains("players: Json.list(j, 'players', Json.uuidValue),"));
    expect(model, contains("notes: Json.stringOrNull(j, 'notes'),"));
  });

  test('endpoint constant', () {
    final api = files['contract/platform_v1/api/matches_api_v1.g.dart']!;
    expect(api, contains('static const createMatch = ApiEndpoint<NoParams, MatchCreateV1, MatchCreateV1>('));
    expect(api, contains("import '../../backends.g.dart';"));
    expect(api, contains('security: Secured.scopes({Scope.matchCreate}),'));
    expect(api, contains("import '../../scopes.g.dart';"));
    expect(api, contains('/// `POST /api/v1/matches` · any of `stx-engine:match-create`'));
  });

  test('scopes', () {
    final scopes = files['contract/scopes.g.dart']!;
    expect(scopes, contains('enum Scope implements StxScope {'));
    expect(scopes, contains("matchCreate('stx-engine:match-create')"));
    expect(scopes, contains('static Set<Scope> fromClaims(Iterable<String> claims)'));
    expect(scopes, contains("'stx-engine:match-create' => matchCreate,"));
  });

  test('scope names fall back to the full claim when short names collide', () {
    final ir = ContractFrontend(_config, Diagnostics()).parseSource('''
openapi: 3.1.0
paths:
  /a:
    get:
      operationId: a
      security:
        - bearerAuth: [stx-engine:candidate-read]
      responses: {}
  /b:
    get:
      operationId: b
      security:
        - bearerAuth: [stx-game-catalog:candidate-read]
      responses: {}
''');
    final registry = ScopeRegistry([ir]);
    expect(registry.dartName('stx-engine:candidate-read'), 'stxEngineCandidateRead');
    expect(registry.dartName('stx-game-catalog:candidate-read'), 'stxGameCatalogCandidateRead');
    expect(registry.literal(['stx-game-catalog:candidate-read']), '{Scope.stxGameCatalogCandidateRead}');
  });
}
