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


  group('result mapping', () {
    test('round-trips a report card and stamps the scale onto every row',
        () async {
      final original = ExamResult(
        id: 'ignored',
        childId: 'child-1',
        academicYearId: '2026–27',
        examLabel: 'Half Yearly',
        date: DateTime(2026, 9, 15),
        examRecordId: 'exam-9',
        scores: const [
          SubjectScore(
            subject: 'Mathematics',
            marks: 72,
            maxMarks: 80,
            classRank: 3,
            remarks: 'Careless in ch. 4',
          ),
          SubjectScore(subject: 'English', grade: 'A2'),
          SubjectScore(subject: 'Hindi', absent: true),
        ],
        attendancePercent: 96,
        teacherRemarks: 'Good effort',
        source: ResultSource.scanned,
        extractionConfidence: 0.8,
        needsReview: true,
        gradeScaleId: 'five',
      );

      final snapshot = await write(Map$.resultToMap(original));
      final parsed = Map$.resultFrom(snapshot);

      expect(parsed.childId, 'child-1');
      expect(parsed.academicYearId, '2026–27');
      expect(parsed.examLabel, 'Half Yearly');
      expect(parsed.date, DateTime(2026, 9, 15));
      expect(parsed.examRecordId, 'exam-9');
      expect(parsed.scores, hasLength(3));
      expect(parsed.scores[0].marks, 72);
      expect(parsed.scores[0].maxMarks, 80);
      expect(parsed.scores[0].classRank, 3);
      expect(parsed.scores[0].remarks, 'Careless in ch. 4');
      expect(parsed.scores[1].grade, 'A2');
      expect(parsed.scores[1].gradeScaleId, 'five');
      expect(parsed.scores[2].absent, isTrue);
      expect(parsed.attendancePercent, 96);
      expect(parsed.teacherRemarks, 'Good effort');
      expect(parsed.source, ResultSource.scanned);
      expect(parsed.extractionConfidence, 0.8);
      expect(parsed.needsReview, isTrue);
      expect(parsed.gradeScaleId, 'five');
      expect(parsed.isDeleted, isFalse);
    });

    test('a partial or oddly typed document parses instead of throwing',
        () async {
      final snapshot = await write(<String, dynamic>{
        'examLabel': 'Only a label',
        'scores': [
          {'subject': 'Mathematics', 'marks': '45', 'maxMarks': 50},
          'not a map',
          {'subject': 'English', 'grade': '', 'classRank': 2.0},
        ],
        'extractionConfidence': 7,
      });
      final parsed = Map$.resultFrom(snapshot);

      expect(parsed.examLabel, 'Only a label');
      expect(parsed.scores, hasLength(2));
      expect(parsed.scores[0].marks, 45);
      expect(parsed.scores[0].percent, 90);
      expect(parsed.scores[1].grade, isNull, reason: 'blank grade is no grade');
      expect(parsed.scores[1].classRank, 2);
      expect(parsed.extractionConfidence, 1, reason: 'clamped into 0–1');
      expect(parsed.source, ResultSource.manual);
      expect(parsed.gradeScaleId, 'cbse9');
    });

    test('search terms cover the label and every subject', () {
      final r = ExamResult(
        id: '',
        childId: 'c',
        academicYearId: '2026–27',
        examLabel: 'Unit Test 2',
        date: DateTime(2026, 9, 1),
        scores: const [
          SubjectScore(subject: 'Social Science'),
          SubjectScore(subject: 'Hindi'),
        ],
      );
      expect(
        Map$.resultSearchTerms(r),
        containsAll(['unit', 'test', 'social', 'science', 'hindi']),
      );
      expect(Map$.resultSearchTerms(r), isNot(contains('2')));
    });
  });
}
