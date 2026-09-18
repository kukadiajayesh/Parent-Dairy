import 'package:flutter_test/flutter_test.dart';
import 'package:parent_academic_diary/data/analytics/notice_extractor.dart';
import 'package:parent_academic_diary/data/analytics/notice_reminders.dart';
import 'package:parent_academic_diary/data/models.dart';

import 'notice_test_support.dart';

NoticeExtraction extraction({
  NoticeKind kind = NoticeKind.exam,
  DateTime? date,
  bool allDay = true,
  double confidence = 0.9,
  List<DateTime> alternates = const [],
}) => NoticeExtraction(
  kind: kind,
  title: 'Test',
  eventAt: kind.isDue ? null : date,
  dueAt: kind.isDue ? date : null,
  allDay: allDay,
  confidence: confidence,
  alternateDates: alternates,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('offsets per kind (§D table)', () {
    final exam = DateTime(2026, 11, 24);

    test('exam: 7, 3, 1 days before and the morning of, all at 07:00', () {
      final times = NoticeReminders.timesFor(extraction(date: exam), now: fixedNow);
      expect(times, [
        DateTime(2026, 11, 17, 7),
        DateTime(2026, 11, 21, 7),
        DateTime(2026, 11, 23, 7),
        DateTime(2026, 11, 24, 7),
      ]);
    });

    test('assignment, activity and meeting: the day before and the morning of', () {
      for (final kind in [NoticeKind.assignment, NoticeKind.activity, NoticeKind.meeting]) {
        final times = NoticeReminders.timesFor(extraction(kind: kind, date: exam), now: fixedNow);
        expect(times, [DateTime(2026, 11, 23, 7), DateTime(2026, 11, 24, 7)], reason: kind.name);
      }
    });

    test('holiday: morning of; fee: 3 days before and morning of', () {
      expect(
        NoticeReminders.timesFor(extraction(kind: NoticeKind.holiday, date: exam), now: fixedNow),
        [DateTime(2026, 11, 24, 7)],
      );
      expect(
        NoticeReminders.timesFor(extraction(kind: NoticeKind.fee, date: exam), now: fixedNow),
        [DateTime(2026, 11, 21, 7), DateTime(2026, 11, 24, 7)],
      );
    });

    test('a timed notice moves the morning-of reminder to an hour before', () {
      final times = NoticeReminders.timesFor(
        extraction(kind: NoticeKind.meeting, date: DateTime(2026, 11, 24, 14), allDay: false),
        now: fixedNow,
      );
      expect(times, [DateTime(2026, 11, 23, 7), DateTime(2026, 11, 24, 13)]);
    });

    test('custom offsets are honoured and capped at four', () {
      final times = NoticeReminders.timesFor(
        extraction(date: exam),
        now: fixedNow,
        offsets: {NoticeKind.exam: [14, 7, 3, 2, 1, 0]},
      );
      expect(times.length, NoticeReminders.maxPerNotice);
      expect(times.first, DateTime(2026, 11, 21, 7));
      expect(times.last, DateTime(2026, 11, 24, 7));
    });

    test('moments already past are dropped; a past date yields nothing', () {
      final soon = NoticeReminders.timesFor(
        extraction(date: DateTime(2026, 9, 22)),
        now: fixedNow,
      );
      expect(soon, [DateTime(2026, 9, 21, 7), DateTime(2026, 9, 22, 7)]);
      expect(NoticeReminders.timesFor(extraction(date: DateTime(2026, 9, 15)), now: fixedNow), isEmpty);
      expect(NoticeReminders.timesFor(extraction(date: null), now: fixedNow), isEmpty);
    });
  });

  group('auto-arm thresholds (§D)', () {
    final future = DateTime(2026, 11, 24);
    NoticeArmDecision decide(NoticeExtraction e, {int week = 0}) =>
        NoticeReminders.decide(e, now: fixedNow, autoArmedThisWeek: week);

    test('≥ 0.8 with a date and an auto-arming kind → auto', () {
      expect(decide(extraction(date: future, confidence: 0.9)), NoticeArmDecision.auto);
      expect(decide(extraction(date: future, confidence: 0.8, kind: NoticeKind.assignment)), NoticeArmDecision.auto);
      expect(decide(extraction(date: future, confidence: 0.8, kind: NoticeKind.meeting)), NoticeArmDecision.auto);
    });

    test('0.5–0.8, a past date, two candidates, or a non-arming kind → inbox', () {
      expect(decide(extraction(date: future, confidence: 0.7)), NoticeArmDecision.inbox);
      expect(decide(extraction(date: future, confidence: 0.5)), NoticeArmDecision.inbox);
      expect(decide(extraction(date: DateTime(2026, 9, 15), confidence: 0.9)), NoticeArmDecision.inbox);
      expect(decide(extraction(date: future, confidence: 0.9, alternates: [DateTime(2026, 11, 26)])), NoticeArmDecision.inbox);
      expect(decide(extraction(date: future, confidence: 0.9, kind: NoticeKind.fee)), NoticeArmDecision.inbox);
      expect(decide(extraction(date: future, confidence: 0.9, kind: NoticeKind.holiday)), NoticeArmDecision.inbox);
      expect(decide(extraction(date: null, confidence: 0.5)), NoticeArmDecision.inbox);
    });

    test('< 0.5 → stored only', () {
      expect(decide(extraction(date: future, confidence: 0.3)), NoticeArmDecision.store);
      expect(decide(extraction(date: null, confidence: 0.3)), NoticeArmDecision.store);
    });

    test('past the weekly cap everything goes to the inbox', () {
      expect(decide(extraction(date: future, confidence: 0.9), week: 19), NoticeArmDecision.auto);
      expect(decide(extraction(date: future, confidence: 0.9), week: 20), NoticeArmDecision.inbox);
    });

    test('the corpus notice "Unit Test 2 — Science — 24 Nov" arms itself', () {
      final e = NoticeExtractor.extract(
        title: 'Unit Test 2 — Science — 24 Nov',
        body: 'Syllabus: Ch 5 to 8.',
        postedAt: fixedNow,
        subjects: const ['Science'],
      );
      expect(decide(e), NoticeArmDecision.auto);
    });
  });

  group('stage-2 date validation', () {
    test('accepts today to a year out, rejects the past and beyond', () {
      expect(NoticeReminders.acceptableDate(DateTime(2026, 9, 20), postedAt: fixedNow), isTrue);
      expect(NoticeReminders.acceptableDate(DateTime(2026, 9, 19), postedAt: fixedNow), isTrue);
      expect(NoticeReminders.acceptableDate(DateTime(2027, 9, 1), postedAt: fixedNow), isTrue);
      expect(NoticeReminders.acceptableDate(DateTime(2026, 9, 1), postedAt: fixedNow), isFalse);
      expect(NoticeReminders.acceptableDate(DateTime(2027, 10, 1), postedAt: fixedNow), isFalse);
      expect(NoticeReminders.acceptableDate(null, postedAt: fixedNow), isFalse);
    });
  });

  group('through AppState', () {
    late NoticeHarness h;

    tearDown(() => h.dispose());

    test('a confident exam notice is armed, announced and undoable', () async {
      h = NoticeHarness();
      final state = await h.start();
      h.platform.post(raw('Unit Test 2 — Science — 24 Nov', 'Syllabus: Ch 5 to 8.'));

      expect(await state.drainNotices(), 1);
      await settle(12);

      final notice = state.notices.single;
      expect(notice.status, NoticeStatus.confirmed);
      expect(notice.reminderIds.length, 4);
      expect(notice.autoArmedAt, fixedNow);
      expect(h.scheduler.scheduled.length, 4);
      expect(h.scheduler.armedShown, [notice.id]);
      expect(state.upcomingNotices.single.id, notice.id);
      expect(state.noticeInbox, isEmpty);

      await state.undoNoticeAutoArm(notice.id);
      await settle(12);
      expect(h.scheduler.scheduled, isEmpty);
      expect(state.noticeById(notice.id)!.status, NoticeStatus.needsReview);
      expect(state.noticeInbox.single.id, notice.id);
    });

    test('ignoring cancels every reminder; a past date never arms', () async {
      h = NoticeHarness();
      final state = await h.start();
      h.platform.post(raw('PTM', 'PTM on Saturday 26 Sep 2026, 9 am to 12 pm.'));
      h.platform.post(raw('Result', 'Unit test held on 15 Sep. Papers shown on 18 Sep.'));
      await state.drainNotices();
      await settle(12);

      final ptm = state.notices.firstWhere((n) => n.title == 'PTM');
      final past = state.notices.firstWhere((n) => n.title == 'Result');
      expect(ptm.isArmed, isTrue);
      expect(past.isArmed, isFalse);
      expect(past.status, NoticeStatus.needsReview);

      await state.ignoreNotice(ptm.id);
      await settle(12);
      expect(h.scheduler.scheduled, isEmpty);
      expect(state.noticeById(ptm.id)!.status, NoticeStatus.ignored);
      expect(state.noticeById(ptm.id)!.reminderIds, isEmpty);
    });

    test('the weekly cap sends the twenty-first confident notice to the inbox', () async {
      h = NoticeHarness(extraPrefs: {
        'notices.autoArmed': [
          for (var i = 0; i < 20; i++) fixedNow.subtract(Duration(hours: i + 1)).toIso8601String(),
        ],
      });
      final state = await h.start();
      h.platform.post(raw('Unit Test 2 — Science — 24 Nov', 'Syllabus: Ch 5 to 8.'));
      await state.drainNotices();
      await settle(12);
      expect(state.notices.single.status, NoticeStatus.needsReview);
      expect(h.scheduler.scheduled, isEmpty);
    });

    test('when the scheduler declines, the notice waits in the inbox instead of pretending', () async {
      h = NoticeHarness();
      h.scheduler.refuse = true;
      final state = await h.start();
      h.platform.post(raw('Unit Test 2 — Science — 24 Nov', 'Syllabus: Ch 5 to 8.'));
      await state.drainNotices();
      await settle(12);
      expect(state.notices.single.status, NoticeStatus.needsReview);
      expect(h.scheduler.armedShown, isEmpty);
    });

    test('confirm arms from the edited extraction and remembers the child for the app', () async {
      h = NoticeHarness();
      final state = await h.start(children: 2);
      h.platform.post(raw('Homework', 'Complete Maths worksheet 4 and submit by Friday.'));
      await state.drainNotices();
      await settle(12);
      final notice = state.notices.single;
      expect(notice.status, NoticeStatus.needsReview);
      expect(notice.childId, isNull, reason: 'two children, no mapping yet');

      final diya = state.children.last.id;
      await state.confirmNotice(
        notice.id,
        extraction: notice.extraction!.withDate(DateTime(2026, 9, 30)),
        childId: diya,
      );
      await settle(12);
      final confirmed = state.noticeById(notice.id)!;
      expect(confirmed.status, NoticeStatus.confirmed);
      expect(confirmed.childId, diya);
      expect(confirmed.date, DateTime(2026, 9, 30));
      expect(confirmed.reminderIds.length, 2);
      expect(state.childIdForPackage(schoolApp), diya);
    });

    test('converting an assignment saves a worksheet and cancels the notice alarms', () async {
      h = NoticeHarness();
      final state = await h.start();
      h.platform.post(raw('Project submission', 'Science project on plants due on 30 Sep 2026.'));
      await state.drainNotices();
      await settle(12);
      final notice = state.notices.single;
      expect(notice.isArmed, isTrue);

      final record = await state.convertNoticeToWorksheet(notice.id);
      await settle(12);
      expect(record.type, RecordType.worksheet);
      expect(record.subject, 'Science');
      expect(record.dueDate, DateTime(2026, 9, 30));
      expect(record.origin, RecordOrigin.notification);
      expect(record.notes, contains('Science project on plants'));
      expect(h.scheduler.scheduled, isEmpty);
      final linked = state.noticeById(notice.id)!;
      expect(linked.status, NoticeStatus.converted);
      expect(linked.linkedRecordId, record.id);
      expect(state.records.map((r) => r.id), contains(record.id));
    });
  });
}
