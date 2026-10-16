import 'package:web/web.dart' as web;

import 'platform.dart';

SecureStore defaultStore() => const _SessionStorage();

AuthBrowser defaultBrowser() => const _WindowBrowser();

final class _SessionStorage implements SecureStore {
  const _SessionStorage();

  @override
  String? read(String key) => web.window.sessionStorage.getItem(key);

  @override
  void write(String key, String? value) =>
      value == null ? web.window.sessionStorage.removeItem(key) : web.window.sessionStorage.setItem(key, value);
}

final class _WindowBrowser implements AuthBrowser {
  const _WindowBrowser();

  @override
  Uri get location => Uri.parse(web.window.location.href);

  @override
  void redirect(Uri uri) => web.window.location.assign(uri.toString());

  @override
  void replace(Uri uri) => web.window.history.replaceState(null, '', uri.toString());
}
