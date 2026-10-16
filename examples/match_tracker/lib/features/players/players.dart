import 'package:stx_annotations/stx_annotations.dart';
import 'package:stx_core/stx_core.dart';

import '../../gen/contract/platform_v1/platform_v1.g.dart';

@BuildTypeConverter(Uuid)
extension type const GhostPlayerId(Uuid value) {}

/// Ghost player suggestions, used by the participants field.
@UiDataSource(endpoint: GhostPlayersApiV1.getGhostPlayerSuggestions, query: 'query', value: 'id', label: 'displayName')
final class GhostPlayerSearchSource {}
