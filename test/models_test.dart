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


  group('ResultSource', () {
    test('wire values round-trip and unknown input falls back', () {
      for (final source in ResultSource.values) {
        expect(ResultSource.fromWire(source.wire), source);
      }
      expect(ResultSource.fromWire('ocr'), ResultSource.manual);
      expect(ResultSource.fromWire(null), ResultSource.manual);
    });
  });

  group('SubjectScore', () {
    test('percent comes from marks when both are present', () {
      const s = SubjectScore(subject: 'Mathematics', marks: 72, maxMarks: 80);
      expect(s.percent, 90);
      expect(s.isDerivedPercent, isFalse);
    });

    test('falls back to the grade band midpoint and says so', () {
      const s = SubjectScore(subject: 'Mathematics', grade: 'B1');
      expect(s.percent, 75.5);
      expect(s.isDerivedPercent, isTrue);

      const five = SubjectScore(
        subject: 'Mathematics',
        grade: 'B',
        gradeScaleId: 'five',
      );
      expect(five.percent, 70.5);
    });

    test('marks win over a grade when both are present', () {
      const s = SubjectScore(
        subject: 'Mathematics',
        marks: 40,
        maxMarks: 100,
        grade: 'A1',
      );
      expect(s.percent, 40);
      expect(s.isDerivedPercent, isFalse);
    });

    test('an absent row has no percent, whatever else it carries', () {
      const s = SubjectScore(
        subject: 'Mathematics',
        marks: 0,
        maxMarks: 100,
        grade: 'E2',
        absent: true,
      );
      expect(s.percent, isNull);
      expect(s.isDerivedPercent, isFalse);
    });

    test('a zero maximum never divides', () {
      const s = SubjectScore(subject: 'Mathematics', marks: 0, maxMarks: 0);
      expect(s.hasMarks, isFalse);
      expect(s.percent, isNull);
    });
  });

  group('ExamResult', () {
    ExamResult card(List<SubjectScore> scores) => ExamResult(
      id: 'r1',
      childId: 'c',
      academicYearId: '2026–27',
      examLabel: 'Term 1',
      date: DateTime(2026, 9, 1),
      scores: scores,
    );

    test('overallPercent weights by max marks across mixed maxima', () {
      // 40/80 and 90/100: (50×80 + 90×100) / 180 = 72.2 — never 130 "marks".
      final r = card(const [
        SubjectScore(subject: 'Mathematics', marks: 40, maxMarks: 80),
        SubjectScore(subject: 'English', marks: 90, maxMarks: 100),
      ]);
      expect(r.overallPercent, closeTo(72.22, 0.01));
      expect(r.gradedSubjectCount, 2);
    });

    test('overallPercent ignores absent rows rather than scoring them zero',
        () {
      final r = card(const [
        SubjectScore(subject: 'Mathematics', marks: 80, maxMarks: 100),
        SubjectScore(subject: 'Hindi', marks: 0, maxMarks: 100, absent: true),
      ]);
      expect(r.overallPercent, 80);
      expect(r.gradedSubjectCount, 1);
    });

    test('a grade-only row counts as a 100-mark paper', () {
      final r = card(const [
        SubjectScore(subject: 'Mathematics', marks: 50, maxMarks: 50),
        SubjectScore(subject: 'English', grade: 'C1'), // 55.5
      ]);
      // (100×50 + 55.5×100) / 150
      expect(r.overallPercent, closeTo((5000 + 5550) / 150, 0.001));
    });

    test('a card with nothing chartable still exists, with a null overall',
        () {
      final r = card(const [
        SubjectScore(subject: 'Mathematics', absent: true),
        SubjectScore(subject: 'English', grade: 'Distinction'),
      ]);
      expect(r.overallPercent, isNull);
      expect(r.gradedSubjectCount, 0);
      expect(r.scores, hasLength(2));
    });

    test('copyWith re-stamps the grade scale onto every row', () {
      final r = card(const [
        SubjectScore(subject: 'Mathematics', grade: 'A'),
      ]).copyWith(gradeScaleId: 'five');
      expect(r.gradeScaleId, 'five');
      expect(r.scores.single.gradeScaleId, 'five');
      expect(r.scores.single.percent, 90.5);
    });
  });

  group('AcademicYear.contains', () {
    const y = AcademicYear(label: '2026–27', span: '', records: 0);

    test('spans April to March', () {
      expect(y.contains(DateTime(2026, 4, 1)), isTrue);
      expect(y.contains(DateTime(2027, 3, 31)), isTrue);
      expect(y.contains(DateTime(2026, 3, 31)), isFalse);
      expect(y.contains(DateTime(2027, 4, 1)), isFalse);
    });

    test('a label without a year matches nothing', () {
      const odd = AcademicYear(label: 'nonsense', span: '', records: 0);
      expect(odd.contains(DateTime(2026, 9, 1)), isFalse);
    });
  });

  group('Child grade scale', () {
    test('defaults to CBSE and resolves through the registry', () {
      const c = Child(
        name: 'A',
        initials: 'A',
        school: 'S',
        grade: 'Class 5',
        section: 'B',
        year: '2026–27',
      );
      expect(c.gradeScaleId, 'cbse9');
      expect(c.copyWith(gradeScaleId: 'five').gradeScale.label, 'Five-letter (A–E)');
    });
  });
}
