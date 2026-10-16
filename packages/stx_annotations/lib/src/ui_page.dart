import 'package:meta/meta_meta.dart';

/// Where a route shows up in the generated navigation.
enum UiNav {
  /// Main navigation (rail on wide screens, bottom bar on narrow screens).
  primary,

  /// Secondary navigation (overflow / settings area).
  secondary,

  /// Not listed; only reachable by navigation from code.
  none,
}

/// What a generated form does after a successful submit.
enum UiNavigate {
  /// Pop back to the previous route.
  back,

  /// Stay on the page and reset the form.
  reset,

  /// Stay on the page and keep the submitted values.
  stay,
}

/// Generates a form for the annotated model: controller, page, contract mapper and merged
/// validation.
///
/// [submit] is a generated contract endpoint constant, e.g. `MatchesApiV1.createMatch`. It
/// provides the body schema (validation), the response type, the required scopes and the
/// endpoint used to send the form.
@Target({TargetKind.classType})
final class UiForm {
  const UiForm({required this.submit, this.onSuccess = UiNavigate.back});

  /// A const `Endpoint` from the generated contract code. Typed as [Object] because this package
  /// has no dependency on stx_core; the compiler resolves and checks the actual type.
  final Object submit;

  final UiNavigate onSuccess;
}

/// Registers the annotated model's page in the generated router.
///
/// Path parameters (`/matches/{id}`) must match a field or a [UiRouteParam]. The page title is
/// the i18n key `<model>.title`.
@Target({TargetKind.classType})
final class UiRoute {
  const UiRoute(this.path, {this.nav = UiNav.none});

  final String path;
  final UiNav nav;
}

/// Binds a path parameter to a field with a different name.
@Target({TargetKind.field})
final class UiRouteParam {
  const UiRouteParam(this.name);

  final String name;
}

/// Adds scopes on top of the scopes derived from the endpoints a page uses. Scopes can only be
/// added, never removed.
@Target({TargetKind.classType})
final class UiRequires {
  const UiRequires(this.scopes);

  /// Values of the generated `Scope` enum.
  final List<Enum> scopes;
}
