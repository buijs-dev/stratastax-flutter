import 'dart:convert';

import 'package:stx_core/stx_core.dart';
import 'package:stx_http/stx_http.dart';
import 'package:stx_search/stx_search.dart';
import 'package:test/test.dart';

/// Shaped like the generated `ListGamesParams` / `GameListV1`.
final class ListParams {
  const ListParams({this.limit, this.cursor, this.filter, this.sort});

  final int? limit;
  final String? cursor;
  final String? filter;
  final String? sort;
}

final class GameList {
  const GameList(this.items, this.nextCursor, this.prevCursor);

  final List<String> items;
  final String? nextCursor;
  final String? prevCursor;

  static GameList decode(Object? json) {
    final j = Json.object(json);
    return GameList(
      Json.list(j, 'items', (v) => v as String),
      Json.stringOrNull(j, 'nextCursor'),
      Json.stringOrNull(j, 'prevCursor'),
    );
  }
}

const listGames = Endpoint<ListParams, NoBody, GameList>(
  operationId: 'listGames',
  method: HttpMethod.get,
  path: PathTemplate(['api', 'v1', 'games']),
  security: Secured.authenticated(),
  encodeQuery: _query,
  decode: GameList.decode,
);

Map<String, List<String>> _query(ListParams p) => {
  if (p.limit case final v?) 'limit': ['$v'],
  if (p.cursor case final v?) 'cursor': [v],
  if (p.filter case final v?) 'filter': [v],
  if (p.sort case final v?) 'sort': [v],
};

final class Transport implements StxTransport {
  final requests = <StxRequest>[];

  @override
  Future<StxResponse> send(StxRequest request) async {
    requests.add(request);
    final cursor = request.uri.queryParameters['cursor'];
    return StxResponse(
      status: 200,
      headers: const {'content-type': 'application/json'},
      body: jsonEncode({
        'limit': 2,
        'items': cursor == null ? ['Catan', 'Everdell'] : ['Pandemic'],
        'nextCursor': cursor == null ? 'n1' : null,
        'prevCursor': cursor == null ? null : 'p1',
      }),
    );
  }

  @override
  void close() {}
}

void main() {
  late Transport transport;
  late StxSearchService<ListParams, GameList, String> service;
  var counted = 0;

  setUp(() {
    transport = Transport();
    counted = 0;
    service = StxSearchService(
      client: StxClient(baseUrl: Uri.parse('http://test'), transport: transport),
      endpoint: listGames,
      params: (q) => ListParams(limit: q.limit, cursor: q.cursor, filter: q.filter, sort: q.sort),
      items: (r) => r.items,
      nextCursor: (r) => r.nextCursor,
      prevCursor: (r) => r.prevCursor,
      tag: 'games',
      cache: StxSearchCache(),
      count: (filter) async => Ok(++counted),
    );
  });

  test('the first page sends filter, sort and limit; the next only cursor and limit', () async {
    const query = StxSearchQuery(filter: 'scoreType==SCORE', sort: 'name:ASC', limit: 2);
    final first = (await service.page(query)).valueOrNull!;
    expect(first.items, ['Catan', 'Everdell']);
    expect(first.hasNext, isTrue);
    expect(first.hasPrev, isFalse);
    expect(transport.requests.last.uri.queryParameters, {
      'limit': '2',
      'filter': 'scoreType==SCORE',
      'sort': 'name:ASC',
    });

    final second = (await service.page(query.at(first.nextCursor))).valueOrNull!;
    expect(second.items, ['Pandemic']);
    expect(second.prevCursor, 'p1');
    expect(transport.requests.last.uri.queryParameters, {'limit': '2', 'cursor': 'n1'});
  });

  test('pages and totals are cached until their tag is invalidated', () async {
    const query = StxSearchQuery(limit: 2);
    await service.page(query);
    await service.page(query);
    expect(transport.requests, hasLength(1));
    expect((await service.total(null)).valueOrNull, 1);
    expect((await service.total(null)).valueOrNull, 1);

    service.invalidate();
    await service.page(query);
    expect(transport.requests, hasLength(2));
    expect((await service.total(null)).valueOrNull, 2);
  });

  test('without a count endpoint the total is null', () async {
    final plain = StxSearchService<ListParams, GameList, String>(
      client: StxClient(baseUrl: Uri.parse('http://test'), transport: transport),
      endpoint: listGames,
      params: (q) => ListParams(limit: q.limit, cursor: q.cursor),
      items: (r) => r.items,
      nextCursor: (r) => r.nextCursor,
      prevCursor: (r) => r.prevCursor,
      tag: 'games',
      cache: StxSearchCache(),
    );
    expect(plain.counts, isFalse);
    expect(await plain.total('a==1'), const Ok<int?, Problem>(null));
  });
}
