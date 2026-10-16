import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:stx_core/stx_core.dart';
import 'package:stx_i18n/stx_i18n.dart';
import 'package:stx_style/stx_style.dart';

import '../data/data_source.dart';
import '../form/field.dart';
import '../primitives/pressable.dart';
import 'field_frame.dart';
import 'text_field.dart';

/// The option list under a field: a token-styled overlay that follows the field.
class _OptionsOverlay extends StatelessWidget {
  const _OptionsOverlay({required this.link, required this.width, required this.group, required this.children});

  final LayerLink link;

  /// The field's tap region group: the overlay lives in the Overlay, not under the field, so
  /// without a shared group a tap on an option counts as "outside" and closes the list first.
  final Object group;
  final double width;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return TapRegion(
      groupId: group,
      child: CompositedTransformFollower(
        link: link,
        targetAnchor: Alignment.bottomLeft,
        offset: Offset(0, tokens.spacing(SpaceToken.xs)),
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  // A popover is always opaque, also when fields are transparent.
                  color: tokens.color(ColorToken.background),
                  border: Border.all(color: tokens.color(tokens.field.border)),
                  borderRadius: BorderRadius.circular(tokens.corner(tokens.field.radius)),
                  boxShadow: [
                    BoxShadow(color: tokens.color(ColorToken.onBackground).withValues(alpha: 0.12), blurRadius: 12),
                  ],
                ),
                child: ListView(padding: EdgeInsets.zero, shrinkWrap: true, children: children),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({required this.text, required this.selected, required this.onPressed, this.muted = false});

  final String text;
  final bool selected;
  final bool muted;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return StxPressable(
      onPressed: onPressed,
      radius: RadiusToken.none,
      semanticLabel: text,
      builder: (context, state) => ColoredBox(
        color: (state.hovered || state.focused || selected)
            ? tokens.color(ColorToken.primary).withValues(alpha: selected ? 0.16 : 0.08)
            : const Color(0x00000000),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: tokens.spacing(tokens.field.padX),
            vertical: tokens.spacing(tokens.field.padY),
          ),
          child: Text(
            text,
            style: context.textStyle(
              tokens.field.text,
              color: muted ? tokens.field.placeholder : tokens.field.foreground,
            ),
          ),
        ),
      ),
    );
  }
}

/// A single choice from a fixed list (e.g. an enum), bound to a `StxField<T?>`.
class StxFormSelect<T> extends StatefulWidget {
  const StxFormSelect({
    super.key,
    required this.field,
    required this.label,
    required this.options,
    required this.optionLabel,
    this.help,
    this.validation = UiFieldValidation.none,
  });

  final StxField<T?> field;
  final Msg label;
  final List<T> options;

  /// Translated label per option (generated for enums: `enum.<Enum>.<value>` keys).
  final Msg Function(T option) optionLabel;
  final Msg? help;
  final UiFieldValidation validation;

  @override
  State<StxFormSelect<T>> createState() => _StxFormSelectState<T>();
}

class _StxFormSelectState<T> extends State<StxFormSelect<T>> {
  final _portal = OverlayPortalController();
  final _link = LayerLink();
  double _width = 240;

