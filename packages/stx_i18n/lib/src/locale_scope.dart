import 'dart:async';

import 'package:flutter/widgets.dart';

import 'formats.dart';
import 'messages.dart';
import 'msg.dart';
import 'overlay_messages.dart';
import 'translation_source.dart';

/// Remembers the user's language choice; e.g. backed by shared preferences or local storage.
abstract interface class LocaleStore {
  Locale? read();

  void write(Locale locale);
}

/// Loads the messages of a locale; generated as `loadMessages` (non-base locales are deferred).
typedef MessagesLoader = FutureOr<StxMessages> Function(Locale locale);

/// Provides the active messages to the tree. Rebuilds dependents only when the locale changes, or
/// when translations from [translations] are laid over the compiled ones.
///
/// With [translations], a locale shows its compiled texts (or the [cache]d bundle) at once and
/// never waits for the backend: the bundle is fetched in the background and swapped in when it
/// arrives, unless the locale changed meanwhile. A failed fetch keeps the texts that are shown.
class StxLocaleScope extends StatefulWidget {
  const StxLocaleScope({
    super.key,
    required this.supported,
    required this.load,
    required this.child,
    this.store,
    this.initial,
    this.translations,
    this.cache,
    this.onIssue,
  });

  final List<Locale> supported;
  final MessagesLoader load;
  final LocaleStore? store;

  /// Published translations from a backend; null: only the compiled texts.
  final TranslationSource? translations;

  /// The last fetched bundle per locale; null: nothing is kept across starts.
  final TranslationCache? cache;

  /// A translation that is left out, or a fetch that failed (logging, monitoring).
  final void Function(TranslationIssue issue)? onIssue;

  /// Overrides the stored and device locale (tests, previews).
  final Locale? initial;
  final Widget child;

  static StxMessages messagesOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_LocaleInherited>()?.messages ?? _fallback;

  static Locale localeOf(BuildContext context) => messagesOf(context).locale;

  /// Switches the language of the app and remembers it.
  static Future<void> setLocale(BuildContext context, Locale locale) =>
      context.findAncestorStateOfType<_StxLocaleScopeState>()!._select(locale, remember: true);

  /// Fetches the translations of the active locale again (e.g. when the app resumes); completes
  /// when they are applied, or when the backend has nothing new.
  static Future<void> refresh(BuildContext context) =>
      context.findAncestorStateOfType<_StxLocaleScopeState>()!._refresh();

  static final _fallback = FallbackMessages();

  @override
  State<StxLocaleScope> createState() => _StxLocaleScopeState();
}

class _StxLocaleScopeState extends State<StxLocaleScope> {
  StxMessages? _messages;
  var _initializing = false;

  /// The selected locale and its compiled messages, under [_messages] when a bundle is laid over.
  Locale? _locale;
  StxMessages? _base;
  TranslationBundle? _bundle;

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
    _locale = locale;
    final loaded = widget.load(locale);
    final base = loaded is StxMessages ? loaded : await loaded;
    if (_locale != locale) return; // switched again while loading
    _base = base;
    _bundle = widget.translations == null ? null : widget.cache?.read(locale);
    _apply(_bundle == null ? base : OverlayMessages(base, _bundle!.messages));
    if (widget.translations != null) unawaited(_fetch(locale)); // never wait for the backend
  }

  Future<void> _refresh() async {
    if (_locale case final locale? when _base != null) await _fetch(locale);
  }

  Future<void> _fetch(Locale locale) async {
    final TranslationBundle? bundle;
    try {
      bundle = await widget.translations!.fetch(locale, etag: _bundle?.etag);
    } on Object catch (e) {
      widget.onIssue?.call(TranslationIssue(TranslationIssueKind.fetch, locale, '$e'));
      return;
    }
    if (bundle == null || !mounted || _locale != locale) return;
    widget.cache?.write(bundle);
    _bundle = bundle;
    _apply(OverlayMessages(_base!, bundle.messages, onIssue: widget.onIssue));
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
