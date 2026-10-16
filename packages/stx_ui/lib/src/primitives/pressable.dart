import 'package:flutter/widgets.dart';
import 'package:stx_style/stx_style.dart';

/// Interaction state passed to [StxPressable.builder].
@immutable
final class PressState {
  const PressState({required this.hovered, required this.pressed, required this.focused, required this.enabled});

  final bool hovered;
  final bool pressed;

  /// Keyboard focus that should be visible (not set for pointer focus).
  final bool focused;
  final bool enabled;
}

/// The interactive base of buttons, options and toggles: tap, Enter/Space, hover, focus
/// traversal, semantics and a pointer cursor. Draws a token focus ring on keyboard focus.
class StxPressable extends StatefulWidget {
  const StxPressable({
    super.key,
    required this.onPressed,
    required this.builder,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
    this.radius = RadiusToken.md,
    this.toggled,
  });

  final VoidCallback? onPressed;
  final Widget Function(BuildContext context, PressState state) builder;
  final FocusNode? focusNode;
  final bool autofocus;
  final String? semanticLabel;

  /// Corner radius of the focus ring.
  final RadiusToken radius;

  /// For checkboxes and toggles: exposed to semantics.
  final bool? toggled;

  @override
  State<StxPressable> createState() => _StxPressableState();
}

class _StxPressableState extends State<StxPressable> {
  var _hovered = false;
  var _pressed = false;
  var _focused = false;

  bool get _enabled => widget.onPressed != null;

  late final Map<Type, Action<Intent>> _actions = {
    ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onPressed?.call()),
  };

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final focus = tokens.focus;
    final state = PressState(hovered: _hovered, pressed: _pressed, focused: _focused, enabled: _enabled);
    final corner = tokens.corner(widget.radius) + focus.offset;
    return Semantics(
      button: widget.toggled == null,
      toggled: widget.toggled,
      enabled: _enabled,
      label: widget.semanticLabel,
      child: FocusableActionDetector(
        enabled: _enabled,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        actions: _actions,
        mouseCursor: _enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
          onTapCancel: _enabled ? () => setState(() => _pressed = false) : null,
          onTapUp: _enabled ? (_) => setState(() => _pressed = false) : null,
          onTap: widget.onPressed,
          child: CustomPaint(
            foregroundPainter: _focused
                ? _RingPainter(
                    color: tokens.color(focus.color),
                    width: focus.width,
                    offset: focus.offset,
                    radius: corner,
                  )
                : null,
            child: widget.builder(context, state),
          ),
        ),
      ),
    );
  }
}

/// The keyboard focus indicator around a widget, from the `focus` tokens.
class StxFocusRing extends StatelessWidget {
  const StxFocusRing({super.key, required this.visible, required this.child, this.radius = RadiusToken.md});

  final bool visible;
  final RadiusToken radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!visible) return child;
    final tokens = context.tokens;
    final focus = tokens.focus;
    return CustomPaint(
      foregroundPainter: _RingPainter(
        color: tokens.color(focus.color),
        width: focus.width,
        offset: focus.offset,
        radius: tokens.corner(radius) + focus.offset,
      ),
      child: child,
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.color, required this.width, required this.offset, required this.radius});

  final Color color;
  final double width;
  final double offset;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).inflate(offset + width / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.color != color || old.width != width || old.offset != offset || old.radius != radius;
}