  void _choose(T? option) {
    widget.field.value = option;
    _portal.hide();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.field,
    builder: (context, _) {
      final tokens = context.tokens;
      final value = widget.field.value;
      final error = widget.field.error;
      return StxFieldFrame(
        label: widget.label,
        help: widget.help,
        required: widget.validation.required,
        error: error == null ? null : fieldErrorMsg(error),
        child: TapRegion(
          groupId: this,
          onTapOutside: (_) => _portal.hide(),
          child: OverlayPortal(
            controller: _portal,
            overlayChildBuilder: (context) => _OptionsOverlay(
              link: _link,
              width: _width,
              group: this,
              children: [
                if (!widget.validation.required)
                  _Option(
                    text: context.msg(StxKeys.fieldChoose),
                    muted: true,
                    selected: value == null,
                    onPressed: () => _choose(null),
                  ),
                for (final option in widget.options)
                  _Option(
                    text: context.msg(widget.optionLabel(option)),
                    selected: option == value,
                    onPressed: () => _choose(option),
                  ),
              ],
            ),
            child: CompositedTransformTarget(
              link: _link,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _width = constraints.maxWidth;
                  return StxPressable(
                    onPressed: _portal.toggle,
                    radius: tokens.field.radius,
                    builder: (context, state) => StxInputBox(
                      focused: state.focused || _portal.isShowing,
                      hasError: error != null,
                      child: Text(
                        context.msg(value == null ? StxKeys.fieldChoose : widget.optionLabel(value)),
                        style: context.textStyle(
                          tokens.field.text,
                          color: value == null ? tokens.field.placeholder : tokens.field.foreground,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Search-as-you-type choice from a [StxDataSource], bound to a `StxField<T?>`. Unbound use
/// (e.g. inside a custom field): pass [onSelected] and no field.
class StxAutocomplete<T> extends StatefulWidget {
  const StxAutocomplete({
    super.key,
    required this.source,
    this.field,
    this.label,
    this.hint,
    this.help,
    this.validation = UiFieldValidation.none,
    this.onSelected,
    this.clearOnSelect = false,
    this.debounce = const Duration(milliseconds: 250),
  });

  final StxDataSource<T> source;
  final StxField<T?>? field;
  final Msg? label;
  final Msg? hint;
  final Msg? help;
  final UiFieldValidation validation;
  final ValueChanged<StxOption<T>>? onSelected;

  /// Empty the input after a choice (for "add to list" use).
  final bool clearOnSelect;
  final Duration debounce;

  @override
  State<StxAutocomplete<T>> createState() => _StxAutocompleteState<T>();
}

class _StxAutocompleteState<T> extends State<StxAutocomplete<T>> {
  final _portal = OverlayPortalController();
  final _link = LayerLink();
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _timer;
  List<StxOption<T>> _options = const [];
  Problem? _problem;
  var _searching = false;
  var _highlight = 0;
  String? _selectedLabel;
  var _query = 0;
  double _width = 240;

  @override
  void initState() {
    super.initState();
    _focus.onKeyEvent = _onKey;
    _focus.addListener(() {
      if (!_focus.hasFocus) _portal.hide();
    });
    widget.field?.addListener(_pull);
  }

  // A reset from outside (the form) clears the shown choice; typing (which also clears the value)
  // does not, because the label no longer matches by then.
  void _pull() {
    if (widget.field?.value == null && _selectedLabel != null && _controller.text == _selectedLabel) {
      _selectedLabel = null;
      _controller.clear();
    }
  }

  void _onChanged(String text) {
    if (text == _selectedLabel) return;
    _selectedLabel = null;
    widget.field?.value = null;
    _timer?.cancel();
    if (text.trim().isEmpty) {
      setState(() => _options = const []);
      _portal.hide();
      return;
    }
    _timer = Timer(widget.debounce, () => _search(text.trim()));
  }

  Future<void> _search(String text) async {
    final query = ++_query;
    setState(() => _searching = true);
    _portal.show();
    final result = await widget.source.search(text);
    if (!mounted || query != _query) return; // a newer search started
    setState(() {
      _searching = false;
      _highlight = 0;
      switch (result) {
        case Ok(:final value):
          _options = value;
          _problem = null;
        case Err(:final error):
          _options = const [];
          _problem = error;
      }
    });
  }

  void _select(StxOption<T> option) {
    widget.field?.value = option.value;
    widget.onSelected?.call(option);
    _selectedLabel = widget.clearOnSelect ? null : option.label;
    final text = widget.clearOnSelect ? '' : option.label;
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _portal.hide();
    setState(() => _options = const []);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || !_portal.isShowing || _options.isEmpty) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        setState(() => _highlight = (_highlight + 1) % _options.length);
      case LogicalKeyboardKey.arrowUp:
        setState(() => _highlight = (_highlight - 1 + _options.length) % _options.length);
      case LogicalKeyboardKey.enter:
        _select(_options[_highlight]);
      case LogicalKeyboardKey.escape:
        _portal.hide();
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    widget.field?.removeListener(_pull);
    _timer?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget input(FieldError? error) => TapRegion(
      groupId: this,
      onTapOutside: (_) => _portal.hide(),
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) => _OptionsOverlay(
          link: _link,
          width: _width,
          group: this,
          children: [
            if (_searching && _options.isEmpty)
              _Option(text: context.msg(StxKeys.stateLoading), muted: true, selected: false, onPressed: null)
            else if (_problem != null)
              _Option(text: context.msg(problemMsg(_problem!)), muted: true, selected: false, onPressed: null)
            else if (_options.isEmpty)
              _Option(text: context.msg(StxKeys.fieldNoResults), muted: true, selected: false, onPressed: null)
            else
              for (var i = 0; i < _options.length; i++)
                _Option(text: _options[i].label, selected: i == _highlight, onPressed: () => _select(_options[i])),
          ],
        ),
        child: CompositedTransformTarget(
          link: _link,
          child: LayoutBuilder(
            builder: (context, constraints) {
              _width = constraints.maxWidth;
              return StxTextField(
                controller: _controller,
                focusNode: _focus,
                label: widget.label,
                hint: widget.hint ?? StxKeys.fieldSearch,
                help: widget.help,
                required: widget.validation.required,
                error: error == null ? null : fieldErrorMsg(error),
                onChanged: _onChanged,
                tapRegionGroup: this,
              );
            },
          ),
        ),
      ),
    );

    final field = widget.field;
    if (field == null) return input(null);
    return ListenableBuilder(listenable: field, builder: (context, _) => input(field.error));
  }
}
