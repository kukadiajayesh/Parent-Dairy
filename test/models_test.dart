import 'package:flutter_test/flutter_test.dart';
import 'package:parent_academic_diary/core/theme/subject_hue.dart';
import 'package:parent_academic_diary/data/models.dart';

void main() {
  group('wire values', () {
    test('survive a round trip', () {
      for (final type in RecordType.values) {
        expect(RecordType.fromWire(type.wire), type);
      }
      for (final status in WorksheetStatus.values) {
        expect(WorksheetStatus.fromWire(status.wire), status);
      }
      for (final sync in SyncState.values) {
        expect(SyncState.fromWire(sync.wire), sync);
      }
    });

    test('fall back rather than throw on unknown input', () {
      // A document written by a future build must not break the timeline.
      expect(RecordType.fromWire('quiz'), RecordType.worksheet);
      expect(WorksheetStatus.fromWire(null), WorksheetStatus.pending);
      expect(SyncState.fromWire('nonsense'), SyncState.synced);
    });
  });

  group('Child.initialsFor', () {
    test('takes first and last initial of a full name', () {
      expect(Child.initialsFor('Aarav Patel'), 'AP');
      expect(Child.initialsFor('  Diya   Rani   Shah '), 'DS');
    });

    test('takes two letters of a single name', () {
      expect(Child.initialsFor('Diya'), 'DI');
    });

    test('degrades safely', () {
      expect(Child.initialsFor('A'), 'A');
      expect(Child.initialsFor(''), '?');
      expect(Child.initialsFor('   '), '?');
    });
  });

  group('DiaryRecord', () {
    DiaryRecord record({
      List<Attachment> attachments = const [],
      Attachment? answerKey,
    }) => DiaryRecord(
      id: 'r1',
      type: RecordType.worksheet,
      subject: 'Mathematics',
      title: 'Fractions',
      date: DateTime(2026, 8, 23),
      attachments: attachments,
      answerKey: answerKey,
    );

    const pending = Attachment(
      name: 'a.jpg',
      meta: 'Page 1',
      sync: SyncState.pending,
    );
    const synced = Attachment(name: 'b.jpg', meta: 'Page 2');
    const failed = Attachment(
      name: 'c.jpg',
      meta: 'Page 3',
      sync: SyncState.failed,
    );

    test('a record with no files is settled', () {
      expect(record().sync, SyncState.synced);
    });

    test('reports the worst state across its files', () {
      expect(record(attachments: [synced, pending]).sync, SyncState.pending);
      expect(
        record(attachments: [synced, pending, failed]).sync,
        SyncState.failed,
      );
    });

    test('counts the answer key as a file but not as a page', () {
      final r = record(attachments: [synced], answerKey: pending);
      expect(r.fileCount, 1, reason: 'the design lists pages, not all files');
      expect(r.allFiles.length, 2);
      expect(r.sync, SyncState.pending);
    });

    test('copyWith can clear the fields that are legitimately nullable', () {
      final r = DiaryRecord(
        id: 'r1',
        type: RecordType.worksheet,
        subject: 'Mathematics',
        title: 'Fractions',
        date: DateTime(2026, 8, 23),
        dueDate: DateTime(2026, 8, 28),
        answerKey: synced,
      );
      expect(r.copyWith(clearDueDate: true).dueDate, isNull);
      expect(r.copyWith(clearAnswerKey: true).answerKey, isNull);
      // And a plain copy keeps them.
      expect(r.copyWith(title: 'x').dueDate, isNotNull);
    });

    test('overdue means pending, dated in the past, and a worksheet', () {
      final past = DateTime.now().subtract(const Duration(days: 2));
      final future = DateTime.now().add(const Duration(days: 2));

      DiaryRecord make({
        required RecordType type,
        required WorksheetStatus status,
        DateTime? due,
      }) => DiaryRecord(
        id: 'r',
        type: type,
        subject: 'Mathematics',
        title: 't',
        date: past,
        dueDate: due,
        status: status,
      );

      expect(
        make(
          type: RecordType.worksheet,
          status: WorksheetStatus.pending,
          due: past,
        ).isOverdue,
        isTrue,
      );
      expect(
        make(
          type: RecordType.worksheet,
          status: WorksheetStatus.completed,
          due: past,
        ).isOverdue,
        isFalse,
      );
      expect(
        make(
          type: RecordType.worksheet,
          status: WorksheetStatus.pending,
          due: future,
        ).isOverdue,
        isFalse,
      );
      expect(
        make(
          type: RecordType.classwork,
          status: WorksheetStatus.pending,
          due: past,
        ).isOverdue,
        isFalse,
      );
    });
  });

  group('Attachment', () {
    test('is only uploaded once it has a download URL', () {
      const staged = Attachment(name: 'a.jpg', meta: '', sync: SyncState.pending);
      expect(staged.isUploaded, isFalse);
      expect(
        staged.copyWith(downloadUrl: 'https://example.com/a.jpg').isUploaded,
        isTrue,
      );
    });
  });

  group('Subject', () {
    test('copyWith preserves the hue and order it is not given', () {
      const subject = Subject(
        name: 'Mathematics',
        abbr: 'MA',
        hue: SubjectHue.indigo,
        order: 1,
      );
      final renamed = subject.copyWith(name: 'Maths');
      expect(renamed.hue, SubjectHue.indigo);
      expect(renamed.order, 1);
      expect(renamed.name, 'Maths');
    });
  });
}
