import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import '../theme/subject_hue.dart';
import 'pressable.dart';

/// Pill chip used for subject pickers, list filters and state selectors.
/// Selected chips take a tinted fill with a matching border; unselected chips
/// sit on the surface with a neutral border.
class AppChip extends StatelessWidget {
  const AppChip({
    super.key,
    required this.label,
    required this.selected,
    this.onTap,
    this.selectedBackground,
    this.selectedBorder,
    this.selectedForeground,
    this.fontSize = 13,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final Color? selectedBackground;
  final Color? selectedBorder;
  final Color? selectedForeground;
  final double fontSize;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final bg = selected ? (selectedBackground ?? k.priFill) : k.surf;
    final border = selected ? (selectedBorder ?? k.priFill) : k.bd3;
    final ink = selected ? (selectedForeground ?? k.surf) : k.tx3;

    return PressDip(
      child: Material(
        color: bg,
        shape: StadiumBorder(side: BorderSide(color: border, width: 1.5)),
        clipBehavior: Clip.antiAlias,
        child: AppInkWell(
          onTap: onTap,
          // A chip picks a value, and both platforms buzz for that natively.
          haptic: true,
          child: Padding(
            padding: padding,
            child: Text(
              label,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
                color: ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Subject chip in its selected/unselected form — the hue is fixed per subject
/// so the same colour identifies it everywhere ("02 — Subject tags").
class SubjectChip extends StatelessWidget {
  const SubjectChip({
    super.key,
    required this.name,
    required this.hue,
    required this.selected,
    this.onTap,
    this.fontSize = 13,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
  });

  final String name;
  final SubjectHue hue;
  final bool selected;
  final VoidCallback? onTap;
  final double fontSize;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    return AppChip(
      label: name,
      selected: selected,
      onTap: onTap,
      fontSize: fontSize,
      padding: padding,
      selectedBackground: hue.tint(k),
      selectedBorder: hue.dot(k),
      selectedForeground: hue.ink(k),
    );
  }
}

/// Filled subject tag with a leading dot — used on detail headers and cards.
class SubjectTag extends StatelessWidget {
  const SubjectTag({super.key, required this.name, required this.hue});

  final String name;
  final SubjectHue hue;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
      decoration: BoxDecoration(
        color: hue.tint(k),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Dot(color: hue.dot(k), size: 9),
          const SizedBox(width: 7),
          Text(
            name,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: hue.ink(k),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small status pill: "Pending", "Completed", "3 photos", "2 attachments".
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
    this.dotColor,
    this.leading,
    this.fontSize = 11.5,
    this.radius = 8,
  });

  final String label;
  final Color background;
  final Color foreground;
  final Color? dotColor;
  final Widget? leading;
  final double fontSize;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 9, vertical: fontSize > 11.5 ? 5 : 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dotColor != null) ...[
            Dot(color: dotColor!, size: 6),
            const SizedBox(width: 5),
          ] else if (leading != null) ...[
            leading!,
            const SizedBox(width: 5),
          ],
          // Loose flex in a min-sized Row is legal under unbounded width (a
          // Wrap), and lets the pill ellipsise when a bounded parent squeezes it.
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w700,
                color: foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class Dot extends StatelessWidget {
  const Dot({super.key, required this.color, this.size = 9});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// Circular monogram avatar — child switcher, account row, children list.
class Monogram extends StatelessWidget {
  const Monogram({
    super.key,
    required this.initials,
    this.size = 40,
    this.fontSize = 15,
    this.background,
    this.foreground,
  });

  final String initials;
  final double size;
  final double fontSize;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background ?? k.priC,
        shape: BoxShape.circle,
      ),
      child: Text(
        initials,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          color: foreground ?? k.priInk,
        ),
      ),
    );
  }
}

/// Rounded-square subject badge showing the two-letter code.
class SubjectBadge extends StatelessWidget {
  const SubjectBadge({
    super.key,
    required this.abbr,
    required this.hue,
    this.size = 38,
    this.fontSize = 12,
    this.radius = 12,
  });

  final String abbr;
  final SubjectHue hue;
  final double size;
  final double fontSize;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: hue.tint(k),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Text(
        abbr,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w800,
          color: hue.ink(k),
        ),
      ),
    );
  }
}

/// Multi-select chip row: every option is on screen and toggles in place, the
/// same interaction the subject picker uses. Chosen over a "Select …" field
/// that opens a sheet — with a short, fixed option list (chapters) the sheet
/// is a round trip for no extra information.
class MultiSelectChips extends StatelessWidget {
  const MultiSelectChips({
    super.key,
    required this.options,
    required this.selected,
    required this.onToggle,
  });

  final List<String> options;
  final List<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in options)
          AppChip(
            label: option,
            selected: selected.contains(option),
            onTap: () => onToggle(option),
          ),
      ],
    );
  }
}
