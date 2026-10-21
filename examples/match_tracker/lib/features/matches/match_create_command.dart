import 'package:stx_annotations/stx_annotations.dart';

import '../../gen/contract/platform_v1/platform_v1.g.dart';
import '../../gen/contract/scopes.g.dart';
import '../games/games.dart';
import 'participants_field.dart';

/// Recording a match (`POST /api/v1/matches`). Everything else is generated: the form state,
/// straight-line validation from the contract, the mapping to `CreateMatchV1`, the page, the route,
/// the navigation entry and the scope check.
@UiRoute('/matches/new')
@UiForm(submit: MatchesApiV1.createMatch)
@UiRequires([Scope.ghostPlayerRead]) // ParticipantsField searches ghost players
@DomainEntity()
final class MatchCreateCommand {
  @UiFormOrder(10)
  @UiFieldDataSource(GameSearchSource)
  @UiFieldHint()
  final GameId gameId;

  @UiFormOrder(20)
  final DateTime playedAt;

  @UiFormOrder(30)
  @UiFieldWidget(ParticipantsField)
  @ContractProperty('participants')
  final List<Participant> players;

  @UiFormOrder(40)
  final bool editRequestsEnabled;

  const MatchCreateCommand({
    required this.gameId,
    required this.playedAt,
    required this.players,
    required this.editRequestsEnabled,
  });
}
