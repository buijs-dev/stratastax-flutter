import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:stx_i18n/stx_i18n.dart';
import 'package:stx_style/stx_style.dart';

import 'field_frame.dart';

/// A text input on [EditableText]: no material, styled by `components.field`.
class StxTextField extends StatefulWidget {
  const StxTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.label,
    this.hint,
    this.help,
    this.error,
    this.required = false,
    this.onChanged,
    this.onSubmitted,
    this.obscure = false,
    this.minLines = 1,
    this.maxLines = 1,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.enabled = true,
    this.autofocus = false,
    this.trailing,
    this.tapRegionGroup = EditableText,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final Msg? label;

  /// Placeholder inside the empty input.
  final Msg? hint;
  final Msg? help;
  final Msg? error;
  final bool required;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool obscure;
  final int minLines;
  final int maxLines;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final bool enabled;
  final bool autofocus;

  /// E.g. a "now" button in a date field.
  final Widget? trailing;

  /// Tap region group of the input: taps inside the group (e.g. an option overlay of the same
  /// field) do not take the focus away.
  final Object tapRegionGroup;

  @override
  State<StxTextField> createState() => _StxTextFieldState();
}

class _StxTextFieldState extends State<StxTextField> {
  TextEditingController? _ownController;
  FocusNode? _ownFocus;

  TextEditingController get _controller => widget.controller ?? (_ownController ??= TextEditingController());
  FocusNode get _focus => widget.focusNode ?? (_ownFocus ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(StxTextField old) {
    super.didUpdateWidget(old);
    if (old.focusNode != widget.focusNode) {
      (old.focusNode ?? _ownFocus)?.removeListener(_onFocus);
      _focus.addListener(_onFocus);
    }
  }

  void _onFocus() => setState(() {});

  @override
  void dispose() {
    _focus.removeListener(_onFocus);
    _ownController?.dispose();
    _ownFocus?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final field = tokens.field;
    final bp = context.breakpoint;
    final style = tokens.textStyle(field.text, bp, color: field.foreground);
    final input = EditableText(
      controller: _controller,
      focusNode: _focus,
      style: style,
      cursorColor: tokens.color(field.borderFocus),
      backgroundCursorColor: tokens.color(field.placeholder),
      selectionColor: tokens.color(field.borderFocus).withValues(alpha: 0.3),
      obscureText: widget.obscure,
      minLines: widget.minLines,
      maxLines: widget.obscure ? 1 : widget.maxLines,
      keyboardType: widget.keyboardType ?? (widget.maxLines > 1 ? TextInputType.multiline : TextInputType.text),
      textInputAction: widget.textInputAction,
      inputFormatters: widget.inputFormatters,
      readOnly: !widget.enabled,
      autofocus: widget.autofocus,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      rendererIgnoresPointer: true,
      groupId: widget.tapRegionGroup,
    );
    final placeholder = widget.hint == null
        ? input
        : Stack(
            children: [
              ValueListenableBuilder(
                valueListenable: _controller,
                builder: (context, value, _) => value.text.isEmpty
                    ? Text(
                        context.msg(widget.hint!),
                        style: tokens.textStyle(field.text, bp, color: field.placeholder),
                        maxLines: 1,
                      )
                    : const SizedBox.shrink(),
              ),
              input,
            ],
          );
    return StxFieldFrame(
      label: widget.label,
      help: widget.help,
      error: widget.error,
      required: widget.required,
      child: Semantics(
        textField: true,
        label: widget.label == null ? null : context.msg(widget.label!),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.enabled ? _focus.requestFocus : null,
          child: MouseRegion(
            cursor: widget.enabled ? SystemMouseCursors.text : SystemMouseCursors.basic,
            child: StxInputBox(
              focused: _focus.hasFocus,
              hasError: widget.error != null,
              enabled: widget.enabled,
              child: widget.trailing == null
                  ? placeholder
                  : Row(
                      spacing: tokens.spacing(SpaceToken.sm),
                      children: [
                        Expanded(child: placeholder),
                        widget.trailing!,
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
