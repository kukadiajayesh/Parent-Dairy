import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../services/image_service.dart';
import '../services/pdf_thumbnail_service.dart';
import '../theme/app_tokens.dart';
import 'app_icons.dart';
import 'image_slot.dart';
import 'pressable.dart';
import 'states.dart';
import 'stroke_icon.dart';

/// Resolves an [Attachment] to something [Image] can draw.
///
/// Prefers the on-device copy: it is already the compressed file that was
/// uploaded, it renders with no network round trip, and it is what makes a
/// just-captured worksheet appear instantly on a phone with no signal. Falls
/// back to the Storage URL for records that arrived from another device.
ImageProvider? attachmentImage(Attachment? attachment) {
  if (attachment == null || attachment.isPdf) return null;

  final localPath = attachment.localPath;
  if (localPath != null && localPath.isNotEmpty) {
    final file = File(localPath);
    // Synchronous on purpose — this runs in build, and an existsSync on a path
    // the app just wrote is a stat call, not I/O worth an await.
    if (file.existsSync()) return FileImage(file);
  }

  final url = attachment.downloadUrl;
  if (url != null && url.isNotEmpty) return NetworkImage(url);

  return null;
}

/// The same for a file the parent has picked but not yet saved.
ImageProvider? fileImage(String? path) {
  if (path == null || path.isEmpty) return null;
  final file = File(path);
  return file.existsSync() ? FileImage(file) : null;
}

/// A thumbnail for [attachment] that always shows something identifiable —
/// a real image preview, or a clearly-labelled PDF page thumbnail — instead of the
/// generic "no attachment yet" dashed placeholder [ImageSlot] falls back to.
///
/// Used everywhere an attachment (not an empty "add" slot) is rendered, so a
/// PDF worksheet page or answer key never reads as a blank "Photo".
Widget attachmentThumb(
  BuildContext context,
  Attachment? attachment, {
  double radius = 12,
  double? width,
  double? height,
  VoidCallback? onTap,
  bool showCaption = true,
}) {
  if (attachment != null && attachment.isPdf) {
    Widget tile = _PdfThumb(
      attachment: attachment,
      radius: radius,
      showCaption: showCaption,
    );
    if (onTap != null) {
      // Same as [ImageSlot]: a rendered PDF page is opaque, so the ink goes
      // over the tile rather than behind it.
      tile = AppInkWell(
        borderRadius: BorderRadius.circular(radius),
        onTap: onTap,
        overlay: true,
        child: tile,
      );
    }
    if (width != null || height != null) {
      tile = SizedBox(width: width, height: height, child: tile);
    }
    return ClipRRect(borderRadius: BorderRadius.circular(radius), child: tile);
  }

  return ImageSlot(
    placeholder: attachment?.meta ?? '',
    image: attachmentImage(attachment),
    radius: radius,
    width: width,
    height: height,
    onTap: onTap,
    showCaption: showCaption,
  );
}

/// Helper to render a thumbnail for a picked attachment before it is saved.
Widget pickedAttachmentThumb(
  BuildContext context,
  PickedAttachment? picked, {
  double radius = 12,
  double? width,
  double? height,
  VoidCallback? onTap,
  bool showCaption = true,
}) {
  if (picked == null) {
    return ImageSlot(
      placeholder: 'Drop an image',
      radius: radius,
      width: width,
      height: height,
      onTap: onTap,
      showCaption: showCaption,
    );
  }

  if (picked.isPdf) {
    final attachment = Attachment(
      name: picked.name,
      meta: showCaption ? 'PDF' : '',
      isPdf: true,
      localPath: picked.path,
      fileSize: picked.bytes,
      mimeType: picked.mimeType ?? 'application/pdf',
      sync: SyncState.pending,
    );
    return attachmentThumb(
      context,
      attachment,
      radius: radius,
      width: width,
      height: height,
      onTap: onTap,
      showCaption: showCaption,
    );
  }

  return ImageSlot(
    placeholder: picked.name,
    image: fileImage(picked.path),
    radius: radius,
    width: width,
    height: height,
    onTap: onTap,
    showCaption: showCaption,
  );
}

/// Renders a PDF attachment's first page via [PdfThumbnailService] and fades
/// it in once ready.
///
/// The three outcomes look different on purpose. A render in flight shows a
/// shimmering skeleton, so a slot that is still working never reads as a slot
/// that has given up — the whole point of the preview is that the parent can
/// tell one worksheet from another at a glance. Only once every attempt has
/// failed (a corrupt file, or a remote-only copy with no signal to fetch it)
/// does it settle on the generic "PDF" tile.
///
/// Renders are serialized behind a single lock in [PdfThumbnailService], so on
/// a screen full of cards the later ones legitimately take a moment, and the
/// first attempt can also lose to a file that is still downloading. A null
/// result is therefore retried a couple of times with a short backoff rather
/// than being treated as final.
class _PdfThumb extends StatefulWidget {
  const _PdfThumb({
    required this.attachment,
    required this.radius,
    required this.showCaption,
  });

  final Attachment attachment;
  final double radius;
  final bool showCaption;

  @override
  State<_PdfThumb> createState() => _PdfThumbState();
}

class _PdfThumbState extends State<_PdfThumb> {
  static const _maxAttempts = 3;

  Uint8List? _bytes;
  bool _loading = true;

  /// Identifies the file the in-flight render belongs to, so a result that
  /// lands after the slot has been recycled onto another attachment is
  /// dropped instead of painting the wrong page.
  late String _key = PdfThumbnailService.cacheKey(widget.attachment);

  @override
  void initState() {
    super.initState();
    _load(widget.attachment, _key);
  }

  @override
  void didUpdateWidget(covariant _PdfThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    final key = PdfThumbnailService.cacheKey(widget.attachment);
    if (key == _key &&
        oldWidget.attachment.sync == widget.attachment.sync &&
        oldWidget.attachment.downloadUrl == widget.attachment.downloadUrl) {
      return;
    }
    // Assigned rather than setState-ed: the rebuild this runs inside will
    // pick the new state up on its own.
    _key = key;
    _bytes = null;
    _loading = true;
    _load(widget.attachment, key);
  }

  Future<void> _load(Attachment attachment, String key) async {
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      final bytes = await PdfThumbnailService.thumbnailFor(attachment);
      if (!mounted || key != _key) return;
      if (bytes != null && bytes.isNotEmpty) {
        setState(() {
          _bytes = bytes;
          _loading = false;
        });
        return;
      }
      if (attempt < _maxAttempts) {
        await Future<void>.delayed(Duration(milliseconds: 350 * attempt));
        if (!mounted || key != _key) return;
      }
    }

    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final bytes = _bytes;

    if (bytes != null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.memory(
            bytes,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
          ),
          Positioned(
            left: 6,
            bottom: 6,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .72),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                child: Text(
                  'PDF',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (_loading) {
      return Skeletons(
        child: Container(
          color: k.skel,
          alignment: Alignment.center,
          child: StrokeIcon(
            AppIcons.document,
            size: 20,
            color: k.tx4.withValues(alpha: .6),
          ),
        ),
      );
    }

    return Container(
      color: k.surf2,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            StrokeIcon(AppIcons.document, size: 22, color: k.tx3),
            if (widget.showCaption) ...[
              const SizedBox(height: 4),
              Text(
                'PDF',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: k.tx3,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
