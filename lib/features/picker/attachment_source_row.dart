import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_icons.dart';
import '../../core/widgets/stroke_icon.dart';

enum AttachmentSource { camera, gallery, files }

/// Camera / Gallery / Files row. The design emphasises the first button on the
/// primary attachment group and keeps the rest neutral.
class AttachmentSourceRow extends StatelessWidget {
  const AttachmentSourceRow({
    super.key,
    required this.onPick,
    this.emphasizeFirst = false,
    this.showFiles = true,
  });

  final ValueChanged<AttachmentSource> onPick;
  final bool emphasizeFirst;

  /// Hidden for image-only attachments (exam timetable, previous exam
  /// papers) — camera and gallery only ever produce images.
  final bool showFiles;

  @override
  Widget build(BuildContext context) {
    final k = context.t;

    Widget button(AttachmentSource source, String label, {bool accent = false}) {
      return Material(
        color: accent ? k.priC : k.surf2,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onPick(source),
          hoverColor: accent ? k.priCH : k.hov,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (accent) ...[
                  StrokeIcon(AppIcons.camera, size: 16, color: k.priInk),
                  const SizedBox(width: 7),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: accent ? k.priInk : k.tx2,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        button(AttachmentSource.camera, 'Camera', accent: emphasizeFirst),
        button(AttachmentSource.gallery, 'Gallery'),
        if (showFiles) button(AttachmentSource.files, 'Files'),
      ],
    );
  }
}
