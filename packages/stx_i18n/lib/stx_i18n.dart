/// Compiled i18n runtime: message keys, the locale scope, framework texts, and translations from a
/// backend laid over the compiled ones. Depends on flutter/widgets and stx_icu only. The message
/// tables themselves are generated per app by stx_compiler.
library;

export 'package:stx_icu/stx_icu.dart' show ArgType;

export 'src/formats.dart';
export 'src/icu_interpreter.dart';
export 'src/keys.dart';
export 'src/locale_scope.dart';
export 'src/messages.dart';
export 'src/msg.dart';
export 'src/overlay_messages.dart';
export 'src/translation_source.dart';
