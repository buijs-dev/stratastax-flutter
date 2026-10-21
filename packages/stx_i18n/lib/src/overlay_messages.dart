import 'package:stx_icu/stx_icu.dart';

import 'formats.dart';
import 'icu_interpreter.dart';
import 'messages.dart';
import 'translation_source.dart';

/// The compiled messages of a locale with translations from a backend laid over them.
///
/// Only keys of [base] are overridden, and only with a text that uses the placeholders of the key
/// ([StxMessages.arguments]) with compatible types; anything else is left out and reported to
/// `onIssue`, so a broken translation never breaks the app. A plain text is used as is, a text with
/// placeholders is interpreted ([formatIcu]); every other key keeps the compiled text.
final class OverlayMessages extends StxMessages {
  OverlayMessages._(this.base, Map<String, String> plain, this._nodes, this.overridden) : super(base.locale, plain);

  factory OverlayMessages(
    StxMessages base,
    Map<String, String> overrides, {
    void Function(TranslationIssue issue)? onIssue,
  }) {
    final plain = {...base.plain};
    final nodes = <String, List<IcuNode>>{};
    final overridden = <String>{};
    void issue(TranslationIssueKind kind, String key, String message) =>
        onIssue?.call(TranslationIssue(kind, base.locale, message, key: key));

    for (final MapEntry(:key, value: text) in overrides.entries) {
      if (!base.plain.containsKey(key)) {
        issue(TranslationIssueKind.unknownKey, key, 'not a key of the app');
        continue;
      }
      final List<IcuNode> parsed;
      final Map<String, ArgType> used;
      try {
        parsed = parseIcu(text);
        used = icuArguments(parsed);
      } on IcuException catch (e) {
        issue(TranslationIssueKind.syntax, key, e.toString());
        continue;
      }
      final declared = {for (final (name, type) in base.arguments[key] ?? const <(String, ArgType)>[]) name: type};
      final wrong = [
        for (final MapEntry(key: name, value: type) in used.entries)
          if (!(declared[name]?.compatibleWith(type) ?? false)) name,
      ];
      if (wrong.isNotEmpty) {
        final expected = declared.isEmpty ? 'none' : declared.keys.map((n) => '{$n}').join(', ');
        issue(
          TranslationIssueKind.arguments,
          key,
          'unknown or mistyped ${wrong.map((n) => '{$n}').join(', ')} (expected: $expected)',
        );
        continue;
      }
      overridden.add(key);
      if (declared.isEmpty) {
        plain[key] = parsed.whereType<IcuText>().map((t) => t.text).join();
      } else {
        plain[key] = text;
        nodes[key] = parsed;
      }
    }
    return OverlayMessages._(base, plain, nodes, overridden);
  }

  /// The compiled messages underneath.
  final StxMessages base;

  /// Parsed overrides of messages with placeholders.
  final Map<String, List<IcuNode>> _nodes;

  /// The keys whose text comes from the backend.
  final Set<String> overridden;

  @override
  Map<String, List<(String, ArgType)>> get arguments => base.arguments;

  @override
  StxLocaleFormats get formats => base.formats;

  @override
  String format(String key, List<Object?> args) {
    final nodes = _nodes[key];
    if (nodes == null) return base.format(key, args);
    final names = base.arguments[key]!;
    return formatIcu(nodes, {for (var i = 0; i < names.length && i < args.length; i++) names[i].$1: args[i]}, formats);
  }
}
