import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';

/// "−  [ 25 ]  +": type any whole number between [min] and [max], or nudge
/// it by [step] with the buttons.
///
/// A valid number is applied while typing. Leaving the box (or pressing
/// Done) puts an out-of-range number back in range, and an empty box back to
/// the last good value.
class NumberField extends StatefulWidget {
  const NumberField({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.step = 1,
    this.label,
    this.compact = false,
  });

  final int value;
  final int min;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;

  /// Read out by screen readers, e.g. "Focus minutes".
  final String? label;

  /// Smaller buttons and box, for dense settings lists.
  final bool compact;

  @override
  State<NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends State<NumberField> {
  late final _text = TextEditingController(text: '${widget.value}');
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus && mounted) _commit();
    });
  }

  @override
  void didUpdateWidget(NumberField old) {
    super.didUpdateWidget(old);
    // Follow outside changes (buttons, "Reset"), but never while typing.
    if (!_focus.hasFocus && _text.text != '${widget.value}') {
      _text.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  int _clamp(int v) =>
      v < widget.min ? widget.min : (v > widget.max ? widget.max : v);

  void _typed(String s) {
    final v = int.tryParse(s);
    if (v != null && v >= widget.min && v <= widget.max && v != widget.value) {
      widget.onChanged(v);
    }
  }

  void _commit() {
    final v = int.tryParse(_text.text);
    final next = v == null ? widget.value : _clamp(v);
    if (next != widget.value) widget.onChanged(next);
    _text.text = '$next';
  }

  void _nudge(int by) {
    _focus.unfocus();
    final next = _clamp(widget.value + by);
    _text.text = '$next';
    if (next != widget.value) widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final compact = widget.compact;
    Widget button(IconData icon, String tip, VoidCallback? onTap) => IconButton(
          tooltip: tip,
          onPressed: onTap,
          // Compact uses exact 30px circles (no density shrink).
          visualDensity:
              compact ? VisualDensity.standard : VisualDensity.compact,
          padding: compact ? EdgeInsets.zero : null,
          constraints: compact
              ? const BoxConstraints.tightFor(width: 30, height: 30)
              : null,
          style: IconButton.styleFrom(
            backgroundColor: AppColors.primarySoft,
            disabledBackgroundColor: AppColors.background,
          ),
          icon: Icon(icon,
              size: compact ? 14 : 18,
              color: onTap == null
                  ? AppColors.textMuted
                  : AppColors.primaryDeep),
        );

    final digits = '${widget.max}'.length;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        button(AppIcons.minus, 'Less',
            widget.value > widget.min ? () => _nudge(-widget.step) : null),
        SizedBox(width: compact ? 5 : 6),
        SizedBox(
          width: compact ? 42 : 56,
          child: Semantics(
            label: widget.label,
            child: TextField(
              controller: _text,
              focusNode: _focus,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(digits),
              ],
              onChanged: _typed,
              onSubmitted: (_) => _commit(),
              onTapOutside: (_) => _focus.unfocus(),
              style: AppText.statValue.copyWith(fontSize: compact ? 13.5 : 16),
              decoration: InputDecoration(
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(vertical: compact ? 6 : 8),
                filled: true,
                fillColor: AppColors.surface,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(compact ? 8 : 10),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(compact ? 8 : 10),
                  borderSide:
                      BorderSide(color: AppColors.primaryDeep, width: 1.5),
                ),
              ),
            ),
          ),
        ),
        SizedBox(width: compact ? 5 : 6),
        button(AppIcons.add, 'More',
            widget.value < widget.max ? () => _nudge(widget.step) : null),
      ],
    );
  }
}
