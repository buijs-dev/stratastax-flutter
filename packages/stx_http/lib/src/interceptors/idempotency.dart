import 'package:stx_core/stx_core.dart';

import '../exchange.dart';

/// Sets `Idempotency-Key` (a UUIDv7, as the contract asks) on endpoints that declare it. Place it
/// before [RetryInterceptor] so every retry carries the same key and the server replays instead
/// of executing twice. Mirrors stratastax-http idempotency-core on the server side.
final class IdempotencyKeyInterceptor implements StxInterceptor {
  IdempotencyKeyInterceptor({Uuid Function()? keyFactory})
      : _keyFactory = keyFactory ?? Uuid.v7;

  static const header = 'Idempotency-Key';

  final Uuid Function() _keyFactory;

  @override
  Future<StxResponse> intercept(StxRequest request, StxNext next) {
    if (!request.endpoint.idempotent || request.header(header) != null) {
      return next(request);
    }

    return next(request.withHeaders({header: _keyFactory().value}));
  }
}
