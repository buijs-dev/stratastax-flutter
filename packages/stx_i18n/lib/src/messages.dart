import 'package:flutter/widgets.dart';
import 'package:stx_icu/stx_icu.dart';

import 'formats.dart';
import 'msg.dart';

/// The compiled messages of one locale. Generated per app (`MessagesNl`): [plain] holds every
/// message by key name, [format] is a generated `switch` for messages with placeholders. Nothing is
/// parsed at runtime. A key without a text (an app built against an older stx_i18n) shows its name.
abstract base class StxMessages {
  const StxMessages(this.locale, this.plain);

  final Locale locale;

  /// By [MsgKey.name]. Messages with placeholders hold their source text, for debugging.
  final Map<String, String> plain;

  /// Formats a message with placeholders; generated.
  String format(String key, List<Object?> args);

  /// The placeholders of every message that has them, in the order of [MsgArgs.args], with their
  /// type; generated. Lets a translation from a backend ([OverlayMessages]) use them by name.
  Map<String, List<(String, ArgType)>> get arguments => const {};

  /// Plural rules, dates and numbers of [locale]; generated from CLDR.
  StxLocaleFormats get formats => const IsoFormats();

  String resolve(Msg msg) => switch (msg) {
    MsgKey(:final name) => plain[name] ?? name,
    MsgArgs(:final key, :final args) => format(key.name, args),
    MsgData(:final text) => text,
  };
}

/// Messages that only know their keys; shown before the real messages load, and used in tests.
final class FallbackMessages extends StxMessages {
  FallbackMessages([Locale locale = const Locale('en')]) : super(locale, const {});

  @override
  String format(String key, List<Object?> args) => '$key$args';
}
