import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../exchange.dart';

StxTransport createPlatformTransport(Duration timeout) => IoTransport(timeout: timeout);

/// `dart:io` transport (VM, Android, iOS, desktop).
final class IoTransport implements StxTransport {
  IoTransport({this.timeout = const Duration(seconds: 30), HttpClient? client})
    : _client = client ?? (HttpClient()..connectionTimeout = timeout);

  final Duration timeout;
  final HttpClient _client;

  @override
  Future<StxResponse> send(StxRequest request) async {
    try {
      return await _send(request).timeout(timeout);
    } on TimeoutException catch (e) {
      throw StxTransportException('timed out after ${timeout.inMilliseconds} ms', e);
    } on SocketException catch (e) {
      throw StxTransportException('connection failed', e);
    } on HandshakeException catch (e) {
      throw StxTransportException('TLS handshake failed', e);
    } on HttpException catch (e) {
      throw StxTransportException('HTTP protocol error', e);
    }
  }

  Future<StxResponse> _send(StxRequest request) async {
    final outgoing = await _client.openUrl(request.method.wire, request.uri);
    outgoing.followRedirects = true;
    request.headers.forEach(outgoing.headers.set);
    if (request.body case final body?) {
      final bytes = utf8.encode(body);
      outgoing.contentLength = bytes.length;
      outgoing.add(bytes);
    }
    final incoming = await outgoing.close();
    final body = await incoming.transform(utf8.decoder).join();
    final headers = <String, String>{};
    incoming.headers.forEach((name, values) => headers[name] = values.join(', '));
    return StxResponse(status: incoming.statusCode, headers: headers, body: body);
  }

  @override
  void close() => _client.close(force: true);
}
