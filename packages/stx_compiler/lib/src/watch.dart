import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';

import 'config.dart';

/// Whether a change to [path] can change the output of `stx build`: stx.yaml, the contracts, the
/// tokens, the translations and app code under `lib/` (not the generated output itself).
bool affectsBuild(StxConfig config, String path) {
  final file = p.normalize(p.absolute(path));
  if (p.isWithin(config.output, file) || file == config.output) return false;
  if (p.basename(file) == StxConfig.fileName && p.dirname(file) == config.projectDir) return true;
  if (config.contracts.any((c) => c.spec == file) || file == config.tokens) return true;
  if (p.isWithin(config.i18n.dir, file)) return file.endsWith('.yaml');
  return p.isWithin(p.join(config.projectDir, 'lib'), file) && file.endsWith('.dart');
}

/// Runs [build] once, then again after every change that [affectsBuild] (debounced; changes during
/// a build trigger one more). stx.yaml is re-read on every build, so [config] only decides what is
/// watched until the next change to stx.yaml. Completes when [stop] completes.
Future<void> watchProject(
  StxConfig Function() config,
  Future<void> Function(List<String> changed) build, {
  Future<void>? stop,
  Duration debounce = const Duration(milliseconds: 200),
}) async {
  var current = config();
  final pending = <String>{};
  var running = false;
  Timer? timer;

  Future<void> run() async {
    if (running) return;
    running = true;
    while (true) {
      final changed = [...pending]..sort();
      pending.clear();
      await build(changed);
      current = config();
      if (pending.isEmpty) break;
    }
    running = false;
  }

  await build(const []);
  final watcher = DirectoryWatcher(current.projectDir);
  final subscription = watcher.events.listen((event) {
    if (!affectsBuild(current, event.path)) return;
    pending.add(p.relative(event.path, from: current.projectDir));
    timer?.cancel();
    timer = Timer(debounce, () => unawaited(run()));
  });
  await (stop ?? Completer<void>().future);
  timer?.cancel();
  await subscription.cancel();
}
