/// Name conversion from contract names to Dart identifiers.
abstract final class Naming {
  /// Reserved words (never valid identifiers) plus members every generated model already has.
  static const _reserved = {
    'assert', 'await', 'break', 'case', 'catch', 'class', 'const', 'continue', 'default', 'do', 'else', //
    'enum', 'extends', 'false', 'final', 'finally', 'for', 'if', 'in', 'is', 'new', 'null', 'rethrow',
    'return', 'super', 'switch', 'this', 'throw', 'true', 'try', 'var', 'void', 'while', 'with', 'yield',
    'hashCode', 'runtimeType', 'toString', 'noSuchMethod', 'encode', 'decode',
  };

  /// Members every generated enum already has.
  static const _enumMembers = {'values', 'index', 'name', 'wire'};

  /// Splits `create_match`, `createMatch`, `If-Match`, `HIGHER_WINS` and `stx-engine:match-read` into
  /// lower-case words.
  static List<String> words(String input) {
    final spaced = input
        .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}')
        .replaceAllMapped(RegExp(r'([A-Z]+)([A-Z][a-z])'), (m) => '${m[1]} ${m[2]}');
    return spaced.split(RegExp(r'[^A-Za-z0-9]+')).where((w) => w.isNotEmpty).map((w) => w.toLowerCase()).toList();
  }

  static String pascal(String input) => words(input).map(_capitalize).join();

  static String camel(String input) {
    final parts = words(input);
    if (parts.isEmpty) return '';
    return parts.first + parts.skip(1).map(_capitalize).join();
  }

  static String snake(String input) => words(input).join('_');

  /// A member name (field, parameter, enum value): camelCase, never reserved, never starting with
  /// a digit.
  static String member(String input) {
    var name = camel(input);
    if (name.isEmpty) name = 'value';
    if (RegExp(r'^[0-9]').hasMatch(name)) name = 'v$name';
    return _reserved.contains(name) ? '$name\$' : name;
  }

  /// An enum value name from a wire value; URIs use their last path segment
  /// (`https://errors.stratastax.io/not-found` → `notFound`).
  static String enumValue(String wire) {
    final uri = Uri.tryParse(wire);
    final source = (uri != null && uri.hasScheme && uri.pathSegments.isNotEmpty)
        ? uri.pathSegments.lastWhere((s) => s.isNotEmpty, orElse: () => wire)
        : wire;
    final name = member(source);
    return _enumMembers.contains(name) ? '$name\$' : name;
  }

  static String _capitalize(String word) => word.isEmpty ? word : word[0].toUpperCase() + word.substring(1);

  /// A Dart string literal for [value]: raw when possible, so regex patterns stay readable.
  static String stringLiteral(String value) {
    if (!value.contains("'") && !value.contains('\n') && !value.contains('\r')) {
      return value.contains(r'\') || value.contains(r'$') ? "r'$value'" : "'$value'";
    }
    final escaped = value
        .replaceAll(r'\', r'\\')
        .replaceAll("'", r"\'")
        .replaceAll(r'$', r'\$')
        .replaceAll('\n', r'\n')
        .replaceAll('\r', r'\r');
    return "'$escaped'";
  }

  /// Text for a `///` doc comment: trimmed lines, no trailing blank lines.
  static List<String> docLines(String? text) {
    if (text == null || text.trim().isEmpty) return const [];
    final lines = text.trim().split('\n').map((l) => l.trimRight()).toList();
    return [for (final l in lines) l.isEmpty ? '///' : '/// $l'];
  }
}
