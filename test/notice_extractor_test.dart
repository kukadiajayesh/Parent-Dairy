import 'package:flutter_test/flutter_test.dart';
import 'package:parent_academic_diary/data/analytics/notice_extractor.dart';
import 'package:parent_academic_diary/data/models.dart';

/// The fixture corpus (prompt 03 §G) — this is the spec for stage 1. Every
/// entry is a realistic school-app notification; add to it whenever a real
/// one is misread.
///
/// All anchored on Sunday 20 September 2026, 18:30.
final postedAt = DateTime(2026, 9, 20, 18, 30);
const subjects = ['Mathematics', 'English', 'Science', 'Hindi', 'Gujarati', 'Social Science', 'Computer'];

class Case {
  const Case(
    this.title,
    this.body, {
    required this.kind,
    this.date,
    this.end,
    this.hour,
    required this.confidence,
    this.subject,
    this.ambiguous = false,
    this.cleanTitle,
  });

  final String title;
  final String body;
  final NoticeKind kind;
  final DateTime? date;
  final DateTime? end;
  final int? hour;
  final double confidence;
  final String? subject;
  final bool ambiguous;
  final String? cleanTitle;
}

final corpus = <Case>[
  // ── exams, every absolute date format ──────────────────────────────────
  Case('Unit Test 2 — Science — 24 Nov', 'Syllabus: Ch 5 to 8.',
      kind: NoticeKind.exam, date: DateTime(2026, 11, 24), confidence: 0.9, subject: 'Science', cleanTitle: 'Science Unit Test 2'),
  Case('Circular', 'Periodic Test 1 in Mathematics will be held on 24/11/2026.',
      kind: NoticeKind.exam, date: DateTime(2026, 11, 24), confidence: 0.9, subject: 'Mathematics'),
  Case('Exam schedule', 'Half yearly exams start from 24-11-26. Timetable to follow.',
      kind: NoticeKind.exam, date: DateTime(2026, 11, 24), confidence: 0.9),
  Case('UT 3', 'English UT 3 on 24th November. Bring your own stationery.',
      kind: NoticeKind.exam, date: DateTime(2026, 11, 24), confidence: 0.9, subject: 'English'),
  Case('Assessment', 'Hindi assessment on November 24. Chapters 1-4.',
      kind: NoticeKind.exam, date: DateTime(2026, 11, 24), confidence: 0.9, subject: 'Hindi'),
  Case('Reminder', 'Mon 24 Nov: Science practical viva for class 5.',
      kind: NoticeKind.exam, date: DateTime(2026, 11, 24), confidence: 0.9, subject: 'Science'),
  Case('Class test', 'Maths class test on 24.11 covering fractions and decimals.',
      kind: NoticeKind.exam, date: DateTime(2026, 11, 24), confidence: 0.9, subject: 'Mathematics'),
  Case('Term 1 exams', 'Term 1 examination from 5 Oct to 12 Oct. Detailed date sheet attached.',
      kind: NoticeKind.exam, date: DateTime(2026, 10, 5), end: DateTime(2026, 10, 12), confidence: 0.9),
  Case('Pre-board', 'Pre-board exams 24–26 November. Reporting time 8.30 am.',
      kind: NoticeKind.exam, date: DateTime(2026, 11, 24), end: DateTime(2026, 11, 26), hour: 8, confidence: 0.9),
  Case('SST test', 'Social Science test tomorrow. Revise map work.',
      kind: NoticeKind.exam, date: DateTime(2026, 9, 21), confidence: 0.7, subject: 'Social Science'),
  Case('Dictation', 'Gujarati dictation next Monday at 9 am.',
      kind: NoticeKind.exam, date: DateTime(2026, 9, 21), hour: 9, confidence: 0.7, subject: 'Gujarati'),
  // Missing year, month already past this year → next year.
  Case('Board exam', 'Board exam practice test on 5 Jan.',
      kind: NoticeKind.exam, date: DateTime(2027, 1, 5), confidence: 0.9),
  // Missing year, only days ago → stays this year (a past date).
  Case('Result', 'Unit test held on 15 Sep: answer sheets will be shown on Wednesday.',
      kind: NoticeKind.exam, date: DateTime(2026, 9, 15), confidence: 0.6, ambiguous: true),
  Case('Computer exam', 'Comp practical exam on 3rd October 2026 from 10:30 in lab 2.',
      kind: NoticeKind.exam, date: DateTime(2026, 10, 3), hour: 10, confidence: 0.9, subject: 'Computer'),

  // ── assignments ────────────────────────────────────────────────────────
  Case('Homework', 'Complete Maths worksheet 4 and submit by Friday.',
      kind: NoticeKind.assignment, date: DateTime(2026, 9, 25), confidence: 0.7, subject: 'Mathematics'),
  Case('Project submission', 'Science project on plants due on 30 Sep 2026.',
      kind: NoticeKind.assignment, date: DateTime(2026, 9, 30), confidence: 0.9, subject: 'Science'),
  Case('Holiday homework', 'Holiday homework for all subjects to be submitted on 12/10.',
      kind: NoticeKind.assignment, date: DateTime(2026, 10, 12), confidence: 0.9),
  Case('English HW', 'Write an essay on My School. Last date 2 Oct.',
      kind: NoticeKind.assignment, date: DateTime(2026, 10, 2), confidence: 0.9, subject: 'English'),
  Case('Assignment', 'Hindi assignment given today, to be submitted day after tomorrow.',
      kind: NoticeKind.assignment, date: DateTime(2026, 9, 22), confidence: 0.6, subject: 'Hindi', ambiguous: true),
  Case('Worksheet', 'EVS worksheet due in 3 days.',
      kind: NoticeKind.assignment, date: DateTime(2026, 9, 23), confidence: 0.7),

  // ── activities ─────────────────────────────────────────────────────────
  Case('Sports Day', 'Annual sports day on 12 Dec at the school ground, 8 am onwards.',
      kind: NoticeKind.activity, date: DateTime(2026, 12, 12), hour: 8, confidence: 0.9),
  Case('Competition', 'Inter-house elocution competition this Friday. Topic: Save water.',
      kind: NoticeKind.activity, date: DateTime(2026, 9, 25), confidence: 0.7),
  Case('Field trip', 'Field trip to the science city on 15th Oct. Consent form by 10 Oct.',
      kind: NoticeKind.activity, date: DateTime(2026, 10, 15), confidence: 0.6, subject: 'Science', ambiguous: true),
  Case('Rehearsal', 'Annual day rehearsal every day from 1 Dec to 10 Dec after school.',
      kind: NoticeKind.activity, date: DateTime(2026, 12, 1), end: DateTime(2026, 12, 10), confidence: 0.9),
  Case('Fancy dress', 'Fancy dress competition for Class 1 and 2 on 02-10-2026.',
      kind: NoticeKind.activity, date: DateTime(2026, 10, 2), confidence: 0.9),

  // ── holidays ───────────────────────────────────────────────────────────
  Case('Holiday', 'School will remain closed on 2 Oct on account of Gandhi Jayanti.',
      kind: NoticeKind.holiday, date: DateTime(2026, 10, 2), confidence: 0.9),
  Case('Diwali vacation', 'Diwali vacation from 8 Nov to 18 Nov. School reopens on 19 Nov.',
      kind: NoticeKind.holiday, date: DateTime(2026, 11, 8), end: DateTime(2026, 11, 18), confidence: 0.6, ambiguous: true),
  Case('No school', 'No school tomorrow due to heavy rain.',
      kind: NoticeKind.holiday, date: DateTime(2026, 9, 21), confidence: 0.7),

  // ── fees ───────────────────────────────────────────────────────────────
  Case('Fee reminder', 'Term 2 fees to be paid by 10 Oct. Late fee applicable after that.',
      kind: NoticeKind.fee, date: DateTime(2026, 10, 10), confidence: 0.9),
  Case('Fee due', 'Second installment due amount Rs 12,500. Pay online before 30/09/2026.',
      kind: NoticeKind.fee, date: DateTime(2026, 9, 30), confidence: 0.9),

  // ── meetings ───────────────────────────────────────────────────────────
  Case('PTM', 'PTM on Saturday 26 Sep 2026, 9 am to 12 pm. Please be on time.',
      kind: NoticeKind.meeting, date: DateTime(2026, 9, 26), hour: 9, confidence: 0.9),
  Case('Orientation', 'Parent orientation for the new session on Sat, 3 Oct.',
      kind: NoticeKind.meeting, date: DateTime(2026, 10, 3), confidence: 0.9),
  Case('Open house', 'Open house next Wednesday. Report cards will be shared.',
      kind: NoticeKind.meeting, date: DateTime(2026, 9, 23), confidence: 0.7),

  // ── no date / no kind / two dates ──────────────────────────────────────
  Case('Unit test', 'Unit test syllabus has been uploaded on the portal.',
      kind: NoticeKind.exam, confidence: 0.5),
  Case('Notice', 'Kindly send Rs 50 for the class photograph.',
      kind: NoticeKind.announcement, confidence: 0.3),
  Case('Bus route', 'Bus no. 7 will leave 10 minutes early from Monday.',
      kind: NoticeKind.announcement, date: DateTime(2026, 9, 21), confidence: 0.5),
  Case('Timetable', 'Science test on 24 Nov and Maths test on 26 Nov.',
      kind: NoticeKind.exam, date: DateTime(2026, 11, 24), confidence: 0.6, subject: 'Science', ambiguous: true),
  Case('Good morning', 'Have a great day! Attendance marked.',
      kind: NoticeKind.unknown, confidence: 0.3),

  // ── Hindi / Gujarati script ────────────────────────────────────────────
  Case('सूचना', 'कल विज्ञान की परीक्षा है। कृपया तैयारी करें।',
      kind: NoticeKind.unknown, confidence: 0.3),
  Case('નોટિસ', 'ગણિત ની કસોટી 24/11 ના રોજ છે.',
      kind: NoticeKind.unknown, date: DateTime(2026, 11, 24), confidence: 0.3),
  Case('Notice', 'Science ni pariksha 24 Nov na roj che. (Science test on 24 Nov)',
      kind: NoticeKind.exam, date: DateTime(2026, 11, 24), confidence: 0.9, subject: 'Science'),
];

