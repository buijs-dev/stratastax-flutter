import 'package:meta/meta.dart';
import 'package:stx_core/stx_core.dart';

/// The OIDC token endpoint (form-encoded POST), for [Session] and [ServiceAccountTokens]; the
/// params are the path segments of `tokenPath` under the issuer.
const tokenEndpoint = Endpoint<List<String>, Map<String, String>, TokenResponse>(
  operationId: 'oidcToken',
  method: HttpMethod.post,
  path: PathTemplate(['{tokenPath}']),
  security: Secured.public(),
  requestContentType: 'application/x-www-form-urlencoded',
  encodePath: _segments,
  encodeBody: _form,
  decode: TokenResponse.decode,
);

List<String> _segments(List<String> path) => path;

Object? _form(Map<String, String> body) => Uri(queryParameters: body).query;

/// The token endpoint's answer (RFC 6749 §5.1).
@immutable
final class TokenResponse {
  const TokenResponse({required this.accessToken, this.refreshToken, this.idToken, this.expiresIn});

  static TokenResponse decode(Object? json) {
    final j = Json.object(json);
    return TokenResponse(
      accessToken: Json.string(j, 'access_token'),
      refreshToken: Json.stringOrNull(j, 'refresh_token'),
      idToken: Json.stringOrNull(j, 'id_token'),
      expiresIn: Json.integerOrNull(j, 'expires_in'),
    );
  }

  final String accessToken;
  final String? refreshToken;
  final String? idToken;
  final int? expiresIn;
}
