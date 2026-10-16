import 'package:stx_core/stx_core.dart';
import 'package:stx_http/stx_http.dart';

/// Endpoints shaped like stx_compiler output.
final class MatchV1 {
  const MatchV1(this.id);

  final Uuid id;

  static Map<String, Object?> encode(MatchV1 v) => {'id': v.id.value};

  static MatchV1 decode(Object? json) => MatchV1(Json.uuid(Json.object(json), 'id'));
}

final class GetMatchParams {
  const GetMatchParams({required this.matchId});

  final Uuid matchId;
}

final class ListMatchesParams {
  const ListMatchesParams({this.limit, this.filter});

  final int? limit;
  final String? filter;
}

final class UpdateMatchParams {
  const UpdateMatchParams({required this.matchId, required this.ifMatch});

  final Uuid matchId;
  final String ifMatch;
}

abstract final class MatchesApiV1 {
  static const getMatch = Endpoint<GetMatchParams, NoBody, MatchV1>(
    operationId: 'getMatch',
    method: HttpMethod.get,
    path: PathTemplate(['api', 'v1', 'matches', '{matchId}']),
    security: Secured.scopes({TestScope.read}),
    encodePath: _getMatchPath,
    decode: MatchV1.decode,
  );

  static const listMatches = Endpoint<ListMatchesParams, NoBody, List<MatchV1>>(
    operationId: 'listMatches',
    method: HttpMethod.get,
    path: PathTemplate(['api', 'v1', 'matches']),
    security: Secured.scopes({TestScope.read}),
    encodeQuery: _listMatchesQuery,
    decode: _listMatchesResponse,
  );

  static const createMatch = Endpoint<NoParams, MatchV1, MatchV1>(
    operationId: 'createMatch',
    method: HttpMethod.post,
    path: PathTemplate(['api', 'v1', 'matches']),
    security: Secured.scopes({TestScope.write}),
    idempotent: true,
    encodeBody: MatchV1.encode,
    decode: MatchV1.decode,
  );

  static const createMatchNoKey = Endpoint<NoParams, MatchV1, MatchV1>(
    operationId: 'createMatchNoKey',
    method: HttpMethod.post,
    path: PathTemplate(['api', 'v1', 'matches']),
    security: Secured.authenticated(),
    encodeBody: MatchV1.encode,
    decode: MatchV1.decode,
  );

  static const deleteMatch = Endpoint<UpdateMatchParams, NoBody, NoContent>(
    operationId: 'deleteMatch',
    method: HttpMethod.delete,
    path: PathTemplate(['api', 'v1', 'matches', '{matchId}']),
    security: Secured.authenticated(),
    encodePath: _deleteMatchPath,
    encodeHeaders: _deleteMatchHeaders,
    decode: NoContent.decode,
  );

  static const importRankings = Endpoint<NoParams, String, NoContent>(
    operationId: 'importRankings',
    method: HttpMethod.post,
    path: PathTemplate(['api', 'v1', 'pipeline', 'import-rankings']),
    security: Secured.public(),
    requestContentType: 'text/csv',
    encodeBody: _importRankingsBody,
    decode: NoContent.decode,
  );

  static List<String> _getMatchPath(GetMatchParams p) => ['api', 'v1', 'matches', p.matchId.value];

  static Map<String, List<String>> _listMatchesQuery(ListMatchesParams p) => {
    if (p.limit case final v?) 'limit': [v.toString()],
    if (p.filter case final v?) 'filter': [v],
  };

  static List<MatchV1> _listMatchesResponse(Object? json) => Json.listValue(json, MatchV1.decode);

  static List<String> _deleteMatchPath(UpdateMatchParams p) => ['api', 'v1', 'matches', p.matchId.value];

  static Map<String, String> _deleteMatchHeaders(UpdateMatchParams p) => {'If-Match': p.ifMatch};

  static Object? _importRankingsBody(String body) => body;
}

const matchId = Uuid.trusted('6f1c2b3a-0d4e-4f5a-9b8c-7d6e5f4a3b2c');

/// Records requests and answers from a queue of responses (or throws queued exceptions).
final class FakeTransport implements StxTransport {
  FakeTransport([List<Object> responses = const []]) : _queue = [...responses];

  final List<Object> _queue;
  final List<StxRequest> requests = [];
  var closed = false;

  void enqueue(Object responseOrException) => _queue.add(responseOrException);

  @override
  Future<StxResponse> send(StxRequest request) async {
    requests.add(request);
    if (_queue.isEmpty) return StxResponse(status: 200, body: '{"id":"${matchId.value}"}');
    final next = _queue.removeAt(0);
    if (next is StxResponse) return next;
    throw next;
  }

  @override
  void close() => closed = true;
}

StxResponse json(int status, String body, {Map<String, String> headers = const {}}) =>
    StxResponse(status: status, body: body, headers: {'content-type': 'application/json', ...headers});

enum TestScope implements StxScope {
  read,
  write;

  @override
  String get claim => 'test:$name';
}
