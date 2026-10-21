import 'dart:convert';

import 'package:stx_core/stx_core.dart';
import 'package:stx_http/stx_http.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late FakeTransport transport;
  late StxClient client;

  setUp(() {
    transport = FakeTransport();
    client = StxClient(baseUrl: Uri.parse('https://stratastax.dev/rest'), transport: transport);
  });

  group('requests', () {
    test('path segments are appended to the base path and encoded', () async {
      await client.fetch(MatchesApiV1.getMatch, const GetMatchParams(matchId: matchId));
      expect(transport.requests.single.uri.toString(), 'https://stratastax.dev/rest/api/v1/matches/${matchId.value}');
      expect(transport.requests.single.method, HttpMethod.get);
    });

    test('query parameters leave out absent values', () async {
      await client.fetch(MatchesApiV1.listMatches, const ListMatchesParams(limit: 10, filter: 'status==DRAFT;a b'));
      final uri = transport.requests.single.uri;
      expect(uri.queryParameters, {'limit': '10', 'filter': 'status==DRAFT;a b'});

      await client.fetch(MatchesApiV1.listMatches, const ListMatchesParams());
      expect(transport.requests.last.uri.hasQuery, isFalse);
    });

    test('JSON bodies are encoded with a content type', () async {
      await client.submit(MatchesApiV1.createMatch, const MatchV1(matchId));
      final request = transport.requests.single;
      expect(request.header('content-type'), 'application/json');
      expect(jsonDecode(request.body!), {'id': matchId.value});
      expect(request.header('accept'), contains('application/problem+json'));
    });

    test('non-JSON bodies are sent as-is with their content type', () async {
      transport.enqueue(StxResponse(status: 204));
      await client.submit(MatchesApiV1.importRankings, 'id,name\n1,Catan');
      final request = transport.requests.single;
      expect(request.header('content-type'), 'text/csv');
      expect(request.body, 'id,name\n1,Catan');
    });

    test('header parameters', () async {
      transport.enqueue(StxResponse(status: 204));
      await client.fetch(MatchesApiV1.deleteMatch, const UpdateMatchParams(matchId: matchId, ifMatch: '"3"'));
      expect(transport.requests.single.header('if-match'), '"3"');
      expect(transport.requests.single.body, isNull);
    });
  });

  group('results', () {
    test('success decodes the body', () async {
      final result = await client.fetch(MatchesApiV1.getMatch, const GetMatchParams(matchId: matchId));
      expect(result.valueOrNull?.id, matchId);
    });

    test('list responses', () async {
      transport.enqueue(json(200, '[{"id":"${matchId.value}"}]'));
      final result = await client.fetch(MatchesApiV1.listMatches, const ListMatchesParams());
      expect(result.valueOrNull?.single.id, matchId);
    });

    test('204 gives NoContent', () async {
      transport.enqueue(StxResponse(status: 204));
      final result = await client.fetch(
        MatchesApiV1.deleteMatch,
        const UpdateMatchParams(matchId: matchId, ifMatch: 'x'),
      );
      expect(result.valueOrNull, NoContent.instance);
    });

    test('exchange keeps status and headers (ETag for If-Match)', () async {
      transport.enqueue(json(200, '{"id":"${matchId.value}"}', headers: {'ETag': '"7"'}));
      final result = await client.exchange(
        MatchesApiV1.getMatch,
        params: const GetMatchParams(matchId: matchId),
        body: (),
      );
      expect(result.valueOrNull?.header('etag'), '"7"');
      expect(result.valueOrNull?.status, 200);
    });

    test('exchangeIfModified: 304 is Ok(null), anything else as exchange', () async {
      transport
        ..enqueue(StxResponse(status: 304, headers: {'ETag': '"7"'}))
        ..enqueue(json(200, '{"id":"${matchId.value}"}', headers: {'ETag': '"8"'}));
      Future<Result<StxReply<MatchV1>?, Problem>> get() => client.exchangeIfModified(
        MatchesApiV1.getMatch,
        params: const GetMatchParams(matchId: matchId),
        body: (),
      );
      expect(await get(), isA<Ok<StxReply<MatchV1>?, Problem>>().having((r) => r.value, 'value', isNull));
      expect((await get()).valueOrNull?.header('etag'), '"8"');

      // Without the conditional call a 304 is not a success.
      transport.enqueue(StxResponse(status: 304));
      final plain = await client.exchange(
        MatchesApiV1.getMatch,
        params: const GetMatchParams(matchId: matchId),
        body: (),
      );
      expect(plain.valueOrNull, isNull);
    });

    test('error responses become the contract problem', () async {
      transport.enqueue(
        json(
          400,
          jsonEncode({
            'type': 'https://errors.stratastax.io/validation',
            'title': 'Validation failed',
            'status': 400,
            'detail': 'invalid',
            'errors': [
              {'field': 'participants', 'code': 'OUT_OF_RANGE', 'message': 'at least 1'},
            ],
          }),
        ),
      );
      final result = await client.submit(MatchesApiV1.createMatch, const MatchV1(matchId));
      final problem = result.errorOrNull!;
      expect(problem.type, ProblemType.validation);
      expect(problem.violations.single.field, 'participants');
    });

    test('error responses without a problem body still give a problem', () async {
      transport.enqueue(StxResponse(status: 404, body: '<html>Not found</html>'));
      final result = await client.fetch(MatchesApiV1.getMatch, const GetMatchParams(matchId: matchId));
      expect(result.errorOrNull, Problem.fromStatus(404));
    });

    test('a response that violates the contract is a decoding problem with the path', () async {
      transport.enqueue(json(200, '{"id": 42}'));
      final result = await client.fetch(MatchesApiV1.getMatch, const GetMatchParams(matchId: matchId));
      expect(result.errorOrNull?.type, ProblemType.decoding);
      expect(result.errorOrNull?.detail, contains('at id'));
      expect(result.errorOrNull?.status, 200);
    });

    test('invalid JSON is a decoding problem', () async {
      transport.enqueue(json(200, '{"id":'));
      final result = await client.fetch(MatchesApiV1.getMatch, const GetMatchParams(matchId: matchId));
      expect(result.errorOrNull?.type, ProblemType.decoding);
    });

    test('transport failures are a network problem', () async {
      transport.enqueue(const StxTransportException('offline'));
      final result = await client.fetch(MatchesApiV1.getMatch, const GetMatchParams(matchId: matchId));
      expect(result.errorOrNull?.type, ProblemType.network);
    });
  });

  test('interceptors run in the given order, outermost first', () async {
    final calls = <String>[];
    final client = StxClient(
      baseUrl: Uri.parse('https://x'),
      transport: transport,
      interceptors: [_Trace('a', calls), _Trace('b', calls)],
    );
    await client.fetch(MatchesApiV1.getMatch, const GetMatchParams(matchId: matchId));
    expect(calls, ['a→', 'b→', '←b', '←a']);
    expect(transport.requests.single.header('x-trace'), 'b');
  });

  test('close closes the transport', () {
    client.close();
    expect(transport.closed, isTrue);
  });
}

final class _Trace implements StxInterceptor {
  _Trace(this.name, this.calls);

  final String name;
  final List<String> calls;

  @override
  Future<StxResponse> intercept(StxRequest request, StxNext next) async {
    calls.add('$name→');
    final response = await next(request.withHeaders({'X-Trace': name}));
    calls.add('←$name');
    return response;
  }
}
