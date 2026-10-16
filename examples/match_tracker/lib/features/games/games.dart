import 'package:stx_annotations/stx_annotations.dart';
import 'package:stx_core/stx_core.dart';

import '../../gen/contract/platform_v1/platform_v1.g.dart';

/// A game id. Zero-cost; `@BuildTypeConverter` tells the compiler it travels as a `Uuid`.
@BuildTypeConverter(Uuid)
extension type const GameId(Uuid value) {}

/// Game suggestions for autocomplete fields. The compiler checks `query`, `value` and `label`
/// against the contract and adds the operation's scope (`stx-engine:game-read`) to every page
/// that uses it.
@UiDataSource(endpoint: GamesApiV1.getGameSuggestions, query: 'query', value: 'id', label: 'displayName')
final class GameSearchSource {}

/// Creating a game: validation, scopes and the endpoint all come from `create_game` in the
/// contract. Labels come from i18n/*.yaml (`gameCreateCommand.*`).
@UiRoute('/games/new', nav: UiNav.secondary)
@UiForm(submit: GamesApiV1.createGame)
@DomainEntity()
final class GameCreateCommand {
  @UiFormOrder(10)
  @UiFieldValidate(minLength: 2, maxLength: 100) // tightens the contract
  final String displayName;

  @UiFormOrder(20)
  @UiFieldType(UiFieldType.textArea)
  final String description;

  @UiFormOrder(30)
  @UiFieldValidate(minimum: 1, maximum: 20)
  final int minPlayers;

  @UiFormOrder(40)
  @UiFieldValidate(minimum: 1, maximum: 20)
  final int maxPlayers;

  @UiFormOrder(50)
  final ScoreTypeV1 scoreType; // contract enum → select, labels from `enum.ScoreTypeV1.*`

  @UiFormOrder(60)
  final WinConditionV1? winCondition;

  @UiFormOrder(70)
  @UiFieldHelp()
  final String? imageUrl; // `format: uri` in the contract → URL validation

  @UiFormOrder(80)
  @UiFieldHelp()
  final String? sourceRef; // maxLength 64 from the contract

  @UiIgnore() // not in the form; the default is sent
  final List<String> tags;

  const GameCreateCommand({
    required this.displayName,
    required this.description,
    required this.minPlayers,
    required this.maxPlayers,
    required this.scoreType,
    this.winCondition,
    this.imageUrl,
    this.sourceRef,
    this.tags = const [],
  });
}
