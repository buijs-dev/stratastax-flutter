import 'package:stx_core/stx_core.dart';
import 'package:test/test.dart';

void main() {
  group('UiFieldValidation.check', () {
    test('required treats null, empty string and empty list as missing', () {
      const v = UiFieldValidation(required: true);
      expect(v.check(null), const FieldError.required());
      expect(v.check(''), const FieldError.required());
      expect(v.check(const <int>[]), const FieldError.required());
      expect(v.check('x'), isNull);
    });

    test('optional empty values are valid even with other rules', () {
      const v = UiFieldValidation(minLength: 3, format: UiFormat.email);
      expect(v.check(null), isNull);
      expect(v.check(''), isNull);
    });

    test('string length counts code points', () {
      const v = UiFieldValidation(maxLength: 2);
      expect(v.check('🎲🎲'), isNull);
      expect(v.check('🎲🎲🎲'), const FieldError.maxLength(2));
      expect(const UiFieldValidation(minLength: 2).check('a'), const FieldError.minLength(2));
    });

    test('items (the MatchCreate.players rule)', () {
      const v = UiFieldValidation(required: true, minItems: 2, maxItems: 8);
      expect(v.check([1]), const FieldError.minItems(2));
      expect(v.check(List.filled(9, 0)), const FieldError.maxItems(8));
      expect(v.check([1, 2]), isNull);
    });

    test('numeric bounds, inclusive and exclusive', () {
      expect(const UiFieldValidation(minimum: 1).check(1), isNull);
      expect(
        const UiFieldValidation(minimum: 1, exclusiveMinimum: true).check(1),
        const FieldError.minimum(1, exclusive: true),
      );
      expect(const UiFieldValidation(maximum: 10).check(11), const FieldError.maximum(10));
      expect(
        const UiFieldValidation(maximum: 10, exclusiveMaximum: true).check(10),
        const FieldError.maximum(10, exclusive: true),
      );
    });

    test('pattern matches the whole value only when anchored by the contract', () {
      const v = UiFieldValidation(pattern: r'^[A-Z]{3}$');
      expect(v.check('ABC'), isNull);
      expect(v.check('ABCD'), const FieldError.pattern(r'^[A-Z]{3}$'));
    });

    test('format', () {
      const v = UiFieldValidation(format: UiFormat.uuid);
      expect(v.check('6f1c2b3a-0d4e-4f5a-9b8c-7d6e5f4a3b2c'), isNull);
      expect(v.check('nope'), const FieldError.format(UiFormat.uuid));
    });
  });

  group('UiFormat.matches', () {
    test('per format', () {
      expect(UiFormat.date.matches('2026-10-11'), isTrue);
      expect(UiFormat.date.matches('11-10-2026'), isFalse);
      expect(UiFormat.dateTime.matches('2026-10-11T10:00:00Z'), isTrue);
      expect(UiFormat.email.matches('a@b.nl'), isTrue);
      expect(UiFormat.email.matches('a@b'), isFalse);
      expect(UiFormat.uri.matches('https://stratastax.io'), isTrue);
      expect(UiFormat.uri.matches('stratastax'), isFalse);
      expect(UiFormat.password.matches(''), isTrue);
    });
  });

  group('FieldError', () {
    test('value equality, so unchanged errors do not notify listeners', () {
      expect(const FieldError.minItems(2), const FieldError.minItems(2));
      expect(const FieldError.minItems(2) == const FieldError.minItems(3), isFalse);
      expect(const FieldError.minItems(2) == const FieldError.maxItems(2), isFalse);
    });

    test('fromViolation maps known codes and keeps unknown ones', () {
      expect(
        FieldError.fromViolation(const ProblemViolation(field: 'name', code: 'REQUIRED', message: '')),
        const FieldError.required(),
      );
      expect(
        FieldError.fromViolation(const ProblemViolation(field: 'name', code: 'NOT_UNIQUE', message: '')),
        const FieldError.server('NOT_UNIQUE'),
      );
    });
  });
}
