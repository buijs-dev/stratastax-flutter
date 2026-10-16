import 'package:flutter/widgets.dart';
import 'package:stx_i18n/stx_i18n.dart';
import 'package:stx_style/stx_style.dart';

/// Label, input and message (hint or error) of every field, styled by `components.field`.
class StxFieldFrame extends StatelessWidget {
  const StxFieldFrame({super.key, required this.child, this.label, this.help, this.error, this.required = false});

  final Msg? label;

  /// Shown below the input when there is no error.
  final Msg? help;
  final Msg? error;

  /// Marks the label (a `*`) and sets semantics.
  final bool required;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final field = tokens.field;
    final bp = context.breakpoint;
    final message = error ?? help;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: tokens.spacing(field.gap),
      children: [
        if (label != null)
          Text(
            required ? '${context.msg(label!)} *' : context.msg(label!),
            style: tokens.textStyle(field.label, bp, color: ColorToken.onBackground),
          ),
        child,
        if (message != null)
          Semantics(
            liveRegion: error != null,
            child: Text(
              context.msg(message),
              style: tokens.textStyle(field.message, bp, color: error != null ? field.borderError : field.placeholder),
            ),
          ),
      ],
    );
  }
}

/// The bordered input box of a field; the border follows focus and error state.
class StxInputBox extends StatelessWidget {
  const StxInputBox({
    super.key,
    required this.focused,
    required this.hasError,
    required this.child,
    this.enabled = true,
  });

  final bool focused;
  final bool hasError;
  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final field = tokens.field;
    final border = hasError ? field.borderError : (focused ? field.borderFocus : field.border);
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.color(field.background),
          borderRadius: BorderRadius.circular(tokens.corner(field.radius)),
          border: Border.all(color: tokens.color(border), width: focused ? field.borderWidth * 2 : field.borderWidth),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: tokens.spacing(field.padX), vertical: tokens.spacing(field.padY)),
          child: child,
        ),
      ),
    );
  }
}
