/// A scope (role) from the contract, e.g. `stx-engine:match-create`. The compiler generates one
/// `enum Scope implements StxScope` over all contracts, so scopes are typed and sets of them const:
///
/// ```dart
/// security: Secured.scopes({Scope.matchCreate}),
/// ```
abstract interface class StxScope {
  /// The claim as it appears in the contract and the access token.
  String get claim;
}

/// What a page needs: every group must be satisfied, and a group is satisfied by any one of its
/// scopes. One group per operation the page uses, because the scopes of one operation are
/// alternatives (`@RolesAllowed` semantics).
///
/// ```dart
/// static const requires = ScopeRequirement([
///   {Scope.matchCreate}, // createMatch
///   {Scope.gameRead},    // getGameSuggestions
/// ]);
/// ```
extension type const ScopeRequirement(List<Set<StxScope>> groups) {
  static const none = ScopeRequirement([]);

  bool satisfiedBy(Set<StxScope> granted) => groups.every((group) => group.isEmpty || group.any(granted.contains));
}
