import 'package:flutter/widgets.dart';
import 'package:stx_core/stx_core.dart';
import 'package:stx_i18n/stx_i18n.dart';
import 'package:stx_style/stx_style.dart';

import '../form/field.dart';
import '../primitives/button.dart';
import '../primitives/layout.dart';
import '../primitives/pressable.dart';
import 'text_field.dart';

/// A month calendar: weekday names, month names and the first day of the week come from the
/// locale's CLDR data.
class StxCalendar extends StatefulWidget {
  const StxCalendar({super.key, required this.onSelected, this.selected, this.today});

  final DateTime? selected;
  final ValueChanged<DateTime> onSelected;

  /// For tests; defaults to now.
  final DateTime? today;

  @override
  State<StxCalendar> createState() => _StxCalendarState();
}

class _StxCalendarState extends State<StxCalendar> {
  late DateTime _month = DateTime((widget.selected ?? _today).year, (widget.selected ?? _today).month);

  DateTime get _today => widget.today ?? DateTime.now();

  void _shift(int months) => setState(() => _month = DateTime(_month.year, _month.month + months));

  static bool _sameDay(DateTime? a, DateTime b) =>
      a != null && a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final formats = context.formats;
    final first = formats.firstDayOfWeek;
    final lead = (_month.weekday - first + 7) % 7;
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    final cells = [
      for (var i = 0; i < lead; i++) null,
      for (var d = 1; d <= days; d++) DateTime(_month.year, _month.month, d),
    ];
    final cell = tokens.spacing(SpaceToken.xl) + tokens.spacing(SpaceToken.xs);
    return StxBox(
      padding: const StxInsets.all(SpaceToken.sm),
      child: SizedBox(
        width: cell * 7,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: tokens.spacing(SpaceToken.sm),
          children: [
            StxRow(
              children: [
                StxButton(
                  const Msg.data('‹'),
                  semanticLabel: StxKeys.calendarPreviousMonth,
                  variant: ButtonVariant.ghost,
                  onPressed: () => _shift(-1),
                ),
                Expanded(
                  child: StxText(
                    Msg.data('${formats.months[_month.month - 1]} ${_month.year}'),
                    style: TextToken.label,
                    align: TextAlign.center,
                  ),
                ),
                StxButton(
                  const Msg.data('›'),
                  semanticLabel: StxKeys.calendarNextMonth,
                  variant: ButtonVariant.ghost,
                  onPressed: () => _shift(1),
                ),
              ],
            ),
            Table(
              defaultColumnWidth: FixedColumnWidth(cell),
              children: [
                TableRow(
                  children: [
                    for (var i = 0; i < 7; i++)
                      SizedBox(
                        height: cell * 0.8,
                        child: Center(
                          child: StxText(
                            Msg.data(formats.weekdaysShort[(first - 1 + i) % 7]),
                            style: TextToken.caption,
                            color: ColorToken.muted,
                          ),
                        ),
                      ),
                  ],
                ),
                for (var row = 0; row * 7 < cells.length; row++)
                  TableRow(
                    children: [
                      for (var col = 0; col < 7; col++)
                        switch (row * 7 + col < cells.length ? cells[row * 7 + col] : null) {
                          final day? => _Day(
                            day: day,
                            size: cell,
                            selected: _sameDay(widget.selected, day),
                            today: _sameDay(_today, day),
                            onPressed: () => widget.onSelected(day),
                          ),
                          null => SizedBox.square(dimension: cell),
                        },
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Day extends StatelessWidget {
  const _Day({
    required this.day,
    required this.size,
    required this.selected,
    required this.today,
    required this.onPressed,
  });

  final DateTime day;
  final double size;
  final bool selected;
  final bool today;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return StxPressable(
      onPressed: onPressed,
      radius: RadiusToken.md,
      semanticLabel: context.formats.date(day, DateStyle.full),
      builder: (context, state) => SizedBox.square(
        dimension: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: selected
                ? tokens.color(ColorToken.primary)
                : (state.hovered ? tokens.color(ColorToken.secondary) : null),
            border: today && !selected ? Border.all(color: tokens.color(ColorToken.border)) : null,
            borderRadius: BorderRadius.circular(tokens.corner(RadiusToken.md)),
          ),
          child: Center(
            child: Text(
              '${day.day}',
              style: context.textStyle(
                TextToken.body,
                color: selected ? ColorToken.onPrimary : ColorToken.onBackground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A text input with a calendar popover, shared by [StxFormDate] and [StxFormDateTime].
class _DateInput extends StatefulWidget {
  const _DateInput({
    required this.label,
    required this.help,
    required this.required,
    required this.error,
    required this.withTime,
    required this.value,
    required this.onChanged,
    required this.clock,
  });

  final Msg label;
  final Msg? help;
  final bool required;
  final FieldError? error;
  final bool withTime;
  final DateTime? value;

  /// The parsed value, or null; the flag says whether the text is invalid (not just empty).
  final void Function(DateTime? value, {required bool invalid}) onChanged;
  final DateTime Function() clock;

  @override
  State<_DateInput> createState() => _DateInputState();
}

class _DateInputState extends State<_DateInput> {
  final _controller = TextEditingController();
  final _portal = OverlayPortalController();
  final _link = LayerLink();
  StxLocaleFormats? _formats;
  var _invalid = false;

  StxLocaleFormats get formats => _formats!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = context.formats;
    if (!identical(next, _formats)) {
      _formats = next;
      _show(widget.value); // re-render in the new locale's format
    }
  }

  @override
  void didUpdateWidget(_DateInput old) {
    super.didUpdateWidget(old);
    // A value set from outside (reset, calendar) replaces the text; typing does not.
    if (widget.value != _parse(_controller.text) && !(widget.value == null && _invalid)) _show(widget.value);
  }

  String _format(DateTime v) => widget.withTime ? formats.inputDateTime(v) : formats.inputDate(v);

  DateTime? _parse(String text) => widget.withTime ? formats.parseInputDateTime(text) : formats.parseInputDate(text);

  void _show(DateTime? value) {
    final text = value == null ? '' : _format(value);
    if (_controller.text != text) {
      _controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
  }

  void _typed(String text) {
    final parsed = _parse(text);
    final invalid = text.trim().isNotEmpty && parsed == null;
    setState(() => _invalid = invalid);
    widget.onChanged(parsed, invalid: invalid);
  }

  void _picked(DateTime day) {
    final current = widget.value ?? widget.clock();
    final value = widget.withTime ? DateTime(day.year, day.month, day.day, current.hour, current.minute) : day;
    _portal.hide();
    setState(() => _invalid = false);
    _show(value);
    widget.onChanged(value, invalid: false);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final example = DateTime(2026, 12, 31, 18, 30);
    final error = _invalid ? FieldError.format(widget.withTime ? UiFormat.dateTime : UiFormat.date) : widget.error;
    return TapRegion(
      groupId: this,
      onTapOutside: (_) => _portal.hide(),
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (context) => CompositedTransformFollower(
          link: _link,
          targetAnchor: Alignment.bottomRight,
          followerAnchor: Alignment.topRight,
          offset: Offset(0, tokens.spacing(SpaceToken.xs)),
          child: Align(
            alignment: Alignment.topRight,
            child: TapRegion(
              groupId: this,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: tokens.color(ColorToken.background),
                  border: Border.all(color: tokens.color(ColorToken.border)),
                  borderRadius: BorderRadius.circular(tokens.corner(RadiusToken.lg)),
                  boxShadow: [
                    BoxShadow(color: tokens.color(ColorToken.onBackground).withValues(alpha: 0.12), blurRadius: 12),
                  ],
                ),
                child: StxCalendar(selected: widget.value, today: widget.clock(), onSelected: _picked),
              ),
            ),
          ),
        ),
        child: CompositedTransformTarget(
          link: _link,
          child: StxTextField(
            controller: _controller,
            label: widget.label,
            hint: Msg.data(_format(example)),
            help: widget.help,
            error: error == null ? null : fieldErrorMsg(error),
            required: widget.required,
            keyboardType: TextInputType.datetime,
            onChanged: _typed,
            tapRegionGroup: this,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.withTime)
                  StxButton(
                    StxKeys.fieldNow,
                    variant: ButtonVariant.ghost,
                    onPressed: () {
                      final now = widget.clock();
                      final value = DateTime(now.year, now.month, now.day, now.hour, now.minute);
                      _show(value);
                      setState(() => _invalid = false);
                      widget.onChanged(value, invalid: false);
                    },
                  ),
                StxButton(StxKeys.calendarOpen, variant: ButtonVariant.ghost, onPressed: _portal.toggle),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A date-time input bound to a `StxField<DateTime?>`: typed in the locale's numeric date order
/// plus `HH:mm`, or picked from the calendar.
class StxFormDateTime extends StatelessWidget {
  const StxFormDateTime({
    super.key,
    required this.field,
    required this.label,
    this.help,
    this.validation = UiFieldValidation.none,
    this.clock = DateTime.now,
  });

  final StxField<DateTime?> field;
  final Msg label;
  final Msg? help;
  final UiFieldValidation validation;
  final DateTime Function() clock;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: field,
    builder: (context, _) => _DateInput(
      label: label,
      help: help,
      required: validation.required,
      error: field.error,
      withTime: true,
      value: field.value,
      clock: clock,
      onChanged: (value, {required invalid}) => field.value = value,
    ),
  );
}

/// A date input bound to a `StxField<LocalDate?>`.
class StxFormDate extends StatelessWidget {
  const StxFormDate({
    super.key,
    required this.field,
    required this.label,
    this.help,
    this.validation = UiFieldValidation.none,
    this.clock = DateTime.now,
  });

  final StxField<LocalDate?> field;
  final Msg label;
  final Msg? help;
  final UiFieldValidation validation;
  final DateTime Function() clock;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: field,
    builder: (context, _) => _DateInput(
      label: label,
      help: help,
      required: validation.required,
      error: field.error,
      withTime: false,
      value: switch (field.value) {
        final d? => DateTime(d.year, d.month, d.day),
        null => null,
      },
      clock: clock,
      onChanged: (value, {required invalid}) => field.value = value == null ? null : LocalDate.fromDateTime(value),
    ),
  );
}
