import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../exchange.dart';

StxTransport createPlatformTransport(Duration timeout) => WebTransport(timeout: timeout);

/// `fetch` transport for the web.
final class WebTransport implements StxTransport {
  WebTransport({this.timeout = const Duration(seconds: 30)});

  final Duration timeout;

  @override
  Future<StxResponse> send(StxRequest request) async {
    final abort = web.AbortController();
    final timer = Timer(timeout, () => abort.abort());
    try {
      final headers = web.Headers();
      request.headers.forEach((name, value) => headers.append(name, value));
      final response = await web.window
          .fetch(
            request.uri.toString().toJS,
            web.RequestInit(
              method: request.method.wire,
              headers: headers,
              body: request.body?.toJS,
              signal: abort.signal,
            ),
          )
          .toDart;
      final body = (await response.text().toDart).toDart;
      final responseHeaders = <String, String>{};
      response.headers.forEachEntry(
        ((JSString value, JSString name) {
          responseHeaders[name.toDart] = value.toDart;
        }).toJS,
      );
      return StxResponse(status: response.status, headers: responseHeaders, body: body);
    } catch (e) {
      // fetch rejects with a JS TypeError (network) or an AbortError (timeout); the representation
      // differs between dart2js and dart2wasm, so the error is not type-tested.
      throw StxTransportException(
        abort.signal.aborted ? 'timed out after ${timeout.inMilliseconds} ms' : 'fetch failed',
        e,
      );
    } finally {
      timer.cancel();
    }
  }

  @override
  void close() {}
}

extension on web.Headers {
  /// `Headers.prototype.forEach(callback(value, name))`; not exposed by package:web.
  @JS('forEach')
  external void forEachEntry(JSFunction callback);
}
