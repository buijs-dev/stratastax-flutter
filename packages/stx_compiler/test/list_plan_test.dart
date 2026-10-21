import 'package:stx_compiler/stx_compiler.dart';
import 'package:test/test.dart';

const _config = ContractConfig(name: 'platformV1', spec: 'spec.yaml', modelSuffix: 'V1', apiSuffix: 'ApiV1');
const _api = 'package:app/gen/contract/platform_v1/api/matches_api_v1.g.dart';

/// The list shape of stratastax-contract: `limit`/`cursor`/`filter`/`sort`, `paged_metadata` +
/// `items`, a `/count` endpoint; [search] adds `x-stx-search` to `listMatches`.
ContractIR _contract({String search = ''}) => ContractFrontend(_config, Diagnostics()).parseSource('''
openapi: 3.1.0
paths:
  /matches:
    get:
      operationId: listMatches
      tags: [matches]
      security: [{bearerAuth: [stx-engine:match-read]}]
$search
      parameters:
        - {name: limit, in: query, schema: {type: integer, minimum: 1, maximum: 100}}
        - {name: cursor, in: query, schema: {type: string}}
        - {name: filter, in: query, schema: {type: string}}
        - {name: sort, in: query, schema: {type: string}}
      responses:
        '200':
          content:
            application/json:
              schema: {\$ref: '#/components/schemas/match_list'}
  /matches/count:
    get:
      operationId: countMatches
      tags: [matches]
      security: [{bearerAuth: [stx-engine:match-read]}]
      parameters:
        - {name: filter, in: query, schema: {type: string}}
      responses:
        '200':
          content:
            application/json:
              schema: {\$ref: '#/components/schemas/count'}
  /matches/suggestions:
    get:
      operationId: getMatchSuggestions
      tags: [matches]
      security: [{bearerAuth: [stx-engine:match-read]}]
      parameters:
        - {name: query, in: query, required: true, schema: {type: string}}
      responses:
        '200':
          content:
            application/json:
              schema: {type: array, items: {\$ref: '#/components/schemas/game_ref'}}
components:
  schemas:
    count:
      type: object
      required: [count]
      properties:
        count: {type: integer, format: int64}
    match_list:
      type: object
      allOf:
        - type: object
          required: [limit]
          properties:
            limit: {type: integer}
            prevCursor: {type: [string, 'null']}
            nextCursor: {type: [string, 'null']}
        - type: object
          required: [items]
          properties:
            items: {type: array, items: {\$ref: '#/components/schemas/match'}}
    status:
      type: string
      enum: [DRAFT, FINALIZED]
    game_ref:
      type: object
      required: [id, displayName]
      properties:
        id: {type: string, format: uuid}
        displayName: {type: string}
    match:
      type: object
      required: [id, game, status, playedAt, rounds]
      properties:
        id: {type: string, format: uuid}
        game: {\$ref: '#/components/schemas/game_ref'}
        status: {\$ref: '#/components/schemas/status'}
        playedAt: {type: string, format: date-time}
        rounds: {type: integer}
        notes: {type: string}
''');

const _string = DartTypeRef(name: 'String', kind: TypeKind.string, library: 'dart:core');
const _int = DartTypeRef(name: 'int', kind: TypeKind.int, library: 'dart:core');
const _dateTime = DartTypeRef(name: 'DateTime', kind: TypeKind.dateTime, library: 'dart:core');
const _uuid = DartTypeRef(name: 'Uuid', kind: TypeKind.uuid, library: 'package:stx_core/src/ids.dart');
const _status = DartTypeRef(
  name: 'StatusV1',
  kind: TypeKind.enumType,
  library: 'package:app/gen/contract/platform_v1/models/status.g.dart',
  enumValues: ['draft', 'finalized'],
);

EndpointRef _endpoint(String operationId) =>
    EndpointRef(operationId: operationId, apiClass: 'MatchesApiV1', member: operationId, library: _api);

FieldIR _field(
  String name,
  DartTypeRef type, {
  String? path,
  ColumnIR? column,
  FilterIR? filter,
  SortIR? sort,
  String? text,
}) => FieldIR(
  name: name,
  type: type,
  location: 'lib/overview.dart:$name',
  contractProperty: path,
  column: column,
  filter: filter,
  sort: sort,
  searchText: text,
);

