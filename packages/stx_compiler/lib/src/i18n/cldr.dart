/// A bundled subset of CLDR (gregorian calendar, cardinal plural rules, decimal symbols) for the
/// languages stx supports, compiled into each locale's generated `StxLocaleFormats`.
library;

import '../naming.dart';

final class CldrLocale {
  const CldrLocale({
    required this.plural,
    required this.months,
    required this.monthsShort,
    required this.weekdays,
    required this.weekdaysShort,
    required this.firstDayOfWeek,
    required this.dateFormats,
    required this.timeFormats,
    required this.dateTimeGlue,
    required this.inputOrder,
    required this.inputSeparator,
    required this.inputPadded,
    required this.decimal,
    required this.group,
    this.minimumGroupingDigits = 1,
    this.percentSuffix = '%',
    this.am = 'AM',
    this.pm = 'PM',
  });

  /// A Dart expression of type `Plural` over the CLDR operands `i` (integer digits) and `v`
  /// (visible fraction digits).
  final String plural;
  final List<String> months;
  final List<String> monthsShort;

  /// Monday first.
  final List<String> weekdays;
  final List<String> weekdaysShort;

  /// `DateTime.monday` (1) … `DateTime.sunday` (7).
  final int firstDayOfWeek;

  /// CLDR patterns for short, medium, long, full.
  final List<String> dateFormats;

  /// CLDR patterns for short, medium.
  final List<String> timeFormats;

  /// `{1}` is the date, `{0}` the time.
  final String dateTimeGlue;

  /// Order of a typed numeric date: `dmy` or `mdy`.
  final String inputOrder;
  final String inputSeparator;
  final bool inputPadded;
  final String decimal;
  final String group;
  final int minimumGroupingDigits;
  final String percentSuffix;
  final String am;
  final String pm;
}

const _oneIfI1V0 = 'i == 1 && v == 0 ? Plural.one : Plural.other';

