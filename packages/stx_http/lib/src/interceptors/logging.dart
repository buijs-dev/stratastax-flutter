import '../exchange.dart';

/// Logs one line per request and one per response. Request bodies are never logged; for failed
/// responses the start of the body is logged (problem documents explain the failure). Header
/// values in [redact] are masked: the access token must never reach a log.
final class LoggingInterceptor implements StxInterceptor {
  LoggingInterceptor({
    required this.log,
    this.logHeaders = false,
    this.errorBodyLength = 300,
    Set<String> redact = const {'authorization', 'cookie', 'set-cookie'},
    Stopwatch Function()? stopwatch,
  }) : redact = {for (final r in redact) r.toLowerCase()},
       _stopwatch = stopwatch ?? Stopwatch.new;

  final void Function(String line) log;
  final bool logHeaders;

  /// Characters of a failed response's body to log; 0 to log none.
  final int errorBodyLength;
  final Set<String> redact;
  final Stopwatch Function() _stopwatch;

  @override
  Future<StxResponse> intercept(StxRequest request, StxNext next) async {
    final id = request.endpoint.operationId;
    log('→ ${request.method.wire} ${request.uri} [$id]${request.attempt > 1 ? ' attempt ${request.attempt}' : ''}');
    if (logHeaders) _headers('→', request.headers);
    final watch = _stopwatch()..start();
    try {
      final response = await next(request);
      log('← ${response.status} [$id] ${watch.elapsedMilliseconds} ms');
      if (!response.isSuccess && errorBodyLength > 0 && response.body.isNotEmpty) {
        final body = response.body.replaceAll(RegExp(r'\s+'), ' ');
        log('←   ${body.length > errorBodyLength ? '${body.substring(0, errorBodyLength)}…' : body}');
      }
      if (logHeaders) _headers('←', response.headers);
      return response;
    } on StxTransportException catch (e) {
      log('✕ [$id] ${e.message} after ${watch.elapsedMilliseconds} ms');
      rethrow;
    }
  }

  void _headers(String direction, Map<String, String> headers) {
    for (final e in headers.entries) {
      log('$direction   ${e.key}: ${redact.contains(e.key.toLowerCase()) ? '***' : e.value}');
    }
  }
}
