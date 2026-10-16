import 'platform.dart';

SecureStore defaultStore() => MemoryStore();

AuthBrowser defaultBrowser() => const _UnsupportedBrowser();

final class _UnsupportedBrowser implements AuthBrowser {
  const _UnsupportedBrowser();

  @override
  Uri get location => Uri();

  @override
  void redirect(Uri uri) =>
      throw UnsupportedError('Redirect login needs a browser; pass an AuthBrowser for this platform');

  @override
  void replace(Uri uri) {}
}
