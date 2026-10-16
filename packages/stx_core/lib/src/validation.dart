import 'package:meta/meta.dart';

import 'ids.dart';
import 'local_date.dart';
import 'problem.dart';

/// String formats from the contract that the UI can check.
enum UiFormat {
  uuid,
  date,
  dateTime,
  email,
  uri,

  /// Only a rendering hint (obscured input); never fails.
  password;

  /// Whether [value] is valid for this format. Used for string-typed fields; typed fields
  /// (`Uuid`, `DateTime`, …) are valid by construction.
  bool matches(String value) => switch (this) {
    uuid => Uuid.tryParse(value) != null,
    date => LocalDate.tryParse(value) != null,
    dateTime => DateTime.tryParse(value) != null,
    email => Email.tryParse(value) != null,
    uri => Uri.tryParse(value)?.hasScheme ?? false,
    password => true,
  };
}

/// Validation rules of one field, generated from the contract and merged with `@UiFieldValidate`.
///
/// Generated forms validate with straight-line code; [check] is the reference implementation that
/// widgets use for live feedback and that generator tests compare against.
@immutable
final class UiFieldValidation {
  const UiFieldValidation({
    this.required = false,
    this.minLength,
    this.maxLength,
    this.minItems,
    this.maxItems,
    this.minimum,
    this.maximum,
    this.exclusiveMinimum = false,
    this.exclusiveMaximum = false,
    this.pattern,
    this.format,
  });

  static const none = UiFieldValidation();

  final bool required;
  final int? minLength;
  final int? maxLength;
  final int? minItems;
  final int? maxItems;
  final num? minimum;
  final num? maximum;
  final bool exclusiveMinimum;
  final bool exclusiveMaximum;

  /// ECMA-262 regular expression from the contract, matched against the whole value.
  final String? pattern;
  final UiFormat? format;

  /// The first violated rule for [value], or null when valid.
  ///
  /// Empty strings and empty lists count as missing for [required].
  FieldError? check(Object? value) {
    if (value == null || (value is String && value.isEmpty) || (value is List && value.isEmpty)) {
      if (required) return const FieldError.required();
      if (value == null) return null;
    }
    return switch (value) {
      String() => _checkString(value),
      List() => _checkList(value),
      num() => _checkNum(value),
      _ => null,
    };
  }

  FieldError? _checkString(String value) {
    if (value.isEmpty) return null; // optional and empty
    final length = value.runes.length;
    if (minLength case final min? when length < min) return FieldError.minLength(min);
    if (maxLength case final max? when length > max) return FieldError.maxLength(max);
    if (format case final f? when !f.matches(value)) return FieldError.format(f);
    if (pattern case final p? when !RegExp(p, unicode: true).hasMatch(value)) return FieldError.pattern(p);
    return null;
  }

  FieldError? _checkList(List<Object?> value) {
    if (minItems case final min? when value.length < min) return FieldError.minItems(min);
    if (maxItems case final max? when value.length > max) return FieldError.maxItems(max);
    return null;
  }

