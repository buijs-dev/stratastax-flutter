import 'dart:async';
import 'dart:convert';

import 'package:stx_http/stx_http.dart';
import 'package:stx_security/stx_security.dart';
import 'package:test/test.dart';

/// A token endpoint: records requests, answers from a queue.
final class _TokenServer implements StxTransport {
  final requests = <(Uri, Map<String, String>)>[];
  final responses = <Object>[];
  Completer<void>? gate;

  @override
  Future<StxResponse> send(StxRequest request) async {
    requests.add((request.uri, Uri.splitQueryString(request.body!)));
    await gate?.future;
    final next = responses.removeAt(0);
    if (next is StxTransportException) throw next;
    return next as StxResponse;
  }

  @override
  void close() {}
}

StxResponse _token(String token, {int expiresIn = 300}) => StxResponse(
  status: 200,
  headers: {'content-type': 'application/json'},
  body: jsonEncode({'access_token': token, 'token_type': 'Bearer', 'expires_in': expiresIn}),
);

void main() {
  late _TokenServer server;
  late DateTime now;
  late ServiceAccountTokens tokens;

  setUp(() {
    server = _TokenServer();
    now = DateTime(2026, 10, 20, 12);
    tokens = ServiceAccountTokens(
      config: ServiceAccountConfig(
        issuer: Uri.parse('https://auth.example.test/realms/stratastax'),
        clientId: 'match-tracker-i18n',
        clientSecret: 's3cret',
        scopes: const ['stx-i18n:bundle-read'],
      ),
      transport: server,
      clock: () => now,
    );
  });

  test('client credentials grant on first use; the token is kept until it nearly expires', () async {
    server.responses.addAll([_token('t1'), _token('t2')]);
    expect(await tokens.accessToken(), 't1');
    final (uri, body) = server.requests.single;
    expect(uri.toString(), 'https://auth.example.test/realms/stratastax/protocol/openid-connect/token');
    expect(body, {
      'grant_type': 'client_credentials',
      'client_id': 'match-tracker-i18n',
      'client_secret': 's3cret',
      'scope': 'stx-i18n:bundle-read',
    });

    now = now.add(const Duration(minutes: 4));
    expect(await tokens.accessToken(), 't1');
    now = now.add(const Duration(seconds: 31)); // within the 30 s margin of the 300 s token
    expect(await tokens.accessToken(), 't2');
    expect(server.requests, hasLength(2));
  });

  test('concurrent callers share one request', () async {
    server
      ..gate = Completer<void>()
      ..responses.add(_token('t1'));
    final all = Future.wait([tokens.accessToken(), tokens.accessToken(), tokens.refreshAccessToken()]);
    server.gate!.complete();
    expect(await all, ['t1', 't1', 't1']);
    expect(server.requests, hasLength(1));
  });

  test('refused: no token; unreachable: the current token is kept', () async {
    server.responses.addAll([
      _token('t1'),
      StxTransportException('offline'),
      StxResponse(status: 401, body: '{"error":"invalid_client"}'),
    ]);
    await tokens.accessToken();
    expect(await tokens.refreshAccessToken(), 't1');
    expect(await tokens.refreshAccessToken(), isNull);
  });

  test('StaticTokenSource: a fixed token; empty is none; it cannot be renewed', () async {
    expect(await const StaticTokenSource('abc').accessToken(), 'abc');
    expect(await const StaticTokenSource('').accessToken(), isNull);
    expect(await const StaticTokenSource('abc').refreshAccessToken(), isNull);
  });
}
