import 'package:flutter/widgets.dart';
import 'package:stx_i18n/stx_i18n.dart';
import 'package:stx_style/stx_style.dart';

import 'pressable.dart';

/// A button styled by a [ButtonVariant] from the tokens (`components.button`).
class StxButton extends StatelessWidget {
  const StxButton(
    this.label, {
    super.key,
    required this.onPressed,
    this.variant = ButtonVariant.primary,
    this.busy = false,
    this.expand = false,
    this.alignment = Alignment.center,
    this.semanticLabel,
    this.focusNode,
  });

  final Msg label;
  final VoidCallback? onPressed;
  final ButtonVariant variant;

  /// Shows a busy state and ignores presses (e.g. while a form submits).
  final bool busy;

  /// Fill the available width.
  final bool expand;

  /// Where the label sits when the button is wider than its label (e.g. navigation items).
  final AlignmentGeometry alignment;

  /// For screen readers when [label] is a symbol (e.g. `‹` with "Previous month").
  final Msg? semanticLabel;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final spec = tokens.button(variant);
    final foreground = tokens.color(spec.foreground);
    final background = tokens.color(spec.background);
    final text = context.msg(label);
    return StxPressable(
      onPressed: busy ? null : onPressed,
      focusNode: focusNode,
      radius: spec.radius,
      semanticLabel: semanticLabel == null ? null : context.msg(semanticLabel!),
      builder: (context, state) {
        // Hover and press tint the background with the foreground color.
        final overlay = state.pressed ? 0.16 : (state.hovered ? 0.08 : 0.0);
        final fill = overlay == 0 ? background : Color.alphaBlend(foreground.withValues(alpha: overlay), background);
        return Opacity(
          opacity: (state.enabled || busy) ? 1 : 0.5,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: spec.minHeight, minWidth: expand ? double.infinity : 0),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(tokens.corner(spec.radius)),
                border: spec.border == null ? null : Border.all(color: tokens.color(spec.border!)),
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: tokens.spacing(spec.padX),
                  vertical: tokens.spacing(spec.padY),
                ),
                child: Align(
                  alignment: alignment,
                  widthFactor: expand ? null : 1,
                  heightFactor: 1,
                  child: ExcludeSemantics(
                    excluding: semanticLabel != null,
                    child: Opacity(
                      opacity: busy ? 0.6 : 1,
                      child: Text(
                        busy ? context.msg(StxKeys.stateLoading) : text,
                        style: tokens.textStyle(spec.text, context.breakpoint, color: spec.foreground),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
