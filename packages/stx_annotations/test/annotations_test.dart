import 'package:stx_annotations/stx_annotations.dart';
import 'package:test/test.dart';

// The consumer syntax from docs/examples must compile against these annotations. Endpoint and
// MsgKey constants are stand-ins: stx_annotations does not depend on stx_core / stx_i18n.
const _createMatch = Object();
const _listGames = Object();
const _playersLabel = Object();

@BuildTypeConverter(String)
extension type const _GameId(String value) {}

@UiDataSource(endpoint: _listGames, query: 'name', value: 'id', label: 'displayName')
final class _GameSearchSource {}

@UiFieldWidget()
final class _PlayerPickerField {}

@UiRoute('/matches/new', nav: UiNav.primary)
@UiForm(submit: _createMatch, onSuccess: UiNavigate.back)
@DomainEntity()
final class _MatchCreateCommand {
  @UiFormOrder(10)
  @UiFieldType(UiFieldType.autocomplete)
  @UiFieldDataSource(_GameSearchSource)
  @UiFieldHint()
  final _GameId gameId;

  @UiFormOrder(20)
  final DateTime playedAt;

  @UiFormOrder(30)
  @UiFieldWidget(_PlayerPickerField)
  @UiFieldLabel(_playersLabel)
  final List<String> players;

  @UiFormOrder(40)
  @UiFieldType(UiFieldType.textArea)
  @UiFieldValidate(maxLength: 280)
  @ContractProperty('notes')
  final String? notes;

  const _MatchCreateCommand({required this.gameId, required this.playedAt, required this.players, this.notes});
}

void main() {
  test('the documented consumer syntax compiles', () {
    final command = _MatchCreateCommand(
      gameId: const _GameId('g'),
      playedAt: DateTime.utc(2026),
      players: const ['a', 'b'],
      notes: 'close game',
    );
    expect(command.gameId.value, 'g');
    expect(command.notes, 'close game');
  });

  test('UiFieldType exposes every kind except custom as a shorthand', () {
    expect(const UiFieldType(UiFieldType.dateTime).kind, UiFieldKind.dateTime);
    expect(UiFieldType.multiAutocomplete, UiFieldKind.multiAutocomplete);
  });
}
