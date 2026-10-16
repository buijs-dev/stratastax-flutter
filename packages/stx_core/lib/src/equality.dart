/// Structural equality for the collection types generated models hold (lists and JSON maps).
/// Used by generated `==` / `hashCode`.
abstract final class DeepEquality {
  static bool equals(Object? a, Object? b) {
    if (identical(a, b)) return true;
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!equals(a[i], b[i])) return false;
      }
      return true;
    }
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final key in a.keys) {
        if (!b.containsKey(key) || !equals(a[key], b[key])) return false;
      }
      return true;
    }
    return a == b;
  }

  static int hash(Object? value) => switch (value) {
    List() => Object.hashAll(value.map(hash)),
    // Order-independent, like map equality.
    Map() => Object.hashAllUnordered(value.entries.map((e) => Object.hash(e.key, hash(e.value)))),
    _ => value.hashCode,
  };
}
