import 'package:stx_compiler/stx_compiler.dart';
import 'package:test/test.dart';

const _config = ContractConfig(name: 'platformV1', spec: 'spec.yaml', modelSuffix: 'V1', apiSuffix: 'ApiV1');
const _lib = 'package:app/gen/contract/platform_v1/api/matches_api_v1.g.dart';

final _contract = ContractFrontend(_config, Diagnostics()).parseSource(r'''
openapi: 3.1.0
paths:
  /matches:
    post:
      operationId: createMatch
      tags: [matches]
      security: [{bearerAuth: [stx-engine:match-create]}]
      requestBody:
        content:
          application/json:
            schema: {$ref: '#/components/schemas/create_match'}
      responses: {'201': {description: Created}}
  /games/suggestions:
    get:
      operationId: getGameSuggestions
      tags: [games]
      security: [{bearerAuth: [stx-engine:game-read]}]
      parameters:
        - {name: query, in: query, required: true, schema: {type: string}}
      responses:
        '200':
          content:
            application/json:
              schema: {type: array, items: {$ref: '#/components/schemas/game_ref'}}
components:
  schemas:
    game_ref:
      type: object
      required: [id, displayName]
      properties:
        id: {type: string, format: uuid}
        displayName: {type: string}
    create_match:
      type: object
      required: [gameId, notes]
      properties:
        gameId: {type: string, format: uuid}
        notes: {type: string, maxLength: 500}
        rounds: {type: integer, minimum: 1, maximum: 10}
''');

const _string = DartTypeRef(name: 'String', kind: TypeKind.string, library: 'dart:core');
const _uuid = DartTypeRef(name: 'Uuid', kind: TypeKind.uuid, library: 'package:stx_core/src/ids.dart');
const _gameId = DartTypeRef(
  name: 'GameId',
  kind: TypeKind.converter,
  library: 'package:app/games.dart',
  converterTarget: _uuid,
  representation: 'value',
);

I18nIR _i18n(List<String> keys) => I18nIR(
  base: 'en',
  locales: const ['en'],
  messages: [
    for (final key in keys) MessageIR(key: key, values: {'en': key}),
  ],
);

final _allKeys = _i18n([
  'matchCreateCommand.title',
  'matchCreateCommand.gameId.label',
  'matchCreateCommand.notes.label',
  'matchCreateCommand.rounds.label',
]);

FormIR _form(List<FieldIR> fields, {RouteIR? route, String name = 'MatchCreateCommand'}) => FormIR(
  name: name,
  library: 'package:app/match.dart',
  location: 'lib/match.dart:1',
  submit: const EndpointRef(operationId: 'createMatch', apiClass: 'MatchesApiV1', member: 'createMatch', library: _lib),
  onSuccess: 'back',
  fields: fields,
  route: route,
);

FieldIR _field(
  String name,
  DartTypeRef type, {
  UiValidateIR validate = const UiValidateIR(),
  String? source,
  String? widget,
}) => FieldIR(
  name: name,
  type: type,
  location: 'lib/match.dart:$name',
  validate: validate,
  dataSource: source,
  widget: widget,
);

final _source = DataSourceIR(
  name: 'GameSearchSource',
  library: 'package:app/games.dart',
  location: 'lib/games.dart:1',
  endpoint: const EndpointRef(
    operationId: 'getGameSuggestions',
    apiClass: 'GamesApiV1',
    member: 'getGameSuggestions',
    library: 'package:app/gen/contract/platform_v1/api/games_api_v1.g.dart',
  ),
  query: 'query',
  value: 'id',
  label: 'displayName',
);

({AppPlan plan, Diagnostics diagnostics}) _plan(
  List<FormIR> forms, {
  I18nIR? i18n,
  Map<String, DataSourceIR> sources = const {},
  Map<String, FieldWidgetIR> widgets = const {},
}) {
  final diagnostics = Diagnostics();
  final plan = AppPlanner(
    ui: UiIR(package: 'app', forms: forms, entities: const {}, dataSources: sources, fieldWidgets: widgets),
    contracts: [_contract],
    i18n: i18n ?? _allKeys,
    diagnostics: diagnostics,
  ).plan();
  return (plan: plan, diagnostics: diagnostics);
}

List<String> _codes(Diagnostics d) => [for (final x in d.all) x.code];

