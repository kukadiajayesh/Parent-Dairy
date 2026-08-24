import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_academic_diary/core/errors/app_failure.dart';
import 'package:parent_academic_diary/data/firestore_paths.dart';
import 'package:parent_academic_diary/data/models.dart';
import 'package:parent_academic_diary/data/repositories/record_repository.dart';
import 'package:parent_academic_diary/data/repositories/subject_repository.dart';
import 'package:parent_academic_diary/data/repositories/year_repository.dart';

const uid = 'parent-1';
const childId = 'child-1';
const year = '2026–27';

DiaryRecord sample({
  String id = '',
  String title = 'Fractions Practice',
  String subject = 'Mathematics',
  String yearLabel = year,
  RecordType type = RecordType.worksheet,
  DateTime? date,
  DateTime? dueDate,
  String notes = '',
  List<Attachment> attachments = const [],
}) => DiaryRecord(
  id: id,
  childId: childId,
  academicYearId: yearLabel,
  type: type,
  subject: subject,
  title: title,
  notes: notes,
  date: date ?? DateTime(2026, 8, 23),
  dueDate: dueDate,
  attachments: attachments,
);

void main() {
  late FakeFirebaseFirestore db;
  const records = RecordRepository();

  setUp(() {
    db = FakeFirebaseFirestore();
    Paths.db = db;
  });

  tearDown(() => Paths.db = null);

  group('save', () {
    test('assigns an id on create and reuses it on update', () async {
      final created = await records.save(
        uid: uid,
        childId: childId,
        record: sample(),
      );
      expect(created.id, isNotEmpty);

      final updated = await records.save(
        uid: uid,
        childId: childId,
        record: created.copyWith(title: 'Fractions Practice v2'),
      );
      expect(updated.id, created.id);

      final all = await Paths.records(uid, childId).get();
      expect(all.docs.length, 1, reason: 'update must not create a second doc');
      expect(all.docs.single.data()['title'], 'Fractions Practice v2');
    });

    test('stamps the child id from the path, not from the caller', () async {
      final saved = await records.save(
        uid: uid,
        childId: childId,
        record: sample().copyWith(childId: 'someone-else'),
      );
      expect(saved.childId, childId);
    });
  });

  group('validation (§31)', () {
    Future<void> expectRejected(DiaryRecord record) async {
      await expectLater(
        records.save(uid: uid, childId: childId, record: record),
        throwsA(isA<AppFailure>()),
      );
    }

    test('rejects a blank title', () => expectRejected(sample(title: '   ')));
    test('rejects a missing subject', () => expectRejected(sample(subject: '')));
    test('rejects a missing year', () => expectRejected(sample(yearLabel: '')));

    test('rejects a due date before the worksheet date', () {
      return expectRejected(
        sample(date: DateTime(2026, 8, 20), dueDate: DateTime(2026, 8, 10)),
      );
    });

    test('accepts a due date on the same day', () async {
      final saved = await records.save(
        uid: uid,
        childId: childId,
        record: sample(
          date: DateTime(2026, 8, 20),
          dueDate: DateTime(2026, 8, 20),
        ),
      );
      expect(saved.id, isNotEmpty);
    });

    test('nothing invalid reaches Firestore', () async {
      await expectRejected(sample(title: ''));
      final all = await Paths.records(uid, childId).get();
      expect(all.docs, isEmpty);
    });
  });

  group('watch', () {
    test('returns only the requested year, newest first', () async {
      await records.save(
        uid: uid,
        childId: childId,
        record: sample(title: 'Older', date: DateTime(2026, 8, 1)),
      );
      await records.save(
        uid: uid,
        childId: childId,
        record: sample(title: 'Newer', date: DateTime(2026, 8, 20)),
      );
      await records.save(
        uid: uid,
        childId: childId,
        record: sample(title: 'Last year', yearLabel: '2025–26'),
      );

      final page = await records
          .watch(uid: uid, childId: childId, yearLabel: year)
          .first;

      expect(page.map((r) => r.title), ['Newer', 'Older']);
    });

    test('excludes soft-deleted records', () async {
      final saved = await records.save(
        uid: uid,
        childId: childId,
        record: sample(),
      );
      await records.softDelete(uid: uid, childId: childId, recordId: saved.id);

      final page = await records
          .watch(uid: uid, childId: childId, yearLabel: year)
          .first;
      expect(page, isEmpty);
    });
  });

  group('soft delete (§30)', () {
    test('keeps the document and can be undone', () async {
      final saved = await records.save(
        uid: uid,
        childId: childId,
        record: sample(),
      );

      await records.softDelete(uid: uid, childId: childId, recordId: saved.id);
      var doc = await Paths.records(uid, childId).doc(saved.id).get();
      expect(doc.exists, isTrue, reason: 'the record must survive deletion');
      expect(doc.data()!['isDeleted'], isTrue);

      await records.restore(uid: uid, childId: childId, recordId: saved.id);
      doc = await Paths.records(uid, childId).doc(saved.id).get();
      expect(doc.data()!['isDeleted'], isFalse);

      final page = await records
          .watch(uid: uid, childId: childId, yearLabel: year)
          .first;
      expect(page.single.id, saved.id);
    });
  });

  group('markCompleted', () {
    test('sets and clears the completion date', () async {
      final saved = await records.save(
        uid: uid,
        childId: childId,
        record: sample(),
      );

      await records.markCompleted(
        uid: uid,
        childId: childId,
        recordId: saved.id,
        completed: true,
      );
      var doc = await Paths.records(uid, childId).doc(saved.id).get();
      expect(doc.data()!['status'], 'completed');
      expect(doc.data()!['completedDate'], isNotNull);

      await records.markCompleted(
        uid: uid,
        childId: childId,
        recordId: saved.id,
        completed: false,
      );
      doc = await Paths.records(uid, childId).doc(saved.id).get();
      expect(doc.data()!['status'], 'pending');
      expect(doc.data()!['completedDate'], isNull);
    });
  });

  group('search (§15)', () {
    setUp(() async {
      await records.save(
        uid: uid,
        childId: childId,
        record: sample(title: 'Fractions Practice', subject: 'Mathematics'),
      );
      await records.save(
        uid: uid,
        childId: childId,
        record: sample(
          title: 'Chapter 4 comprehension',
          subject: 'English',
          notes: 'Read the passage twice',
          type: RecordType.classwork,
        ),
      );
      await records.save(
        uid: uid,
        childId: childId,
        record: sample(title: 'Old multiplication drill', yearLabel: '2025–26'),
      );
    });

    test('matches on subject', () async {
      final found = await records.search(
        uid: uid,
        childId: childId,
        query: 'mathematics',
        yearLabel: year,
      );
      expect(found.single.title, 'Fractions Practice');
    });

    test('matches on a note', () async {
      final found = await records.search(
        uid: uid,
        childId: childId,
        query: 'passage',
        yearLabel: year,
      );
      expect(found.single.subject, 'English');
    });

    test('is case-insensitive and ignores punctuation', () async {
      final found = await records.search(
        uid: uid,
        childId: childId,
        query: '  FRACTIONS! ',
        yearLabel: year,
      );
      expect(found, hasLength(1));
    });

    test('scopes to the active year unless asked for all years', () async {
      final scoped = await records.search(
        uid: uid,
        childId: childId,
        query: 'drill',
        yearLabel: year,
      );
      expect(scoped, isEmpty);

      final everywhere = await records.search(
        uid: uid,
        childId: childId,
        query: 'drill',
      );
      expect(everywhere, hasLength(1));
    });

    test('a multi-word query requires every word', () async {
      final both = await records.search(
        uid: uid,
        childId: childId,
        query: 'fractions practice',
        yearLabel: year,
      );
      expect(both, hasLength(1));

      final mismatch = await records.search(
        uid: uid,
        childId: childId,
        query: 'fractions comprehension',
        yearLabel: year,
      );
      expect(mismatch, isEmpty);
    });

    test('an empty query returns nothing rather than everything', () async {
      final found = await records.search(
        uid: uid,
        childId: childId,
        query: '   ',
        yearLabel: year,
      );
      expect(found, isEmpty);
    });
  });

  group('pendingUploads', () {
    test('finds records whose files never reached Storage', () async {
      await records.save(
        uid: uid,
        childId: childId,
        record: sample(title: 'Synced'),
      );
      await records.save(
        uid: uid,
        childId: childId,
        record: sample(
          title: 'Queued',
          attachments: const [
            Attachment(name: 'a.jpg', meta: '', sync: SyncState.pending),
          ],
        ),
      );

      final stranded = await records.pendingUploads(uid: uid, childId: childId);
      expect(stranded.map((r) => r.title), ['Queued']);
    });
  });

  group('YearRepository', () {
    const years = YearRepository();

    test('derives an April–March span from a label', () {
      expect(YearRepository.spanFor('2026–27'), 'Apr 2026 – Mar 2027');
      expect(YearRepository.spanFor('nonsense'), 'nonsense');
    });

    test('keeps exactly one year active', () async {
      await years.create(
        uid,
        const AcademicYear(label: '2025–26', span: '', records: 0, active: true),
      );
      await years.create(
        uid,
        const AcademicYear(label: '2026–27', span: '', records: 0),
      );

      await years.setActive(uid, '2026–27');
      final all = await Paths.years(uid).get();
      final active = all.docs.where((d) => d.data()['active'] == true);
      expect(active, hasLength(1));
      expect(active.single.data()['label'], '2026–27');
    });

    test('seeds only when the account has none', () async {
      await years.seedIfEmpty(uid, '2026–27');
      await years.seedIfEmpty(uid, '2027–28');
      final all = await Paths.years(uid).get();
      expect(all.docs, hasLength(1));
    });

    test('a record-count bump on a missing year is silently ignored', () async {
      await years.bumpRecordCount(uid, 'no-such-year', 1);
      // Reaching here without throwing is the assertion: a dropped counter must
      // never fail the save that triggered it.
      expect(true, isTrue);
    });
  });

  group('SubjectRepository', () {
    const subjects = SubjectRepository();

    test('seeds the default list once', () async {
      await subjects.seedDefaults(uid, childId);
      await subjects.seedDefaults(uid, childId);
      final all = await Paths.subjects(uid, childId).get();
      expect(all.docs, hasLength(SubjectRepository.defaults.length));
    });

    test('deactivating hides a subject but keeps the document', () async {
      final created = await subjects.create(
        uid,
        childId,
        SubjectRepository.defaults.first,
      );
      await subjects.deactivate(uid, childId, created.id);

      final visible = await subjects.watch(uid, childId).first;
      expect(visible, isEmpty);

      final doc = await Paths.subjects(uid, childId).doc(created.id).get();
      expect(doc.exists, isTrue);
    });

    test('reorder rewrites the display order', () async {
      await subjects.seedDefaults(uid, childId);
      final current = await subjects.watch(uid, childId).first;
      final reversed = current.reversed.toList();

      await subjects.reorder(uid, childId, reversed);
      final after = await subjects.watch(uid, childId).first;
      expect(after.map((s) => s.name), reversed.map((s) => s.name));
    });
  });
}
