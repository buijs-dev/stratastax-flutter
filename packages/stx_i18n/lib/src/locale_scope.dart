import 'dart:async';

import 'package:flutter/widgets.dart';

import 'formats.dart';
import 'messages.dart';
import 'msg.dart';

/// Remembers the user's language choice; e.g. backed by shared preferences or local storage.
abstract interface class LocaleStore {
  Locale? read();

  void write(Locale locale);
}

/// Loads the messages of a locale; generated as `loadMessages` (non-base locales are deferred).
typedef MessagesLoader = FutureOr<StxMessages> Function(Locale locale);

/// Provides the active messages to the tree. Rebuilds dependents only when the locale changes.
class StxLocaleScope extends StatefulWidget {
  const StxLocaleScope({
    super.key,
    required this.supported,
    required this.load,
    required this.child,
    this.store,
    this.initial,
  });

  final List<Locale> supported;
  final MessagesLoader load;
  final LocaleStore? store;

  /// Overrides the stored and device locale (tests, previews).
  final Locale? initial;
  final Widget child;

  static StxMessages messagesOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_LocaleInherited>()?.messages ?? _fallback;

  static Locale localeOf(BuildContext context) => messagesOf(context).locale;

  /// Switches the language of the app and remembers it.
  static Future<void> setLocale(BuildContext context, Locale locale) =>
      context.findAncestorStateOfType<_StxLocaleScopeState>()!._select(locale, remember: true);

  static final _fallback = FallbackMessages();

  @override
  State<StxLocaleScope> createState() => _StxLocaleScopeState();
}

class _StxLocaleScopeState extends State<StxLocaleScope> {
  StxMessages? _messages;
  var _initializing = false;

  @override
  void initState() {
    super.initState();
    final device = WidgetsBinding.instance.platformDispatcher.locale;
    _initializing = true;
    _select(widget.initial ?? widget.store?.read() ?? device, remember: false);
    _initializing = false;
  }

  Locale _match(Locale requested) {
    for (final locale in widget.supported) {
      if (locale == requested) return locale;
    }
    for (final locale in widget.supported) {
      if (locale.languageCode == requested.languageCode) return locale;
    }
    return widget.supported.first;
  }

  Future<void> _select(Locale requested, {required bool remember}) async {
    final locale = _match(requested);
    if (remember) widget.store?.write(locale);
    final loaded = widget.load(locale);
    if (loaded is StxMessages) {
      _apply(loaded);
    } else {
      _apply(await loaded);
    }
  }

  void _apply(StxMessages messages) {
    if (!mounted) return;
    if (_initializing) {
      _messages = messages; // synchronous load during initState: build has not run yet
    } else {
      setState(() => _messages = messages); // asynchronous (deferred) load or a locale switch
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = _messages;
    if (messages == null) return const SizedBox.shrink();
    return _LocaleInherited(messages: messages, child: widget.child);
  }
}

class _LocaleInherited extends InheritedWidget {
  const _LocaleInherited({required this.messages, required super.child});

  final StxMessages messages;

  @override
  bool updateShouldNotify(_LocaleInherited oldWidget) => !identical(oldWidget.messages, messages);
}

extension MsgResolve on BuildContext {
  /// The text of [msg] in the active locale.
  String msg(Msg msg) => StxLocaleScope.messagesOf(this).resolve(msg);

  /// Dates, times, numbers and plural rules of the active locale.
  StxLocaleFormats get formats => StxLocaleScope.messagesOf(this).formats;
}
