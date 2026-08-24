import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import 'app_icons.dart';
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

    Widget content;
    if (image != null) {
      content = Image(image: image!, fit: BoxFit.cover);
    } else {
      content = Stack(
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
    }

    Widget slot = ClipRRect(borderRadius: shape, child: content);
    if (onTap != null) {
      slot = Material(
        color: Colors.transparent,
        child: InkWell(borderRadius: shape, onTap: onTap, child: slot),
      );
    }

    if (width != null || height != null) {
      slot = SizedBox(width: width, height: height, child: slot);
    }
    return slot;
  }
}
