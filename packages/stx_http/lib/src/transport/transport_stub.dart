import '../exchange.dart';

StxTransport createPlatformTransport(Duration timeout) =>
    throw UnsupportedError('No HTTP transport for this platform; pass one to StxClient(transport: ...)');
