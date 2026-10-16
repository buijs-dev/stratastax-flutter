import 'package:flutter/widgets.dart';
import 'package:stx_core/stx_core.dart';
import 'package:stx_i18n/stx_i18n.dart';
import 'package:stx_security/stx_security.dart';
import 'package:stx_style/stx_style.dart';

import '../primitives/button.dart';
import '../primitives/layout.dart';

/// Who is using the app: whether they are signed in and which scopes their token grants.
/// [SessionAccess] for a real login; [StaticAccess] for tests and previews.
abstract interface class StxAccess implements Listenable {
  bool get authenticated;

  Set<StxScope> get scopes;

  /// Sign-in / sign-out actions; null when the app has no login (tests, previews).
  StxAuth? get auth;
}

/// A way to sign in: the identity provider's own page, or a social provider directly.
@immutable
final class StxLoginOption {
  const StxLoginOption({required this.label, this.idpHint});

  final Msg label;

  /// Keycloak `kc_idp_hint`, e.g. `google`; null for the provider's login page.
  final String? idpHint;
}

abstract interface class StxAuth {
  List<StxLoginOption> get options;

  /// Shown in the shell (user data).
  String? get userName;

  /// Why the last login did not complete, if it failed.
  Msg? get failure;

  void login(StxLoginOption option);

  void logout();
}

/// [StxAccess] and [StxAuth] backed by an OIDC [Session].
final class SessionAccess extends ChangeNotifier implements StxAccess, StxAuth {
  SessionAccess(this.session, {required this.options}) {
    session.addListener(notifyListeners);
  }

  final Session session;

  @override
  final List<StxLoginOption> options;

  @override
  bool get authenticated => session.authenticated;

  @override
  Set<StxScope> get scopes => session.scopes;

  @override
  StxAuth get auth => this;

  @override
  String? get userName => session.profile?.displayName;

  @override
  Msg? get failure => switch (session.failure) {
    null => null,
    LoginFailure.denied => StxKeys.sessionCancelled,
    LoginFailure.stateMismatch || LoginFailure.exchange => StxKeys.sessionFailed,
  };

  @override
  void login(StxLoginOption option) => session.login(idpHint: option.idpHint);

  @override
  void logout() => session.logout();

  @override
  void dispose() {
    session.removeListener(notifyListeners);
    super.dispose();
  }
}

/// Fixed access, e.g. for tests or a development build.
final class StaticAccess extends ChangeNotifier implements StxAccess {
  StaticAccess({this.authenticated = false, this.scopes = const {}});

  StaticAccess.anonymous() : this();

  @override
  bool authenticated;

  @override
  Set<StxScope> scopes;

  @override
  StxAuth? get auth => null;

  void update({bool? authenticated, Set<StxScope>? scopes}) {
    this.authenticated = authenticated ?? this.authenticated;
    this.scopes = scopes ?? this.scopes;
    notifyListeners();
  }
}

/// Provides [StxAccess]; dependents rebuild when it notifies (sign-in, sign-out, token refresh).
class StxAccessScope extends InheritedNotifier<StxAccess> {
  const StxAccessScope({super.key, required StxAccess access, required super.child}) : super(notifier: access);

  static StxAccess of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<StxAccessScope>();
    assert(scope != null, 'No StxAccessScope above this widget; StxApp adds one.');
    return scope!.notifier!;
  }

  static bool allows(BuildContext context, ScopeRequirement requires) {
    final access = of(context);
    return access.authenticated && requires.satisfiedBy(access.scopes);
  }
}

/// Shows [child] only when the user satisfies [requires]; the generated page puts its form inside,
/// so a form the user may not submit is never built.
class StxGuard extends StatelessWidget {
  const StxGuard({super.key, required this.requires, required this.child, this.denied, this.signedOut});

  final ScopeRequirement requires;
  final Widget child;

  /// Shown when signed in without the scopes; defaults to [StxForbidden].
  final Widget? denied;

  /// Shown when signed out; defaults to [StxSignIn].
  final Widget? signedOut;

  @override
  Widget build(BuildContext context) {
    final access = StxAccessScope.of(context);
    if (!access.authenticated) return signedOut ?? const StxSignIn();
    if (!requires.satisfiedBy(access.scopes)) return denied ?? const StxForbidden();
    return child;
  }
}

/// The default "no access" view.
class StxForbidden extends StatelessWidget {
  const StxForbidden({super.key, this.message = StxKeys.accessForbidden});

  final Msg message;

  @override
  Widget build(BuildContext context) => Center(
    child: StxBox(
      padding: const StxInsets.all(SpaceToken.xl),
      child: StxText(message, style: TextToken.header3, color: ColorToken.muted, align: TextAlign.center),
    ),
  );
}

/// The sign-in view: one button per [StxLoginOption] of the app's [StxAuth], and the reason when
/// the last attempt failed.
class StxSignIn extends StatelessWidget {
  const StxSignIn({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = StxAccessScope.of(context).auth;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: StxBox(
          padding: const StxInsets.all(SpaceToken.xl),
          child: StxColumn(
            gap: SpaceToken.md,
            mainAxisSize: MainAxisSize.min,
            children: [
              const StxText(StxKeys.sessionTitle, style: TextToken.header2, align: TextAlign.center),
              if (auth?.failure case final failure?)
                StxText(failure, color: ColorToken.danger, align: TextAlign.center),
              if (auth == null)
                const StxText(StxKeys.accessSignIn, color: ColorToken.muted, align: TextAlign.center)
              else
                for (final (i, option) in auth.options.indexed)
                  StxButton(
                    option.label,
                    expand: true,
                    variant: i == 0 ? ButtonVariant.primary : ButtonVariant.secondary,
                    onPressed: () => auth.login(option),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
