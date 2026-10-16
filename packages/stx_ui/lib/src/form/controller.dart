import 'package:flutter/foundation.dart';
import 'package:stx_core/stx_core.dart';
import 'package:stx_http/stx_http.dart';

import 'field.dart';

sealed class StxFormStatus {
  const StxFormStatus();
}

final class FormIdle extends StxFormStatus {
  const FormIdle();
}

final class FormSubmitting extends StxFormStatus {
  const FormSubmitting();
}

final class FormFailed extends StxFormStatus {
  const FormFailed(this.problem);

  final Problem problem;
}

final class FormSucceeded<R> extends StxFormStatus {
  const FormSucceeded(this.response);

  final R response;
}

/// The base of every generated form controller (`MatchCreateCommandForm`).
///
/// [C] is the domain command, [B] the contract body and [R] the response. The generated subclass
/// declares the fields and implements validation (straight-line code), [toCommand] and
/// [toContract].
abstract class StxFormController<C, B, R> extends ChangeNotifier {
  StxFormController() {
    for (final field in fields) {
      field.addListener(_revalidate);
    }
  }

  /// All fields, in form order.
  List<StxField<Object?>> get fields;

  /// Fields by contract property name, to show server-side violations on the right field.
  Map<String, StxField<Object?>> get contractFields;

  Endpoint<NoParams, B, R> get endpoint;

  /// Validates every field; returns whether all are valid.
  bool validate();

  /// Only valid after [validate] returned true.
  C toCommand();

  B toContract(C command);

  /// Puts every field back to its initial value; generated.
  void resetFields();

  /// Empties the form for the next entry; the status (e.g. [FormSucceeded]) is kept, so a
  /// confirmation can still be shown.
  void reset() {
    _attempted = false;
    _resetting = true;
    resetFields();
    _resetting = false;
    notifyListeners();
  }

  var _resetting = false;

  StxFormStatus _status = const FormIdle();
  bool _attempted = false;

  StxFormStatus get status => _status;

  bool get submitting => _status is FormSubmitting;

  void _set(StxFormStatus status) {
    _status = status;
    notifyListeners();
  }

  // After the first submit attempt, errors update while the user types; a confirmation or
  // problem banner disappears on the next edit.
  void _revalidate() {
    if (submitting || _resetting) return;
    if (_status is FormSucceeded || _status is FormFailed) _set(const FormIdle());
    if (_attempted) validate();
  }

  /// Validates, then sends the body. Returns null when validation fails locally.
  Future<Result<R, Problem>?> submit(StxClient client) async {
    if (submitting) return null;
    _attempted = true;
    if (!validate()) {
      _set(const FormIdle());
      return null;
    }
    _set(const FormSubmitting());
    final result = await client.submit(endpoint, toContract(toCommand()));
    switch (result) {
      case Ok(:final value):
        _set(FormSucceeded(value));
      case Err(:final error):
        for (final violation in error.violations) {
          final name = violation.field.split(RegExp(r'[.\[]')).first;
          contractFields[name]?.check(FieldError.fromViolation(violation));
        }
        _set(FormFailed(error));
    }
    return result;
  }

  @override
  void dispose() {
    for (final field in fields) {
      field
        ..removeListener(_revalidate)
        ..dispose();
    }
    super.dispose();
  }
}
