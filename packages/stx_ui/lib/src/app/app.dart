import 'package:flutter/widgets.dart';
import 'package:stx_i18n/stx_i18n.dart';
import 'package:stx_style/stx_style.dart';

import '../primitives/button.dart';
import '../primitives/layout.dart';
import 'access.dart';
import 'router.dart';

/// Provides the generated `AppServices` (clients, session, data sources) to the tree.
class StxServices<T extends Object> extends InheritedWidget {
  const StxServices({super.key, required this.value, required super.child});

  final T value;

  static T of<T extends Object>(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<StxServices<T>>();
    assert(scope != null, 'No StxServices<$T> above this widget.');
    return scope!.value;
  }

  @override
  bool updateShouldNotify(StxServices<T> oldWidget) => !identical(oldWidget.value, value);
}

/// The app root, on `WidgetsApp.router`: no MaterialApp, no CupertinoApp. Generated apps use it
/// from `lib/gen/app/app.g.dart`.
class StxApp extends StatelessWidget {
  const StxApp({
    super.key,
    required this.light,
    required this.dark,
    required this.locales,
    required this.messages,
    required this.router,
    required this.access,
    this.mode = StxThemeMode.system,
    this.localeStore,
    this.initialLocale,
    this.title = '',
  });

  final StxTokens light;
  final StxTokens dark;
  final StxThemeMode mode;
  final List<Locale> locales;
  final MessagesLoader messages;
  final LocaleStore? localeStore;
  final Locale? initialLocale;
  final RouterConfig<Object> router;
  final StxAccess access;

  /// Window / tab title (data, set by the app).
  final String title;

  @override
  Widget build(BuildContext context) => StxLocaleScope(
    supported: locales,
    load: messages,
    store: localeStore,
    initial: initialLocale,
    child: Builder(
      builder: (context) => WidgetsApp.router(
        routerConfig: router,
        title: title,
        color: light.color(ColorToken.primary),
        locale: StxLocaleScope.localeOf(context),
        supportedLocales: locales,
        localizationsDelegates: const [DefaultWidgetsLocalizations.delegate],
        builder: (context, child) => StxTheme(
          light: light,
          dark: dark,
          mode: mode,
          child: StxAccessScope(
            access: access,
            child: Builder(
              builder: (context) => DefaultTextStyle(
                style: context.textStyle(TextToken.body),
                child: ColoredBox(color: context.tokens.color(ColorToken.background), child: child),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Navigation around the pages: a side rail from the `md` breakpoint, a bottom bar below it.
/// Items the user has no scopes for are not shown.
class StxAppShell<R extends Object> extends StatelessWidget {
  const StxAppShell({super.key, required this.navigator, required this.items, required this.child, this.title});

  final StxNavigator<R> navigator;
  final List<NavItem<R>> items;
  final Msg? title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final access = StxAccessScope.of(context);
    final visible = [
      for (final item in items)
        if (access.authenticated && item.requires.satisfiedBy(access.scopes)) item,
    ];
    final current = navigator.current;
    final wide = context.breakpoint.index >= Breakpoint.md.index;
    final buttons = [
      for (final item in visible)
        StxButton(
          item.title,
          alignment: wide ? AlignmentDirectional.centerStart : Alignment.center,
          variant: item.route == current ? ButtonVariant.secondary : ButtonVariant.ghost,
          onPressed: () => navigator.go(item.route),
        ),
    ];
    if (visible.isEmpty) return child;
    final bar = StxBox(
      padding: const StxInsets.all(SpaceToken.sm),
      background: ColorToken.surface,
      border: ColorToken.border,
      child: wide
          ? StxColumn(
              gap: SpaceToken.xs,
              children: [
                if (title != null)
                  StxBox(
                    padding: const StxInsets.symmetric(x: SpaceToken.sm, y: SpaceToken.md),
                    child: StxText(title!, style: TextToken.header3),
                  ),
                ...buttons,
                const Spacer(),
                if (access.auth case final auth? when access.authenticated) ...[
                  if (auth.userName case final name?)
                    StxBox(
                      padding: const StxInsets.symmetric(x: SpaceToken.sm),
                      child: StxText(Msg.data(name), style: TextToken.caption, color: ColorToken.muted),
                    ),
                  StxButton(
                    StxKeys.sessionSignOut,
                    variant: ButtonVariant.ghost,
                    alignment: AlignmentDirectional.centerStart,
                    onPressed: auth.logout,
                  ),
                ],
              ],
            )
          : SafeArea(
              top: false,
              child: StxRow(
                main: MainAxisAlignment.spaceEvenly,
                children: [for (final b in buttons) Flexible(child: b)],
              ),
            ),
    );
    return wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: 240, child: bar),
              Expanded(child: child),
            ],
          )
        : Column(
            children: [
              Expanded(child: child),
              bar,
            ],
          );
  }
}