void main() {
  final valid = [
    _field('gameId', _gameId, source: 'GameSearchSource'),
    _field('notes', _string, validate: const UiValidateIR(maxLength: 280)),
  ];

  test('a valid form: converter mapping, data source, merged rules, scopes', () {
    final result = _plan([_form(valid)], sources: {'GameSearchSource': _source});
    expect(result.diagnostics.all, isEmpty);
    final form = result.plan.forms.single;
    expect(form.assignments, {'gameId': 'c.gameId.value', 'notes': 'c.notes'});
    final notes = form.fields.firstWhere((f) => f.field.name == 'notes');
    expect(notes.rules.maxLength, 280);
    expect(notes.rules.required, isTrue);
    expect(form.fields.first.kind, FieldKind.autocomplete);
    expect(form.requires, [
      ['stx-engine:match-create'],
      ['stx-engine:game-read'],
    ]);
  });

  test('STX-U001: required contract property not mapped', () {
    final result = _plan(
      [
        _form([valid.first]),
      ],
      sources: {'GameSearchSource': _source},
    );
    expect(_codes(result.diagnostics), [UiCodes.unmappedRequired]);
  });

  test('STX-U002: field without contract property', () {
    final result = _plan(
      [
        _form([...valid, _field('extra', _string)]),
      ],
      sources: {'GameSearchSource': _source},
    );
    expect(_codes(result.diagnostics), [UiCodes.unmappedField]);
    expect(result.diagnostics.all.single.hint, contains('@UiIgnore'));
  });

  test('STX-U003: type mismatch', () {
    final result = _plan([
      _form([_field('gameId', _string), valid.last]),
    ]);
    expect(_codes(result.diagnostics), [UiCodes.typeMismatch]);
    expect(result.diagnostics.all.single.message, 'String cannot be sent as uuid');
  });

  test('STX-U003: a nullable field for a required property', () {
    final result = _plan(
      [
        _form([valid.first, _field('notes', _string.withNullable(true))]),
      ],
      sources: {'GameSearchSource': _source},
    );
    expect(_codes(result.diagnostics), [UiCodes.typeMismatch]);
  });

  test('STX-U004: loosening the contract', () {
    final result = _plan(
      [
        _form([valid.first, _field('notes', _string, validate: const UiValidateIR(maxLength: 600))]),
      ],
      sources: {'GameSearchSource': _source},
    );
    expect(_codes(result.diagnostics), [UiCodes.loosened]);
    expect(result.diagnostics.all.single.message, contains('maxLength 600 is looser than the contract (500)'));
  });

  test('STX-U005: custom widget for the wrong type', () {
    final result = _plan(
      [
        _form([valid.first, _field('notes', _string, widget: 'NotesField')]),
      ],
      sources: {'GameSearchSource': _source},
      widgets: {
        'NotesField': const FieldWidgetIR(
          name: 'NotesField',
          library: 'package:app/notes.dart',
          location: 'lib/notes.dart:1',
          valueType: DartTypeRef(name: 'int', kind: TypeKind.int, library: 'dart:core'),
        ),
      },
    );
    expect(_codes(result.diagnostics), [UiCodes.widgetType]);
  });

  test('STX-U006: duplicate routes', () {
    const route = RouteIR(path: '/matches/new', nav: 'primary');
    final result = _plan(
      [_form(valid, route: route), _form(valid, route: route, name: 'OtherCommand')],
      sources: {'GameSearchSource': _source},
      i18n: _i18n([
        ..._allKeys.messages.map((m) => m.key),
        'otherCommand.title',
        'otherCommand.gameId.label',
        'otherCommand.notes.label',
      ]),
    );
    expect(_codes(result.diagnostics), [UiCodes.route]);
  });

  test('STX-U007: data source properties are checked against the contract', () {
    final broken = DataSourceIR(
      name: 'GameSearchSource',
      library: _source.library,
      location: _source.location,
      endpoint: _source.endpoint,
      query: 'q',
      value: 'id',
      label: 'displayName',
    );
    final result = _plan([_form(valid)], sources: {'GameSearchSource': broken});
    expect(_codes(result.diagnostics), contains(UiCodes.dataSource));
    expect(result.diagnostics.all.first.hint, 'parameters: query');
  });

  test('STX-U008: duplicate form order', () {
    final result = _plan(
      [
        _form([
          FieldIR(name: 'gameId', type: _gameId, location: 'a', order: 10, dataSource: 'GameSearchSource'),
          FieldIR(name: 'notes', type: _string, location: 'b', order: 10),
        ]),
      ],
      sources: {'GameSearchSource': _source},
    );
    expect(_codes(result.diagnostics), [UiCodes.order]);
  });

  test('STX-I001: a key the page needs is missing', () {
    final result = _plan(
      [_form(valid)],
      sources: {'GameSearchSource': _source},
      i18n: _i18n(['matchCreateCommand.title', 'matchCreateCommand.gameId.label']),
    );
    expect(_codes(result.diagnostics), [I18nCodes.missingBase]);
    expect(result.diagnostics.all.single.message, contains('matchCreateCommand.notes.label'));
  });

  test('numbers get inferred inputs and merged bounds', () {
    final result = _plan(
      [
        _form([
          ...valid,
          _field(
            'rounds',
            const DartTypeRef(name: 'int', kind: TypeKind.int, library: 'dart:core', nullable: true),
            validate: const UiValidateIR(maximum: 5),
          ),
        ]),
      ],
      sources: {'GameSearchSource': _source},
    );
    expect(result.diagnostics.all, isEmpty);
    final rounds = result.plan.forms.single.fields.last;
    expect(rounds.kind, FieldKind.number);
    expect(rounds.rules.minimum, 1);
    expect(rounds.rules.maximum, 5);
    expect(rounds.rules.required, isFalse);
  });
}
