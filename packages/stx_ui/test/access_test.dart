import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stx_core/stx_core.dart';
import 'package:stx_i18n/stx_i18n.dart';
import 'package:stx_ui/stx_ui.dart';
import 'package:stx_ui/testing.dart';

import 'support.dart';

final class _Auth extends ChangeNotifier implements StxAccess, StxAuth {
  @override
  bool authenticated = false;

  @override
  Set<StxScope> scopes = const {};

  @override
  Msg? failure;

  final logins = <String?>[];

  @override
  StxAuth get auth => this;

  @override
  List<StxLoginOption> get options => [
    const StxLoginOption(label: StxKeys.accessSignIn),
    StxLoginOption(label: StxKeys.sessionSignInWith('Google'), idpHint: 'google'),
  ];

  @override
  String? get userName => 'Gillian';

  @override
  void login(StxLoginOption option) => logins.add(option.idpHint);

  @override
  void logout() {}
}

Future<void> _pump(WidgetTester tester, StxAccess access) async {
  await tester.pumpWidget(
    StxTestHost(
      tokens: testTokens,
      messages: MapMessages({
        StxKeys.sessionTitle.name: 'Sign in to continue',
        StxKeys.accessSignIn.name: 'Sign in',
        'stx.session.signInWith': 'Sign in with {provider}',
        StxKeys.sessionFailed.name: 'Signing in did not work',
        StxKeys.accessForbidden.name: 'No access',
      }),
      child: StxAccessScope(
        access: access,
        child: const SizedBox(
          width: 600,
          height: 400,
          child: StxGuard(
            requires: ScopeRequirement([
              {_Scope.needed},
            ]),
            child: Text('secret'),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('signed out: one button per login option', (tester) async {
    final auth = _Auth();
    await _pump(tester, auth);
    expect(find.text('secret'), findsNothing);
    expect(find.text('Sign in to continue'), findsOneWidget);
    await tester.tap(find.text('Sign in with Google'));
    await tester.tap(find.text('Sign in'));
    expect(auth.logins, ['google', null]);
  });

  testWidgets('a failed login is explained', (tester) async {
    final auth = _Auth()..failure = StxKeys.sessionFailed;
    await _pump(tester, auth);
    expect(find.text('Signing in did not work'), findsOneWidget);
  });

  testWidgets('signing in shows the page; missing scopes show no access', (tester) async {
    final auth = _Auth();
    await _pump(tester, auth);
    auth
      ..authenticated = true
      ..scopes = {_Scope.other}
      ..notifyListeners();
    await tester.pump();
    expect(find.text('No access'), findsOneWidget);
    auth
      ..scopes = {_Scope.needed}
      ..notifyListeners();
    await tester.pump();
    expect(find.text('secret'), findsOneWidget);
  });

  testWidgets('without auth (tests, previews) the sign-in view only explains', (tester) async {
    await _pump(tester, StaticAccess.anonymous());
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.byType(StxButton), findsNothing);
  });
}

enum _Scope implements StxScope {
  needed,
  other;

  @override
  String get claim => 'test:$name';
}
