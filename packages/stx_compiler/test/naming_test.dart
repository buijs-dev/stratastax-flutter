import 'package:stx_compiler/stx_compiler.dart';
import 'package:test/test.dart';

void main() {
  test('words split every naming style used in contracts', () {
    expect(Naming.words('create_match'), ['create', 'match']);
    expect(Naming.words('createMatch'), ['create', 'match']);
    expect(Naming.words('If-Match'), ['if', 'match']);
    expect(Naming.words('HIGHER_WINS'), ['higher', 'wins']);
    expect(Naming.words('stx-engine:match-read'), ['stx', 'engine', 'match', 'read']);
    expect(Naming.words('HTTPStatus'), ['http', 'status']);
  });

  test('pascal, camel, snake', () {
    expect(Naming.pascal('create_match'), 'CreateMatch');
    expect(Naming.camel('ghost-players'), 'ghostPlayers');
    expect(Naming.snake('MatchesApiV1'), 'matches_api_v1');
  });

  test('member names never collide with keywords or generated members', () {
    expect(Naming.member('default'), r'default$');
    expect(Naming.member('hashCode'), r'hashCode$');
    expect(Naming.member('encode'), r'encode$');
    expect(Naming.member('2fa'), 'v2fa');
    // Common property names stay as they are.
    expect(Naming.member('type'), 'type');
    expect(Naming.member('name'), 'name');
  });

  test('enum values', () {
    expect(Naming.enumValue('WIN_LOSS'), 'winLoss');
    expect(Naming.enumValue('https://errors.stratastax.io/not-found'), 'notFound');
    expect(Naming.enumValue('name'), r'name$');
  });

  test('string literals', () {
    expect(Naming.stringLiteral('plain'), "'plain'");
    expect(Naming.stringLiteral(r'^\d+$'), r"r'^\d+$'");
    expect(Naming.stringLiteral("it's"), r"'it\'s'");
    expect(Naming.stringLiteral(r"it's $5"), r"'it\'s \$5'");
  });
}
