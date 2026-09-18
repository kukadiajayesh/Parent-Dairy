import 'dart:convert';
import 'dart:io';

import 'package:pdfx/pdfx.dart' as pdfx;

import '../../../data/models.dart';
import '../../errors/app_failure.dart';
import '../attachment_actions.dart';
import '../image_service.dart';
import 'gemini_client.dart';
import 'gemini_key_store.dart';

/// One file bound for the model: an on-device path plus what it is.
class AiSourceFile {
  const AiSourceFile({
    required this.path,
    required this.name,
    required this.mimeType,
    required this.isPdf,
    required this.bytes,
    required this.cacheKey,
    this.subject = '',
  });

  final String path;
  final String name;
  final String mimeType;
  final bool isPdf;
  final int bytes;

  /// Attachment id when known, else the path — what the Files API cache
  /// keys on.
  final String cacheKey;
  final String subject;
}

/// What a request would send, before it is sent — for the caps and the
/// "This will read {n} pages" confirmation.
class AiPayloadSummary {
  const AiPayloadSummary({
    required this.images,
    required this.pdfPages,
    required this.totalBytes,
  });

  final int images;
  final int pdfPages;
  final int totalBytes;

  int get pages => images + pdfPages;
  bool get needsConfirmation => images > AiAttachments.confirmAboveImages;
}

/// Turns attachments into request parts within the caps of prompt 02 §B.
abstract final class AiAttachments {
  static const int maxImages = 12;
  static const int maxPdfPages = 40;
  static const int maxBytes = 20 * 1024 * 1024;

  /// Above this an image goes through the Files API instead of inline.
  static const int inlineLimit = 6 * 1024 * 1024;
  static const int confirmAboveImages = 6;

  /// Resolves saved attachments to local files, downloading from Storage if
  /// this phone has never seen them.
  static Future<List<AiSourceFile>> fromAttachments(
    Iterable<Attachment> attachments, {
    String subject = '',
  }) async {
    final out = <AiSourceFile>[];
    for (final a in attachments) {
      final file = await AttachmentActions.ensureLocal(a);
      out.add(
        AiSourceFile(
          path: file.path,
          name: a.name,
          mimeType: a.mimeType ?? (a.isPdf ? 'application/pdf' : 'image/jpeg'),
          isPdf: a.isPdf,
          bytes: await file.length(),
          cacheKey: a.id.isNotEmpty ? a.id : file.path,
          subject: subject,
        ),
      );
    }
    return out;
  }

  static List<AiSourceFile> fromPicked(Iterable<PickedAttachment> picked) => [
    for (final p in picked)
      AiSourceFile(
        path: p.path,
        name: p.name,
        mimeType: p.mimeType ?? (p.isPdf ? 'application/pdf' : 'image/jpeg'),
        isPdf: p.isPdf,
        bytes: p.bytes,
        cacheKey: p.path,
      ),
  ];

  /// Counts what would be sent and refuses, with a clear message, anything
  /// over the caps. Image sizes are the *downscaled* sizes.
  static Future<AiPayloadSummary> summarise(List<AiSourceFile> files) async {
    var images = 0;
    var pdfPages = 0;
    var bytes = 0;
    for (final f in files) {
      if (f.isPdf) {
        pdfPages += await pdfPageCount(f.path);
        bytes += f.bytes;
      } else {
        images += 1;
        // The downscaled JPEG is what goes over the wire; its exact size is
        // not known until it is made, so 1.2MB is the budget per image.
        bytes += f.bytes < 1200 * 1024 ? f.bytes : 1200 * 1024;
      }
    }
    final summary = AiPayloadSummary(
      images: images,
      pdfPages: pdfPages,
      totalBytes: bytes,
    );
    if (images > maxImages) {
      throw AppFailure(
        FailureKind.fileTooLarge,
        'That is $images images; Gemini requests are capped at $maxImages. '
        'Untick a few pages.',
        canRetry: false,
      );
    }
    if (pdfPages > maxPdfPages) {
      throw AppFailure(
        FailureKind.fileTooLarge,
        'Those PDFs run to $pdfPages pages; the cap is $maxPdfPages. Untick '
        'one of them.',
        canRetry: false,
      );
    }
    if (bytes > maxBytes) {
      throw const AppFailure(
        FailureKind.fileTooLarge,
        'That is more than 20 MB of pages. Untick a few and try again.',
        canRetry: false,
      );
    }
    return summary;
  }

  /// Builds the parts: images downscaled to 1600px/q75 and sent inline
  /// (EXIF dropped by the re-encode); anything over 6MB, and every PDF,
  /// through the Files API under [key].
  static Future<List<GeminiPart>> toParts(
    List<AiSourceFile> files, {
    required GeminiClient client,
    required GeminiKey key,
    CancellationToken? cancel,
    void Function(int done, int total)? onProgress,
  }) async {
    final parts = <GeminiPart>[];
    var done = 0;
    for (final f in files) {
      cancel?.throwIfCancelled();
      if (f.isPdf) {
        final uri = await client.uploadFile(
          File(f.path),
          mimeType: 'application/pdf',
          key: key,
          cacheKey: f.cacheKey,
          displayName: f.name,
          cancel: cancel,
        );
        parts.add(FileDataPart(mimeType: 'application/pdf', fileUri: uri));
      } else {
        final small = await ImageService.compressForAi(f.path);
        final bytes = await File(small).readAsBytes();
        if (bytes.length <= inlineLimit) {
          parts.add(
            InlineDataPart(mimeType: 'image/jpeg', base64Data: base64Encode(bytes)),
          );
        } else {
          final uri = await client.uploadFile(
            File(small),
            mimeType: 'image/jpeg',
            key: key,
            cacheKey: f.cacheKey,
            displayName: f.name,
            cancel: cancel,
          );
          parts.add(FileDataPart(mimeType: 'image/jpeg', fileUri: uri));
        }
      }
      done++;
      onProgress?.call(done, files.length);
    }
    return parts;
  }

  /// Page count of a PDF. The platform renderer is authoritative; when it
  /// is unavailable (tests, a corrupt file) a byte scan is close enough for
  /// a cap check.
  static Future<int> pdfPageCount(String path) async {
    try {
      final doc = await pdfx.PdfDocument.openFile(path);
      final count = doc.pagesCount;
      await doc.close();
      if (count > 0) return count;
    } catch (_) {
      // Fall through to the scan.
    }
    try {
      return countPdfPagesInBytes(await File(path).readAsBytes());
    } catch (_) {
      return 1;
    }
  }

  /// `/Type /Page` objects (not `/Pages`). Misses object-stream PDFs, where
  /// it under-counts — acceptable for a cap check, never for rendering.
  static int countPdfPagesInBytes(List<int> bytes) {
    final text = latin1.decode(bytes, allowInvalid: true);
    final matches = RegExp(r'/Type\s*/Page(?![s/])').allMatches(text).length;
    return matches == 0 ? 1 : matches;
  }
}
