import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_academic_diary/core/errors/app_failure.dart';
import 'package:parent_academic_diary/data/firestore_paths.dart';
import 'package:parent_academic_diary/data/models.dart';
import 'package:parent_academic_diary/data/repositories/result_repository.dart';

const uid = 'parent-1';
const childId = 'child-1';
const year = '2026–27';

ExamResult sample({
  String id = '',
  String label = 'Unit Test 1',
  String yearLabel = year,
  DateTime? date,
  List<SubjectScore>? scores,
}) => ExamResult(
  id: id,
  childId: childId,
  academicYearId: yearLabel,
  examLabel: label,
  date: date ?? DateTime(2026, 8, 20),
  scores:
      scores ??
      const [
        SubjectScore(subject: 'Mathematics', marks: 72, maxMarks: 80),
        SubjectScore(subject: 'English', marks: 90, maxMarks: 100),
      ],
);

void main() {
  late FakeFirebaseFirestore db;
  const repo = ResultRepository();

  setUp(() {
    db = FakeFirebaseFirestore();
    Paths.db = db;
  });

  tearDown(() => Paths.db = null);

  group('save', () {
    test('assigns an id on create and reuses it on update', () async {
      final created = await repo.save(
        uid: uid,
        childId: childId,
        result: sample(),
      );
      expect(created.id, isNotEmpty);

      final updated = await repo.save(
        uid: uid,
        childId: childId,
        result: created.copyWith(examLabel: 'Unit Test 1 (corrected)'),
      );
      expect(updated.id, created.id);

      final all = await Paths.results(uid, childId).get();
      expect(all.docs.length, 1);
      expect(all.docs.single.data()['examLabel'], 'Unit Test 1 (corrected)');
    });

    test('stamps the child id from the path', () async {
      final saved = await repo.save(
        uid: uid,
        childId: childId,
        result: sample().copyWith(childId: 'someone-else'),
      );
      expect(saved.childId, childId);
    });

    test('writes search terms for the label and subjects', () async {
      await repo.save(uid: uid, childId: childId, result: sample());
      final doc = (await Paths.results(uid, childId).get()).docs.single;
      expect(
        doc.data()['searchTerms'],
        containsAll(['unit', 'test', 'mathematics', 'english']),
      );
    });
  });

  group('validation', () {
    Future<void> expectRejected(ExamResult result, [String? contains]) async {
      await expectLater(
        repo.save(uid: uid, childId: childId, result: result),
        throwsA(
          isA<AppFailure>()
              .having((f) => f.kind, 'kind', FailureKind.invalidFile)
              .having((f) => f.canRetry, 'canRetry', isFalse)
              .having(
                (f) => f.message,
                'message',
                contains == null ? isNotEmpty : stringContainsInOrder([contains]),
              ),
        ),
      );
    }

    test('rejects a blank label', () => expectRejected(sample(label: '  ')));
    test('rejects a missing year', () => expectRejected(sample(yearLabel: '')));
    test(
      'rejects an empty score list',
      () => expectRejected(sample(scores: const []), 'at least one subject'),
    );

    test('rejects a date more than a day in the future', () async {
      await expectRejected(
        sample(date: DateTime.now().add(const Duration(days: 2))),
        'future',
      );
      // Tomorrow is fine — the card is often entered the night before.
      final saved = await repo.save(
        uid: uid,
        childId: childId,
        result: sample(date: DateTime.now().add(const Duration(hours: 20))),
      );
      expect(saved.id, isNotEmpty);
    });

    test('rejects marks above the maximum', () async {
      await expectRejected(
        sample(
          scores: const [
            SubjectScore(subject: 'Mathematics', marks: 85, maxMarks: 80),
          ],
        ),
        'Mathematics',
      );
    });

    test('rejects a zero maximum and negative marks', () async {
      await expectRejected(
        sample(
          scores: const [
            SubjectScore(subject: 'Mathematics', marks: 0, maxMarks: 0),
          ],
        ),
      );
      await expectRejected(
        sample(
          scores: const [
            SubjectScore(subject: 'Mathematics', marks: -1, maxMarks: 80),
          ],
        ),
      );
    });

    test('accepts a grade-only card and an all-absent card', () async {
      final graded = await repo.save(
        uid: uid,
        childId: childId,
        result: sample(
          scores: const [SubjectScore(subject: 'Mathematics', grade: 'A1')],
        ),
      );
      expect(graded.id, isNotEmpty);

      // A document of record even when it cannot be charted.
      final absent = await repo.save(
        uid: uid,
        childId: childId,
        result: sample(
          label: 'Missed',
          scores: const [SubjectScore(subject: 'Mathematics', absent: true)],
        ),
      );
      expect(absent.overallPercent, isNull);
    });

    test('nothing invalid reaches Firestore', () async {
      await expectRejected(sample(label: ''));
      final all = await Paths.results(uid, childId).get();
      expect(all.docs, isEmpty);
    });
  });

  group('watch', () {
    test('returns only the requested year, newest first', () async {
      await repo.save(
        uid: uid,
        childId: childId,
        result: sample(label: 'Older', date: DateTime(2026, 7, 1)),
      );
      await repo.save(
        uid: uid,
        childId: childId,
        result: sample(label: 'Newer', date: DateTime(2026, 8, 20)),
      );
      await repo.save(
        uid: uid,
        childId: childId,
        result: sample(
          label: 'Last year',
          yearLabel: '2025–26',
          date: DateTime(2026, 2, 1),
        ),
      );

      final page = await repo
          .watch(uid: uid, childId: childId, yearLabel: year)
          .first;
      expect(page.map((r) => r.examLabel), ['Newer', 'Older']);

      final everything = await repo.allYears(uid: uid, childId: childId);
      expect(everything.map((r) => r.examLabel), [
        'Newer',
        'Older',
        'Last year',
      ]);
    });

    test('round-trips every score field', () async {
      await repo.save(
        uid: uid,
        childId: childId,
        result: sample(
          scores: const [
            SubjectScore(
              subject: 'Science',
              marks: 37.5,
              maxMarks: 50,
              grade: 'B1',
              classRank: 4,
              remarks: 'Revise chapter 3',
            ),
            SubjectScore(subject: 'Hindi', absent: true),
          ],
        ).copyWith(
          attendancePercent: 92.5,
          teacherRemarks: 'Good term',
          gradeScaleId: 'five',
        ),
      );

      final loaded = (await repo
              .watch(uid: uid, childId: childId, yearLabel: year)
              .first)
          .single;
      final science = loaded.scoreFor('Science')!;
      expect(science.marks, 37.5);
      expect(science.maxMarks, 50);
      expect(science.grade, 'B1');
      expect(science.classRank, 4);
      expect(science.remarks, 'Revise chapter 3');
      expect(science.gradeScaleId, 'five');
      expect(loaded.scoreFor('Hindi')!.absent, isTrue);
      expect(loaded.attendancePercent, 92.5);
      expect(loaded.teacherRemarks, 'Good term');
      expect(loaded.source, ResultSource.manual);
      expect(loaded.gradeScaleId, 'five');
    });
  });

  group('soft delete', () {
    test('keeps the document, drops it from reads, and can be undone',
        () async {
      final saved = await repo.save(
        uid: uid,
        childId: childId,
        result: sample(),
      );

      await repo.softDelete(uid: uid, childId: childId, resultId: saved.id);
      var doc = await Paths.results(uid, childId).doc(saved.id).get();
      expect(doc.exists, isTrue);
      expect(doc.data()!['isDeleted'], isTrue);
      expect(
        await repo.watch(uid: uid, childId: childId, yearLabel: year).first,
        isEmpty,
      );

      await repo.restore(uid: uid, childId: childId, resultId: saved.id);
      doc = await Paths.results(uid, childId).doc(saved.id).get();
      expect(doc.data()!['isDeleted'], isFalse);
      expect(
        (await repo.watch(uid: uid, childId: childId, yearLabel: year).first)
            .single
            .id,
        saved.id,
      );
    });
  });

  group('search', () {
    setUp(() async {
      await repo.save(
        uid: uid,
        childId: childId,
        result: sample(label: 'Half Yearly'),
      );
      await repo.save(
        uid: uid,
        childId: childId,
        result: sample(
          label: 'Old term',
          yearLabel: '2025–26',
          date: DateTime(2025, 10, 1),
        ),
      );
    });

    test('matches on label and on subject', () async {
      final byLabel = await repo.search(
        uid: uid,
        childId: childId,
        query: 'half',
        yearLabel: year,
      );
      expect(byLabel.single.examLabel, 'Half Yearly');

      final bySubject = await repo.search(
        uid: uid,
        childId: childId,
        query: 'english',
        yearLabel: year,
      );
      expect(bySubject.single.examLabel, 'Half Yearly');
    });

    test('scopes to a year unless asked for all', () async {
      final scoped = await repo.search(
        uid: uid,
        childId: childId,
        query: 'term',
        yearLabel: year,
      );
      expect(scoped, isEmpty);
      final everywhere = await repo.search(
        uid: uid,
        childId: childId,
        query: 'term',
      );
      expect(everywhere.single.examLabel, 'Old term');
    });
  });
}
