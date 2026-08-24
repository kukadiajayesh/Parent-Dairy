import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../../core/errors/app_failure.dart';
import '../../core/services/telemetry_service.dart';
import '../models.dart';
import 'attachment_repository.dart';
import 'record_repository.dart';

/// Overall upload state, surfaced by the shell as "Syncing" / "Waiting for
/// internet" / "Synced" (§25).
enum QueueStatus { idle, uploading, waiting, failed }

/// Moves attachment bytes to Storage after their record has already been saved.
///
/// Records are written to Firestore first and always succeed locally, thanks to
/// Firestore's offline cache. Files cannot work that way — they need a network
/// — so they queue here and drain when one is available. That split is what
/// lets a parent photograph a worksheet in a school corridor with no signal and
/// still see it on the timeline immediately (§25, §32).
class UploadQueue extends ChangeNotifier {
  UploadQueue({
    required this._attachments,
    required this._records,
    required this._offline,
  }) {
    _offline.addListener(_onConnectivityChanged);
  }


  final AttachmentRepository _attachments;
  final RecordRepository _records;
  final ValueListenable<bool> _offline;

  final Queue<_Job> _jobs = Queue<_Job>();
  final Set<String> _queuedRecordIds = <String>{};

  bool _draining = false;
  QueueStatus _status = QueueStatus.idle;
  int _completed = 0;
  int _total = 0;

  QueueStatus get status => _status;

  /// 0–1 across the current batch; 1 when there is nothing to do.
  double get progress => _total == 0 ? 1 : _completed / _total;

  int get pendingCount => _jobs.length;

  /// Queues every not-yet-uploaded file on [record].
  void enqueue({
    required String uid,
    required String childId,
    required DiaryRecord record,
  }) {
    if (record.sync == SyncState.synced) return;
    if (!_queuedRecordIds.add(record.id)) return;

    _jobs.add(_Job(uid: uid, childId: childId, record: record));
    _total += 1;
    _drain();
  }

  /// Picks up work stranded by a previous session — an app killed mid-upload,
  /// or a save made while offline that was never drained.
  Future<void> resume({required String uid, required String childId}) async {
    try {
      final stranded = await _records.pendingUploads(uid: uid, childId: childId);
      for (final record in stranded) {
        enqueue(uid: uid, childId: childId, record: record);
      }
    } catch (_) {
      // A failed sweep is retried on the next launch or reconnect.
    }
  }

  void _onConnectivityChanged() {
    if (_offline.value) {
      if (_jobs.isNotEmpty) _setStatus(QueueStatus.waiting);
      return;
    }
    _drain();
  }

  Future<void> _drain() async {
    if (_draining) return;
    if (_jobs.isEmpty) {
      _reset();
      return;
    }
    if (_offline.value) {
      _setStatus(QueueStatus.waiting);
      return;
    }

    _draining = true;
    _setStatus(QueueStatus.uploading);

    var sawFailure = false;
    while (_jobs.isNotEmpty && !_offline.value) {
      final job = _jobs.removeFirst();
      try {
        await _process(job);
      } catch (_) {
        sawFailure = true;
      } finally {
        _queuedRecordIds.remove(job.record.id);
        _completed += 1;
        notifyListeners();
      }
    }

    _draining = false;

    if (_jobs.isNotEmpty) {
      // Stopped early because the network dropped mid-batch.
      _setStatus(QueueStatus.waiting);
      return;
    }
    if (sawFailure) {
      _setStatus(QueueStatus.failed);
      _completed = 0;
      _total = 0;
      return;
    }
    _reset();
  }

  Future<void> _process(_Job job) async {
    final record = job.record;

    Future<Attachment> send(Attachment attachment) async {
      if (attachment.sync == SyncState.synced) return attachment;
      try {
        return await _attachments.upload(
          attachment,
          uid: job.uid,
          childId: job.childId,
          recordId: record.id,
          type: record.type,
        );
      } catch (error) {
        final failure = AppFailure.from(error);
        unawaited(Telemetry.uploadFailed(failure.kind.name));
        unawaited(
          Telemetry.recordError(
            failure,
            StackTrace.current,
            context: 'uploadAttachment',
          ),
        );
        // A file whose local copy is gone can never succeed; anything else is
        // worth another attempt on the next reconnect.
        return attachment.copyWith(
          sync: failure.canRetry ? SyncState.pending : SyncState.failed,
        );
      }
    }

    final uploaded = <Attachment>[];
    for (final attachment in record.attachments) {
      uploaded.add(await send(attachment));
    }
    final key = record.answerKey == null ? null : await send(record.answerKey!);

    await _records.updateFiles(
      uid: job.uid,
      childId: job.childId,
      recordId: record.id,
      attachments: uploaded,
      answerKey: key,
    );

    // Anything still pending lost its network rather than its file — requeue so
    // the next drain picks it up instead of stranding it.
    final settled = record.copyWith(attachments: uploaded, answerKey: key);
    if (settled.sync == SyncState.pending) {
      _jobs.add(_Job(uid: job.uid, childId: job.childId, record: settled));
      _queuedRecordIds.add(settled.id);
      _total += 1;
    }
  }

  void _reset() {
    _completed = 0;
    _total = 0;
    _setStatus(QueueStatus.idle);
  }

  void _setStatus(QueueStatus value) {
    if (_status == value) return;
    _status = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _offline.removeListener(_onConnectivityChanged);
    super.dispose();
  }
}

class _Job {
  const _Job({required this.uid, required this.childId, required this.record});

  final String uid;
  final String childId;
  final DiaryRecord record;
}
