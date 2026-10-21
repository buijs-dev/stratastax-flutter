/// An ICU MessageFormat subset: compiled to Dart string interpolation by stx_compiler, interpreted
/// at runtime by stx_i18n for translations from a backend.
///
/// Supported: text, `{name}`, `{n, number[, integer|percent]}`, `{d, date[, short|medium|long|full]}`,
/// `{d, time[, short|medium]}`, `{n, plural, =0 {…} one {…} other {…}}` with `#`, and
/// `{x, select, a {…} other {…}}`. Apostrophes quote: `''` is a literal `'`, `'{'` a literal `{`.
library;

sealed class IcuNode {
  const IcuNode();
}

final class IcuText extends IcuNode {
  const IcuText(this.text);

  final String text;
}

/// `#` inside a plural: the number, formatted.
final class IcuPound extends IcuNode {
  const IcuPound();
}

final class IcuArg extends IcuNode {
  const IcuArg(this.name, {this.type, this.style});

  final String name;

  /// null, `number`, `date` or `time`.
  final String? type;
  final String? style;
}

final class IcuChoice extends IcuNode {
  const IcuChoice(this.name, this.kind, this.options);

  final String name;

  /// `plural` or `select`.
  final String kind;

  /// Selector (`=0`, `one`, `other`, `male`) → message, in source order.
  final Map<String, List<IcuNode>> options;
}

/// The Dart type a placeholder needs.
enum ArgType {
  /// Any value; `toString()`.
  any,
  number,
  date,
  string;

  /// Whether a value declared as [this] can be used where [other] is needed: equal, or either is
  /// [any] (the rule between the locales of one message).
  bool compatibleWith(ArgType other) => this == other || this == any || other == any;
}

final class IcuException implements Exception {
  const IcuException(this.message, this.offset);

  final String message;
  final int offset;

  @override
  String toString() => '$message (at $offset)';
}

const _pluralCategories = {'zero', 'one', 'two', 'few', 'many', 'other'};
const _numberStyles = {'integer', 'percent'};
const _dateStyles = {'short', 'medium', 'long', 'full'};
const _timeStyles = {'short', 'medium'};

/// Parses [source]; throws [IcuException].
List<IcuNode> parseIcu(String source) => _Parser(source).parse();

final class _Parser {
  _Parser(this.source);

  final String source;
  var pos = 0;

  List<IcuNode> parse() {
    final nodes = _message(inPlural: false, nested: false);
    if (pos < source.length) throw IcuException('unexpected "${source[pos]}"', pos);
    return nodes;
  }

  bool get _end => pos >= source.length;

  String get _char => source[pos];

  List<IcuNode> _message({required bool inPlural, required bool nested}) {
    final nodes = <IcuNode>[];
    final text = StringBuffer();
    void flush() {
      if (text.isNotEmpty) nodes.add(IcuText(text.toString()));
      text.clear();
    }

    while (!_end) {
      final c = _char;
      if (c == '}') {
        if (!nested) throw IcuException('unmatched "}"', pos);
        break;
      }
      if (c == '{') {
        flush();
        nodes.add(_argument(inPlural: inPlural));
      } else if (c == '#' && inPlural) {
        flush();
        nodes.add(const IcuPound());
        pos++;
      } else if (c == "'") {
        // '' → '; '{…' / '}…' / '#…' → quoted literal until the next single quote.
        if (pos + 1 < source.length && source[pos + 1] == "'") {
          text.write("'");
          pos += 2;
        } else if (pos + 1 < source.length && '{}#'.contains(source[pos + 1])) {
          pos++;
          while (!_end && _char != "'") {
            text.write(_char);
            pos++;
          }
          pos++; // closing quote (or end)
        } else {
          text.write("'");
          pos++;
        }
      } else {
        text.write(c);
        pos++;
      }
    }
    flush();
    return nodes;
  }

