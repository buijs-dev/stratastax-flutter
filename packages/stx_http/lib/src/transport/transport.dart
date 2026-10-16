import '../exchange.dart';
import 'transport_stub.dart'
    if (dart.library.io) 'transport_io.dart'
    if (dart.library.js_interop) 'transport_web.dart'
    as platform;

/// The transport for the current platform: `dart:io` `HttpClient` on VM / mobile / desktop,
/// `fetch` on the web.
StxTransport createTransport({Duration timeout = const Duration(seconds: 30)}) =>
    platform.createPlatformTransport(timeout);
