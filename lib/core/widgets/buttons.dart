import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Filled 52dp action button — style guide "04 — Buttons", primary variant.
class AppFilledButton extends StatelessWidget {
  const AppFilledButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.color,
    this.hoverColor,
    this.foreground,
    this.height = 52,
    this.elevated = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final Color? color;
  final Color? hoverColor;
  final Color? foreground;
  final double height;
  final bool elevated;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final bg = color ?? k.priFill;
    return _PressableSurface(
      height: height,
      onTap: onPressed,
      background: bg,
      hoverBackground: hoverColor ?? k.priFillH,
      borderRadius: BorderRadius.circular(16),
      shadow: elevated
          ? [
              BoxShadow(
                color: const Color(0xFF1F1B16).withValues(alpha: .18),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ]
          : null,
      child: _Label(
        label: label,
        icon: icon,
        color: foreground ?? Colors.white,
        fontSize: 15,
      ),
    );
  }
}

/// Tonal button — filled with a container colour rather than the brand colour.
class AppTonalButton extends StatelessWidget {
  const AppTonalButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    required this.background,
    required this.hoverBackground,
    required this.foreground,
    this.height = 52,
    this.fontSize = 15,
    this.borderRadius = 16,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final Color background;
  final Color hoverBackground;
  final Color foreground;
  final double height;
  final double fontSize;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return _PressableSurface(
      height: height,
      onTap: onPressed,
      background: background,
      hoverBackground: hoverBackground,
      borderRadius: BorderRadius.circular(borderRadius),
      child: _Label(
        label: label,
        icon: icon,
        color: foreground,
        fontSize: fontSize,
      ),
    );
  }
}

/// Outlined button — 1.5dp border, primary label, transparent fill.
class AppOutlinedButton extends StatelessWidget {
  const AppOutlinedButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.height = 52,
    this.borderRadius = 16,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    return _PressableSurface(
      height: height,
      onTap: onPressed,
      background: Colors.transparent,
      hoverBackground: k.surf2,
      border: Border.all(color: k.bd5, width: 1.5),
      borderRadius: BorderRadius.circular(borderRadius),
      child: _Label(label: label, icon: icon, color: k.pri, fontSize: 15),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label({
    required this.label,
    required this.color,
    required this.fontSize,
    this.icon,
  });

  final String label;
  final Widget? icon;
  final Color color;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final text = Text(
      label,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
        color: color,
      ),
    );
    if (icon == null) return text;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconTheme(data: IconThemeData(color: color), child: icon!),
        const SizedBox(width: 9),
        text,
      ],
    );
  }
}

/// Shared tap surface: the design expresses interaction as a hover background
/// swap, so we render a ripple over the resting colour and keep the geometry.
class _PressableSurface extends StatelessWidget {
  const _PressableSurface({
    required this.child,
    required this.background,
    required this.hoverBackground,
    required this.borderRadius,
    this.height,
    this.onTap,
    this.border,
    this.shadow,
  });

  final Widget child;
  final Color background;
  final Color hoverBackground;
  final BorderRadius borderRadius;
  final double? height;
  final VoidCallback? onTap;
  final BoxBorder? border;
  final List<BoxShadow>? shadow;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : .5,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: enabled ? shadow : null,
        ),
        child: Material(
          color: background,
          // Material accepts `shape` or `borderRadius`, never both — the shape
          // carries the same radius plus the border when one is requested.
          shape: RoundedRectangleBorder(
            borderRadius: borderRadius,
            side: border == null ? BorderSide.none : (border! as Border).top,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            hoverColor: hoverBackground,
            child: SizedBox(
              height: height,
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// 40dp square icon button used in every app bar in the design.
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.child,
    this.onTap,
    this.size = 40,
    this.background,
    this.hoverBackground,
    this.borderRadius = 12,
    this.tooltip,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double size;
  final Color? background;
  final Color? hoverBackground;
  final double borderRadius;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    Widget button = Material(
      color: background ?? Colors.transparent,
      borderRadius: BorderRadius.circular(borderRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        hoverColor: hoverBackground ?? k.surf2,
        child: SizedBox.square(dimension: size, child: Center(child: child)),
      ),
    );
    if (tooltip != null) button = Tooltip(message: tooltip!, child: button);
    return button;
  }
}
