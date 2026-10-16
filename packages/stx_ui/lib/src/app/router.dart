import 'package:flutter/widgets.dart';
import 'package:stx_core/stx_core.dart';
import 'package:stx_i18n/stx_i18n.dart';
import 'package:stx_style/stx_style.dart';

import '../primitives/layout.dart';

/// A navigation entry, generated from `@UiRoute(nav: ...)`.
@immutable
final class NavItem<R> {
  const NavItem({required this.route, required this.title, required this.requires, this.secondary = false});

  final R route;
  final Msg title;
  final ScopeRequirement requires;
  final bool secondary;
}

/// The generated routing functions; [R] is the generated sealed `AppRoute`.
final class StxRoutes<R extends Object> {
  const StxRoutes({
    required this.parse,
    required this.segments,
    required this.build,
    required this.requires,
    required this.home,
    this.nav = const [],
  });

  /// Path segments → route; null for unknown paths. Generated as a `switch` over segment patterns.
  final R? Function(List<String> segments) parse;
  final List<String> Function(R route) segments;
  final Widget Function(R route) build;
  final ScopeRequirement Function(R route) requires;
  final R home;
  final List<NavItem<R>> nav;
}

/// Navigation API for pages: `StxRouter.of<AppRoute>(context).go(const MatchCreateRoute())`.
abstract interface class StxNavigator<R extends Object> {
  R get current;

  /// Replace the stack with [route].
  void go(R route);

  /// Push [route] on top of the current page.
  void push(R route);

  /// Pop the current page; at the root, go to the home route.
  void back();

  /// Whether [back] returns to a previous page.
  bool get canBack;
}

abstract final class StxRouter {
  static StxNavigator<R> of<R extends Object>(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_NavigatorScope<R>>();
    assert(scope != null, 'No StxRouter<$R> above this widget.');
    return scope!.navigator;
  }

  /// A [RouterConfig] for `WidgetsApp.router`. [shell] wraps the page navigator (e.g. [StxAppShell]).
  static RouterConfig<Object> config<R extends Object>(
    StxRoutes<R> routes, {
    Widget Function(BuildContext context, StxNavigator<R> navigator, Widget pages)? shell,
    String? initialLocation,
  }) => RouterConfig<Object>(
    routeInformationProvider: PlatformRouteInformationProvider(
      initialRouteInformation: RouteInformation(
        uri: Uri.parse(initialLocation ?? WidgetsBinding.instance.platformDispatcher.defaultRouteName),
      ),
    ),
    routeInformationParser: _Parser(),
    routerDelegate: _Delegate<R>(routes, shell),
    backButtonDispatcher: RootBackButtonDispatcher(),
  );
}

class _Parser extends RouteInformationParser<Object> {
  @override
  Future<Object> parseRouteInformation(RouteInformation routeInformation) async => routeInformation.uri;

  @override
  RouteInformation? restoreRouteInformation(Object configuration) =>
      RouteInformation(uri: configuration is Uri ? configuration : Uri.parse('/'));
}

/// A parsed location that matched no route.
final class _NotFound {
  const _NotFound(this.uri);

  final Uri uri;
}

class _Delegate<R extends Object> extends RouterDelegate<Object>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<Object>
    implements StxNavigator<R> {
  _Delegate(this.routes, this.shell) : _stack = [routes.home];

  final StxRoutes<R> routes;
  final Widget Function(BuildContext, StxNavigator<R>, Widget)? shell;
  List<Object> _stack;

  @override
  final navigatorKey = GlobalKey<NavigatorState>();

  @override
  R get current => _stack.lastWhere((e) => e is R, orElse: () => routes.home) as R;

  @override
  void go(R route) {
    _stack = [route];
    notifyListeners();
  }

  @override
  void push(R route) {
    _stack = [..._stack, route];
    notifyListeners();
  }

  @override
  bool get canBack => _stack.length > 1;

  @override
  void back() {
    _stack = _stack.length > 1 ? _stack.sublist(0, _stack.length - 1) : [routes.home];
    notifyListeners();
  }

  @override
  Object? get currentConfiguration {
    final top = _stack.last;
    return top is _NotFound ? top.uri : Uri(pathSegments: routes.segments(top as R));
  }

  @override
  Future<void> setNewRoutePath(Object configuration) async {
    final uri = configuration as Uri;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    final route = segments.isEmpty ? routes.home : routes.parse(segments);
    _stack = [route ?? _NotFound(uri)];
    notifyListeners();
  }

  @override
  Widget build(BuildContext context) {
    final pages = Navigator(
      key: navigatorKey,
      pages: [
        for (final (index, entry) in _stack.indexed)
          _StxPage(
            key: ValueKey('$index:${entry is R ? routes.segments(entry).join('/') : 'not-found'}'),
            child: entry is R ? routes.build(entry) : const _NotFoundView(),
          ),
      ],
      onDidRemovePage: (page) {
        if (_stack.length > 1) {
          _stack = _stack.sublist(0, _stack.length - 1);
          notifyListeners();
        }
      },
    );
    return _NavigatorScope<R>(
      navigator: this,
      current: _stack.last,
      child: shell == null ? pages : Builder(builder: (context) => shell!(context, this, pages)),
    );
  }
}

class _NavigatorScope<R extends Object> extends InheritedWidget {
  const _NavigatorScope({required this.navigator, required this.current, required super.child});

  final StxNavigator<R> navigator;
  final Object current;

  @override
  bool updateShouldNotify(_NavigatorScope<R> oldWidget) => !identical(oldWidget.current, current);
}

class _StxPage extends Page<void> {
  const _StxPage({required super.key, required this.child});

  final Widget child;

  @override
  Route<void> createRoute(BuildContext context) => PageRouteBuilder<void>(
    settings: this,
    transitionDuration: const Duration(milliseconds: 160),
    reverseTransitionDuration: const Duration(milliseconds: 120),
    pageBuilder: (context, animation, secondary) => _PageBackground(child: child),
    transitionsBuilder: (context, animation, secondary, child) => FadeTransition(opacity: animation, child: child),
  );
}

class _PageBackground extends StatelessWidget {
  const _PageBackground({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ColoredBox(color: context.tokens.color(ColorToken.background), child: child);
}

class _NotFoundView extends StatelessWidget {
  const _NotFoundView();

  @override
  Widget build(BuildContext context) => const Center(
    child: StxText(StxKeys.routeNotFound, style: TextToken.header3, color: ColorToken.muted),
  );
}