final _fields = [
  _field(
    'gameName',
    _string,
    path: 'game.displayName',
    column: const ColumnIR(order: 10, primary: true),
    text: 'gameName',
  ),
  _field(
    'gameId',
    _uuid,
    path: 'game.id',
    filter: const FilterIR(source: 'MatchSource'),
  ),
  _field(
    'playedAt',
    _dateTime,
    column: const ColumnIR(order: 20),
    filter: const FilterIR(),
    sort: const SortIR(direction: 'desc', initial: true),
  ),
  _field('status', _status, column: const ColumnIR(order: 30), filter: const FilterIR()),
  _field('rounds', _int, column: const ColumnIR(order: 40), filter: const FilterIR(), sort: const SortIR()),
];

ListPageIR _list(
  List<FieldIR> fields, {
  bool count = true,
  String list = 'listMatches',
  int? pageSize,
  List<String> actions = const [],
}) => ListPageIR(
  name: 'MatchOverview',
  library: 'package:app/overview.dart',
  location: 'lib/overview.dart:1',
  list: _endpoint(list),
  count: count ? _endpoint('countMatches') : null,
  fields: fields,
  pageSize: pageSize,
  route: const RouteIR(path: '/matches', nav: 'primary'),
  actions: actions,
);

final _source = DataSourceIR(
  name: 'MatchSource',
  library: 'package:app/sources.dart',
  location: 'lib/sources.dart:1',
  endpoint: _endpoint('getMatchSuggestions'),
  query: 'query',
  value: 'id',
  label: 'displayName',
);

final _keys = I18nIR(
  base: 'en',
  locales: const ['en'],
  messages: [
    for (final key in [
      'matchOverview.title',
      for (final f in ['gameName', 'gameId', 'playedAt', 'status', 'rounds', 'notes', 'createdAt', 'id'])
        'matchOverview.$f.label',
      'enum.StatusV1.draft',
      'enum.StatusV1.finalized',
    ])
      MessageIR(key: key, values: {'en': key}),
  ],
);

({AppPlan plan, Diagnostics diagnostics}) _plan(ListPageIR list, {ContractIR? contract}) {
  final diagnostics = Diagnostics();
  final plan = AppPlanner(
    ui: UiIR(
      package: 'app',
      forms: const [],
      entities: const {},
      dataSources: {'MatchSource': _source},
      fieldWidgets: const {},
      lists: [list],
    ),
    contracts: [contract ?? _contract()],
    i18n: _keys,
    diagnostics: diagnostics,
  ).plan();
  return (plan: plan, diagnostics: diagnostics);
}

List<String> _messages(Diagnostics d) => [for (final x in d.all) '${x.code} ${x.message}'];

