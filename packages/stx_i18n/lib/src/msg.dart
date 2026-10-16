import 'package:meta/meta.dart';

/// Text to show. Widgets accept a [Msg], never a `String`: either a translation key
/// ([MsgKey]), a key with arguments ([MsgArgs]) or explicit user data ([Msg.data]).
@immutable
sealed class Msg {
  const Msg();

  /// Text that is data, not UI copy (a player name, a game title). Never a string literal: the
  /// `no_string_in_ui` lint flags `Msg.data('…')`.
  const factory Msg.data(String text) = MsgData;
}

/// A translation key: its dotted name, e.g. `matchCreateCommand.gameId.label`. Constants are
/// generated per app (`MsgMatchCreateCommand.gameIdLabel`) and by stx_i18n for framework texts
/// ([StxKeys], namespace `stx`). The name is the identity, so app and framework keys never collide
/// and an app can override a framework text by translating the same key.
final class MsgKey extends Msg {
  const MsgKey(this.name);

  final String name;

  @override
  bool operator ==(Object other) => other is MsgKey && other.name == name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'MsgKey($name)';
}

/// A translation key with placeholder values, in the order the placeholders are declared.
final class MsgArgs extends Msg {
  const MsgArgs(this.key, this.args);

  final MsgKey key;
  final List<Object?> args;

  @override
  bool operator ==(Object other) {
    if (other is! MsgArgs || other.key != key || other.args.length != args.length) return false;
    for (var i = 0; i < args.length; i++) {
      if (other.args[i] != args[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(key, Object.hashAll(args));

  @override
  String toString() => 'MsgArgs($key, $args)';
}

final class MsgData extends Msg {
  const MsgData(this.text);

  final String text;

  @override
  bool operator ==(Object other) => other is MsgData && other.text == text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => 'Msg.data($text)';
}
