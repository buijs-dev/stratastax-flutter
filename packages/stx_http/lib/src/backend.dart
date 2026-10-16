import 'exchange.dart';

/// Runtime configuration of one backend: where it lives and extra interceptors for its client
/// (between logging and authentication / idempotency / retry).
final class StxBackend {
  const StxBackend({required this.baseUrl, this.interceptors = const []});

  final Uri baseUrl;
  final List<StxInterceptor> interceptors;
}
