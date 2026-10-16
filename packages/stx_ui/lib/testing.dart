/// Test support: wraps a widget in everything stx widgets need (directionality, media query,
/// theme, messages) without a full app.
library;

import 'package:flutter/widgets.dart';
import 'package:stx_i18n/stx_i18n.dart';
import 'package:stx_style/stx_style.dart';

/// Messages from a map of key name → text; unknown keys render as their name.
final class MapMessages extends StxMessages {
  MapMessages(Map<String, String> texts, {Locale locale = const Locale('en'), this.formats = const IsoFormats()})
    : super(locale, texts);

  @override
  final StxLocaleFormats formats;

  @override
  String format(String key, List<Object?> args) {
    var text = plain[key] ?? key;
    for (final arg in args) {
      text = text.replaceFirst(RegExp(r'\{[^}]+\}'), '$arg');
    }
    return text;
  }
}

/// Hosts [child] for widget tests and previews, with what `WidgetsApp` normally provides:
/// default shortcuts and actions (Enter/Space activate), a focus scope, tap regions and an overlay.
class StxTestHost extends StatelessWidget {
  const StxTestHost({
    super.key,
    required this.tokens,
    required this.child,
    this.messages,
    this.size = const Size(800, 600),
  });

  final StxTokens tokens;
  final StxMessages? messages;
  final Size size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final messages = this.messages ?? MapMessages(const {});
    return MediaQuery(
      data: MediaQueryData(size: size),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Shortcuts(
          shortcuts: WidgetsApp.defaultShortcuts,
          child: Actions(
            actions: WidgetsApp.defaultActions,
            child: FocusScope(
              autofocus: true,
              child: StxLocaleScope(
                supported: [messages.locale],
                load: (_) => messages,
                initial: messages.locale,
                child: StxTheme(
                  light: tokens,
                  mode: StxThemeMode.light,
                  child: TapRegionSurface(child: _HostOverlay(child: child)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HostOverlay extends StatefulWidget {
  const _HostOverlay({required this.child});

  final Widget child;

  @override
  State<_HostOverlay> createState() => _HostOverlayState();
}

class _HostOverlayState extends State<_HostOverlay> {
  late final OverlayEntry _entry = OverlayEntry(
    builder: (_) => Align(alignment: Alignment.topLeft, child: widget.child),
  );

  @override
  void didUpdateWidget(_HostOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _entry.markNeedsBuild();
  }

  @override
  void dispose() {
    _entry
      ..remove()
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Overlay(initialEntries: [_entry]);
}