void main() {
  test('the corpus is at least thirty strings', () {
    expect(corpus.length, greaterThanOrEqualTo(30));
  });

  for (final c in corpus) {
    test('"${c.title}: ${c.body}"', () {
      final e = NoticeExtractor.extract(
        title: c.title,
        body: c.body,
        postedAt: postedAt,
        subjects: subjects,
      );
      expect(e.kind, c.kind, reason: 'kind');
      if (c.date == null) {
        expect(e.date, isNull, reason: 'date');
      } else {
        expect(e.date, isNotNull, reason: 'date');
        expect(DateTime(e.date!.year, e.date!.month, e.date!.day), c.date, reason: 'date');
      }
      if (c.end != null) expect(e.endAt, c.end, reason: 'endAt');
      if (c.hour != null) {
        expect(e.allDay, isFalse, reason: 'allDay');
        expect(e.date!.hour, c.hour, reason: 'hour');
      } else if (c.date != null) {
        expect(e.allDay, isTrue, reason: 'allDay');
      }
      expect(e.confidence, closeTo(c.confidence, 0.001), reason: 'confidence');
      expect(e.subject, c.subject, reason: 'subject');
      expect(e.isAmbiguous, c.ambiguous, reason: 'ambiguous');
      if (c.cleanTitle != null) expect(e.title, c.cleanTitle, reason: 'title');
      expect(e.source, 'rules');
      if (c.kind != NoticeKind.unknown || c.date != null) {
        expect(e.matchedPhrases, isNotEmpty, reason: 'matchedPhrases');
      }
    });
  }

  test('a due date lands in dueAt for assignments and eventAt for exams', () {
    final hw = NoticeExtractor.extract(title: 'HW', body: 'Submit by 30 Sep', postedAt: postedAt);
    expect(hw.dueAt, DateTime(2026, 9, 30));
    expect(hw.eventAt, isNull);
    final exam = NoticeExtractor.extract(title: 'Exam', body: 'Exam on 30 Sep', postedAt: postedAt);
    expect(exam.eventAt, DateTime(2026, 9, 30));
    expect(exam.dueAt, isNull);
  });

  test('times: 9 am, 09:00, 9.30am, 2 PM onwards', () {
    int hour(String body) =>
        NoticeExtractor.extract(title: 'PTM', body: body, postedAt: postedAt).date!.hour;
    expect(hour('PTM on 26 Sep at 9 am'), 9);
    expect(hour('PTM on 26 Sep at 09:00'), 9);
    expect(hour('PTM on 26 Sep 9.30am'), 9);
    expect(hour('PTM on 26 Sep 2 PM onwards'), 14);
    expect(NoticeExtractor.extract(title: 'PTM', body: 'PTM on 26 Sep 9.30am', postedAt: postedAt).date!.minute, 30);
    expect(hour('PTM on 26 Sep at 12 pm'), 12);
  });

  test('relative dates: this vs next weekday', () {
    // Posted on a Sunday.
    DateTime on(String body) =>
        NoticeExtractor.extract(title: 'Test', body: body, postedAt: postedAt).date!;
    expect(on('Test this Sunday'), DateTime(2026, 9, 20));
    expect(on('Test next Sunday'), DateTime(2026, 9, 27));
    expect(on('Test on Thursday'), DateTime(2026, 9, 24));
    expect(on('Test coming Tuesday'), DateTime(2026, 9, 22));
  });

  test('numeric dates are day-first and a month above 12 is not a date', () {
    final e = NoticeExtractor.extract(title: 'Test', body: 'Test on 11/24', postedAt: postedAt);
    expect(e.date, isNull);
    expect(e.confidence, 0.5);
  });

  test('the subject list is what decides a subject match', () {
    final e = NoticeExtractor.extract(
      title: 'Test',
      body: 'Sanskrit test on 24 Nov',
      postedAt: postedAt,
      subjects: subjects,
    );
    expect(e.subject, isNull);
    expect(e.title, 'Sanskrit Test');
  });

  test('looksLikeNotice is the keyword rule', () {
    expect(NoticeExtractor.looksLikeNotice('Unit test on Monday'), isTrue);
    expect(NoticeExtractor.looksLikeNotice('Have a nice day'), isFalse);
  });

  test('a title with a generic app string falls back to the body', () {
    final e = NoticeExtractor.extract(
      title: 'New notification',
      body: 'Science project due on 30 Sep. Bring chart paper.',
      postedAt: postedAt,
      subjects: subjects,
    );
    expect(e.title, 'Science project due');
  });
}
