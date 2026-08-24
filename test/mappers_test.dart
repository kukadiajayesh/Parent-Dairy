import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:parent_academic_diary/core/theme/subject_hue.dart';
import 'package:parent_academic_diary/data/mappers.dart';
import 'package:parent_academic_diary/data/models.dart';

void main() {
  late FakeFirebaseFirestore db;

  setUp(() => db = FakeFirebaseFirestore());

  Future<DocumentSnapshot<Map<String, dynamic>>> write(
    Map<String, dynamic> data,
  ) async {
    final ref = db.collection('t').doc('d');
    await ref.set(data);
    return ref.get();
  }

  group('record mapping', () {
    test('round-trips every field the timeline reads', () async {
      final original = DiaryRecord(
        id: 'ignored',
        childId: 'child-1',
        academicYearId: '2026–27',
        type: RecordType.classwork,
        subject: 'Science',
        title: 'Leaf diagram',
        date: DateTime(2026, 8, 20),
        dueDate: DateTime(2026, 9, 1),
        completedDate: DateTime(2026, 8, 22),
        notes: 'Copied from board',
        status: WorksheetStatus.completed,
        attachments: const [
          Attachment(
            id: 'a1',
            name: 'leaf.jpg',
            meta: 'Photo 1',
            fileSize: 1234,
            mimeType: 'image/jpeg',
            downloadUrl: 'https://example.com/leaf.jpg',
          ),
        ],
        answerKey: const Attachment(
          id: 'k1',
          name: 'key.pdf',
          meta: '240 KB',
          isPdf: true,
        ),
      );

      final snapshot = await write(Map$.recordToMap(original));
      final parsed = Map$.recordFrom(snapshot);

      expect(parsed.childId, 'child-1');
      expect(parsed.academicYearId, '2026–27');
      expect(parsed.type, RecordType.classwork);
      expect(parsed.subject, 'Science');
      expect(parsed.title, 'Leaf diagram');
      expect(parsed.date, DateTime(2026, 8, 20));
      expect(parsed.dueDate, DateTime(2026, 9, 1));
      expect(parsed.completedDate, DateTime(2026, 8, 22));
      expect(parsed.notes, 'Copied from board');
      expect(parsed.status, WorksheetStatus.completed);
      expect(parsed.attachments.single.name, 'leaf.jpg');
      expect(parsed.attachments.single.fileSize, 1234);
      expect(parsed.attachments.single.downloadUrl, isNotNull);
      expect(parsed.answerKey?.isPdf, isTrue);
      expect(parsed.isDeleted, isFalse);
    });

    test('a nearly empty document parses instead of throwing', () async {
      // Guards against a partial write or an older schema taking down the
      // whole timeline.
      final snapshot = await write(<String, dynamic>{'title': 'Only a title'});
      final parsed = Map$.recordFrom(snapshot);

      expect(parsed.title, 'Only a title');
      expect(parsed.subject, '');
      expect(parsed.type, RecordType.worksheet);
      expect(parsed.attachments, isEmpty);
      expect(parsed.answerKey, isNull);
      expect(parsed.date, isNotNull);
    });

    test('an attachments field of the wrong shape yields an empty list',
        () async {
      final snapshot = await write(<String, dynamic>{
        'title': 't',
        'attachments': 'not-a-list',
      });
      expect(Map$.recordFrom(snapshot).attachments, isEmpty);
    });

    test('flags a record with unsent files so the queue can find it', () {
      final map = Map$.recordToMap(
        DiaryRecord(
          id: 'r',
          type: RecordType.worksheet,
          subject: 'Mathematics',
          title: 't',
          date: DateTime(2026, 8, 23),
          attachments: const [
            Attachment(name: 'a.jpg', meta: '', sync: SyncState.pending),
          ],
        ),
      );
      expect(map['hasPendingUpload'], isTrue);
    });
  });

  group('searchTerms', () {
    List<String> termsFor({String title = '', String notes = '', String subject = ''}) =>
        Map$.searchTermsFor(
          DiaryRecord(
            id: 'r',
            type: RecordType.worksheet,
            subject: subject,
            title: title,
            notes: notes,
            date: DateTime(2026, 8, 23),
          ),
        );

    test('covers title, notes and subject, lower-cased', () {
      final terms = termsFor(
        title: 'Fractions Practice',
        notes: 'Pages 24-25',
        subject: 'Mathematics',
      );
      expect(terms, containsAll(['fractions', 'practice', 'mathematics', 'pages', '24', '25']));
    });

    test('drops single characters and de-duplicates', () {
      final terms = termsFor(title: 'a a Maths Maths');
      expect(terms.where((t) => t == 'maths').length, 1);
      expect(terms, isNot(contains('a')));
    });

    test('is bounded so a long note cannot bloat the document', () {
      final terms = termsFor(
        notes: List.generate(200, (i) => 'word$i').join(' '),
      );
      expect(terms.length, lessThanOrEqualTo(40));
    });
  });

  group('subject and year mapping', () {
    test('an unknown hue falls back to stone rather than throwing', () async {
      final snapshot = await write(<String, dynamic>{
        'name': 'Robotics',
        'abbr': 'RO',
        'hue': 'chartreuse',
        'order': 9,
      });
      expect(Map$.subjectFrom(snapshot).hue, SubjectHue.stone);
    });

    test('a subject with no active flag is treated as active', () async {
      final snapshot = await write(<String, dynamic>{'name': 'Art'});
      expect(Map$.subjectFrom(snapshot).active, isTrue);
    });

    test('a child with no stored initials derives them from the name',
        () async {
      final snapshot = await write(<String, dynamic>{'name': 'Aarav Patel'});
      expect(Map$.childFrom(snapshot).initials, 'AP');
    });
  });
}
