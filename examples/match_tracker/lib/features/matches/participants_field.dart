import 'package:flutter/widgets.dart';
import 'package:stx_annotations/stx_annotations.dart';
import 'package:stx_i18n/stx_i18n.dart';
import 'package:stx_style/stx_style.dart';
import 'package:stx_ui/stx_ui.dart';

import '../../gen/app/services.g.dart';
import '../../gen/contract/platform_v1/platform_v1.g.dart';
import '../../gen/i18n/keys.g.dart';
import '../../gen/style/tokens.g.dart';
import '../players/players.dart';

/// One player in a match. Maps to the contract's `match_participant_input` by field name;
/// [displayName] is UI-only (no contract property), so it is ignored.
@DomainEntity()
final class Participant {
  const Participant({required this.ghostPlayerId, required this.displayName, this.outcome});

  final GhostPlayerId ghostPlayerId;

  @UiIgnore()
  final String displayName;

  final OutcomeV1? outcome;

  Participant copyWith({OutcomeV1? outcome}) =>
      Participant(ghostPlayerId: ghostPlayerId, displayName: displayName, outcome: outcome);
}

/// A custom field: the compiler checks that it edits `List<Participant>`, the type of the field
/// it is used for. Built from stx_ui widgets only, styled by tokens.
@UiFieldWidget()
final class ParticipantsField extends StxFieldWidget<List<Participant>> {
  const ParticipantsField({super.key, required super.field, required super.label, super.validation});

  @override
  Widget build(BuildContext context) => StxFieldBuilder(
    field: field,
    builder: (context, players) => StxFieldFrame(
      label: label,
      required: validation.minItems != null,
      error: field.error == null ? null : fieldErrorMsg(field.error!),
      child: StxColumn(
        gap: SpaceToken.sm,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ICU plural, compiled per locale: `{count, plural, =0 {…} one {# player} other {# players}}`.
          StxText(
            MsgMatchCreateCommand.playersCount(count: players.length),
            style: TextToken.caption,
            color: ColorToken.muted,
          ),
          for (final (index, player) in players.indexed)
            StxRow(
              gap: SpaceToken.sm,
              children: [
                Expanded(child: StxText(Msg.data(player.displayName))),
                StxButton(
                  player.outcome == OutcomeV1.win
                      ? MsgMatchCreateCommand.playersWinner
                      : MsgMatchCreateCommand.playersMarkWinner,
                  variant: player.outcome == OutcomeV1.win ? AppButton.win : ButtonVariant.secondary,
                  onPressed: () => field.value = [
                    for (final (i, p) in players.indexed)
                      p.copyWith(outcome: i == index ? OutcomeV1.win : OutcomeV1.loss),
                  ],
                ),
                StxButton(
                  MsgMatchCreateCommand.playersRemove,
                  variant: ButtonVariant.ghost,
                  onPressed: () => field.value = [...players]..removeAt(index),
                ),
              ],
            ),
          StxAutocomplete<GhostPlayerId>(
            source: AppServices.of(context).ghostPlayerSearchSource.map(GhostPlayerId.new),
            hint: MsgMatchCreateCommand.playersAdd,
            clearOnSelect: true,
            onSelected: (option) =>
                field.value = [...players, Participant(ghostPlayerId: option.value, displayName: option.label)],
          ),
        ],
      ),
    ),
  );
}
