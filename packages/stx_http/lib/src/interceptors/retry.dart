import 'dart:math';

import '../exchange.dart';

/// Retries retryable endpoints (safe methods, or operations with an idempotency key) on transport
/// failures and on [statuses], with exponential backoff and jitter. A numeric `Retry-After` header
/// is honoured up to [maxDelay].
final class RetryInterceptor implements StxInterceptor {
  RetryInterceptor({
    this.maxAttempts = 3,
    this.baseDelay = const Duration(milliseconds: 200),
    this.maxDelay = const Duration(seconds: 10),
    this.statuses = const {502, 503, 504},
    Future<void> Function(Duration delay)? sleep,
    Random? random,
  }) : _sleep = sleep ?? Future<void>.delayed,
       _random = random ?? Random();

  final int maxAttempts;
  final Duration baseDelay;
  final Duration maxDelay;
  final Set<int> statuses;
  final Future<void> Function(Duration delay) _sleep;
  final Random _random;

  @override
  Future<StxResponse> intercept(StxRequest request, StxNext next) async {
    if (!request.endpoint.retryable) return next(request);
    for (var attempt = 1; ; attempt++) {
      final current = request.copyWith(attempt: attempt);
      final last = attempt >= maxAttempts;
      try {
        final response = await next(current);
        if (last || !statuses.contains(response.status)) return response;
        await _sleep(_delay(attempt, response.header('retry-after')));
      } on StxTransportException {
        if (last) rethrow;
        await _sleep(_delay(attempt, null));
      }
    }
  }

  Duration _delay(int attempt, String? retryAfter) {
    if (int.tryParse(retryAfter ?? '') case final seconds?) {
      final requested = Duration(seconds: seconds);
      return requested > maxDelay ? maxDelay : requested;
    }
    final exponential = baseDelay * pow(2, attempt - 1).toInt();
    final jitter = Duration(milliseconds: _random.nextInt(baseDelay.inMilliseconds + 1));
    final delay = exponential + jitter;
    return delay > maxDelay ? maxDelay : delay;
  }
}
