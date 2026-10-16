/// CLDR plural categories.
enum Plural { zero, one, two, few, many, other }

enum DateStyle { short, medium, long, full }

enum TimeStyle { short, medium }

/// Locale formatting: plural rules, dates, times and numbers. Generated per locale by stx_compiler
/// from bundled CLDR data (`_FormatsNl` in `messages_nl.g.dart`); date patterns are compiled to
/// string interpolation, so nothing is parsed at runtime.
abstract class StxLocaleFormats {
  const StxLocaleFormats({
    required this.decimalSeparator,
    required this.groupSeparator,
    this.minimumGroupingDigits = 1,
    this.percentSuffix = '%',
  });

  final String decimalSeparator;
  final String groupSeparator;

  /// Digits before the first group separator appears (`es`: 2, so 1234 stays `1234`).
  final int minimumGroupingDigits;

  /// Appended to a percentage, with the locale's spacing (`de`: ` %`).
  final String percentSuffix;

  Plural plural(num n);

  String date(DateTime value, [DateStyle style = DateStyle.medium]);

  String time(DateTime value, [TimeStyle style = TimeStyle.short]);

  String dateTime(DateTime value, {DateStyle date = DateStyle.medium, TimeStyle time = TimeStyle.short});

  /// Month names, January first.
  List<String> get months;

  List<String> get monthsShort;

  /// Weekday names, Monday first (index = `DateTime.weekday - 1`).
  List<String> get weekdays;

  List<String> get weekdaysShort;

  /// `DateTime.monday` … `DateTime.sunday`.
  int get firstDayOfWeek;

  /// A date as typed in a field: the locale's numeric order with a four-digit year
  /// (`nl`: `31-12-2026`, `en`: `12/31/2026`).
  String inputDate(DateTime value);

  /// Parses [inputDate]'s format; null when the text is not a valid date.
  DateTime? parseInputDate(String text);

  /// `HH:mm`, 24-hour, for every locale (unambiguous to type).
  String inputTime(DateTime value) => '${_two(value.hour)}:${_two(value.minute)}';

  DateTime? parseInputTime(String text, DateTime date) {
    final m = RegExp(r'^\s*(\d{1,2})[:.](\d{2})\s*$').firstMatch(text);
    if (m == null) return null;
    final hour = int.parse(m[1]!), minute = int.parse(m[2]!);
    if (hour > 23 || minute > 59) return null;
    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  String inputDateTime(DateTime value) => '${inputDate(value)} ${inputTime(value)}';

  DateTime? parseInputDateTime(String text) {
    final parts = text.trim().split(RegExp(r'\s+'));
    if (parts.length != 2) return null;
    final date = parseInputDate(parts[0]);
    return date == null ? null : parseInputTime(parts[1], date);
  }

  /// A decimal number with grouping and at most [maxFractionDigits] fraction digits.
  String number(num value, {int maxFractionDigits = 3}) {
    final negative = value < 0;
    final fixed = value.abs().toStringAsFixed(maxFractionDigits);
    var (whole, fraction) = fixed.contains('.') ? (fixed.split('.')[0], fixed.split('.')[1]) : (fixed, '');
    fraction = fraction.replaceFirst(RegExp(r'0+$'), '');
    if (whole.length >= 4 + minimumGroupingDigits - 1) {
      final b = StringBuffer();
      for (var i = 0; i < whole.length; i++) {
        if (i > 0 && (whole.length - i) % 3 == 0) b.write(groupSeparator);
        b.write(whole[i]);
      }
      whole = b.toString();
    }
    return '${negative ? '-' : ''}$whole${fraction.isEmpty ? '' : '$decimalSeparator$fraction'}';
  }

  String integer(num value) => number(value.round(), maxFractionDigits: 0);

  String percent(num value) => '${number(value * 100, maxFractionDigits: 0)}$percentSuffix';

  static String _two(int v) => v.toString().padLeft(2, '0');
}

/// ISO dates, English names and English plural rules: the fallback before generated messages are
/// loaded, and for tests.
class IsoFormats extends StxLocaleFormats {
  const IsoFormats() : super(decimalSeparator: '.', groupSeparator: ',');

  @override
  Plural plural(num n) => n == 1 ? Plural.one : Plural.other;

  @override
  String date(DateTime value, [DateStyle style = DateStyle.medium]) => inputDate(value);

  @override
  String time(DateTime value, [TimeStyle style = TimeStyle.short]) =>
      style == TimeStyle.short ? inputTime(value) : '${inputTime(value)}:${value.second.toString().padLeft(2, '0')}';

  @override
  String dateTime(DateTime value, {DateStyle date = DateStyle.medium, TimeStyle time = TimeStyle.short}) =>
      '${this.date(value, date)} ${this.time(value, time)}';

  @override
  List<String> get months => const [
    'January', 'February', 'March', 'April', 'May', 'June', //
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  @override
  List<String> get monthsShort => const [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  List<String> get weekdays => const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

  @override
  List<String> get weekdaysShort => const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  int get firstDayOfWeek => DateTime.monday;

  @override
  String inputDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  @override
  DateTime? parseInputDate(String text) =>
      parseNumericDate(text, RegExp(r'^\s*(\d{4})-(\d{1,2})-(\d{1,2})\s*$'), 1, 2, 3);
}

/// Parses a numeric date with [pattern]'s groups at [year], [month], [day]; null for impossible
/// dates (e.g. 30 February). Used by generated formats.
DateTime? parseNumericDate(String text, RegExp pattern, int year, int month, int day) {
  final m = pattern.firstMatch(text);
  if (m == null) return null;
  final y = int.parse(m[year]!), mo = int.parse(m[month]!), d = int.parse(m[day]!);
  final value = DateTime(y, mo, d);
  return value.year == y && value.month == mo && value.day == d ? value : null;
}

/// Two-digit zero padding, used by generated date patterns.
String pad2(int value) => value.toString().padLeft(2, '0');

/// CLDR operand `v`: the number of visible fraction digits (`1` → 0, `1.5` → 1, `1.0` → 1).
int visibleFractionDigits(num n) {
  if (n is int) return 0;
  final text = n.toString();
  final dot = text.indexOf('.');
  return dot < 0 || text.contains('e') ? 0 : text.length - dot - 1;
}
