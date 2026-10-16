/// HTTP client for contract endpoints: typed calls, an interceptor chain and platform transports
/// (`dart:io` and `fetch`). Pure Dart.
library;

export 'src/backend.dart';
export 'src/client.dart';
export 'src/exchange.dart';
export 'src/interceptors/bearer_auth.dart';
export 'src/interceptors/idempotency.dart';
export 'src/interceptors/logging.dart';
export 'src/interceptors/retry.dart';
export 'src/transport/transport.dart' show createTransport;
