import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../core/errors/app_failure.dart';
import '../../core/services/image_service.dart';
import '../firestore_paths.dart';
import '../models.dart';

/// Firebase Storage reads and writes for attachments (§23, §33).
///
/// Files are never uploaded inline with a form save. Saving writes the record
/// with its attachments marked [SyncState.pending] and the local path recorded;
/// the bytes follow after. That is what makes "save a worksheet on the school
/// run with no signal" work, and what stops a failed upload from costing the
/// parent the record (§32).
class AttachmentRepository {
  AttachmentRepository({FirebaseStorage? storage}) : _injected = storage;

  final FirebaseStorage? _injected;

  /// Resolved lazily so constructing the repository — which happens as soon as
  /// [AppState] is built — does not require Firebase to be initialised.
  FirebaseStorage get _storage => _injected ?? FirebaseStorage.instance;
  static const _uuid = Uuid();

  /// Turns a freshly picked file into the attachment the record stores before
  /// anything is uploaded.
  static Attachment stage(
    PickedAttachment picked, {
    required String caption,
  }) => Attachment(
    id: _uuid.v4(),
    name: picked.name,
    meta: caption,
    isPdf: picked.isPdf,
    localPath: picked.path,
    fileSize: picked.bytes,
    mimeType: picked.mimeType,
    sync: SyncState.pending,
  );

  static String folderFor(RecordType type) =>
      type == RecordType.worksheet ? 'worksheets' : 'classwork';

  /// Uploads one staged attachment and returns it with its Storage path and
  /// download URL filled in.
  ///
  /// Throws [AppFailure]; the caller decides whether to retry now or leave the
  /// attachment pending for the queue to pick up later.
  Future<Attachment> upload(
    Attachment attachment, {
    required String uid,
    required String childId,
    required String recordId,
    required RecordType type,
    void Function(double progress)? onProgress,
  }) async {
    final localPath = attachment.localPath;
    if (localPath == null) {
      throw const AppFailure(
        FailureKind.invalidFile,
        'That file is no longer on this device.',
        canRetry: false,
      );
    }

    final file = File(localPath);
    if (!await file.exists()) {
      throw const AppFailure(
        FailureKind.notFound,
        'That file is no longer on this device.',
        canRetry: false,
      );
    }

    final folder = Paths.storageFolder(
      uid: uid,
      childId: childId,
      recordId: recordId,
      typeFolder: folderFor(type),
    );
    final path = '$folder/${attachment.id}_${attachment.name}';

    try {
      final ref = _storage.ref(path);
      final task = ref.putFile(
        file,
        SettableMetadata(
          contentType: attachment.mimeType ?? 'application/octet-stream',
          // Attachments are immutable once written; a long cache keeps the
          // timeline from re-fetching the same worksheet photo repeatedly.
          cacheControl: 'public, max-age=31536000, immutable',
          customMetadata: {'recordId': recordId, 'childId': childId},
        ),
      );

      if (onProgress != null) {
        task.snapshotEvents.listen((snapshot) {
          if (snapshot.totalBytes <= 0) return;
          onProgress(snapshot.bytesTransferred / snapshot.totalBytes);
        }, onError: (_) {});
      }

      final snapshot = await task;
      final url = await snapshot.ref.getDownloadURL();

      return attachment.copyWith(
        storagePath: path,
        downloadUrl: url,
        fileSize: attachment.fileSize > 0
            ? attachment.fileSize
            : snapshot.totalBytes,
        sync: SyncState.synced,
      );
    } catch (error) {
      throw AppFailure.from(error);
    }
  }

  /// Removes one file. Missing objects are treated as success — deleting a
  /// record whose upload never landed must not fail.
  Future<void> delete(Attachment attachment) async {
    final path = attachment.storagePath;
    if (path == null || path.isEmpty) return;
    try {
      await _storage.ref(path).delete();
    } on FirebaseException catch (error) {
      if (error.code == 'object-not-found') return;
      throw AppFailure.from(error);
    } catch (error) {
      throw AppFailure.from(error);
    }
  }

  /// Best-effort cleanup of everything under a deleted record.
  ///
  /// Soft-deleted records keep their files by design (§30) — this is only
  /// called on a permanent delete.
  Future<void> deleteAll(Iterable<Attachment> attachments) async {
    for (final attachment in attachments) {
      try {
        await delete(attachment);
      } catch (_) {
        // One orphaned object is a far smaller problem than a delete that
        // halts halfway and leaves the record in an unknown state.
      }
    }
  }

  /// Uploads a child's profile photo (§5) and returns its download URL.
  ///
  /// Kept outside the record folders because it belongs to the child, not to
  /// any one worksheet, and is overwritten in place on every change so old
  /// avatars do not accumulate.
  Future<String> uploadChildPhoto({
    required String uid,
    required String childId,
    required File file,
  }) async {
    try {
      final ref = _storage.ref('users/$uid/children/$childId/profile.jpg');
      final snapshot = await ref.putFile(
        file,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      return snapshot.ref.getDownloadURL();
    } catch (error) {
      throw AppFailure.from(error);
    }
  }

  /// Caches a remote attachment locally so the viewer can open it offline and
  /// share it without a second download.
  Future<File?> download(Attachment attachment, {required File target}) async {
    try {
      if (await target.exists()) return target;
      await target.parent.create(recursive: true);

      final path = attachment.storagePath;
      if (path != null && path.isNotEmpty) {
        try {
          await _storage.ref(path).writeToFile(target);
          return target;
        } catch (_) {
          // If storage reference download fails, attempt fallback to downloadUrl.
        }
      }

      final url = attachment.downloadUrl;
      if (url != null && url.isNotEmpty) {
        final client = HttpClient();
        try {
          final uri = Uri.tryParse(url);
          if (uri != null) {
            final request = await client.getUrl(uri);
            final response = await request.close();
            if (response.statusCode == 200) {
              final bytes = await consolidateHttpClientResponseBytes(response);
              await target.writeAsBytes(bytes);
              return target;
            }
          }
        } finally {
          client.close();
        }
      }

      return null;
    } catch (error) {
      throw AppFailure.from(error);
    }
  }
}
