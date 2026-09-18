# 01 — Exams, marks and weak-subject analytics

> Assumes `00-shared-context.md`.
> Build this **before** the Gemini prompt. AI extracts and explains; this layer
> decides. A model must never be the thing that ranks a child as weak in maths.

## Goal

Turn on the exam and marks half of the app, store results in a shape that can
be queried and charted, and derive each child's weak subjects with a rule a
parent could check by hand.

## Why it is blocked today

1. `firestore.rules` → `isValidRecord()` allows
   `data.type in ['worksheet', 'classwork']`. **Every exam write is rejected by
   the server right now**, even though `RecordType.exam`,
   `AddExamPage`, `ExamDetailPage` and `Routes.addExam` already exist. Fix this
   first or nothing below works.
2. `kShowExamMarks` is `false`, so the Performance tab, the Add-sheet exam and
   marks rows, the "Latest marks" home block and the subject Exams/Marks tabs
   are all compiled out.
3. There is no marks model at all. `DiaryRecord` carries an exam *paper*; it has
   nowhere to put a score.

## A. Unblock exam records

- `firestore.rules`: allow `data.type in ['worksheet', 'classwork', 'exam']`.
  Add exam-only validation mirroring `RecordRepository._validate`: when
  `data.type == 'exam'`, require a non-empty `examType` (≤ 60 chars) and an
  `examTimetable` map. Keep the `attachments.size() <= 50` bound.
- Add the matching rules unit expectations if a rules test harness exists; if
  not, note the manual `firebase deploy --only firestore:rules` step in the
  README.
- Flip `kShowExamMarks` to `true` **at the end of this prompt**, once every
  surface it reveals is actually built. Leave the flag in place — it is how the
  build stays shippable mid-way.

## B. The results model

New collection, deliberately **not** a `DiaryRecord` variant: a report card
covers many subjects at once, while a record is single-subject, so folding
marks into records would force one document per subject and lose the "this
exam, across the class's subjects" view the Performance tab needs.

```
users/{uid}/children/{childId}/results/{resultId}
```

### `lib/data/models.dart`

```dart
enum ResultSource { manual('manual'), scanned('scanned'), imported('imported'); ... }

/// One subject row on one report card.
class SubjectScore {
  final String subject;       // must match a Subject.name, or be free text
  final double? marks;        // null when the school reports grades only
  final double? maxMarks;
  final String? grade;        // 'A1', 'B+', 'Distinction', …
  final int? classRank;
  final String remarks;
  final bool absent;

  /// 0–100, or null when neither marks nor a mappable grade is present.
  /// Grades resolve through [GradeScale]; see §C.
  double? get percent;
}

/// A whole exam result — one report card, one unit test, one term.
class ExamResult {
  final String id;
  final String childId;
  final String academicYearId;   // the year *label*, same convention as records
  final String examLabel;        // 'Unit Test 1', 'Term 1', 'Half Yearly'
  final DateTime date;
  final String? examRecordId;    // links to the DiaryRecord of type exam, if any
  final List<SubjectScore> scores;
  final double? attendancePercent;
  final String teacherRemarks;
  final ResultSource source;
  final double extractionConfidence; // 1.0 for manual entry
  final bool needsReview;            // true until a parent confirms a scan
  final DateTime? createdAt, updatedAt;
  final bool isDeleted;
  final DateTime? deletedAt;

  double? get overallPercent;       // marks-weighted, ignoring absent rows
  int get gradedSubjectCount;
}
```

Rules of the shape:

- `academicYearId` holds the **label** (`2026–27`), matching `DiaryRecord`.
- A result with zero usable `percent` values still saves — it is a document of
  record even if it cannot be charted.
- `absent` rows are excluded from every average, never scored as zero.

### `lib/data/mappers.dart`

`Map$.resultToMap` / `Map$.resultFrom` / `Map$.subjectScoreToMap` /
`Map$.subjectScoreFrom`, defensive in the existing style. Add `searchTerms` for
the result (exam label + subject names) so results appear in global search.

### `lib/data/firestore_paths.dart`

```dart
static CollectionReference<Map<String, dynamic>> results(String uid, String childId)
    => child(uid, childId).collection('results');
```

### `firestore.rules`

