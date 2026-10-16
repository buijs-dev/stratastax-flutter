import 'dart:async';

import 'package:stx_core/stx_core.dart';
import 'package:stx_http/stx_http.dart';
import 'package:test/test.dart';

import 'support.dart';

final class _Tokens implements TokenSource {
  _Tokens(this.current, {this.next});

  String? current;
  String? next;
  var refreshes = 0;
  Completer<void>? gate;

  @override
  Future<String?> accessToken() async => current;

  @override
  Future<String?> refreshAccessToken() async {
    refreshes++;
    await gate?.future;
    current = next;
    return next;
  }
}

StxClient _client(FakeTransport transport, List<StxInterceptor> interceptors) =>
    StxClient(baseUrl: Uri.parse('https://x'), transport: transport, interceptors: interceptors);

void main() {
  group('BearerAuthInterceptor', () {
    test('adds the bearer token to authenticated endpoints only', () async {
      final transport = FakeTransport([StxResponse(status: 204), StxResponse(status: 204)]);
      final client = _client(transport, [BearerAuthInterceptor(_Tokens('t1'))]);
      await client.fetch(MatchesApiV1.getMatch, const GetMatchParams(matchId: matchId));
      await client.submit(MatchesApiV1.importRankings, 'csv'); // public
      expect(transport.requests[0].header('authorization'), 'Bearer t1');
      expect(transport.requests[1].header('authorization'), isNull);
    });

    test('on 401: refresh once and retry with the new token', () async {
      final tokens = _Tokens('old', next: 'new');
      final transport = FakeTransport([StxResponse(status: 401)]);
      final client = _client(transport, [BearerAuthInterceptor(tokens)]);
      final result = await client.fetch(MatchesApiV1.getMatch, const GetMatchParams(matchId: matchId));
      expect(result.isOk, isTrue);
      expect(tokens.refreshes, 1);
      expect(transport.requests.map((r) => r.header('authorization')), ['Bearer old', 'Bearer new']);
    });

    test('when refresh fails the 401 is returned as an authentication problem', () async {
      final transport = FakeTransport([StxResponse(status: 401)]);
      final client = _client(transport, [BearerAuthInterceptor(_Tokens('old'))]);
      final result = await client.fetch(MatchesApiV1.getMatch, const GetMatchParams(matchId: matchId));
      expect(result.errorOrNull?.type, ProblemType.authentication);
      expect(transport.requests, hasLength(1));
    });

    test('concurrent 401s share one refresh', () async {
      final tokens = _Tokens('old', next: 'new')..gate = Completer<void>();
      final transport = FakeTransport([StxResponse(status: 401), StxResponse(status: 401)]);
      final client = _client(transport, [BearerAuthInterceptor(tokens)]);
      final calls = [
        client.fetch(MatchesApiV1.getMatch, const GetMatchParams(matchId: matchId)),
        client.fetch(MatchesApiV1.getMatch, const GetMatchParams(matchId: matchId)),
      ];
      await Future<void>.delayed(Duration.zero);
      tokens.gate!.complete();
      final results = await Future.wait(calls);
      expect(results.every((r) => r.isOk), isTrue);
      expect(tokens.refreshes, 1);
    });
  });

  group('IdempotencyKeyInterceptor', () {
    test('sets a UUIDv7 key only on endpoints that declare it', () async {
      final transport = FakeTransport();
      final client = _client(transport, [IdempotencyKeyInterceptor()]);
      await client.submit(MatchesApiV1.createMatch, const MatchV1(matchId));
      await client.submit(MatchesApiV1.createMatchNoKey, const MatchV1(matchId));
      final key = transport.requests[0].header(IdempotencyKeyInterceptor.header)!;
      expect(Uuid.tryParse(key)?.value[14], '7');
      expect(transport.requests[1].header(IdempotencyKeyInterceptor.header), isNull);
    });

    test('retries reuse the same key', () async {
      final transport = FakeTransport([StxResponse(status: 503)]);
      final client = _client(transport, [IdempotencyKeyInterceptor(), RetryInterceptor(sleep: (_) async {})]);
      await client.submit(MatchesApiV1.createMatch, const MatchV1(matchId));
      expect(transport.requests, hasLength(2));
      expect(transport.requests.map((r) => r.header('idempotency-key')).toSet(), hasLength(1));
    });
  });

  group('RetryInterceptor', () {
    late List<Duration> sleeps;
    RetryInterceptor retry({int maxAttempts = 3}) =>
        RetryInterceptor(maxAttempts: maxAttempts, sleep: (d) async => sleeps.add(d));

    setUp(() => sleeps = []);

    test('retries retryable endpoints on 503 and transport errors', () async {
      final transport = FakeTransport([StxResponse(status: 503), const StxTransportException('reset')]);
      final client = _client(transport, [retry()]);
      final result = await client.fetch(MatchesApiV1.getMatch, const GetMatchParams(matchId: matchId));
      expect(result.isOk, isTrue);
      expect(transport.requests.map((r) => r.attempt), [1, 2, 3]);
      expect(sleeps, hasLength(2));
      expect(sleeps[1], greaterThan(sleeps[0] - const Duration(milliseconds: 200)));
    });

    test('never retries a POST without idempotency key', () async {
      final transport = FakeTransport([StxResponse(status: 503)]);
      final client = _client(transport, [retry()]);
      final result = await client.submit(MatchesApiV1.createMatchNoKey, const MatchV1(matchId));
      expect(result.errorOrNull?.status, 503);
      expect(transport.requests, hasLength(1));
    });

    test('gives up after maxAttempts', () async {
      final transport = FakeTransport([const StxTransportException('1'), const StxTransportException('2')]);
      final client = _client(transport, [retry(maxAttempts: 2)]);
      final result = await client.fetch(MatchesApiV1.getMatch, const GetMatchParams(matchId: matchId));
      expect(result.errorOrNull?.type, ProblemType.network);
      expect(transport.requests, hasLength(2));
    });

    test('does not retry other statuses', () async {
      final transport = FakeTransport([StxResponse(status: 500)]);
      final client = _client(transport, [retry()]);
      await client.fetch(MatchesApiV1.getMatch, const GetMatchParams(matchId: matchId));
      expect(transport.requests, hasLength(1));
    });

    test('honours Retry-After, capped at maxDelay', () async {
      final transport = FakeTransport([
        StxResponse(status: 503, headers: {'Retry-After': '2'}),
        StxResponse(status: 503, headers: {'Retry-After': '120'}),
      ]);
      final client = _client(transport, [retry()]);
      await client.fetch(MatchesApiV1.getMatch, const GetMatchParams(matchId: matchId));
      expect(sleeps, [const Duration(seconds: 2), const Duration(seconds: 10)]);
    });
  });

  group('LoggingInterceptor', () {
    test('one line per request and response, tokens redacted, no bodies', () async {
      final lines = <String>[];
      final transport = FakeTransport();
      final client = _client(transport, [
        LoggingInterceptor(log: lines.add, logHeaders: true),
        BearerAuthInterceptor(_Tokens('secret-token')),
      ]);
      await client.submit(MatchesApiV1.createMatch, const MatchV1(matchId));
      final log = lines.join('\n');
      expect(lines.first, startsWith('→ POST https://x/api/v1/matches [createMatch]'));
      expect(log, contains('← 200 [createMatch]'));
      expect(log, isNot(contains(matchId.value))); // body
      // The logger sits outside the auth interceptor, so it never sees the token; even when it
      // does (other orders), authorization is masked.
      expect(log, isNot(contains('secret-token')));
    });

    test('masks configured headers wherever it sits in the chain', () async {
      final lines = <String>[];
      final client = _client(FakeTransport(), [
        BearerAuthInterceptor(_Tokens('secret-token')),
        LoggingInterceptor(log: lines.add, logHeaders: true),
      ]);
      await client.fetch(MatchesApiV1.getMatch, const GetMatchParams(matchId: matchId));
      expect(lines, contains('→   Authorization: ***'));
      expect(lines.join(), isNot(contains('secret-token')));
    });

    test('failed responses log the start of their body', () async {
      final lines = <String>[];
      final client = _client(FakeTransport([StxResponse(status: 404, body: '{"error":\n "Player not found"}')]), [
        LoggingInterceptor(log: lines.add),
      ]);
      await client.fetch(MatchesApiV1.getMatch, const GetMatchParams(matchId: matchId));
      expect(lines, contains('←   {"error": "Player not found"}'));
    });

    test('transport failures are logged and rethrown', () async {
      final lines = <String>[];
      final client = _client(FakeTransport([const StxTransportException('offline')]), [
        LoggingInterceptor(log: lines.add),
      ]);
      final result = await client.fetch(MatchesApiV1.getMatch, const GetMatchParams(matchId: matchId));
      expect(result.errorOrNull?.type, ProblemType.network);
      expect(lines.last, startsWith('✕ [getMatch] offline'));
    });
  });
}
