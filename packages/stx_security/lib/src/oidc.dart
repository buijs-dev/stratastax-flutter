import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';

/// An OpenID Connect client (Authorization Code + PKCE). Endpoint paths follow Keycloak's layout
/// under the realm [issuer], e.g. `https://auth.example.com/realms/stratastax`.
@immutable
final class OidcConfig {
  const OidcConfig({
    required this.issuer,
    required this.clientId,
    required this.redirectUri,
    this.postLogoutRedirectUri,
    this.scopes = const ['openid', 'profile'],
    this.roleClaims = defaultRoleClaims,
    this.authorizePath = 'protocol/openid-connect/auth',
    this.tokenPath = 'protocol/openid-connect/token',
    this.logoutPath = 'protocol/openid-connect/logout',
    this.refreshMargin = const Duration(seconds: 30),
  });

  /// Where Quarkus OIDC and Keycloak put roles, plus the OAuth `scope` claim.
  static const defaultRoleClaims = ['realm_access.roles', 'resource_access.*.roles', 'scope', 'groups'];

  final Uri issuer;
  final String clientId;

  /// Where the identity provider sends the browser back with `code` and `state`.
  final Uri redirectUri;
  final Uri? postLogoutRedirectUri;
  final List<String> scopes;

  /// Claims (dotted paths, `*` matches every key) that hold roles or scopes; strings are split on
  /// spaces.
  final List<String> roleClaims;
  final String authorizePath;
  final String tokenPath;
  final String logoutPath;

  /// Refresh the access token this long before it expires.
  final Duration refreshMargin;

  Uri endpoint(String path) =>
      issuer.replace(pathSegments: [...issuer.pathSegments.where((s) => s.isNotEmpty), ...path.split('/')]);
}

/// PKCE (RFC 7636) with the S256 method.
@immutable
final class Pkce {
  const Pkce(this.verifier);

  /// 64 characters from the unreserved set, from a secure random source.
  factory Pkce.generate([Random? random]) => Pkce(randomToken(64, random));

  final String verifier;

  String get challenge => base64Url.encode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');
}

const _unreserved = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

/// A random string of [length] unreserved characters (for PKCE verifiers and `state`).
String randomToken(int length, [Random? random]) {
  final rng = random ?? Random.secure();
  return String.fromCharCodes([
    for (var i = 0; i < length; i++) _unreserved.codeUnitAt(rng.nextInt(_unreserved.length)),
  ]);
}
