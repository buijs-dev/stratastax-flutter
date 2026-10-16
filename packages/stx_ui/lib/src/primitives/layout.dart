import 'package:flutter/widgets.dart';
import 'package:stx_i18n/stx_i18n.dart';
import 'package:stx_style/stx_style.dart';

/// Padding in spacing tokens.
@immutable
final class StxInsets {
  const StxInsets.all(SpaceToken value) : this.only(left: value, top: value, right: value, bottom: value);

  const StxInsets.symmetric({SpaceToken x = SpaceToken.none, SpaceToken y = SpaceToken.none})
    : this.only(left: x, top: y, right: x, bottom: y);

  const StxInsets.only({
    this.left = SpaceToken.none,
    this.top = SpaceToken.none,
    this.right = SpaceToken.none,
    this.bottom = SpaceToken.none,
  });

  static const none = StxInsets.all(SpaceToken.none);

  final SpaceToken left;
  final SpaceToken top;
  final SpaceToken right;
  final SpaceToken bottom;

  EdgeInsets resolve(StxTokens tokens) =>
      EdgeInsets.fromLTRB(tokens.spacing(left), tokens.spacing(top), tokens.spacing(right), tokens.spacing(bottom));
}

/// A container styled only through tokens.
class StxBox extends StatelessWidget {
  const StxBox({
    super.key,
    this.padding = StxInsets.none,
    this.background,
    this.border,
    this.radius = RadiusToken.none,
    this.child,
  });

  final StxInsets padding;
  final ColorToken? background;
  final ColorToken? border;
  final RadiusToken radius;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final corner = tokens.corner(radius);
    final content = Padding(padding: padding.resolve(tokens), child: child);
    if (background == null && border == null) return content;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background == null ? null : tokens.color(background!),
        border: border == null ? null : Border.all(color: tokens.color(border!)),
        borderRadius: corner == 0 ? null : BorderRadius.circular(corner),
      ),
      child: content,
    );
  }
}

/// Text in a token style. Takes a [Msg], never a `String`.
class StxText extends StatelessWidget {
  const StxText(
    this.text, {
    super.key,
    this.style = TextToken.body,
    this.color = ColorToken.onBackground,
    this.align,
    this.maxLines,
    this.overflow,
  });

  final Msg text;
  final TextToken style;
  final ColorToken color;
  final TextAlign? align;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) => Text(
    context.msg(text),
    style: context.textStyle(style, color: color),
    textAlign: align,
    maxLines: maxLines,
    overflow: overflow ?? (maxLines == null ? null : TextOverflow.ellipsis),
  );
}

/// A row with a token gap between children.
class StxRow extends StatelessWidget {
  const StxRow({
    super.key,
    required this.children,
    this.gap = SpaceToken.none,
    this.main = MainAxisAlignment.start,
    this.cross = CrossAxisAlignment.center,
    this.mainAxisSize = MainAxisSize.max,
  });

  final List<Widget> children;
  final SpaceToken gap;
  final MainAxisAlignment main;
  final CrossAxisAlignment cross;
  final MainAxisSize mainAxisSize;

  @override
  Widget build(BuildContext context) => Row(
    spacing: context.tokens.spacing(gap),
    mainAxisAlignment: main,
    crossAxisAlignment: cross,
    mainAxisSize: mainAxisSize,
    children: children,
  );
}

/// A column with a token gap between children.
class StxColumn extends StatelessWidget {
  const StxColumn({
    super.key,
    required this.children,
    this.gap = SpaceToken.none,
    this.main = MainAxisAlignment.start,
    this.cross = CrossAxisAlignment.stretch,
    this.mainAxisSize = MainAxisSize.max,
  });

  final List<Widget> children;
  final SpaceToken gap;
  final MainAxisAlignment main;
  final CrossAxisAlignment cross;
  final MainAxisSize mainAxisSize;

  @override
  Widget build(BuildContext context) => Column(
    spacing: context.tokens.spacing(gap),
    mainAxisAlignment: main,
    crossAxisAlignment: cross,
    mainAxisSize: mainAxisSize,
    children: children,
  );
}
