import 'package:stx_annotations/stx_annotations.dart';

import '../../gen/contract/platform_v1/platform_v1.g.dart';
import '../games/games.dart';
import 'match_create_command.dart';

/// The matches the user can see (`GET /api/v1/matches`), newest first. Nested values are paths
/// (`game.displayName`); their filter names are flattened as in the contract (`game.id` →
/// `gameId`). Saving a match (`createMatch`, tag `matches`) drops the cached pages.
@UiRoute('/matches', nav: UiNav.primary, home: true)
@UiListPage(
  list: MatchesApiV1.listMatches,
  count: MatchesApiV1.countMatches,
  panel: UiSearchPanel(layout: UiPanelLayout.side, position: UiPanelPosition.start),
  actions: [UiAction(MatchCreateCommand)], // /matches/new, embedded in this page
)
@DomainEntity()
final class MatchOverview {
  @UiColumn(order: 10, primary: true, flex: 2)
  @ContractProperty('game.displayName')
  @SearchText(alias: 'gameName')
  final String gameName;

  /// Filter only: pick a game.
  @ContractProperty('game.id')
  @SearchFilter(source: GameSearchSource)
  final GameId gameId;

  @UiColumn(order: 20)
  @SearchFilter()
  @SearchSort(direction: SearchDirection.desc, initial: true)
  final DateTime playedAt;

  @UiColumn(order: 30)
  @ContractProperty('recorder.displayName')
  @SearchFilter(alias: 'recorderName')
  final String recorderName;

  /// Not filterable: `status` is not in the endpoint's filter list.
  @UiColumn(order: 40)
  final MatchStatusV1 status;

  @UiColumn(order: 50)
  @SearchFilter()
  @SearchSort()
  final bool editRequestsEnabled;

  const MatchOverview({
    required this.gameName,
    required this.gameId,
    required this.playedAt,
    required this.recorderName,
    required this.status,
    required this.editRequestsEnabled,
  });
}
