/// The outcome of an operation that can fail with a typed error [E].
///
/// Exhaustive by construction:
///
/// ```dart
/// switch (result) {
///   case Ok(:final value): …
///   case Err(:final error): …
/// }
/// ```
sealed class Result<T, E> {
  const Result();

  bool get isOk => this is Ok<T, E>;

  bool get isErr => this is Err<T, E>;

  T? get valueOrNull => switch (this) {
    Ok(:final value) => value,
    Err() => null,
  };

  E? get errorOrNull => switch (this) {
    Ok() => null,
    Err(:final error) => error,
  };

  Result<U, E> map<U>(U Function(T value) transform) => switch (this) {
    Ok(:final value) => Ok(transform(value)),
    Err(:final error) => Err(error),
  };

  Result<T, F> mapErr<F>(F Function(E error) transform) => switch (this) {
    Ok(:final value) => Ok(value),
    Err(:final error) => Err(transform(error)),
  };

  R fold<R>(R Function(T value) ok, R Function(E error) err) => switch (this) {
    Ok(:final value) => ok(value),
    Err(:final error) => err(error),
  };
}

final class Ok<T, E> extends Result<T, E> {
  const Ok(this.value);

  final T value;

  @override
  bool operator ==(Object other) => other is Ok<T, E> && other.value == value;

  @override
  int get hashCode => Object.hash(Ok, value);

  @override
  String toString() => 'Ok($value)';
}

final class Err<T, E> extends Result<T, E> {
  const Err(this.error);

  final E error;

  @override
  bool operator ==(Object other) => other is Err<T, E> && other.error == error;

  @override
  int get hashCode => Object.hash(Err, error);

  @override
  String toString() => 'Err($error)';
}
