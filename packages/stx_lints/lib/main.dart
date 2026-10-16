import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';

import 'src/rules.dart';

/// The analyzer plugin entry point (`plugins: stx_lints:` in analysis_options.yaml).
final plugin = StxLintsPlugin();

class StxLintsPlugin extends Plugin {
  @override
  String get name => 'stx_lints';

  @override
  void register(PluginRegistry registry) {
    for (final rule in allRules) {
      registry.registerWarningRule(rule);
    }
  }
}
