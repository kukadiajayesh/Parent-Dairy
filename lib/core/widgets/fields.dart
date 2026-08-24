import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import 'app_icons.dart';
import 'stroke_icon.dart';

/// 12/600 caption above every input. Turns primary when the field is focused
/// or filled, error-red when the field is invalid ("05 — Inputs").
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key, this.emphasis = FieldEmphasis.neutral});

  final String text;
  final FieldEmphasis emphasis;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final color = switch (emphasis) {
      FieldEmphasis.neutral => k.tx3,
      FieldEmphasis.primary => k.pri,
      FieldEmphasis.error => k.err,
    };
    return Text(
      text,
      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
    );
  }
}

enum FieldEmphasis { neutral, primary, error }

/// Single-line text field with the design's 56dp filled-with-border treatment.
class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    required this.label,
    this.controller,
    this.hintText,
    this.helperText,
    this.errorText,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.sentences,
    this.maxLines = 1,
    this.minHeight = 56,
    this.onChanged,
  });

  final String label;
  final TextEditingController? controller;
  final String? hintText;
  final String? helperText;
  final String? errorText;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final int maxLines;
  final double minHeight;
  final ValueChanged<String>? onChanged;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  late final FocusNode _focus = FocusNode()..addListener(_onFocusChange);

  void _onFocusChange() => setState(() {});

  @override
  void dispose() {
    _focus
      ..removeListener(_onFocusChange)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final hasError = widget.errorText != null;
    final active = _focus.hasFocus || (widget.controller?.text.isNotEmpty ?? false);
    final border = hasError ? k.err : (active ? k.pri : k.bd3);
    final emphasis = hasError
        ? FieldEmphasis.error
        : (active ? FieldEmphasis.primary : FieldEmphasis.neutral);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(widget.label, emphasis: emphasis),
        const SizedBox(height: 6),
        Container(
          constraints: BoxConstraints(minHeight: widget.minHeight),
          padding: EdgeInsets.symmetric(
            horizontal: 16,
            vertical: widget.maxLines == 1 ? 0 : 14,
          ),
          alignment: widget.maxLines == 1 ? Alignment.centerLeft : null,
          decoration: BoxDecoration(
            color: hasError ? k.errC : k.surf2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border, width: 1.5),
          ),
          child: TextField(
            controller: widget.controller,
            focusNode: _focus,
            keyboardType: widget.keyboardType,
            textCapitalization: widget.textCapitalization,
            maxLines: widget.maxLines,
            minLines: widget.maxLines == 1 ? 1 : null,
            onChanged: widget.onChanged,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: hasError ? k.errInk : k.tx,
            ),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
              hintText: widget.hintText,
              hintStyle: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: k.tx6,
              ),
            ),
          ),
        ),
        if (widget.errorText != null || widget.helperText != null) ...[
          const SizedBox(height: 6),
          Text(
            widget.errorText ?? widget.helperText!,
            style: TextStyle(
              fontSize: 12,
              fontWeight: hasError ? FontWeight.w500 : FontWeight.w400,
              color: hasError ? k.err : k.tx4,
            ),
          ),
        ],
      ],
    );
  }
}

/// A field-shaped row that opens a picker instead of accepting typing — dates,
/// class, section, academic year.
class PickerField extends StatelessWidget {
  const PickerField({
    super.key,
    required this.label,
    required this.value,
    this.onTap,
    this.trailing = PickerTrailing.caret,
    this.isPlaceholder = false,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;
  final PickerTrailing trailing;
  final bool isPlaceholder;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FieldLabel(label),
        const SizedBox(height: 6),
        Material(
          color: k.surf2,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: k.bd3, width: 1.5),
          ),
          child: InkWell(
            onTap: onTap,
            child: Container(
              height: 56,
              padding: EdgeInsets.symmetric(
                horizontal: trailing == PickerTrailing.calendar ? 14 : 16,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      value,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: trailing == PickerTrailing.calendar ? 14.5 : 15,
                        fontWeight: FontWeight.w500,
                        color: isPlaceholder ? k.tx6 : k.tx,
                      ),
                    ),
                  ),
                  switch (trailing) {
                    PickerTrailing.caret =>
                      StrokeIcon(AppIcons.caretDown, size: 16, color: k.tx4),
                    PickerTrailing.calendar =>
                      StrokeIcon(AppIcons.calendar, size: 17, color: k.tx4),
                    PickerTrailing.none => const SizedBox.shrink(),
                  },
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

enum PickerTrailing { caret, calendar, none }

/// Pill switch matching the design's 52×30 (settings) / 48×28 (rows) toggles.
class AppSwitch extends StatelessWidget {
  const AppSwitch({
    super.key,
    required this.value,
    this.onChanged,
    this.width = 52,
    this.height = 30,
    this.activeColor,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final double width;
  final double height;
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final knob = height - 4;
    return GestureDetector(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        width: width,
        height: height,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: value ? (activeColor ?? k.secFill) : k.bd4,
          borderRadius: BorderRadius.circular(999),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: knob,
            height: knob,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}

