/// The stx compiler: reads stx.yaml, the contracts, tokens, translations and annotated sources of a
/// consumer app and generates its code (docs/ARCHITECTURE.md §3).
library;

export 'src/config.dart';
export 'src/contract/contract_frontend.dart';
export 'src/contract/contract_renderer.dart';
export 'src/contract/ir.dart';
export 'src/contract/scope_registry.dart';
export 'src/diagnostics.dart';
export 'src/i18n/i18n_frontend.dart';
export 'src/i18n/i18n_renderer.dart';
export 'src/i18n/i18n_sync.dart';
export 'src/naming.dart';
export 'src/output.dart';
export 'src/package_locator.dart';
export 'src/pipeline.dart';
export 'src/remote_source.dart';
export 'src/scan.dart';
export 'src/watch.dart';
export 'src/style/style_frontend.dart';
export 'src/style/style_ir.dart';
export 'src/style/style_renderer.dart';
export 'src/ui/annotation_frontend.dart';
export 'src/ui/app_plan.dart';
export 'src/ui/app_renderer.dart';
export 'src/ui/ui_ir.dart';
export 'src/yaml_writer.dart';