  FieldError? _checkNum(num value) {
    if (minimum case final min? when exclusiveMinimum ? value <= min : value < min) {
      return FieldError.minimum(min, exclusive: exclusiveMinimum);
    }
    if (maximum case final max? when exclusiveMaximum ? value >= max : value > max) {
      return FieldError.maximum(max, exclusive: exclusiveMaximum);
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is UiFieldValidation &&
      other.required == required &&
      other.minLength == minLength &&
      other.maxLength == maxLength &&
      other.minItems == minItems &&
      other.maxItems == maxItems &&
      other.minimum == minimum &&
      other.maximum == maximum &&
      other.exclusiveMinimum == exclusiveMinimum &&
      other.exclusiveMaximum == exclusiveMaximum &&
      other.pattern == pattern &&
      other.format == format;

  @override
  int get hashCode => Object.hash(
    required,
    minLength,
    maxLength,
    minItems,
    maxItems,
    minimum,
    maximum,
    exclusiveMinimum,
    exclusiveMaximum,
    pattern,
    format,
  );
}

/// Why a field value is invalid. Rendered via the i18n keys `stx.validation.*`; never carries
/// display text itself.
@immutable
sealed class FieldError {
  const FieldError();

  const factory FieldError.required() = RequiredError;
  const factory FieldError.minLength(int min) = MinLengthError;
  const factory FieldError.maxLength(int max) = MaxLengthError;
  const factory FieldError.minItems(int min) = MinItemsError;
  const factory FieldError.maxItems(int max) = MaxItemsError;
  const factory FieldError.minimum(num min, {bool exclusive}) = MinimumError;
  const factory FieldError.maximum(num max, {bool exclusive}) = MaximumError;
  const factory FieldError.pattern(String pattern) = PatternError;
  const factory FieldError.format(UiFormat format) = FormatError;

  /// A violation reported by the server for a rule the client could not check (e.g. uniqueness).
  const factory FieldError.server(String code) = ServerError;

  /// Maps a server-side [ProblemViolation] onto a field error. Known codes become a typed error
  /// where the server gives enough information; everything else becomes [ServerError] so the UI
  /// can look up `problem.validation.<code>`.
  factory FieldError.fromViolation(ProblemViolation violation) => switch (violation.code) {
    'REQUIRED' => const FieldError.required(),
    _ => FieldError.server(violation.code),
  };
}

final class RequiredError extends FieldError {
  const RequiredError();

  @override
  bool operator ==(Object other) => other is RequiredError;

  @override
  int get hashCode => (RequiredError).hashCode;

  @override
  String toString() => 'FieldError.required()';
}

final class MinLengthError extends FieldError {
  const MinLengthError(this.min);

  final int min;

  @override
  bool operator ==(Object other) => other is MinLengthError && other.min == min;

  @override
  int get hashCode => Object.hash(MinLengthError, min);

  @override
  String toString() => 'FieldError.minLength($min)';
}

final class MaxLengthError extends FieldError {
  const MaxLengthError(this.max);

  final int max;

  @override
  bool operator ==(Object other) => other is MaxLengthError && other.max == max;

  @override
  int get hashCode => Object.hash(MaxLengthError, max);

  @override
  String toString() => 'FieldError.maxLength($max)';
}

final class MinItemsError extends FieldError {
  const MinItemsError(this.min);

  final int min;

  @override
  bool operator ==(Object other) => other is MinItemsError && other.min == min;

  @override
  int get hashCode => Object.hash(MinItemsError, min);

  @override
  String toString() => 'FieldError.minItems($min)';
}

final class MaxItemsError extends FieldError {
  const MaxItemsError(this.max);

  final int max;

  @override
  bool operator ==(Object other) => other is MaxItemsError && other.max == max;

  @override
  int get hashCode => Object.hash(MaxItemsError, max);

  @override
  String toString() => 'FieldError.maxItems($max)';
}

final class MinimumError extends FieldError {
  const MinimumError(this.min, {this.exclusive = false});

  final num min;
  final bool exclusive;

  @override
  bool operator ==(Object other) => other is MinimumError && other.min == min && other.exclusive == exclusive;

  @override
  int get hashCode => Object.hash(MinimumError, min, exclusive);

  @override
  String toString() => 'FieldError.minimum($min, exclusive: $exclusive)';
}

final class MaximumError extends FieldError {
  const MaximumError(this.max, {this.exclusive = false});

  final num max;
  final bool exclusive;

  @override
  bool operator ==(Object other) => other is MaximumError && other.max == max && other.exclusive == exclusive;

  @override
  int get hashCode => Object.hash(MaximumError, max, exclusive);

  @override
  String toString() => 'FieldError.maximum($max, exclusive: $exclusive)';
}

final class PatternError extends FieldError {
  const PatternError(this.pattern);

  final String pattern;

  @override
  bool operator ==(Object other) => other is PatternError && other.pattern == pattern;

  @override
  int get hashCode => Object.hash(PatternError, pattern);

  @override
  String toString() => 'FieldError.pattern($pattern)';
}

final class FormatError extends FieldError {
  const FormatError(this.format);

  final UiFormat format;

  @override
  bool operator ==(Object other) => other is FormatError && other.format == format;

  @override
  int get hashCode => Object.hash(FormatError, format);

  @override
  String toString() => 'FieldError.format(${format.name})';
}

final class ServerError extends FieldError {
  const ServerError(this.code);

  final String code;

  @override
  bool operator ==(Object other) => other is ServerError && other.code == code;

  @override
  int get hashCode => Object.hash(ServerError, code);

  @override
  String toString() => 'FieldError.server($code)';
}
