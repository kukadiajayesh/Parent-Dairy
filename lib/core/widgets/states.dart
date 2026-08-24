import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import 'app_icons.dart';
import 'buttons.dart';
import 'stroke_icon.dart';

/// Full empty state: the stacked-pages illustration, a headline, a supporting
/// line and one primary action. Used wherever a collection has no records.
class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    super.key,
    required this.title,
    required this.description,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String description;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 44),
      decoration: BoxDecoration(
        color: k.surf,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: k.bd),
      ),
      child: Column(
        children: [
          const _EmptyIllustration(),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            textAlign: TextAlign.center,
            style: AppText.body.copyWith(color: k.tx3, height: 1.55),
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: 16),
            AppFilledButton(
              label: actionLabel!,
              onPressed: onAction,
              height: 48,
              elevated: false,
              icon: const StrokeIcon(AppIcons.plus, size: 17, strokeWidth: 2.3),
            ),
          ],
        ],
      ),
    );
  }
}

/// Two tilted record cards on a tinted tile — the design's empty illustration.
class _EmptyIllustration extends StatelessWidget {
  const _EmptyIllustration();

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    Widget sheet(Color border, double angle) => Transform.rotate(
          angle: angle,
          child: Container(
            width: 52,
            height: 68,
            decoration: BoxDecoration(
              color: k.surf,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: border, width: 1.5),
            ),
          ),
        );

    return SizedBox(
      width: 110,
      height: 110,
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: k.surf2,
                borderRadius: BorderRadius.circular(28),
              ),
            ),
          ),
          Positioned(left: 24, top: 18, child: sheet(k.bd4, -8 * 3.1415926 / 180)),
          Positioned(left: 36, top: 24, child: sheet(k.priBd, 6 * 3.1415926 / 180)),
          Positioned(
            left: 46,
            top: 40,
            child: Transform.rotate(
              angle: 6 * 3.1415926 / 180,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _bar(30, k.priC),
                  const SizedBox(height: 6),
                  _bar(22, k.bd),
                  const SizedBox(height: 6),
                  _bar(26, k.bd),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bar(double width, Color color) => Container(
        width: width,
        height: 4,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(999),
        ),
      );
}

/// Compact empty state for a filtered list that came back with nothing.
class EmptyListNotice extends StatelessWidget {
  const EmptyListNotice({
    super.key,
    required this.title,
    required this.description,
  });

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 44),
      decoration: BoxDecoration(
        color: k.surf,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: k.bd4, style: BorderStyle.solid),
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: DashedBorder(color: k.bd4),
      ),
      child: Column(
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: k.tx3, height: 1.4),
          ),
        ],
      ),
    );
  }
}

/// Full error state: warning glyph, headline, description, cancel + retry.
class ErrorStateView extends StatelessWidget {
  const ErrorStateView({
    super.key,
    required this.title,
    required this.description,
    required this.actionLabel,
    this.onAction,
    this.onCancel,
  });

  final String title;
  final String description;
  final String actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      decoration: BoxDecoration(
        color: k.surf,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: k.bd),
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: k.errC,
              borderRadius: BorderRadius.circular(24),
            ),
            child: StrokeIcon(
              AppIcons.warningTriangle,
              size: 32,
              color: k.err,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            textAlign: TextAlign.center,
            style: AppText.body.copyWith(color: k.tx3, height: 1.55),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: AppOutlinedButton(
                  label: 'Cancel',
                  onPressed: onCancel,
                  height: 48,
                  borderRadius: 15,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AppFilledButton(
                  label: actionLabel,
                  onPressed: onAction,
                  height: 48,
                  elevated: false,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Inline error banner shown above a form when a save fails.
class InlineErrorBanner extends StatelessWidget {
  const InlineErrorBanner({
    super.key,
    required this.title,
    required this.description,
    this.actionLabel = 'Retry',
    this.onAction,
  });

  final String title;
  final String description;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: k.errC,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          StrokeIcon(AppIcons.errorCircle, size: 20, color: k.err),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: k.errInk,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  description,
                  style: TextStyle(fontSize: 12.5, color: k.errInk2),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          InkWell(
            onTap: onAction,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                actionLabel,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: k.err,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Offline notice: the design shows it inline at the top of the timeline.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key, this.onDismiss});

  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: k.warnC,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: k.warn, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Offline',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: k.warnInk,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  "Changes will sync when you're back online.",
                  style: TextStyle(fontSize: 12, color: k.warnInk2),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          InkWell(
            onTap: onDismiss,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                'Dismiss',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: k.warnInk,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shimmering skeleton block. The design animates opacity between .55 and 1
/// on a 1.4s ease-in-out loop; [Skeletons] drives that for a whole subtree.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height,
    this.radius = 6,
    this.tone = SkeletonTone.surface,
  });

  final double? width;
  final double? height;
  final double radius;
  final SkeletonTone tone;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: switch (tone) {
          SkeletonTone.surface => k.surf2,
          SkeletonTone.solid => k.skel,
          SkeletonTone.soft => k.hov,
        },
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

enum SkeletonTone { surface, solid, soft }

class Skeletons extends StatefulWidget {
  const Skeletons({super.key, required this.child});

  final Widget child;

  @override
  State<Skeletons> createState() => _SkeletonsState();
}

class _SkeletonsState extends State<Skeletons>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  late final Animation<double> _opacity = Tween<double>(
    begin: .55,
    end: 1,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      FadeTransition(opacity: _opacity, child: widget.child);
}

/// A 1.5dp dashed rounded border — Flutter has no built-in dashed [BoxBorder].
class DashedBorder extends BoxBorder {
  const DashedBorder({
    required this.color,
    this.width = 1.5,
    this.dash = 5,
    this.gap = 4,
  });

  final Color color;
  final double width;
  final double dash;
  final double gap;

  @override
  BorderSide get bottom => BorderSide(color: color, width: width);
  @override
  BorderSide get top => BorderSide(color: color, width: width);
  @override
  bool get isUniform => true;
  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(width);

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    TextDirection? textDirection,
    BoxShape shape = BoxShape.rectangle,
    BorderRadius? borderRadius,
  }) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..isAntiAlias = true;

    final inset = rect.deflate(width / 2);
    final path = Path();
    if (shape == BoxShape.circle) {
      path.addOval(inset);
    } else if (borderRadius != null) {
      path.addRRect(borderRadius.toRRect(inset));
    } else {
      path.addRect(inset);
    }

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance = end + gap;
      }
    }
  }

  @override
  ShapeBorder scale(double t) =>
      DashedBorder(color: color, width: width * t, dash: dash * t, gap: gap * t);
}

/// Rounded container with a dashed outline — upload drop zones, "add more"
/// tiles, and the empty list notice.
class DashedContainer extends StatelessWidget {
  const DashedContainer({
    super.key,
    required this.child,
    this.radius = 20,
    this.padding = const EdgeInsets.all(18),
    this.color,
    this.background,
    this.onTap,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? background;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: background ?? k.surf,
        borderRadius: BorderRadius.circular(radius),
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: DashedBorder(color: color ?? k.bd5),
      ),
      child: child,
    );
    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(radius),
      child: content,
    );
  }
}
