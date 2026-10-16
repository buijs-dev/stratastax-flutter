import '../exchange.dart';

/// Supplies access tokens; implemented by the session in stx_security.
abstract interface class TokenSource {
  /// The current access token, or null when signed out.
  Future<String?> accessToken();

  /// Obtains a new access token (e.g. with the refresh token); null when that is not possible.
  Future<String?> refreshAccessToken();
}

/// Adds `Authorization: Bearer <token>` to endpoints that require authentication, and on a 401
/// refreshes the token once and retries. Concurrent 401s share one refresh (single-flight).
/// Public endpoints never get the header.
final class BearerAuthInterceptor implements StxInterceptor {
  BearerAuthInterceptor(this.tokens);

  final TokenSource tokens;
  Future<String?>? _refreshing;

  @override
  Future<StxResponse> intercept(StxRequest request, StxNext next) async {
    if (!request.endpoint.security.requiresAuthentication) {
      return next(request);
    }

    final token = await tokens.accessToken();
    final response = await next(_authorized(request, token));
    if (response.status != 401) {
      return response;
    }

    final refreshed = await _refresh();
    if (refreshed == null || refreshed == token) {
      return response;
    }

    return next(_authorized(request, refreshed));
  }

  StxRequest _authorized(StxRequest request, String? token) =>
      token == null ? request : request.withHeaders({'Authorization': 'Bearer $token'});

  Future<String?> _refresh() => _refreshing ??= tokens.refreshAccessToken().whenComplete(() => _refreshing = null);
}
