import 'package:stx_annotations/stx_annotations.dart';

import '../../gen/contract/platform_v1/platform_v1.g.dart';
import 'games.dart';

/// The game catalogue (`GET /api/v1/games`). The fields are paths into `GameV1`; the search
/// annotations follow `@SearchFilter` / `@SearchSort` on `Game` in stratastax-engine, with the
/// names the endpoint filters and sorts on (`name` for `displayName`). Inputs follow from the
/// types: chips for the enum, from–to for numbers and dates.
@UiRoute('/games', nav: UiNav.primary)
@UiListPage(
  list: GamesApiV1.listGames,
  count: GamesApiV1.countGames,
  cache: UiCache(mode: UiCacheMode.staleWhileRevalidate, ttlSeconds: 300), // the catalogue rarely changes
  actions: [UiAction(GameCreateCommand)], // /games/new, embedded in this page
)
@DomainEntity()
final class GameOverview {
  @UiColumn(order: 10, primary: true, flex: 2)
  @SearchText(alias: 'name')
  @SearchSort(alias: 'name', initial: true)
  final String displayName;

  @SearchText() // searched, not shown
  final String description;

  @UiColumn(order: 20)
  @SearchFilter()
  final ScoreTypeV1 scoreType;

  @UiColumn(order: 30)
  @SearchFilter()
  final int minPlayers;

  @UiColumn(order: 40)
  @SearchFilter()
  final int maxPlayers;

  @UiColumn(order: 50)
  @SearchFilter()
  @SearchSort(direction: SearchDirection.desc)
  final DateTime createdAt;

  const GameOverview({
    required this.displayName,
    required this.description,
    required this.scoreType,
    required this.minPlayers,
    required this.maxPlayers,
    required this.createdAt,
  });
}
