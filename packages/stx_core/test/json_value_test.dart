import 'package:stx_core/stx_core.dart';
import 'package:test/test.dart';

void main() {
  test('listValue decodes nested lists with index paths', () {
    final nested = Json.list(
      {
        'grid': [
          [1, 2],
          [3],
        ],
      },
      'grid',
      (json) => Json.listValue(json, Json.integerValue),
    );
    expect(nested, [
      [1, 2],
      [3],
    ]);
    expect(
      () => Json.list(
        {
          'grid': [
            [1, 'x'],
          ],
        },
        'grid',
        (json) => Json.listValue(json, Json.integerValue),
      ),
      throwsA(isA<JsonDecodeException>().having((e) => e.path, 'path', 'grid[0][1]')),
    );
  });

  test('listValue at the root (list responses)', () {
    expect(
      () => Json.listValue([1, null], Json.integerValue),
      throwsA(isA<JsonDecodeException>().having((e) => e.path, 'path', '[1]')),
    );
  });

  test('emailValue', () {
    expect(Json.emailValue('a@b.nl').value, 'a@b.nl');
    expect(() => Json.emailValue('nope'), throwsA(isA<JsonDecodeException>()));
  });
}
