import 'package:flutter_test/flutter_test.dart';
import 'package:parent_academic_diary/data/analytics/subject_insights.dart';
import 'package:parent_academic_diary/data/models.dart';

/// The clock every scenario runs against, so recency never drifts.
final now = DateTime(2026, 9, 19);

const subjects = ['Mathematics', 'English', 'Science'];

ExamResult result(
  String id,
  DateTime date,
  Map<String, double?> marks, {
  Map<String, String> grades = const {},
  Map<String, String> remarks = const {},
  Set<String> absent = const {},
  double maxMarks = 100,
}) => ExamResult(
  id: id,
  childId: 'c',
  academicYearId: '2026–27',
  examLabel: id,
  date: date,
  scores: [
    for (final entry in marks.entries)
      SubjectScore(
        subject: entry.key,
        marks: entry.value,
        maxMarks: entry.value == null ? null : maxMarks,
        grade: grades[entry.key],
        remarks: remarks[entry.key] ?? '',
        absent: absent.contains(entry.key),
      ),
  ],
);

DiaryRecord worksheet({
  required String subject,
  WorksheetStatus status = WorksheetStatus.pending,
  DateTime? due,
  List<String> chapters = const [],
}) => DiaryRecord(
  id: '$subject-${chapters.join()}-${due?.day}',
  type: RecordType.worksheet,
  subject: subject,
  title: 't',
  date: DateTime(2026, 8, 1),
  dueDate: due,
  status: status,
  chapters: chapters,
);

List<SubjectInsight> compute({
  List<ExamResult> results = const [],
  List<DiaryRecord> records = const [],
  List<String> names = subjects,
}) => computeSubjectInsights(
  results: results,
  records: records,
  subjects: names,
  childName: 'Aarav',
  now: now,
);

SubjectInsight pick(List<SubjectInsight> all, String subject) =>
    all.singleWhere((i) => i.subject == subject);

