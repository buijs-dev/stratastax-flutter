import 'package:flutter/foundation.dart';

import 'gen/app/app.g.dart';

/// Signs in with OIDC (stx.yaml `security`); the API base URL and issuer come from
/// `--dart-define=STX_API_BASE_URL=…` / `STX_OIDC_ISSUER=…`.
void main() => runStxApp(AppConfig.fromEnvironment(log: kDebugMode ? debugPrint : null));