const cldr = <String, CldrLocale>{
  'en': CldrLocale(
    plural: _oneIfI1V0,
    months: [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ],
    monthsShort: ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'],
    weekdays: ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'],
    weekdaysShort: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
    firstDayOfWeek: 7,
    dateFormats: ['M/d/yy', 'MMM d, y', 'MMMM d, y', 'EEEE, MMMM d, y'],
    timeFormats: ['h:mm a', 'h:mm:ss a'],
    dateTimeGlue: '{1}, {0}',
    inputOrder: 'mdy',
    inputSeparator: '/',
    inputPadded: false,
    decimal: '.',
    group: ',',
  ),
  'nl': CldrLocale(
    plural: _oneIfI1V0,
    months: [
      'januari',
      'februari',
      'maart',
      'april',
      'mei',
      'juni',
      'juli',
      'augustus',
      'september',
      'oktober',
      'november',
      'december',
    ],
    monthsShort: ['jan', 'feb', 'mrt', 'apr', 'mei', 'jun', 'jul', 'aug', 'sep', 'okt', 'nov', 'dec'],
    weekdays: ['maandag', 'dinsdag', 'woensdag', 'donderdag', 'vrijdag', 'zaterdag', 'zondag'],
    weekdaysShort: ['ma', 'di', 'wo', 'do', 'vr', 'za', 'zo'],
    firstDayOfWeek: 1,
    dateFormats: ['dd-MM-y', 'd MMM y', 'd MMMM y', 'EEEE d MMMM y'],
    timeFormats: ['HH:mm', 'HH:mm:ss'],
    dateTimeGlue: '{1} {0}',
    inputOrder: 'dmy',
    inputSeparator: '-',
    inputPadded: true,
    decimal: ',',
    group: '.',
  ),
  'de': CldrLocale(
    plural: _oneIfI1V0,
    months: [
      'Januar',
      'Februar',
      'März',
      'April',
      'Mai',
      'Juni',
      'Juli',
      'August',
      'September',
      'Oktober',
      'November',
      'Dezember',
    ],
    monthsShort: ['Jan.', 'Feb.', 'März', 'Apr.', 'Mai', 'Juni', 'Juli', 'Aug.', 'Sept.', 'Okt.', 'Nov.', 'Dez.'],
    weekdays: ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag'],
    weekdaysShort: ['Mo.', 'Di.', 'Mi.', 'Do.', 'Fr.', 'Sa.', 'So.'],
    firstDayOfWeek: 1,
    dateFormats: ['dd.MM.yy', 'dd.MM.y', 'd. MMMM y', 'EEEE, d. MMMM y'],
    timeFormats: ['HH:mm', 'HH:mm:ss'],
    dateTimeGlue: '{1}, {0}',
    inputOrder: 'dmy',
    inputSeparator: '.',
    inputPadded: true,
    decimal: ',',
    group: '.',
    percentSuffix: ' %',
  ),
  'fr': CldrLocale(
    plural: 'i == 0 || i == 1 ? Plural.one : (i != 0 && i % 1000000 == 0 && v == 0 ? Plural.many : Plural.other)',
    months: [
      'janvier',
      'février',
      'mars',
      'avril',
      'mai',
      'juin',
      'juillet',
      'août',
      'septembre',
      'octobre',
      'novembre',
      'décembre',
    ],
    monthsShort: ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'],
    weekdays: ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'],
    weekdaysShort: ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'],
    firstDayOfWeek: 1,
    dateFormats: ['dd/MM/y', 'd MMM y', 'd MMMM y', 'EEEE d MMMM y'],
    timeFormats: ['HH:mm', 'HH:mm:ss'],
    dateTimeGlue: '{1} {0}',
    inputOrder: 'dmy',
    inputSeparator: '/',
    inputPadded: true,
    decimal: ',',
    group: ' ',
    percentSuffix: ' %',
  ),
  'es': CldrLocale(
    plural: 'i == 1 && v == 0 ? Plural.one : (i != 0 && i % 1000000 == 0 && v == 0 ? Plural.many : Plural.other)',
    months: [
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre',
    ],
    monthsShort: ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sept', 'oct', 'nov', 'dic'],
    weekdays: ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'],
    weekdaysShort: ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'],
    firstDayOfWeek: 1,
    dateFormats: ['d/M/yy', 'd MMM y', "d 'de' MMMM 'de' y", "EEEE, d 'de' MMMM 'de' y"],
    timeFormats: ['H:mm', 'H:mm:ss'],
    dateTimeGlue: '{1}, {0}',
    inputOrder: 'dmy',
    inputSeparator: '/',
    inputPadded: true,
    decimal: ',',
    group: '.',
    minimumGroupingDigits: 2,
    percentSuffix: ' %',
  ),
};

/// The CLDR data for [locale] (`nl`, `nl_BE` and `nl-BE` all use `nl`); null when unsupported.
CldrLocale? cldrFor(String locale) => cldr[locale.split(RegExp('[-_]')).first.toLowerCase()];

/// Compiles a CLDR date/time pattern to the contents of a Dart string literal over the
/// `DateTime` variable [v] (quotes included in the result).
String compileDatePattern(String pattern, CldrLocale data, {String v = 'v'}) {
  final b = StringBuffer("'");
  var i = 0;
  void literal(String text) => b.write(text.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll(r'$', r'\$'));
  while (i < pattern.length) {
    final c = pattern[i];
    if (c == "'") {
      final end = pattern.indexOf("'", i + 1);
      if (end == i + 1) {
        literal("'");
        i += 2;
        continue;
      }
      literal(pattern.substring(i + 1, end < 0 ? pattern.length : end));
      i = end < 0 ? pattern.length : end + 1;
      continue;
    }
    if (!RegExp('[A-Za-z]').hasMatch(c)) {
      literal(c);
      i++;
      continue;
    }
    var n = 1;
    while (i + n < pattern.length && pattern[i + n] == c) {
      n++;
    }
    i += n;
    b.write(switch ((c, n)) {
      ('y', 2) => '\${pad2($v.year % 100)}',
      ('y', _) => '\${$v.year}',
      ('M', 1) => '\${$v.month}',
      ('M', 2) => '\${pad2($v.month)}',
      ('M', 3) => '\${monthsShort[$v.month - 1]}',
      ('M', _) => '\${months[$v.month - 1]}',
      ('d', 1) => '\${$v.day}',
      ('d', _) => '\${pad2($v.day)}',
      ('E', 4) => '\${weekdays[$v.weekday - 1]}',
      ('E', _) => '\${weekdaysShort[$v.weekday - 1]}',
      ('H', 1) => '\${$v.hour}',
      ('H', _) => '\${pad2($v.hour)}',
      ('h', 1) => '\${($v.hour + 11) % 12 + 1}',
      ('h', _) => '\${pad2(($v.hour + 11) % 12 + 1)}',
      ('m', 1) => '\${$v.minute}',
      ('m', _) => '\${pad2($v.minute)}',
      ('s', 1) => '\${$v.second}',
      ('s', _) => '\${pad2($v.second)}',
      ('a', _) => "\${$v.hour < 12 ? ${Naming.stringLiteral(data.am)} : ${Naming.stringLiteral(data.pm)}}",
      _ => throw ArgumentError('unsupported pattern letter "$c" in "$pattern"'),
    });
  }
  b.write("'");
  return b.toString();
}

