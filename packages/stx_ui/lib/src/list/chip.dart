import 'package:flutter/widgets.dart';
import 'package:stx_i18n/stx_i18n.dart';
import 'package:stx_style/stx_style.dart';

import '../primitives/pressable.dart';

/// A small toggle or tag, styled by `components.chip`: choice filters, sort options and the
/// active filters above an overview's results.
class StxChip extends StatelessWidget {
  const StxChip(
    this.label, {
    super.key,
    required this.onPressed,
    this.selected = false,
    this.trailing,
    this.semanticLabel,
  });

  final Msg label;
  final bool selected;
  final VoidCallback? onPressed;

  /// After the label, e.g. a sort direction or a remove mark.
  final Msg? trailing;
  final Msg? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final spec = tokens.chip;
    final foreground = selected ? spec.selectedForeground : spec.foreground;
    final text = [context.msg(label), if (trailing != null) context.msg(trailing!)].join(' ');
    return StxPressable(
      onPressed: onPressed,
      radius: spec.radius,
      toggled: selected,
      semanticLabel: semanticLabel == null ? null : '${context.msg(semanticLabel!)} ${context.msg(label)}',
      builder: (context, state) {
        final background = tokens.color(selected ? spec.selectedBackground : spec.background);
        final overlay = state.pressed ? 0.16 : (state.hovered ? 0.08 : 0.0);
        return DecoratedBox(
          decoration: BoxDecoration(
            color: overlay == 0
                ? background
                : Color.alphaBlend(tokens.color(foreground).withValues(alpha: overlay), background),
            borderRadius: BorderRadius.circular(tokens.corner(spec.radius)),
            border: selected ? null : Border.all(color: tokens.color(spec.border)),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: tokens.spacing(spec.padX), vertical: tokens.spacing(spec.padY)),
            child: Text(text, style: context.textStyle(spec.text, color: foreground), maxLines: 1),
          ),
        );
      },
    );
  }
}