void main() {
  group('the headline scenario from §E', () {
    // Three results: Mathematics sits at 45%, Science at 88%, English is the
    // child's middle ground.
    final three = [
      result('UT1', DateTime(2026, 7, 10), {
        'Mathematics': 48,
        'English': 70,
        'Science': 86,
      }),
      result('UT2', DateTime(2026, 8, 10), {
        'Mathematics': 45,
        'English': 72,
        'Science': 88,
      }),
      result('Term 1', DateTime(2026, 9, 10), {
        'Mathematics': 42,
        'English': 74,
        'Science': 90,
      }),
    ];

    test('a 45% subject is weak and an 88% subject is strong', () {
      final insights = compute(results: three);
      final maths = pick(insights, 'Mathematics');
      final science = pick(insights, 'Science');

      expect(maths.band, InsightBand.weak);
      expect(maths.averagePercent, closeTo(45, 0.01));
      expect(maths.sampleCount, 3);
      expect(science.band, InsightBand.strong);
      expect(science.averagePercent, closeTo(88, 0.01));
    });

    test('every band is explainable from its reasons', () {
      final maths = pick(compute(results: three), 'Mathematics');
      // +3 (below passing) +2 (well below own average) +2 (dropping 3/exam
      // does NOT fire — slope is −3) → the reasons name exactly what fired.
      expect(maths.reasons.first, 'Averaging 45% — below a passing mark');
      expect(
        maths.reasons,
        contains(matches(r"^\d+ points below Aarav's own average$")),
      );
      expect(maths.reasons.any((r) => r.startsWith('Dropping')), isFalse);
      expect(maths.signalScore, 5);
    });

    test('the strong subject carries a positive reason too', () {
      final science = pick(compute(results: three), 'Science');
      expect(science.reasons, ['Averaging 88%']);
      expect(science.signalScore, -2);
    });

    test('trend is a least-squares slope in points per exam', () {
      final insights = compute(results: three);
      expect(pick(insights, 'Mathematics').trendPerExam, closeTo(-3, 0.001));
      expect(pick(insights, 'Science').trendPerExam, closeTo(2, 0.001));
      expect(pick(insights, 'English').latestPercent, 74);
    });

    test('delta is measured against the child, not against 100', () {
      final maths = pick(compute(results: three), 'Mathematics');
      // Child mean = (48+70+86+45+72+88+42+74+90)/9 = 68.33
      expect(maths.deltaVsOwnAverage, closeTo(45 - 68.333, 0.01));
    });

    test('confidence is full at three-plus recent results', () {
      final maths = pick(compute(results: three), 'Mathematics');
      // 3/4 samples × 1.0 recency (9 days old).
      expect(maths.confidence, closeTo(0.75, 0.001));
    });
  });

  group('a single result', () {
    final one = [
      result('UT1', DateTime(2026, 9, 1), {
        'Mathematics': 30,
        'English': 95,
        'Science': 60,
      }),
    ];

    test('is not unknown — it is scored — but has no trend', () {
      // §E's "a child with one result must come out unknown for everything"
      // reads as: nothing can be *trended*. A single 30% is still a 30%, and
      // the rule's bands say so; hiding it would be the model deciding.
      final insights = compute(results: one);
      for (final i in insights) {
        expect(i.sampleCount, 1);
        expect(i.trendPerExam, isNull, reason: i.subject);
        expect(i.confidence, closeTo(0.25, 0.001), reason: i.subject);
      }
      expect(pick(insights, 'Mathematics').band, InsightBand.weak);
      expect(pick(insights, 'English').band, InsightBand.strong);
      expect(pick(insights, 'Science').band, InsightBand.steady);
    });
  });

  group('no results', () {
    test('every subject is unknown, even with worksheet signals', () {
      final records = [
        for (var i = 0; i < 5; i++)
          worksheet(
            subject: 'Mathematics',
            due: DateTime(2026, 8, 1 + i),
            chapters: ['Chapter 3'],
          ),
      ];
      final insights = compute(records: records);
      for (final i in insights) {
        expect(i.band, InsightBand.unknown, reason: i.subject);
        expect(i.confidence, 0);
        expect(i.averagePercent, isNull);
      }
      // The worksheet signals are still reported — they just never rank.
      final maths = pick(insights, 'Mathematics');
      expect(maths.overdueCount, 5);
      expect(maths.completionRate, 0);
      expect(maths.reasons, [
        'Only 0 of 5 worksheets marked done',
        '5 worksheets overdue',
      ]);
      expect(weakSubjectsFrom(insights), isEmpty);
    });
  });

  group('absent rows', () {
    test('an all-absent subject is unknown and never scored as zero', () {
      final results = [
        result('UT1', DateTime(2026, 8, 1), {
          'Mathematics': 80,
          'English': 80,
        }, absent: {'English'}),
        result('UT2', DateTime(2026, 9, 1), {
          'Mathematics': 82,
          'English': 80,
        }, absent: {'English'}),
      ];
      final english = pick(compute(results: results), 'English');
      expect(english.band, InsightBand.unknown);
      expect(english.sampleCount, 0);
      expect(english.averagePercent, isNull);
    });

    test('an absent row is skipped, not averaged in', () {
      final results = [
        result('UT1', DateTime(2026, 8, 1), {'Mathematics': 90}),
        result('UT2', DateTime(2026, 9, 1), {
          'Mathematics': 0,
        }, absent: {'Mathematics'}),
      ];
      final maths = pick(compute(results: results), 'Mathematics');
      expect(maths.sampleCount, 1);
      expect(maths.averagePercent, 90);
    });
  });

  group('grade-only results', () {
    test('resolve through the scale and are flagged as derived', () {
      final results = [
        result(
          'Term 1',
          DateTime(2026, 9, 1),
          {'Mathematics': null, 'English': null},
          grades: {'Mathematics': 'D', 'English': 'A1'},
        ),
      ];
      expect(results.single.scores.first.isDerivedPercent, isTrue);
      final insights = compute(results: results);
      expect(pick(insights, 'Mathematics').averagePercent, 36.5);
      expect(pick(insights, 'Mathematics').band, InsightBand.weak);
      expect(pick(insights, 'English').averagePercent, 95.5);
    });

    test('a grade off the scale leaves the subject unknown', () {
      final results = [
        result(
          'Term 1',
          DateTime(2026, 9, 1),
          {'Mathematics': null},
          grades: {'Mathematics': 'Distinction'},
        ),
      ];
      expect(
        pick(compute(results: results), 'Mathematics').band,
        InsightBand.unknown,
      );
    });
  });

  group('signal weights', () {
    List<ExamResult> series(String subject, List<double> marks) => [
      for (var i = 0; i < marks.length; i++)
        result('R$i', DateTime(2026, 4 + i, 1), {subject: marks[i]}),
    ];

    test('50–59% is a watch, not a fail', () {
      final maths = pick(
        compute(results: series('Mathematics', [55, 56])),
        'Mathematics',
      );
      expect(maths.band, InsightBand.watch);
      expect(maths.reasons, ['Averaging 56%']);
    });

    test('a steep drop adds its own reason once there are three results', () {
      final maths = pick(
        compute(results: series('Mathematics', [80, 72, 64])),
        'Mathematics',
      );
      expect(maths.trendPerExam, closeTo(-8, 0.001));
      expect(maths.reasons, ['Dropping about 8 points each exam']);
      expect(maths.band, InsightBand.watch);
    });

    test('a poor last exam adds one point', () {
      final maths = pick(
        compute(results: series('Mathematics', [70, 70, 35])),
        'Mathematics',
      );
      expect(maths.reasons, contains('Last exam was 35%'));
    });

    test('improvement pulls the score back', () {
      final maths = pick(
        compute(results: series('Mathematics', [50, 56, 62])),
        'Mathematics',
      );
      // +2 (averaging 56) −1 (improving 6/exam) = 1 → steady.
      expect(maths.signalScore, 1);
      expect(maths.band, InsightBand.steady);
      expect(maths.reasons, [
        'Averaging 56%',
        'Improving about 6 points each exam',
      ]);
    });

    test('worksheet signals need four worksheets or three overdue', () {
      final results = series('Mathematics', [70, 71]);
      final threeWorksheets = [
        for (var i = 0; i < 3; i++)
          worksheet(subject: 'Mathematics', due: DateTime(2026, 8, 1 + i)),
      ];
      final withThree = pick(
        compute(results: results, records: threeWorksheets),
        'Mathematics',
      );
      // Three overdue fires; the completion rule needs a fourth worksheet.
      expect(withThree.reasons, ['3 worksheets overdue']);

      final fourWorksheets = [
        ...threeWorksheets,
        worksheet(subject: 'Mathematics', status: WorksheetStatus.completed),
      ];
      final withFour = pick(
        compute(results: results, records: fourWorksheets),
        'Mathematics',
      );
      expect(withFour.reasons, [
        'Only 1 of 4 worksheets marked done',
        '3 worksheets overdue',
      ]);
      expect(withFour.completionRate, 0.25);
    });
  });

  group('confidence recency', () {
    test('decays from 60 to 180 days and floors at half', () {
      double confidenceAt(DateTime date) => pick(
        compute(results: [
          result('R', date, {'Mathematics': 70}),
        ]),
        'Mathematics',
      ).confidence;

      expect(confidenceAt(now.subtract(const Duration(days: 30))), 0.25);
      expect(
        confidenceAt(now.subtract(const Duration(days: 120))),
        closeTo(0.25 * 0.75, 0.001),
      );
      expect(confidenceAt(now.subtract(const Duration(days: 400))), 0.125);
    });
  });

  group('focus chapters', () {
    test('rank pending chapters and remark mentions, capped at three', () {
      final records = [
        worksheet(subject: 'Mathematics', chapters: ['Chapter 4']),
        worksheet(subject: 'Mathematics', chapters: ['Chapter 4', 'Chapter 2']),
        worksheet(subject: 'Mathematics', chapters: ['Chapter 7']),
        worksheet(subject: 'Mathematics', chapters: ['Chapter 9']),
        worksheet(
          subject: 'Mathematics',
          status: WorksheetStatus.completed,
          chapters: ['Chapter 1'],
        ),
      ];
      final results = [
        result(
          'UT1',
          DateTime(2026, 9, 1),
          {'Mathematics': 40},
          remarks: {'Mathematics': 'Weak in ch. 2 and Chapter 4'},
        ),
      ];
      final maths = pick(
        compute(results: results, records: records),
        'Mathematics',
      );
      // Chapter 4: 2 worksheets + 1 remark; Chapter 2: 1 + 1; then the first
      // single-count chapter seen. Chapter 1 is done and never appears.
      expect(maths.focusChapters, ['Chapter 4', 'Chapter 2', 'Chapter 7']);
    });
  });

  group('weakSubjectsFrom', () {
    test('orders worst first and breaks ties deterministically', () {
      final results = [
        // Child mean is 62. Hindi averages 30 with a steep drop (score 8);
        // Mathematics and Art both sit at 45, 17 points under the child's
        // mean (score 5 each) and tie all the way down to the name.
        for (var i = 0; i < 3; i++)
          result('R$i', DateTime(2026, 5 + i, 1), {
            'Hindi': [40, 30, 20][i].toDouble(),
            'Mathematics': 45,
            'Art': 45,
            'English': 95,
            'Science': 95,
          }),
      ];
      final weak = weakSubjectsFrom(
        compute(
          results: results,
          names: ['Mathematics', 'English', 'Hindi', 'Science'],
        ),
      );
      expect(weak.map((i) => i.subject), ['Hindi', 'Art', 'Mathematics']);
      expect(weak.first.signalScore, greaterThan(weak.last.signalScore));
    });
  });

  group('subjects', () {
    test('a report-card subject the child does not have still gets a row', () {
      final results = [
        result('UT1', DateTime(2026, 9, 1), {
          'Mathematics': 70,
          'Social Science': 40,
        }),
      ];
      final insights = compute(results: results);
      expect(insights.map((i) => i.subject), [
        ...subjects,
        'Social Science',
      ]);
      expect(pick(insights, 'Social Science').band, InsightBand.weak);
    });

    test('soft-deleted results and records are ignored', () {
      final results = [
        result('UT1', DateTime(2026, 9, 1), {
          'Mathematics': 20,
        }).copyWith(isDeleted: true),
      ];
      expect(
        pick(compute(results: results), 'Mathematics').band,
        InsightBand.unknown,
      );
    });
  });
}
