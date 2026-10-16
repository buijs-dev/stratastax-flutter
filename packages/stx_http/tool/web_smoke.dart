// Compile check for the web transport: `dart compile js|wasm tool/web_smoke.dart` (run in CI).
import 'package:stx_http/stx_http.dart';

void main() {
  final client = StxClient(baseUrl: Uri.parse('https://stratastax.dev/rest'));
  print(client.baseUrl);
}
