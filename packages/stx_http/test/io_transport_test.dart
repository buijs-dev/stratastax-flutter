@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:stx_core/stx_core.dart';
import 'package:stx_http/io.dart';
import 'package:stx_http/stx_http.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late HttpServer server;
  late StxClient client;
  final received = <({String method, String path, String? auth, String body})>[];

  setUp(() async {
    received.clear();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      received.add((
        method: request.method,
        path: request.uri.toString(),
        auth: request.headers.value('authorization'),
        body: body,
      ));
      switch (request.uri.path) {
        case '/rest/api/v1/matches':
          request.response
            ..statusCode = 201
            ..headers.contentType = ContentType.json
            ..headers.set('ETag', '"1"')
            ..write(body);
        case final path when path.startsWith('/rest/api/v1/matches/'):
          request.response
            ..statusCode = 404
            ..headers.contentType = ContentType('application', 'problem+json')
            ..write(
              jsonEncode({
                'type': 'https://errors.stratastax.io/not-found',
                'title': 'Not found',
                'status': 404,
                'detail': 'no match',
              }),
            );
        default:
          request.response.statusCode = 500;
      }
      await request.response.close();
    });
    client = StxClient(baseUrl: Uri.parse('http://${server.address.host}:${server.port}/rest'));
  });

  tearDown(() async {
    client.close();
    await server.close(force: true);
  });

  test('round trip over a real socket', () async {
    final result = await client.exchange(MatchesApiV1.createMatch, params: (), body: const MatchV1(matchId));
    expect(result.valueOrNull?.value.id, matchId);
    expect(result.valueOrNull?.status, 201);
    expect(result.valueOrNull?.header('etag'), '"1"');
    expect(received.single.method, 'POST');
    expect(jsonDecode(received.single.body), {'id': matchId.value});
  });

  test('problem documents from the server', () async {
    final result = await client.fetch(MatchesApiV1.getMatch, const GetMatchParams(matchId: matchId));
    expect(result.errorOrNull?.type, ProblemType.notFound);
    expect(result.errorOrNull?.detail, 'no match');
  });

  test('connection refused is a network problem', () async {
    final port = server.port;
    await server.close(force: true);
    final offline = StxClient(
      baseUrl: Uri.parse('http://127.0.0.1:$port'),
      transport: IoTransport(timeout: const Duration(seconds: 2)),
    );
    final result = await offline.fetch(MatchesApiV1.getMatch, const GetMatchParams(matchId: matchId));
    expect(result.errorOrNull?.type, ProblemType.network);
    offline.close();
  });
}