void main() {
  test('STX-U006: an action opens a page without a route', () {
    final result = _plan(_list(_fields, actions: ['MatchCreateCommand']));
    expect(_messages(result.diagnostics), [
      'STX-U006 UiAction(MatchCreateCommand): MatchCreateCommand has no @UiRoute',
    ]);
  });

  test('a valid overview: paths, filters by type, sorts, search text, count and scopes', () {
    final result = _plan(_list(_fields));
    expect(result.diagnostics.all, isEmpty, reason: '${_messages(result.diagnostics)}');
    final list = result.plan.lists.single;
    expect(list.itemType, 'MatchV1');
    expect(list.paramsClass, 'ListMatchesParams');
    expect(list.countParamsClass, 'CountMatchesParams');
    expect(list.searchFields, ['gameName']);
    expect(
      [for (final f in list.filters) (f.kind, f.field)],
      [
        (FilterKind.source, 'gameId'), // game.id, flattened
        (FilterKind.dateRange, 'playedAt'),
        (FilterKind.choice, 'status'),
        (FilterKind.range, 'rounds'),
      ],
    );
    expect(list.initialSort?.field, 'playedAt');
    expect(list.initialSort?.direction, 'desc');
    expect(
      [for (final c in list.columns) c.value],
      [
        'Msg.data(item.game.displayName)',
        'Msg.data(context.formats.dateTime(item.playedAt.toLocal()))',
        '_statusV1Label(item.status)',
        'Msg.data(context.formats.number(item.rounds))',
      ],
    );
    expect(list.columns[1].sortField, 'playedAt');
    expect(list.pageSize, 20); // stx.yaml default
    expect(result.plan.routed.single.page, 'MatchOverviewPage');
  });

  test('renders the page and the service', () {
    final plan = _plan(_list(_fields)).plan;
    final files = {
      for (final f in AppRenderer(plan, ScopeRegistry([_contract()])).render()) f.path: f.content,
    };
    final page = files['app/pages/match_overview.page.g.dart']!;
    expect(page, contains('StxSourceFilter<Uuid>(field: \'gameId\''));
    expect(page, contains('StxChoiceFilter<StatusV1>(field: \'status\''));
    expect(page, contains("sort: const SortField('playedAt', SortDirection.desc)"));
    expect(page, contains("search: StxTextFilter(fields: const ['gameName'], label: StxKeys.searchLabel)"));
    final services = files['app/services.g.dart']!;
    expect(services, contains('late final searchCache = StxSearchCache(maxEntries: 200);'));
    expect(services, contains('MatchesApiV1.countMatches, CountMatchesParams(filter: filter)'));
    expect(services, contains("tag: 'matches'"));
    expect(files['app/routes.g.dart'], contains("['matches'] => const MatchOverviewRoute()"));
  });

  test('STX-U010: the list operation must have the list parameters and return a page', () {
    final result = _plan(_list(_fields, list: 'getMatchSuggestions', count: false));
    expect(_messages(result.diagnostics), [
      contains('STX-U010 MatchesApiV1.getMatchSuggestions has no query parameter'),
    ]);
  });

  test('STX-U010: a count endpoint takes only filter and returns {count}', () {
    final result = _plan(
      ListPageIR(
        name: 'MatchOverview',
        library: 'package:app/overview.dart',
        location: 'lib/overview.dart:1',
        list: _endpoint('listMatches'),
        count: _endpoint('getMatchSuggestions'),
        fields: _fields,
      ),
    );
    expect(_messages(result.diagnostics), [contains('is not a count operation')]);
  });

  test('STX-U002: a path that is not in the item schema', () {
    final result = _plan(_list([..._fields, _field('winner', _string, path: 'game.winner', column: const ColumnIR())]));
    expect(_messages(result.diagnostics), [contains('STX-U002 GameRefV1 has no property "winner" (in "game.winner")')]);
  });

  test('STX-U003: an optional property needs a nullable field', () {
    final result = _plan(_list([..._fields, _field('notes', _string, column: const ColumnIR())]));
    expect(_messages(result.diagnostics), [contains('STX-U003 "notes" may be absent')]);
    final ok = _plan(_list([..._fields, _field('notes', _string.withNullable(true), column: const ColumnIR())]));
    expect(ok.diagnostics.all, isEmpty);
    expect(
      ok.plan.lists.single.columns.last.value,
      'switch (item.notes) { final v? => Msg.data(v), null => StxListColumn.none }',
    );
  });

  test('STX-U010: one initial sort, search text on strings, no filter input for a bare id', () {
    final result = _plan(
      _list([
        ..._fields,
        _field(
          'createdAt',
          _dateTime,
          path: 'playedAt',
          sort: const SortIR(alias: 'createdAt', initial: true),
        ),
        _field('roundsText', _int, path: 'rounds', text: ''),
        _field('id', _uuid, filter: const FilterIR()),
      ]),
    );
    expect(_messages(result.diagnostics), [
      contains('only one field can be the initial sort'),
      contains('@SearchText needs a string field'),
      contains('no filter input for "id" (uuid)'),
    ]);
  });

  test('STX-U010: with x-stx-search the aliases must be in its whitelist', () {
    final contract = _contract(
      search: '''
      x-stx-search:
        filter: [gameId, gameName, playedAt, status]
        sort: [playedAt]''',
    );
    final result = _plan(_list(_fields), contract: contract);
    expect(_messages(result.diagnostics), [
      contains('cannot filter on "rounds" (x-stx-search)'),
      contains('cannot sort on "rounds" (x-stx-search)'),
    ]);
  });

  test('STX-U010: pageSize within the limit of the contract', () {
    final result = _plan(_list(_fields, pageSize: 500));
    expect(_messages(result.diagnostics), [contains('pageSize 500 is outside 1–100')]);
  });
}
