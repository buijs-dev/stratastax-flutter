import 'package:stx_compiler/stx_compiler.dart';
import 'package:test/test.dart';

const _config = ContractConfig(name: 'platformV1', spec: 'spec.yaml', modelSuffix: 'V1', apiSuffix: 'ApiV1');

({ContractIR ir, Diagnostics diagnostics}) _parse(String yaml) {
  final diagnostics = Diagnostics();
  final ir = ContractFrontend(_config, diagnostics).parseSource(yaml);
  return (ir: ir, diagnostics: diagnostics);
}

ObjectSchemaIR _object(ContractIR ir, String key) => ir.schemas[key]! as ObjectSchemaIR;

PropertyIR _property(ContractIR ir, String schema, String name) =>
    _object(ir, schema).properties.firstWhere((p) => p.wireName == name);

const _secured = '''
      security:
        - bearerAuth:
            - stx-engine:match-read''';

void main() {
  group('schemas', () {
    final parsed = _parse('''
openapi: 3.1.0
paths: {}
components:
  schemas:
    display_name:
      type: string
      minLength: 1
      maxLength: 100
    date_time:
      type: string
      format: date-time
    score_type:
      type: string
      enum: [SCORE, WIN_LOSS]
    paged_metadata:
      type: object
      required: [limit]
      properties:
        limit:
          type: integer
          minimum: 1
          maximum: 100
        nextCursor:
          type: [string, 'null']
    match:
      type: object
      required: [id, displayName, playedAt, status]
      properties:
        id:
          type: string
          format: uuid
        displayName:
          \$ref: '#/components/schemas/display_name'
        playedAt:
          anyOf:
            - \$ref: '#/components/schemas/date_time'
            - type: 'null'
        scoreType:
          \$ref: '#/components/schemas/score_type'
        status:
          type: string
          enum: [DRAFT, FINALIZED]
        attributes:
          type: object
          additionalProperties: true
        scores:
          type: object
          additionalProperties:
            type: integer
        tags:
          type: array
          minItems: 1
          items:
            type: string
    match_list:
      type: object
      allOf:
        - \$ref: '#/components/schemas/paged_metadata'
        - type: object
          required: [items]
          properties:
            items:
              type: array
              items:
                \$ref: '#/components/schemas/match'
''');
    final ir = parsed.ir;

    test('no diagnostics', () => expect(parsed.diagnostics.all, isEmpty));

    test('aliases are inlined with their constraints, not generated', () {
      expect(ir.schemas.keys, isNot(contains('display_name')));
      expect(ir.schemas.keys, isNot(contains('date_time')));
      final displayName = _property(ir, 'match', 'displayName');
      expect((displayName.type as PrimitiveTypeIR).kind, PrimitiveKind.string);
      expect(displayName.constraints.minLength, 1);
      expect(displayName.constraints.maxLength, 100);
    });

    test('anyOf [x, null] and type [x, null] are nullable', () {
      final playedAt = _property(ir, 'match', 'playedAt');
      expect(playedAt.nullable, isTrue);
      expect(playedAt.required, isTrue);
      expect((playedAt.type as PrimitiveTypeIR).kind, PrimitiveKind.dateTime);
      expect(_property(ir, 'paged_metadata', 'nextCursor').nullable, isTrue);
    });

    test('formats map to Dart types', () {
      expect((_property(ir, 'match', 'id').type as PrimitiveTypeIR).kind, PrimitiveKind.uuid);
    });

    test('component and inline enums', () {
      expect(ir.schemas['score_type'], isA<EnumSchemaIR>());
      expect((ir.schemas['score_type']! as EnumSchemaIR).values.map((v) => v.dartName), ['score', 'winLoss']);
      final status = _property(ir, 'match', 'status').type as RefTypeIR;
      expect(status.schema, 'MatchStatus');
      expect(ir.schemas['MatchStatus']!.dartName, 'MatchStatusV1');
    });

    test('maps and lists', () {
      expect((_property(ir, 'match', 'attributes').type as MapTypeIR).value, isNull);
      expect(
        ((_property(ir, 'match', 'scores').type as MapTypeIR).value! as PrimitiveTypeIR).kind,
        PrimitiveKind.integer,
      );
      final tags = _property(ir, 'match', 'tags');
      expect(tags.type, isA<ListTypeIR>());
      expect(tags.constraints.minItems, 1);
    });

    test('allOf flattens properties and required of all parts', () {
      final list = _object(ir, 'match_list');
      expect(list.properties.map((p) => p.wireName), ['limit', 'nextCursor', 'items']);
      expect(list.properties.firstWhere((p) => p.wireName == 'items').required, isTrue);
      expect(list.properties.firstWhere((p) => p.wireName == 'limit').required, isTrue);
      expect(list.properties.firstWhere((p) => p.wireName == 'limit').constraints.maximum, 100);
    });
  });

  group('operations', () {
    final parsed = _parse('''
openapi: 3.1.0
security:
  - bearerAuth: []
paths:
  /api/v1/matches/{matchId}:
    parameters:
      - \$ref: '#/components/parameters/path_match_id'
    get:
      operationId: getMatch
      tags: [matches]
$_secured
      responses:
        '200':
          \$ref: '#/components/responses/match'
    patch:
      operationId: updateMatch
      tags: [matches]
      security:
        - bearerAuth: [stx-engine:match-update, stx-engine:match-admin]
      parameters:
        - name: If-Match
          in: header
          required: true
          schema:
            type: string
      requestBody:
        content:
          application/json:
            schema:
              \$ref: '#/components/schemas/update_match'
      responses:
        '204':
          description: Updated
  /api/v1/matches:
    post:
      operationId: createMatch
      tags: [matches]
      security:
        - bearerAuth: []
      parameters:
        - \$ref: '#/components/parameters/header_idempotency_key'
      requestBody:
        content:
          application/json:
            schema:
              type: object
              required: [gameId]
              properties:
                gameId:
                  type: string
                  format: uuid
      responses:
        '201':
          content:
            application/json:
              schema:
                type: array
                items:
                  \$ref: '#/components/schemas/match'
  /api/v1/health:
    get:
      operationId: health
      tags: [system]
      security: []
      responses:
        '200':
          description: OK
  /api/v1/rankings:
    post:
      operationId: importRankings
      tags: [system]
$_secured
      requestBody:
        content:
          text/csv:
            schema:
              type: string
      responses:
        '204':
          description: Imported
  /api/v1/undeclared:
    get:
      operationId: undeclared
      tags: [system]
      responses:
        '204':
          description: OK
components:
  parameters:
    path_match_id:
      name: matchId
      in: path
      required: true
      schema:
        type: string
        format: uuid
    header_idempotency_key:
      name: Idempotency-Key
      in: header
      required: true
      schema:
        type: string
  responses:
    match:
      content:
        application/json:
          schema:
            \$ref: '#/components/schemas/match'
  schemas:
    match:
      type: object
      required: [id]
      properties:
        id:
          type: string
          format: uuid
    update_match:
      type: object
      required: [version]
      properties:
        version:
          type: integer
        playedAt:
          type: [string, 'null']
          format: date-time
        notes:
          type: string
''');
    final ir = parsed.ir;
    OperationIR op(String id) => ir.operations.firstWhere((o) => o.operationId == id);

    test('root-level security is ignored: undeclared is an error (STX-C001)', () {
      final errors = parsed.diagnostics.all.where((d) => d.isError).toList();
      expect(errors.map((d) => d.code), [ContractCodes.undeclaredSecurity]);
      expect(errors.single.location, contains('undeclared'));
      expect(op('undeclared').security, isA<UndeclaredSecurity>());
    });

    test('security kinds', () {
      expect(op('health').security, isA<PublicSecurity>());
      expect(op('createMatch').security, isA<AuthenticatedSecurity>());
      expect((op('updateMatch').security as ScopedSecurity).scopes, [
        'stx-engine:match-admin',
        'stx-engine:match-update',
      ]);
    });

    test('path-level parameters and \$ref parameters', () {
      final matchId = op('getMatch').params.single;
      expect(matchId.location, ParamLocation.path);
      expect(matchId.required, isTrue);
      expect((matchId.type as PrimitiveTypeIR).kind, PrimitiveKind.uuid);
    });

    test('Idempotency-Key becomes a flag, not a parameter', () {
      expect(op('createMatch').idempotent, isTrue);
      expect(op('createMatch').params, isEmpty);
    });

    test('header parameters get Dart names', () {
      final ifMatch = op('updateMatch').params.firstWhere((p) => p.location == ParamLocation.header);
      expect(ifMatch.dartName, 'ifMatch');
      expect(ifMatch.wireName, 'If-Match');
    });

    test('inline request bodies and list responses', () {
      expect((op('createMatch').body!.type as RefTypeIR).schema, 'CreateMatchRequest');
      expect(ir.schemas['CreateMatchRequest']!.dartName, 'CreateMatchRequestV1');
      expect(op('createMatch').response, isA<ListTypeIR>());
      expect((op('getMatch').response! as RefTypeIR).schema, 'match');
      expect(op('updateMatch').response, isNull);
    });

    test('non-JSON string bodies keep their content type', () {
      expect(op('importRankings').body!.contentType, 'text/csv');
      expect(op('importRankings').body!.isJson, isFalse);
    });

    test('optional nullable properties of PATCH bodies become Patch<T>', () {
      expect(_property(ir, 'update_match', 'playedAt').patch, isTrue);
      expect(_property(ir, 'update_match', 'notes').patch, isFalse); // optional, not nullable
      expect(_property(ir, 'update_match', 'version').patch, isFalse); // required
    });

    test('operations are sorted by tag, then operationId', () {
      expect(ir.operations.map((o) => o.operationId), [
        'createMatch',
        'getMatch',
        'updateMatch',
        'health',
        'importRankings',
        'undeclared',
      ]);
    });
  });

  group('errors', () {
    test('external refs are rejected with a hint', () {
      final parsed = _parse('''
openapi: 3.1.0
paths: {}
components:
  schemas:
    match:
      type: object
      properties:
        game:
          \$ref: './game.yaml'
''');
      final error = parsed.diagnostics.all.single;
      expect(error.code, ContractCodes.unresolvedRef);
      expect(error.hint, contains('bundled'));
    });

    test('anyOf alternatives are not supported yet', () {
      final parsed = _parse('''
openapi: 3.1.0
paths: {}
components:
  schemas:
    match:
      type: object
      properties:
        score:
          anyOf:
            - type: string
            - type: integer
''');
      expect(parsed.diagnostics.all.single.code, ContractCodes.unsupported);
    });

    test('two schemas with the same Dart name collide', () {
      final parsed = _parse('''
openapi: 3.1.0
paths: {}
components:
  schemas:
    match_status:
      type: string
      enum: [A]
    MatchStatus:
      type: string
      enum: [B]
''');
      expect(parsed.diagnostics.all.single.code, ContractCodes.nameCollision);
    });

    test('operations without operationId', () {
      final parsed = _parse('''
openapi: 3.1.0
paths:
  /x:
    get:
      security: []
      responses: {}
''');
      expect(parsed.diagnostics.all.single.code, ContractCodes.missingOperationId);
    });
  });
}
