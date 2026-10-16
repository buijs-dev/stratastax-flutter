import 'package:stx_core/stx_core.dart';
import 'package:test/test.dart';

void main() {
  group('Uuid', () {
    test('parse normalizes to lower case', () {
      expect(Uuid.parse('6F1C2B3A-0D4E-4F5A-9B8C-7D6E5F4A3B2C').value, '6f1c2b3a-0d4e-4f5a-9b8c-7d6e5f4a3b2c');
    });

    test('rejects malformed input', () {
      expect(Uuid.tryParse('6f1c2b3a0d4e4f5a9b8c7d6e5f4a3b2c'), isNull);
      expect(() => Uuid.parse('x'), throwsFormatException);
    });
  });

  group('Email', () {
    test('trims and validates shallowly', () {
      expect(Email.tryParse(' a@b.nl ')?.value, 'a@b.nl');
      expect(Email.tryParse('a b@c.nl'), isNull);
    });
  });

  group('LocalDate', () {
    test('round-trips the wire format', () {
      expect(LocalDate.parse('2026-01-05').toString(), '2026-01-05');
    });

    test('rejects dates that do not exist', () {
      expect(LocalDate.tryParse('2026-02-29'), isNull);
      expect(LocalDate.tryParse('2028-02-29'), LocalDate(2028, 2, 29));
      expect(() => LocalDate(2026, 13, 1), throwsArgumentError);
    });

    test('orders chronologically', () {
      final dates = [LocalDate(2026, 3, 1), LocalDate(2025, 12, 31), LocalDate(2026, 2, 28)]..sort();
      expect(dates.map((d) => '$d'), ['2025-12-31', '2026-02-28', '2026-03-01']);
    });
  });
}