Mirror the records block: owner-only, create/update validated
(`isNonEmptyString(examLabel, 80)`, `date is timestamp`, `scores is list`,
`scores.size() <= 30`, `isDeleted is bool`), `allow delete: if false`.

### `firestore.indexes.json`

```
results: isDeleted ASC, academicYearId ASC, date DESC     (the Performance tab)
results: isDeleted ASC, date DESC                          (all-years trend)
```

## C. Grade scales

Indian report cards often carry grades, not marks. Add
`lib/core/config/grade_scale.dart`:

```dart
class GradeScale {
  final String id, label;              // 'cbse9', 'CBSE 9-point'
  final Map<String, ({double min, double max})> bands;  // 'A1' -> (91, 100)
  double? percentFor(String grade);    // midpoint of the band
}
```

Ship three: **CBSE 9-point** (A1 91–100, A2 81–90, B1 71–80, B2 61–70, C1 51–60,
C2 41–50, D 33–40, E1/E2 below), **five-letter** (A–E in 20-point bands) and
**none**. The scale is a per-child setting (`Child.gradeScaleId`, defaulting to
`cbse9`), editable in the child setup form. A grade converts to the **midpoint**
of its band and the resulting `percent` is flagged as derived, so the UI can say
"approximate" rather than pretending an A1 is 95.5%.

## D. Repository and state

`lib/data/repositories/result_repository.dart` — `watch({uid, childId, yearLabel})`
(ordered `date` desc, `isDeleted == false`, `limit(200)`), `save`, `softDelete`,
`restore`, `allYears({uid, childId})` for the trend chart. Same `AppFailure`
wrapping and `_validate` pattern as `RecordRepository` (non-empty `examLabel`,
non-empty `childId` and `academicYearId`, `date` not in the future by more than
a day, at least one score row, `marks <= maxMarks` where both are present).

`AppState`: a `_resultsSub` alongside `_recordsSub`, resubscribed by
`_resubscribeRecords()` (rename it `_resubscribeChildYearScoped()` if that reads
better, but keep the existing call sites working). Expose:

```dart
List<ExamResult> get results;
List<ExamResult> get resultsByDateDesc;
ExamResult? resultById(String id);
Future<ExamResult> saveResult(ExamResult result);
Future<void> deleteResult(String id);
List<SubjectInsight> get subjectInsights;   // §E, memoised
List<SubjectInsight> get weakSubjects;      // band == weak, worst first
```

`subjectInsights` must be **memoised** against the results+records list identity
— it is read from `build()` on the home and performance screens and must not be
recomputed on every notify.

## E. Weak-subject analytics — the exact rule

New pure-Dart file `lib/data/analytics/subject_insights.dart`. No Firebase
import, no `BuildContext`, fully unit-testable, deterministic.

```dart
enum InsightBand { strong, steady, watch, weak, unknown }

class SubjectInsight {
  final String subject;
  final InsightBand band;
  final double? averagePercent;      // mean of that subject's percent values
  final double? latestPercent;
  final double? deltaVsOwnAverage;   // subject mean − child's overall mean
  final double? trendPerExam;        // least-squares slope, points per exam
  final int sampleCount;             // scored results for this subject
  final double completionRate;       // completed ÷ total worksheets, 0–1
  final int overdueCount;
  final List<String> reasons;        // human-readable, ordered by weight
  final double confidence;           // 0–1, from sampleCount and recency
  final List<String> focusChapters;  // chapters over-represented in low scores
}
```

### Scoring

Compute over the **active academic year** by default, with an `allYears` toggle.

1. `subjectMean` = mean `percent` across that subject's non-absent scores.
2. `childMean` = mean `percent` across every subject in the same results.
3. `trendPerExam` = least-squares slope of `percent` vs. result index, computed
   only when `sampleCount >= 3`.
4. Signals, each contributing a weight:
   - `subjectMean < 50` → **+3**, reason `"Averaging {x}% — below a passing mark"`
   - `50 <= subjectMean < 60` → **+2**, reason `"Averaging {x}%"`
   - `deltaVsOwnAverage <= -15` → **+2**, reason
     `"{y} points below {child}'s own average"`
   - `trendPerExam <= -5` with `sampleCount >= 3` → **+2**, reason
     `"Dropping about {z} points each exam"`
   - `latestPercent < 40` → **+1**, reason `"Last exam was {x}%"`
   - `completionRate < 0.5` with `>= 4` worksheets → **+1**, reason
     `"Only {n} of {m} worksheets marked done"`
   - `overdueCount >= 3` → **+1**, reason `"{n} worksheets overdue"`
   - `subjectMean >= 85` → **−2**; `trendPerExam >= +5` → **−1**
