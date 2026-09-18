import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:parent_academic_diary/core/services/ai/subject_matcher.dart';
import 'package:parent_academic_diary/data/models.dart';
import 'package:parent_academic_diary/data/models_ai.dart';
import 'package:parent_academic_diary/features/ai/scan_timetable_page.dart';

import 'notice_test_support.dart';

Future<Map<String, Object?>> fixture(String name) async =>
    Map<String, Object?>.from(jsonDecode(await File('test/fixtures/ai/$name').readAsString()) as Map);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TimetableExtraction', () {
    test('parses the fixture, drops the subject-less row and sorts undated last', () async {
      final t = TimetableExtraction.fromJson(await fixture('timetable.json'));
      expect(t.examLabel, 'Half Yearly Examination');
      expect(t.confidence, closeTo(0.86, 0.001));
      expect(t.entries.length, 4);
      expect(t.droppedRows, 1);
      expect(t.unreadable, 'the last row is cut off');

      final sorted = t.sorted;
      expect(sorted.map((e) => e.subject), ['Maths', 'Hindi', 'English', 'EVS']);
      expect(sorted.first.startsAt, DateTime(2026, 10, 5, 9));
      expect(sorted[1].startsAt, DateTime(2026, 10, 6, 9, 30));
      expect(sorted[2].startsAt, DateTime(2026, 10, 7));
      expect(sorted.last.date, isNull);
      expect(sorted.last.wantsReview, isTrue);
      expect(sorted.first.wantsReview, isFalse);
      expect(sorted.first.notes, 'Ch 1-6');
    });

    test('round-trips through toJson and maps printed subjects to the child\'s', () async {
      final t = TimetableExtraction.fromJson(await fixture('timetable.json'));
      final again = TimetableExtraction.fromJson(t.toJson());
      expect(again.entries.length, 4);
      expect(again.sorted.first.startTime, (9, 0));
      const known = ['Mathematics', 'English', 'Hindi', 'Environmental Studies'];
      expect(
        [for (final e in t.sorted) SubjectMatcher.match(e.subject, known)],
        ['Mathematics', 'Hindi', 'English', 'Environmental Studies'],
      );
    });

    test('the review turns rows into schedule notes', () {
      final review = TimetableReview(
        examLabel: 'Unit Test 2',
        rows: [
          TimetableRow(subject: 'Mathematics', date: DateTime(2026, 10, 5, 9), notes: 'Ch 1-6'),
          TimetableRow(subject: 'English', date: DateTime(2026, 10, 7)),
        ],
        model: 'gemini-test',
      );
      expect(review.scheduleNotes, 'Mon, 5 Oct 9:00 am · Mathematics (Ch 1-6)\nWed, 7 Oct · English');
    });
  });

  group('saveTimetableExams', () {
    late NoticeHarness h;
    tearDown(() => h.dispose());

    test('creates one exam per row sharing the timetable, with reminders armed per date', () async {
      h = NoticeHarness(enabled: false);
      final state = await h.start();
      const timetable = Attachment(
        id: 'tt-1',
        name: 'timetable.jpg',
        meta: '120 KB',
        localPath: '/tmp/timetable.jpg',
        sync: SyncState.pending,
      );
      final saved = await state.saveTimetableExams(
        entries: [
          (subject: 'Mathematics', date: DateTime(2026, 10, 5)),
          (subject: 'English', date: DateTime(2026, 10, 7)),
          (subject: 'Hindi', date: DateTime(2026, 10, 6)),
        ],
        examType: 'Half Yearly',
        timetable: timetable,
        scheduleNotes: 'Mon, 5 Oct · Mathematics',
        model: 'gemini-test',
      );
      await settle(12);

      expect(saved.length, 3);
      expect(saved.map((r) => r.subject), ['Mathematics', 'English', 'Hindi']);
      expect(saved.every((r) => r.isExam && r.examType == 'Half Yearly'), isTrue);
      expect(saved.every((r) => r.origin == RecordOrigin.ai), isTrue);
      expect(saved.every((r) => r.examTimetable?.name == 'timetable.jpg'), isTrue);
      // Each record uploads under its own folder, so the ids must differ.
      expect(saved.map((r) => r.examTimetable!.id).toSet().length, 3);
      expect(saved[1].date, DateTime(2026, 10, 7));
      expect(saved.first.notes, contains('gemini-test'));
      expect(saved.first.notes, contains('Mon, 5 Oct · Mathematics'));
      expect(state.records.where((r) => r.isExam).length, 3);
    });
  });
}
