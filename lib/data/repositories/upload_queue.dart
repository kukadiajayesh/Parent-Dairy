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

  /// Attempts per record before its files are reported as failed. Three passes
  /// covers a flaky connection without hammering a genuinely broken upload.
  static const int maxAttempts = 3;

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
        // A failed *upload* does not throw — it comes back as a flag, because
        // the record still has to be written with its files marked. Only a
        // Firestore write failure reaches the catch below.
        if (await _process(job)) sawFailure = true;
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

  /// Uploads a job's files. Returns true when at least one of them ended in a
  /// state the queue will not retry — the caller turns that into
  /// [QueueStatus.failed].
  Future<bool> _process(_Job job) async {
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
    final hardWords = record.hardWords == null
        ? null
        : await send(record.hardWords!);
    final examTimetable = record.examTimetable == null
        ? null
        : await send(record.examTimetable!);

    await _records.updateFiles(
      uid: job.uid,
      childId: job.childId,
      recordId: record.id,
      attachments: uploaded,
      answerKey: key,
      hardWords: hardWords,
      examTimetable: examTimetable,
    );

    final settled = record.copyWith(
      attachments: uploaded,
      answerKey: key,
      hardWords: hardWords,
      examTimetable: examTimetable,
    );

    // Anything still pending lost its network rather than its file — requeue so
    // the next drain picks it up instead of stranding it. Bounded, so a file
    // that fails every time does not spin the queue indefinitely; once the
    // attempts run out it is reported as failed and left for an explicit retry.
    if (settled.sync == SyncState.pending && job.attempt < maxAttempts) {
      _jobs.add(job.next(settled));
      _queuedRecordIds.add(settled.id);
      _total += 1;
      return false;
    }

    return settled.sync != SyncState.synced;
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
  const _Job({
    required this.uid,
    required this.childId,
    required this.record,
    this.attempt = 1,
  });

  final String uid;
  final String childId;
  final DiaryRecord record;

  /// How many times this record's files have been tried. Bounds the retry
  /// loop so a file that keeps failing cannot spin forever.
  final int attempt;

  _Job next(DiaryRecord updated) => _Job(
    uid: uid,
    childId: childId,
    record: updated,
    attempt: attempt + 1,
  );
}
