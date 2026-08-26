import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_academic_diary/core/errors/app_failure.dart';
import 'package:parent_academic_diary/data/models.dart';
import 'package:parent_academic_diary/data/repositories/attachment_repository.dart';
import 'package:parent_academic_diary/data/repositories/record_repository.dart';
import 'package:parent_academic_diary/data/repositories/upload_queue.dart';

/// An attachment repository whose uploads fail in a controlled way.
class _FakeAttachments implements AttachmentRepository {
  _FakeAttachments({this.failure, this.succeedAfter});

  /// Thrown by every upload until [succeedAfter] attempts have been made.
  final AppFailure? failure;
  final int? succeedAfter;

  int attempts = 0;

  @override
  Future<Attachment> upload(
    Attachment attachment, {
    required String uid,
    required String childId,
    required String recordId,
    required RecordType type,
    void Function(double progress)? onProgress,
  }) async {
    attempts++;
    final f = failure;
    if (f != null && (succeedAfter == null || attempts <= succeedAfter!)) {
      throw f;
    }
    return attachment.copyWith(
      storagePath: 'p/$recordId/${attachment.id}',
      downloadUrl: 'https://example.com/${attachment.id}',
      sync: SyncState.synced,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Captures what the queue writes back, without a Firestore.
class _FakeRecords implements RecordRepository {
  final List<List<Attachment>> writes = [];

  @override
  Future<void> updateFiles({
    required String uid,
    required String childId,
    required String recordId,
    required List<Attachment> attachments,
    Attachment? answerKey,
    Attachment? hardWords,
    Attachment? examTimetable,
  }) async {
    writes.add(attachments);
  }

  @override
  Future<List<DiaryRecord>> pendingUploads({
    required String uid,
    required String childId,
  }) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

DiaryRecord recordWithPendingFile() => DiaryRecord(
  id: 'r1',
  childId: 'c1',
  academicYearId: '2026–27',
  type: RecordType.worksheet,
  subject: 'Mathematics',
  title: 'Fractions',
  date: DateTime(2026, 8, 23),
  attachments: const [
    Attachment(
      id: 'a1',
      name: 'page-1.jpg',
      meta: 'Page 1',
      localPath: '/tmp/page-1.jpg',
      sync: SyncState.pending,
    ),
  ],
);

/// Lets the queue's async drain finish.
Future<void> drain() async {
  for (var i = 0; i < 40; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late ValueNotifier<bool> offline;

  setUp(() => offline = ValueNotifier<bool>(false));
  tearDown(() => offline.dispose());

  UploadQueue queueWith(_FakeAttachments a, _FakeRecords r) =>
      UploadQueue(attachments: a, records: r, offline: offline);

  test('a successful upload settles the queue as idle', () async {
    final attachments = _FakeAttachments();
    final records = _FakeRecords();
    final queue = queueWith(attachments, records)
      ..enqueue(uid: 'u', childId: 'c1', record: recordWithPendingFile());

    await drain();

    expect(queue.status, QueueStatus.idle);
    expect(records.writes.single.single.sync, SyncState.synced);
    expect(records.writes.single.single.downloadUrl, isNotNull);
    queue.dispose();
  });

  test('a permanently failed upload reports failed, not idle', () async {
    // The regression this exists for: the upload error is caught inside the
    // queue and turned into a marked attachment rather than rethrown, so a
    // drain that "completed" used to reset the status to idle — and the More
    // screen cheerfully read "Synced" while the file was stranded.
    final attachments = _FakeAttachments(
      failure: const AppFailure(
        FailureKind.notFound,
        'gone',
        canRetry: false,
      ),
    );
    final records = _FakeRecords();
    final queue = queueWith(attachments, records)
      ..enqueue(uid: 'u', childId: 'c1', record: recordWithPendingFile());

    await drain();

    expect(
      queue.status,
      QueueStatus.failed,
      reason: 'a stranded file must not be reported as synced',
    );
    expect(records.writes.single.single.sync, SyncState.failed);
    queue.dispose();
  });

  test('a retryable failure is retried, then capped', () async {
    final attachments = _FakeAttachments(
      failure: const AppFailure(FailureKind.offline, 'no network'),
    );
    final records = _FakeRecords();
    final queue = queueWith(attachments, records)
      ..enqueue(uid: 'u', childId: 'c1', record: recordWithPendingFile());

    await drain();

    expect(
      attachments.attempts,
      UploadQueue.maxAttempts,
      reason: 'retries must be bounded, not infinite',
    );
    expect(queue.status, QueueStatus.failed);
    queue.dispose();
  });

  test('a flaky upload that later succeeds ends idle', () async {
    final attachments = _FakeAttachments(
      failure: const AppFailure(FailureKind.offline, 'no network'),
      succeedAfter: 1,
    );
    final records = _FakeRecords();
    final queue = queueWith(attachments, records)
      ..enqueue(uid: 'u', childId: 'c1', record: recordWithPendingFile());

    await drain();

    expect(queue.status, QueueStatus.idle);
    expect(records.writes.last.single.sync, SyncState.synced);
    queue.dispose();
  });

  test('an already-synced record is not queued at all', () async {
    final attachments = _FakeAttachments();
    final records = _FakeRecords();
    final queue = queueWith(attachments, records)
      ..enqueue(
        uid: 'u',
        childId: 'c1',
        record: recordWithPendingFile().copyWith(
          attachments: const [
            Attachment(id: 'a1', name: 'p.jpg', meta: '', sync: SyncState.synced),
          ],
        ),
      );

    await drain();

    expect(attachments.attempts, 0);
    expect(queue.status, QueueStatus.idle);
    queue.dispose();
  });

  test('while offline the queue waits instead of uploading', () async {
    offline.value = true;
    final attachments = _FakeAttachments();
    final records = _FakeRecords();
    final queue = queueWith(attachments, records)
      ..enqueue(uid: 'u', childId: 'c1', record: recordWithPendingFile());

    await drain();
    expect(queue.status, QueueStatus.waiting);
    expect(attachments.attempts, 0);

    // Reconnecting drains it without any further prompting.
    offline.value = false;
    await drain();
    expect(queue.status, QueueStatus.idle);
    expect(attachments.attempts, 1);
    queue.dispose();
  });
}
