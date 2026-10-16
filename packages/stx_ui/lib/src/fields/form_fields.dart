import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:stx_core/stx_core.dart';
import 'package:stx_i18n/stx_i18n.dart';
import 'package:stx_style/stx_style.dart';

import '../form/field.dart';
import '../primitives/pressable.dart';
import 'field_frame.dart';
import 'text_field.dart';

/// Base of custom field widgets (`@UiFieldWidget`). The compiler checks that [T] matches the type
/// of the field it is used for.
abstract class StxFieldWidget<T> extends StatelessWidget {
  const StxFieldWidget({super.key, required this.field, required this.label, this.validation = UiFieldValidation.none});

  final StxField<T> field;
  final Msg label;
  final UiFieldValidation validation;
}

/// Rebuilds when [field] changes.
class StxFieldBuilder<T> extends StatelessWidget {
  const StxFieldBuilder({super.key, required this.field, required this.builder});

  final StxField<T> field;
  final Widget Function(BuildContext context, T value) builder;

  @override
  Widget build(BuildContext context) =>
      ListenableBuilder(listenable: field, builder: (context, _) => builder(context, field.value));
}

/// A text input bound to a `StxField<String?>`; empty text is `null`.
class StxFormText extends StatefulWidget {
  const StxFormText({
    super.key,
    required this.field,
    required this.label,
    this.hint,
    this.help,
    this.validation = UiFieldValidation.none,
    this.multiline = false,
    this.obscure = false,
    this.keyboardType,
  });

  final StxField<String?> field;
  final Msg label;
  final Msg? hint;
  final Msg? help;
  final UiFieldValidation validation;
  final bool multiline;
  final bool obscure;
  final TextInputType? keyboardType;

  @override
  State<StxFormText> createState() => _StxFormTextState();
}

class _StxFormTextState extends State<StxFormText> {
  late final _controller = TextEditingController(text: widget.field.value ?? '');

  @override
  void initState() {
    super.initState();
    _controller.addListener(_push);
    widget.field.addListener(_pull);
  }

  void _push() => widget.field.value = _controller.text.isEmpty ? null : _controller.text;

  void _pull() {
    final text = widget.field.value ?? '';
    if (_controller.text != text) _controller.text = text;
  }

  @override
  void dispose() {
    widget.field.removeListener(_pull);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.field,
    builder: (context, _) => StxTextField(
      controller: _controller,
      label: widget.label,
      hint: widget.hint,
      help: widget.help,
      error: widget.field.error == null ? null : fieldErrorMsg(widget.field.error!),
      required: widget.validation.required,
      obscure: widget.obscure,
      minLines: widget.multiline ? 3 : 1,
      maxLines: widget.multiline ? 8 : 1,
      keyboardType:
          widget.keyboardType ?? (widget.validation.format == UiFormat.email ? TextInputType.emailAddress : null),
      inputFormatters: [if (widget.validation.maxLength case final max?) LengthLimitingTextInputFormatter(max)],
    ),
  );
}

/// A number input bound to a `StxField<int?>` or `StxField<double?>`.
class StxFormNumber<T extends num> extends StatefulWidget {
  const StxFormNumber({
    super.key,
    required this.field,
    required this.label,
    this.hint,
    this.help,
    this.validation = UiFieldValidation.none,
  });

  final StxField<T?> field;
  final Msg label;
  final Msg? hint;
  final Msg? help;
  final UiFieldValidation validation;

  @override
  State<StxFormNumber<T>> createState() => _StxFormNumberState<T>();
}

class _StxFormNumberState<T extends num> extends State<StxFormNumber<T>> {
  late final _controller = TextEditingController(text: widget.field.value?.toString() ?? '');
  bool get _integer => T == int;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_push);
    widget.field.addListener(_pull);
  }

  num? _parse(String text) => _integer ? int.tryParse(text.trim()) : double.tryParse(text.trim().replaceAll(',', '.'));

  void _push() => widget.field.value = _parse(_controller.text) as T?;

  // A reset from outside (the form) empties the input; typing an invalid number does not.
  void _pull() {
    if (widget.field.value == null && _parse(_controller.text) != null) _controller.clear();
  }

  @override
  void dispose() {
    widget.field.removeListener(_pull);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.field,
    builder: (context, _) => StxTextField(
      controller: _controller,
      label: widget.label,
      hint: widget.hint,
      help: widget.help,
      error: widget.field.error == null ? null : fieldErrorMsg(widget.field.error!),
      required: widget.validation.required,
      keyboardType: TextInputType.numberWithOptions(decimal: !_integer, signed: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(_integer ? r'[-0-9]' : r'[-0-9.,]'))],
    ),
  );
}

/// A checkbox bound to a `StxField<bool?>` (null shows unchecked).
class StxFormCheckbox extends StatelessWidget {
  const StxFormCheckbox({super.key, required this.field, required this.label, this.help});

  final StxField<bool?> field;
  final Msg label;
  final Msg? help;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: field,
    builder: (context, _) {
      final tokens = context.tokens;
      final checked = field.value ?? false;
      return StxFieldFrame(
        help: help,
        error: field.error == null ? null : fieldErrorMsg(field.error!),
        child: StxPressable(
          toggled: checked,
          onPressed: () => field.value = !checked,
          radius: RadiusToken.sm,
          builder: (context, state) => Row(
            spacing: tokens.spacing(SpaceToken.sm),
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: tokens.color(checked ? ColorToken.primary : tokens.field.background),
                  border: Border.all(color: tokens.color(checked ? ColorToken.primary : tokens.field.border), width: 2),
                  borderRadius: BorderRadius.circular(tokens.corner(RadiusToken.sm)),
                ),
                child: SizedBox.square(
                  dimension: 20,
                  child: checked ? CustomPaint(painter: _CheckPainter(tokens.color(ColorToken.onPrimary))) : null,
                ),
              ),
              Flexible(child: Text(context.msg(label), style: context.textStyle(tokens.field.text))),
            ],
          ),
        ),
      );
    },
  );
}

class _CheckPainter extends CustomPainter {
  _CheckPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * 0.22, size.height * 0.52)
      ..lineTo(size.width * 0.42, size.height * 0.72)
      ..lineTo(size.width * 0.78, size.height * 0.3);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_CheckPainter old) => old.color != color;
}
