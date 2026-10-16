import 'dart:convert';

/// The claims of a JWT, decoded without verifying the signature: the client only reads them to
/// adapt the UI; the API verifies every token.
Map<String, Object?>? jwtClaims(String token) {
  final parts = token.split('.');
  if (parts.length != 3) return null;
  try {
    final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
    final json = jsonDecode(payload);
    return json is Map<String, Object?> ? json : null;
  } on FormatException {
    return null;
  }
}

/// Every role or scope found in [claims] at [paths] (dotted, `*` matches every key); string values
/// are split on whitespace (the OAuth `scope` claim).
Set<String> jwtRoles(Map<String, Object?> claims, List<String> paths) {
  final result = <String>{};
  void collect(Object? node, List<String> path) {
    if (path.isEmpty) {
      switch (node) {
        case final String value:
          result.addAll(value.split(RegExp(r'\s+')).where((s) => s.isNotEmpty));
        case final List<Object?> values:
          result.addAll(values.whereType<String>());
      }
      return;
    }
    if (node is! Map<String, Object?>) return;
    final key = path.first;
    if (key == '*') {
      for (final value in node.values) {
        collect(value, path.sublist(1));
      }
    } else {
      collect(node[key], path.sublist(1));
    }
  }

  for (final path in paths) {
    collect(claims, path.split('.'));
  }
  return result;
}

/// The expiry (`exp`) of a token, if present.
DateTime? jwtExpiry(Map<String, Object?> claims) => switch (claims['exp']) {
  final num seconds => DateTime.fromMillisecondsSinceEpoch((seconds * 1000).round(), isUtc: true),
  _ => null,
};
