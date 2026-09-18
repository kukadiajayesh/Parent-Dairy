import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import 'app_icons.dart';
import 'pressable.dart';
import 'states.dart';
import 'stroke_icon.dart';

/// Flutter counterpart of the design's `<image-slot>`: an attachment thumbnail
/// that falls back to a dashed placeholder with a caption while no image is
/// attached. Pass [image] once real attachments exist and the placeholder is
/// replaced with the photo, cropped to fill.
class ImageSlot extends StatelessWidget {
  const ImageSlot({
    super.key,
    this.placeholder = 'Drop an image',
    this.radius = 12,
    this.width,
    this.height,
    this.image,
    this.onTap,
    this.showCaption = true,
  });

  final String placeholder;
  final double radius;
  final double? width;
  final double? height;
  final ImageProvider? image;
  final VoidCallback? onTap;
  final bool showCaption;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final shape = BorderRadius.circular(radius);
    final ink = k.tx;

    Widget buildPlaceholder() => Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0x14808080),
            borderRadius: shape,
          ),
          // The web component draws a 1.5px dashed ring at 35% of the
          // inherited text colour; Flutter has no dashed BoxBorder.
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: shape,
              border: DashedBorder(color: ink.withValues(alpha: .35)),
            ),
          ),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                StrokeIcon(
                  AppIcons.imagePlaceholder,
                  size: 22,
                  color: ink.withValues(alpha: .45),
                ),
                if (showCaption && placeholder.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    placeholder,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.3,
                      fontWeight: FontWeight.w500,
                      color: ink.withValues(alpha: .75),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );

    // A failed/evicted load (corrupt file, 404, network drop) falls back to
    // the same dashed placeholder instead of rendering blank.
    final content = image != null
        ? Image(
            image: image!,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stack) => buildPlaceholder(),
          )
        : buildPlaceholder();

    Widget slot = ClipRRect(borderRadius: shape, child: content);
    if (onTap != null) {
      // `overlay`: an attached photo fills this slot opaquely, and ink painted
      // on the Material underneath it would never be seen.
      slot = AppInkWell(
        borderRadius: shape,
        onTap: onTap,
        overlay: true,
        child: slot,
      );
    }

    if (width != null || height != null) {
      slot = SizedBox(width: width, height: height, child: slot);
    }
    return slot;
  }
}

/// A static stand-in for an attachment thumbnail: a neutral rounded tile with
/// a glyph, and nothing else.
///
/// Deliberately does no work — no file read, no PDF page render, no network
/// fetch. Used where a list wants a uniform, instantly-painted thumbnail
/// column rather than a real preview (the Home "Recent activity" rows), so a
/// PDF row never renders differently from an image row beside it.
class ThumbPlaceholder extends StatelessWidget {
  const ThumbPlaceholder({
    super.key,
    required this.icon,
    this.size,
    this.width,
    this.height,
    this.radius = 12,
    this.iconSize = 20,
    this.background,
    this.foreground,
  });

  final SvgIcon icon;

  /// Convenience for a square tile; [width]/[height] win when both are given.
  final double? size;
  final double? width;
  final double? height;
  final double radius;
  final double iconSize;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    return Container(
      width: width ?? size,
      height: height ?? size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background ?? k.surf2,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: StrokeIcon(icon, size: iconSize, color: foreground ?? k.tx3),
    );
  }
}
