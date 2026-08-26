import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pdfx/pdfx.dart';
import 'package:synchronized/synchronized.dart';

import '../../data/models.dart';
import 'attachment_actions.dart';
import 'telemetry_service.dart';

/// Renders the first page of a PDF attachment to a small raster image, so
/// worksheet/answer-key PDFs show a real page preview everywhere instead of
/// a generic "PDF" badge.
///
/// Rendering (and, for an attachment this device hasn't seen yet,
/// downloading it first via [AttachmentActions.ensureLocal]) is comparatively
/// expensive, so successful results are cached in memory for the life of the
/// app, keyed by the attachment's id. Renders are also serialized through a
/// single [Lock]: the underlying platform PDF renderer is not safe to have
/// several documents open at once, which a screen like the Timeline — every
/// card built and asking for its thumbnail at the same time — would
/// otherwise trigger constantly.
abstract final class PdfThumbnailService {
  static final Map<String, Uint8List> _cache = {};
  static final Map<String, Future<Uint8List?>> _inFlight = {};
  static final Lock _lock = Lock();

  static String cacheKey(Attachment attachment) {
    if (attachment.id.isNotEmpty) return attachment.id;
    if (attachment.localPath != null && attachment.localPath!.isNotEmpty) {
      return attachment.localPath!;
    }
    if (attachment.storagePath != null && attachment.storagePath!.isNotEmpty) {
      return attachment.storagePath!;
    }
    if (attachment.downloadUrl != null && attachment.downloadUrl!.isNotEmpty) {
      return attachment.downloadUrl!;
    }
    return attachment.name;
  }

  static Future<Uint8List?> thumbnailFor(Attachment attachment) {
    final key = cacheKey(attachment);
    final cached = _cache[key];
    if (cached != null) return Future.value(cached);

    return _inFlight.putIfAbsent(
      key,
      () => _render(attachment, key)
          .whenComplete(() => _inFlight.remove(key)),
    );
  }

  static Future<Uint8List?> _render(Attachment attachment, String key) async {
    try {
      final file = await AttachmentActions.ensureLocal(attachment);
      if (!await file.exists()) {
        debugPrint('PDF thumbnail file does not exist for $key: ${file.path}');
        return null;
      }

      final bytes = await _lock.synchronized(() async {
        final document = await PdfDocument.openFile(file.path);
        try {
          final page = await document.getPage(1);
          try {
            // Rendered larger than typical thumbnail slots so it stays
            // sharp on high-density screens; PdfPageImage scales down to fit.
            final targetWidth = page.width > 0 ? page.width * 2 : 500.0;
            final targetHeight = page.height > 0 ? page.height * 2 : 700.0;

            final image = await page.render(
              width: targetWidth,
              height: targetHeight,
              format: PdfPageImageFormat.png,
              backgroundColor: '#FFFFFF',
            );
            return image?.bytes;
          } finally {
            await page.close();
          }
        } finally {
          await document.close();
        }
      });

      if (bytes != null && bytes.isNotEmpty) {
        _cache[key] = bytes;
      }
      return bytes;
    } catch (error, stack) {
      unawaited(
        Telemetry.recordError(error, stack, context: 'pdfThumbnailRender'),
      );
      debugPrint('PDF thumbnail failed for $key: $error');
      return null;
    }
  }

  @visibleForTesting
  static void clearCache() {
    _cache.clear();
    _inFlight.clear();
  }
}
