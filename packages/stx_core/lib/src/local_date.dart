import 'package:meta/meta.dart';

/// A calendar date without time or zone, the Dart type for OpenAPI `format: date`.
@immutable
final class LocalDate implements Comparable<LocalDate> {
  /// Throws [ArgumentError] when the date does not exist (e.g. 2026-02-30).
  factory LocalDate(int year, int month, int day) {
    final utc = DateTime.utc(year, month, day);
    if (utc.year != year || utc.month != month || utc.day != day) {
      throw ArgumentError('Invalid date: $year-$month-$day');
    }
    return LocalDate._(year, month, day);
  }

  const LocalDate._(this.year, this.month, this.day);

  factory LocalDate.fromDateTime(DateTime dateTime) => LocalDate._(dateTime.year, dateTime.month, dateTime.day);

  static final _pattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

  /// Parses `YYYY-MM-DD` (RFC 3339 full-date).
  static LocalDate? tryParse(String source) {
    final match = _pattern.firstMatch(source);
    if (match == null) return null;
    try {
      return LocalDate(int.parse(match[1]!), int.parse(match[2]!), int.parse(match[3]!));
    } on ArgumentError {
      return null;
    }
  }

  static LocalDate parse(String source) =>
      tryParse(source)
          ?? (throw FormatException('Invalid date, expected YYYY-MM-DD', source));

  final int year;
  final int month;
  final int day;

  /// Midnight UTC of this date.
  DateTime toDateTimeUtc() => DateTime.utc(year, month, day);

  @override
  int compareTo(LocalDate other) => switch (year.compareTo(other.year)) {
    0 => switch (month.compareTo(other.month)) {
      0 => day.compareTo(other.day),
      final c => c,
    },
    final c => c,
  };

  @override
  bool operator ==(Object other) =>
      other is LocalDate && other.year == year && other.month == month && other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  /// `YYYY-MM-DD`, the wire format.
  @override
  String toString() =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
}
