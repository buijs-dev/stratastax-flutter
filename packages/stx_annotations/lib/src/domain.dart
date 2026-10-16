import 'package:meta/meta_meta.dart';

/// Marks a domain model, like `@DomainEntity` in stratastax-entity.
///
/// Fields map to the linked contract schema by name; see [ContractProperty] to deviate.
@Target({TargetKind.classType})
final class DomainEntity {
  const DomainEntity();
}

/// Declares how a domain type maps to a contract type, like `@BuildTypeConverter` in
/// stratastax-entity.
///
/// ```dart
/// @BuildTypeConverter(Uuid)
/// extension type const GameId(Uuid value) {}
/// ```
///
/// The annotated type must wrap exactly one value of type [target].
@Target({TargetKind.classType, TargetKind.extensionType})
final class BuildTypeConverter {
  const BuildTypeConverter(this.target);

  /// The contract-side type, e.g. `Uuid`, `String` or `int`.
  final Type target;
}

/// Declares that values of the annotated type are generated client-side, like
/// `@BuildTypeGenerator` in stratastax-entity (e.g. ids for optimistic creates).
@Target({TargetKind.classType, TargetKind.extensionType})
final class BuildTypeGenerator {
  const BuildTypeGenerator(this.source, {this.key = ''});

  /// A class with a const constructor and a `T generate()` method.
  final Type source;

  /// Optional discriminator when one generator serves several types.
  final String key;
}

/// Maps a field to a differently named contract property, like `@RestProperty` in
/// stratastax-entity.
@Target({TargetKind.field})
final class ContractProperty {
  const ContractProperty(this.name);

  /// The property name exactly as it appears in the OpenAPI schema.
  final String name;
}
