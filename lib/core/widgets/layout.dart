import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import 'app_icons.dart';
import 'buttons.dart';
import 'stroke_icon.dart';

/// 11/700 uppercase section heading with 1.2px tracking ("Overline").
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final label = Text(
      text.toUpperCase(),
      style: AppText.overline.copyWith(color: k.tx4),
    );
    if (trailing == null) return label;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [label, trailing!],
    );
  }
}

/// "View all" affordance next to a [SectionLabel].
class SectionAction extends StatelessWidget {
  const SectionAction({super.key, required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: k.pri,
          ),
        ),
      ),
    );
  }
}

/// Card surface used by every list row and record card: white/`surf` fill,
/// 1dp `bd` border, and the design's whisper-soft shadow.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(14),
    this.radius = 20,
    this.background,
    this.borderColor,
    this.shadow = false,
    this.clip = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? background;
  final Color? borderColor;
  final bool shadow;
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: BorderSide(color: borderColor ?? k.bd),
    );

    Widget card = Material(
      color: background ?? k.surf,
      shape: shape,
      clipBehavior: clip || onTap != null ? Clip.antiAlias : Clip.none,
      child: onTap == null
          ? Padding(padding: padding, child: child)
          : InkWell(
              onTap: onTap,
              hoverColor: k.hov2,
              child: Padding(padding: padding, child: child),
            ),
    );

    if (shadow) {
      card = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF1F1B16).withValues(alpha: .05),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: card,
      );
    }
    return card;
  }
}

/// Back-chevron + title header used by every pushed screen.
class ScreenHeader extends StatelessWidget implements PreferredSizeWidget {
  const ScreenHeader({
    super.key,
    this.title,
    this.onBack,
    this.actions = const [],
    this.leadingIsClose = false,
    this.subtitle,
  });

  final String? title;
  final String? subtitle;
  final VoidCallback? onBack;
  final List<Widget> actions;
  final bool leadingIsClose;

  @override
  Size get preferredSize => const Size.fromHeight(52);

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          AppIconButton(
            onTap: onBack ?? () => Navigator.of(context).maybePop(),
            tooltip: leadingIsClose ? 'Close' : 'Back',
            child: StrokeIcon(
              leadingIsClose ? AppIcons.close : AppIcons.back,
              size: 22,
              color: k.tx,
            ),
          ),
          const SizedBox(width: 8),
          if (title != null)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title!,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.titleLarge.copyWith(color: k.tx),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: k.tx4,
                      ),
                    ),
                ],
              ),
            )
          else
            const Spacer(),
          ...actions,
        ],
      ),
    );
  }
}

/// Sticky bottom action bar: `border-top`, page background, safe-area aware.
class StickyFooter extends StatelessWidget {
  const StickyFooter({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    return Container(
      decoration: BoxDecoration(
        color: k.bg,
        border: Border(top: BorderSide(color: k.bd2)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        14,
        20,
        18 + MediaQuery.viewPaddingOf(context).bottom,
      ),
      child: child,
    );
  }
}

/// Horizontal rule matching `height:1px;background:var(--bd)`.
class HairLine extends StatelessWidget {
  const HairLine({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) =>
      Container(height: 1, color: color ?? context.t.bd);
}

/// Grouped settings list: one rounded card, hairline-separated rows.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i != children.length - 1) {
        rows.add(Container(height: 1, color: k.surf3));
      }
    }
    return Container(
      decoration: BoxDecoration(
        color: k.surf,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: k.bd),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: rows),
    );
  }
}

class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.label,
    this.subtitle,
    this.value,
    this.trailing,
    this.onTap,
    this.showChevron = true,
    this.labelColor,
    this.leading,
    this.hoverColor,
  });

  final String label;
  final String? subtitle;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showChevron;
  final Color? labelColor;
  final Widget? leading;
  final Color? hoverColor;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        hoverColor: hoverColor ?? k.bg,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          child: Row(
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 10)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: labelColor != null
                            ? FontWeight.w700
                            : FontWeight.w600,
                        color: labelColor ?? k.tx,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(fontSize: 12, color: k.tx4),
                      ),
                    ],
                  ],
                ),
              ),
              if (value != null) ...[
                const SizedBox(width: 12),
                Text(value!, style: TextStyle(fontSize: 12.5, color: k.tx4)),
              ],
              if (trailing != null) ...[const SizedBox(width: 12), trailing!],
              if (showChevron) ...[
                const SizedBox(width: 12),
                StrokeIcon(AppIcons.forward, size: 17, color: k.tx5),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
