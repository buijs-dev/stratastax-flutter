import '../naming.dart';
import 'ir.dart';

/// All scopes of all contracts of an app: one generated `Scope` enum covers every contract.
final class ScopeRegistry {
  factory ScopeRegistry(Iterable<ContractIR> contracts) {
    final usage = <String, Set<String>>{};
    for (final contract in contracts) {
      for (final operation in contract.operations) {
        if (operation.security case ScopedSecurity(:final scopes)) {
          for (final scope in scopes) {
            usage.putIfAbsent(scope, () => {}).add('${contract.name}.${operation.operationId}');
          }
        }
      }
    }
    final claims = usage.keys.toList()..sort();
    return ScopeRegistry._(claims, {for (final c in claims) c: usage[c]!.toList()..sort()});
  }

  ScopeRegistry._(this.claims, this.usage) {
    final short = {for (final c in claims) c: Naming.member(c.contains(':') ? c.substring(c.lastIndexOf(':') + 1) : c)};
    final counts = <String, int>{};
    for (final name in short.values) {
      counts[name] = (counts[name] ?? 0) + 1;
    }
    for (final claim in claims) {
      _names[claim] = counts[short[claim]]! > 1 ? Naming.member(claim) : short[claim]!;
    }
  }

  /// Sorted.
  final List<String> claims;

  /// Claim → operations that accept it, for documentation.
  final Map<String, List<String>> usage;

  final Map<String, String> _names = {};

  /// The `Scope` enum value name, e.g. `matchRead` for `stx-engine:match-read`.
  String dartName(String claim) => _names[claim]!;

  /// A set literal of `Scope` values, e.g. `{Scope.matchCreate, Scope.matchAdmin}`.
  String literal(Iterable<String> scopes) => '{${[for (final s in scopes) 'Scope.${dartName(s)}'].join(', ')}}';
}
