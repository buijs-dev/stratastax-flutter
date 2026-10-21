/// OIDC login (Authorization Code + PKCE), session, token refresh and scopes for stratastax-flutter,
/// and service accounts (client credentials) for backends that do not act as the user.
/// Pure Dart; the web redirect and storage use package:web.
library;

export 'src/jwt.dart';
export 'src/oidc.dart';
export 'src/platform/platform.dart';
export 'src/client_credentials.dart';
export 'src/session.dart';
export 'src/token_endpoint.dart' show TokenResponse;