5. Band from the total: `>= 4` **weak**, `2–3` **watch**, `0–1` with
   `subjectMean >= 75` **strong**, otherwise **steady**. `sampleCount == 0`
   **unknown** — never call a subject weak on worksheet signals alone.
6. `confidence` = `min(1, sampleCount / 4) * recencyFactor`, where
   `recencyFactor` is 1.0 within 60 days of the newest result, decaying to 0.5
   at 180 days.
7. `focusChapters`: for each of the subject's records, take the chapters on
   records whose worksheet is incomplete or overdue, plus any chapter named in a
   score's `remarks`; rank by frequency; cap at three.

Every band change must be explainable from `reasons` alone — the UI shows them
verbatim. Write the tests first: a child with three results, a subject at 45%
and a subject at 88%, must come out `weak` and `strong`; a child with one result
must come out `unknown` for everything.

## F. Screens

Follow the design system; each needs empty/loading/error states.

1. **Performance tab** — fourth bottom-nav destination, between Timeline and
   More, as the design puts it. Contents: a child + year header, a
   subject-vs-subject bar list (`averagePercent`, coloured by
   `Subject.hue`), the overall trend line across results, a "Needs attention"
   section listing `weakSubjects` as cards showing band, average, the top two
   `reasons`, and two actions — **View subject** and **Generate practice**
   (the latter is wired in prompt `02`; until then, hide it behind
   `kAiEnabled`).
2. **Add result** (`Routes.addResult`) — exam label, date, exam type, optional
   link to an existing exam record, then a per-subject row list seeded from the
   child's subjects: marks / max / grade / absent toggle / remarks. A "same max
   for all" helper, because a report card usually is. Live overall percentage in
   the sticky footer.
3. **Result detail** (`Routes.resultDetail`) — the report card as saved, per
   subject with percent and delta vs. that subject's own average, teacher
   remarks, source badge (`Entered by you` / `Scanned`), edit and delete.
4. **Subject detail** — restore the design's Exams and Marks tabs and the trend
   chart, now that data exists.
5. **Home** — the "Latest marks" block: newest result, overall percent, and up
   to two weak subjects.
6. **Add sheet** — wire the existing `Exam` row to `Routes.addExam` (it is an
   empty `onTap: () {}` today) and the `Marks` row to `Routes.addResult`.
7. **More → Academic** — a "Grade scale" row.

Charts: draw with `CustomPainter` against `AppTokens`. Do **not** add a charting
package for two charts.

## G. Edge cases to handle explicitly

- A score's subject is not in the child's subject list → save it, show it with a
  neutral hue, and offer "Add {name} as a subject" inline.
- Two results with the same `examLabel` and date → on save, warn and offer
  "Replace" or "Keep both".
- Max marks differ across subjects (80 vs 100) → percent always normalises;
  never sum raw marks across different maxima.
- A result dated in a different academic year than the active one → assign by
  the date falling inside the year's span, not by what is selected.
- Deleting a subject must not orphan its scores; historic results keep the name.

## H. Tests

- `subject_insights_test.dart` — the table of scenarios in §E, plus: all-absent
  subject, grade-only result, single result, tie-breaking order of
  `weakSubjects`.
- `grade_scale_test.dart` — every band boundary of CBSE 9-point, unknown grade.
- `result_repository_test.dart` — save/validate/soft delete/year scoping over
  `fake_cloud_firestore`.
- `models_test.dart` additions — `ExamResult` wire round trip, `overallPercent`
  with absent rows and mixed maxima.
- `app_smoke_test.dart` — with `kShowExamMarks` true, the Performance tab is
  reachable, renders the weak-subject card, and does not overflow at 411.4dp.

## Deliverable

A summary listing: the rules change, the new collection and indexes with the
deploy command, the insight rule as implemented (any deviation from §E flagged),
and a screenshot or golden of the Performance tab in both themes.
