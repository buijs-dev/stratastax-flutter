import 'platform_stub.dart' if (dart.library.js_interop) 'platform_web.dart' as platform;

/// Small key-value storage for the refresh token and a pending login (PKCE verifier, `state`).
abstract interface class SecureStore {
  String? read(String key);

  void write(String key, String? value);
}

/// Keeps values in memory only: nothing survives a reload.
final class MemoryStore implements SecureStore {
  final _values = <String, String>{};

  @override
  String? read(String key) => _values[key];

  @override
  void write(String key, String? value) => value == null ? _values.remove(key) : _values[key] = value;
}

/// The browser location for the redirect-based login.
abstract interface class AuthBrowser {
  Uri get location;

  /// Leaves the app (to the identity provider).
  void redirect(Uri uri);

  /// Replaces the current location without a navigation (removes `code` and `state`).
  void replace(Uri uri);
}

/// `sessionStorage` on the web (survives reloads, not other tabs); memory elsewhere.
SecureStore defaultStore() => platform.defaultStore();

/// `window.location` on the web; unsupported elsewhere until a native login flow exists.
AuthBrowser defaultBrowser() => platform.defaultBrowser();
