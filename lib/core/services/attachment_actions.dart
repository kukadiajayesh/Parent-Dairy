import 'dart:io';

import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/models.dart';
import '../../data/repositories/attachment_repository.dart';
import '../errors/app_failure.dart';

/// Preview, share, download and open for a saved attachment (§23).
///
/// Every action needs the file on disk first. [ensureLocal] is the single place
/// that resolves that — using the copy left behind by the capture flow when it
/// exists, and pulling from Storage only when this device has never seen the
/// file (a record created on the parent's other phone).
abstract final class AttachmentActions {
  static final AttachmentRepository _repo = AttachmentRepository();

  static Future<File> ensureLocal(Attachment attachment) async {
    final localPath = attachment.localPath;
    if (localPath != null && localPath.isNotEmpty) {
      final existing = File(localPath);
      if (await existing.exists()) return existing;
    }

    final hasStorage = attachment.storagePath != null && attachment.storagePath!.isNotEmpty;
    final hasUrl = attachment.downloadUrl != null && attachment.downloadUrl!.isNotEmpty;

    if (!hasStorage && !hasUrl) {
      throw const AppFailure(
        FailureKind.notFound,
        'That file has not finished uploading yet.',
        canRetry: false,
      );
    }

    final cache = await getTemporaryDirectory();
    final targetFolder = Directory('${cache.path}/attachments');
    if (!await targetFolder.exists()) {
      await targetFolder.create(recursive: true);
    }

    final id = attachment.id.isNotEmpty
        ? attachment.id
        : (attachment.storagePath?.hashCode.toString() ??
            attachment.downloadUrl?.hashCode.toString() ??
            attachment.name.hashCode.toString());
    final safeName = attachment.name.isNotEmpty ? attachment.name : 'document.pdf';
    final target = File('${targetFolder.path}/${id}_$safeName');

    final downloaded = await _repo.download(attachment, target: target);
    if (downloaded == null) {
      throw const AppFailure(
        FailureKind.notFound,
        'That file could not be downloaded.',
      );
    }
    return downloaded;
  }

  /// Hands the file to the system share sheet.
  static Future<void> share(Attachment attachment) async {
    final file = await ensureLocal(attachment);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: attachment.mimeType)],
        subject: attachment.name,
      ),
    );
  }

  /// Shares every file on a record at once — the detail screen's Share action.
  static Future<void> shareRecord(DiaryRecord record) async {
    final files = <XFile>[];
    for (final attachment in record.allFiles) {
      try {
        final file = await ensureLocal(attachment);
        files.add(XFile(file.path, mimeType: attachment.mimeType));
      } catch (_) {
        // Skip a file that never uploaded rather than blocking the share of
        // the ones that did.
      }
    }
    if (files.isEmpty) {
      throw const AppFailure(
        FailureKind.notFound,
        'There are no files on this record to share yet.',
        canRetry: false,
      );
    }
    await SharePlus.instance.share(
      ShareParams(files: files, subject: '${record.subject} — ${record.title}'),
    );
  }

  /// Saves a copy somewhere the parent can find it with a file manager, then
  /// reports where it went.
  ///
  /// Android apps cannot write to the public Downloads folder without extra
  /// permissions, so this uses the app's own external directory — visible in
  /// any file manager, and removed cleanly when the app is uninstalled.
  static Future<String> saveToDevice(Attachment attachment) async {
    final source = await ensureLocal(attachment);
    final dir =
        await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/Academic Diary');
    await folder.create(recursive: true);

    final target = File('${folder.path}/${attachment.name}');
    await source.copy(target.path);
    return target.path;
  }

  /// Opens the file in whatever app the device uses for it — the only sane way
  /// to show a PDF without embedding a renderer.
  static Future<void> open(Attachment attachment) async {
    final file = await ensureLocal(attachment);
    final result = await OpenFilex.open(
      file.path,
      type: attachment.mimeType,
    );
    if (result.type == ResultType.noAppToOpen) {
      throw const AppFailure(
        FailureKind.invalidFile,
        'No app on this phone can open that file.',
        canRetry: false,
      );
    }
  }
}
