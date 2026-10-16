import 'package:meta/meta.dart';

/// A property of a PATCH body that is optional *and* nullable in the contract, so "leave unchanged"
/// (absent) and "clear" (null) differ. Mirrors `PatchField` in stratastax-entity.
///
/// ```dart
/// UpdateMatchV1(playedAt: Patch.value(now), playsetId: const Patch.value(null)) // set, clear
/// UpdateMatchV1() // everything Patch.unset(): nothing changes
/// ```
@immutable
sealed class Patch<T> {
  const Patch();

  const factory Patch.unset() = PatchUnset<T>;
  const factory Patch.value(T? value) = PatchValue<T>;

  bool get isProvided => this is PatchValue<T>;

  /// The new value when provided, otherwise [current].
  T? orKeep(T? current) => switch (this) {
    PatchUnset() => current,
    PatchValue(:final value) => value,
  };
}

final class PatchUnset<T> extends Patch<T> {
  const PatchUnset();

  @override
  bool operator ==(Object other) => other is PatchUnset;

  @override
  int get hashCode => (PatchUnset).hashCode;

  @override
  String toString() => 'Patch.unset()';
}

final class PatchValue<T> extends Patch<T> {
  const PatchValue(this.value);

  final T? value;

  @override
  bool operator ==(Object other) => other is PatchValue && other.value == value;

  @override
  int get hashCode => Object.hash(PatchValue, value);

  @override
  String toString() => 'Patch.value($value)';
}
