import 'package:flutter/foundation.dart';
import 'package:stx_core/stx_core.dart';
import 'package:stx_i18n/stx_i18n.dart';

/// The state of one form field: its value and its validation error. One notifier per field, so
/// typing in a field only rebuilds that field.
class StxField<T> extends ChangeNotifier {
  StxField(this._value);

  T _value;
  FieldError? _error;

  T get value => _value;

  set value(T next) {
    if (next == _value) return;
    _value = next;
    notifyListeners();
  }

  FieldError? get error => _error;

  /// Back to [initial] without an error (after a successful submit).
  void reset(T initial) {
    _value = initial;
    _error = null;
    notifyListeners();
  }

  /// Sets the error from a validator; returns whether the field is valid.
  bool check(FieldError? error) {
    if (error != _error) {
      _error = error;
      notifyListeners();
    }
    return error == null;
  }
}

/// The message of a validation error (framework keys `stx.validation.*`).
Msg fieldErrorMsg(FieldError error) => switch (error) {
  RequiredError() => StxKeys.validationRequired,
  MinLengthError(:final min) => StxKeys.validationMinLength(min),
  MaxLengthError(:final max) => StxKeys.validationMaxLength(max),
  MinItemsError(:final min) => StxKeys.validationMinItems(min),
  MaxItemsError(:final max) => StxKeys.validationMaxItems(max),
  MinimumError(:final min) => StxKeys.validationMinimum(min),
  MaximumError(:final max) => StxKeys.validationMaximum(max),
  PatternError() => StxKeys.validationPattern,
  FormatError() => StxKeys.validationFormat,
  // Codes of the stratastax backend (validation_error.yaml); unknown codes stay visible.
  ServerError(code: 'OUT_OF_RANGE') => StxKeys.validationCodesOutOfRange,
  ServerError(code: 'NOT_FOUND') => StxKeys.validationCodesNotFound,
  ServerError(code: 'VALUE_TOO_LONG') => StxKeys.validationCodesTooLong,
  ServerError(code: 'INVALID_FORMAT') => StxKeys.validationFormat,
  ServerError(:final code) => StxKeys.validationServer(code),
};

/// The message for a failed call (framework keys `stx.problem.*`).
Msg problemMsg(Problem problem) => switch (problem.type) {
  ProblemType.network => StxKeys.problemNetwork,
  ProblemType.validation => StxKeys.problemValidation,
  ProblemType.authorization || ProblemType.authentication => StxKeys.problemAuthorization,
  ProblemType.notFound => StxKeys.problemNotFound,
  ProblemType.conflict || ProblemType.preconditionFailed => StxKeys.problemConflict,
  _ => StxKeys.problemGeneric,
};