  IcuNode _argument({required bool inPlural}) {
    final start = pos;
    pos++; // {
    final name = _word();
    if (name.isEmpty) throw IcuException('expected an argument name', pos);
    _spaces();
    if (_consume('}')) return IcuArg(name);
    if (!_consume(',')) throw IcuException('expected "," or "}" after {$name', pos);
    _spaces();
    final type = _word();
    _spaces();
    switch (type) {
      case 'number' || 'date' || 'time':
        String? style;
        if (_consume(',')) {
          _spaces();
          style = _word();
          _spaces();
          final allowed = switch (type) {
            'number' => _numberStyles,
            'date' => _dateStyles,
            _ => _timeStyles,
          };
          if (!allowed.contains(style)) throw IcuException('unknown $type style "$style" (${allowed.join(', ')})', pos);
        }
        if (!_consume('}')) throw IcuException('expected "}" to close {$name, $type', pos);
        return IcuArg(name, type: type, style: style);
      case 'plural' || 'select':
        if (!_consume(',')) throw IcuException('expected "," after $type', pos);
        final options = <String, List<IcuNode>>{};
        while (true) {
          _spaces();
          if (_consume('}')) break;
          if (_end) throw IcuException('unclosed {$name, $type', start);
          final selector = _consume('=') ? '=${_word()}' : _word();
          if (selector.isEmpty || selector == '=') throw IcuException('expected a selector', pos);
          if (type == 'plural' && !selector.startsWith('=') && !_pluralCategories.contains(selector)) {
            throw IcuException('unknown plural category "$selector" (${_pluralCategories.join(', ')}, =N)', pos);
          }
          if (type == 'plural' && selector.startsWith('=') && num.tryParse(selector.substring(1)) == null) {
            throw IcuException('"$selector" is not a number', pos);
          }
          _spaces();
          if (!_consume('{')) throw IcuException('expected "{" after "$selector"', pos);
          options[selector] = _message(inPlural: type == 'plural' || inPlural, nested: true);
          if (!_consume('}')) throw IcuException('unclosed option "$selector"', pos);
        }
        if (!options.containsKey('other')) throw IcuException('{$name, $type} needs an "other" option', start);
        return IcuChoice(name, type, options);
      default:
        throw IcuException('unknown argument type "$type" (number, date, time, plural, select)', pos);
    }
  }

  String _word() {
    final start = pos;
    while (!_end && RegExp(r'[A-Za-z0-9_]').hasMatch(_char)) {
      pos++;
    }
    return source.substring(start, pos);
  }

  void _spaces() {
    while (!_end && (_char == ' ' || _char == '\n' || _char == '\t')) {
      pos++;
    }
  }

  bool _consume(String c) {
    if (!_end && _char == c) {
      pos++;
      return true;
    }
    return false;
  }
}

/// The placeholders of [nodes] with the type each needs, in order of first appearance.
/// Throws [IcuException] when one placeholder is used with conflicting types.
Map<String, ArgType> icuArguments(List<IcuNode> nodes) {
  final result = <String, ArgType>{};
  void add(String name, ArgType type) {
    final existing = result[name];
    if (existing == null || existing == ArgType.any) {
      result[name] = type;
    } else if (type != ArgType.any && type != existing) {
      throw IcuException('"$name" is used as ${existing.name} and as ${type.name}', 0);
    }
  }

  void walk(List<IcuNode> nodes) {
    for (final node in nodes) {
      switch (node) {
        case IcuArg(:final name, :final type):
          add(name, switch (type) {
            'number' => ArgType.number,
            'date' || 'time' => ArgType.date,
            _ => ArgType.any,
          });
        case IcuChoice(:final name, :final kind, :final options):
          add(name, kind == 'plural' ? ArgType.number : ArgType.string);
          for (final option in options.values) {
            walk(option);
          }
        case IcuText() || IcuPound():
          break;
      }
    }
  }

  walk(nodes);
  return result;
}