/// The Dart source of the `StxLocaleFormats` subclass [className] for [data].
String renderFormats(String className, CldrLocale data) {
  String list(List<String> items) => 'const [${items.map(Naming.stringLiteral).join(', ')}]';
  String dateSwitch() => [
    for (final (i, style) in const ['short', 'medium', 'long', 'full'].indexed)
      '    DateStyle.$style => ${compileDatePattern(data.dateFormats[i], data)},',
  ].join('\n');
  String timeSwitch() => [
    for (final (i, style) in const ['short', 'medium'].indexed)
      '    TimeStyle.$style => ${compileDatePattern(data.timeFormats[i], data)},',
  ].join('\n');
  final glue = Naming.stringLiteral(data.dateTimeGlue)
      .replaceAll('{1}', r'${this.date(v, date)}')
      .replaceAll('{0}', r'${this.time(v, time)}')
      .replaceFirst(RegExp("^r'"), "'");

  final d = data.inputPadded ? r'${pad2(v.day)}' : r'${v.day}';
  final m = data.inputPadded ? r'${pad2(v.month)}' : r'${v.month}';
  final sep = data.inputSeparator;
  final inputDate = data.inputOrder == 'mdy' ? "'$m$sep$d$sep\${v.year}'" : "'$d$sep$m$sep\${v.year}'";
  final sepRegex = RegExp.escape(sep);
  final groups = data.inputOrder == 'mdy' ? '3, 1, 2' : '3, 2, 1';

  return '''
final class $className extends StxLocaleFormats {
  const $className()
    : super(
        decimalSeparator: ${Naming.stringLiteral(data.decimal)},
        groupSeparator: ${Naming.stringLiteral(data.group)},
        minimumGroupingDigits: ${data.minimumGroupingDigits},
        percentSuffix: ${Naming.stringLiteral(data.percentSuffix)},
      );

  static final _input = RegExp(r'^\\s*(\\d{1,2})$sepRegex(\\d{1,2})$sepRegex(\\d{4})\\s*\$');

  @override
  Plural plural(num n) {
    final i = n.abs().truncate();
    final v = visibleFractionDigits(n);
    return ${data.plural};
  }

  @override
  String date(DateTime v, [DateStyle style = DateStyle.medium]) => switch (style) {
${dateSwitch()}
  };

  @override
  String time(DateTime v, [TimeStyle style = TimeStyle.short]) => switch (style) {
${timeSwitch()}
  };

  @override
  String dateTime(DateTime v, {DateStyle date = DateStyle.medium, TimeStyle time = TimeStyle.short}) => $glue;

  @override
  List<String> get months => ${list(data.months)};

  @override
  List<String> get monthsShort => ${list(data.monthsShort)};

  @override
  List<String> get weekdays => ${list(data.weekdays)};

  @override
  List<String> get weekdaysShort => ${list(data.weekdaysShort)};

  @override
  int get firstDayOfWeek => ${data.firstDayOfWeek};

  @override
  String inputDate(DateTime v) => $inputDate;

  @override
  DateTime? parseInputDate(String text) => parseNumericDate(text, _input, $groups);
}
''';
}
