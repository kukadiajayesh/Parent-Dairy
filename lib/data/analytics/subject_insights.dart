import 'dart:math' as math;

import '../models.dart';

/// Where a subject stands, from a rule a parent could check by hand.
///
/// The bands are deliberately coarse. A model may later *explain* a weak
/// subject or *generate* practice for it, but the verdict itself is this
/// file's — deterministic, unit-tested, and never a language model's guess.
enum InsightBand {
  strong,
  steady,
  watch,
  weak,

  /// No scored result yet. Worksheet signals alone never make a subject
  /// "weak" — a pile of pending homework is not a mark.
  unknown;

  String get label => switch (this) {
    InsightBand.strong => 'Strong',
    InsightBand.steady => 'Steady',
    InsightBand.watch => 'Watch',
    InsightBand.weak => 'Needs attention',
    InsightBand.unknown => 'No marks yet',
  };
}

class SubjectInsight {
  const SubjectInsight({
    required this.subject,
    required this.band,
    required this.averagePercent,
    required this.latestPercent,
    required this.deltaVsOwnAverage,
    required this.trendPerExam,
    required this.sampleCount,
    required this.completionRate,
    required this.overdueCount,
    required this.reasons,
    required this.confidence,
    required this.focusChapters,
    required this.signalScore,
  });

  final String subject;
  final InsightBand band;

  /// Mean of this subject's `percent` values across scored results.
  final double? averagePercent;
  final double? latestPercent;

  /// Subject mean − the child's overall mean. Negative means below their own
  /// average.
  final double? deltaVsOwnAverage;

  /// Least-squares slope of percent against result index, in points per
  /// exam. Null until there are three results to draw a line through.
  final double? trendPerExam;

  /// Scored (non-absent, numeric) results for this subject.
  final int sampleCount;

  /// Completed ÷ total worksheets, 0–1. A subject with no worksheets reads
  /// as 1.0 — nothing outstanding — rather than 0.
  final double completionRate;
  final int overdueCount;

  /// Human-readable, heaviest signal first. The UI shows these verbatim, so
  /// every band is explainable from this list alone.
  final List<String> reasons;

  /// 0–1, from how many results back the verdict and how recent they are.
  final double confidence;

  /// Chapters over-represented in pending or overdue worksheets and in
  /// remarks — where practice would land first. At most three.
  final List<String> focusChapters;

  /// The summed signal weight behind [band]. Exposed so "worst first" is a
  /// stable ordering rather than a re-derivation.
  final int signalScore;
}

/// Tunables from prompt 01 §E, in one place so a change is a diff, not a hunt.
abstract final class InsightRule {
  static const double failingMean = 50;
  static const double lowMean = 60;
  static const double strongMean = 85;
  static const double strongBandMean = 75;
  static const double laggingDelta = -15;
  static const double droppingTrend = -5;
  static const double risingTrend = 5;
  static const double poorLatest = 40;
  static const double lowCompletion = 0.5;
  static const int minWorksheetsForCompletion = 4;
  static const int overdueThreshold = 3;
  static const int minSamplesForTrend = 3;
  static const int weakScore = 4;
  static const int watchScore = 2;
  static const int fullConfidenceSamples = 4;
  static const int freshDays = 60;
  static const int staleDays = 180;
  static const int maxFocusChapters = 3;
}

/// Computes one [SubjectInsight] per subject, in the order of [subjects]
/// followed by any subject that appears only on a report card.
///
/// Pure: same inputs, same output. [now] is injectable so tests pin the
/// clock; the app passes nothing and gets the wall clock.
List<SubjectInsight> computeSubjectInsights({
  required List<ExamResult> results,
  required List<DiaryRecord> records,
  required List<String> subjects,
  String childName = 'your child',
  DateTime? now,
}) {
  final clock = now ?? DateTime.now();

  // Oldest first, so "latest" and the trend's x-axis both read left to right.
  final ordered = results.where((r) => !r.isDeleted).toList()
    ..sort((a, b) {
      final byDate = a.date.compareTo(b.date);
      return byDate != 0 ? byDate : a.id.compareTo(b.id);
    });

  final names = <String>[...subjects];
  final extras = <String>{};
  for (final result in ordered) {
    for (final score in result.scores) {
      if (score.subject.isNotEmpty && !names.contains(score.subject)) {
        extras.add(score.subject);
      }
    }
  }
  names.addAll(extras.toList()..sort());

  final everyPercent = [
    for (final result in ordered)
      for (final row in result.scoredRows) row.percent!,
  ];
  final childMean = _mean(everyPercent);

  final liveRecords = records.where((r) => !r.isDeleted).toList();

  return [
    for (final name in names)
      _insightFor(
        name,
        results: ordered,
        records: liveRecords,
        childMean: childMean,
        childName: childName,
        now: clock,
      ),
  ];
}

/// Subjects in the weak band, worst first: heaviest signal score, then lowest
/// average, then name — so two parents with the same marks see the same list
/// in the same order.
List<SubjectInsight> weakSubjectsFrom(List<SubjectInsight> insights) =>
    insights.where((i) => i.band == InsightBand.weak).toList()..sort((a, b) {
      final byScore = b.signalScore.compareTo(a.signalScore);
      if (byScore != 0) return byScore;
      final byMean = (a.averagePercent ?? 101).compareTo(
        b.averagePercent ?? 101,
      );
      if (byMean != 0) return byMean;
      return a.subject.compareTo(b.subject);
    });

SubjectInsight _insightFor(
  String name, {
  required List<ExamResult> results,
  required List<DiaryRecord> records,
  required double? childMean,
  required String childName,
  required DateTime now,
}) {
  final samples = <({DateTime date, double percent, String remarks})>[
    for (final result in results)
      for (final row in result.scores)
        if (row.subject == name && !row.absent && row.percent != null)
          (date: result.date, percent: row.percent!, remarks: row.remarks),
  ];

  final sampleCount = samples.length;
  final percents = [for (final s in samples) s.percent];
  final mean = _mean(percents);
  final latest = samples.isEmpty ? null : samples.last.percent;
  final delta = (mean == null || childMean == null) ? null : mean - childMean;
  final trend = sampleCount >= InsightRule.minSamplesForTrend
      ? _slope(percents)
      : null;

  final worksheets = records
      .where((r) => r.subject == name && r.isWorksheet)
      .toList();
  final completed = worksheets
      .where((w) => w.status == WorksheetStatus.completed)
      .length;
  final completionRate = worksheets.isEmpty
      ? 1.0
      : completed / worksheets.length;
  final overdue = worksheets.where((w) => _isOverdue(w, now)).toList();

  // (weight, reason). Negative weights pull a subject towards "strong"; they
  // still carry a reason so a Strong card can say why.
  final signals = <(int, String)>[];
  if (mean != null) {
    if (mean < InsightRule.failingMean) {
      signals.add((3, 'Averaging ${_pct(mean)}% — below a passing mark'));
    } else if (mean < InsightRule.lowMean) {
      signals.add((2, 'Averaging ${_pct(mean)}%'));
    }
  }
  if (delta != null && delta <= InsightRule.laggingDelta) {
    signals.add((2, "${_pct(-delta)} points below $childName's own average"));
  }
  if (trend != null && trend <= InsightRule.droppingTrend) {
    signals.add((2, 'Dropping about ${_pct(-trend)} points each exam'));
  }
  if (latest != null && latest < InsightRule.poorLatest) {
    signals.add((1, 'Last exam was ${_pct(latest)}%'));
  }
  if (worksheets.length >= InsightRule.minWorksheetsForCompletion &&
      completionRate < InsightRule.lowCompletion) {
    signals.add((
      1,
      'Only $completed of ${worksheets.length} worksheets marked done',
    ));
  }
  if (overdue.length >= InsightRule.overdueThreshold) {
    signals.add((1, '${overdue.length} worksheets overdue'));
  }
  if (mean != null && mean >= InsightRule.strongMean) {
    signals.add((-2, 'Averaging ${_pct(mean)}%'));
  }
  if (trend != null && trend >= InsightRule.risingTrend) {
    signals.add((-1, 'Improving about ${_pct(trend)} points each exam'));
  }

  // Heaviest first; List.sort is stable in Dart so equal weights keep the
  // order they were added in, which is the order §E lists them.
  signals.sort((a, b) => b.$1.abs().compareTo(a.$1.abs()));
  final score = signals.fold<int>(0, (sum, s) => sum + s.$1);

  final InsightBand band;
  if (sampleCount == 0) {
    band = InsightBand.unknown;
  } else if (score >= InsightRule.weakScore) {
    band = InsightBand.weak;
  } else if (score >= InsightRule.watchScore) {
    band = InsightBand.watch;
  } else if (mean != null && mean >= InsightRule.strongBandMean) {
    band = InsightBand.strong;
  } else {
    band = InsightBand.steady;
  }

  final double confidence;
  if (sampleCount == 0) {
    confidence = 0;
  } else {
    final age = now.difference(samples.last.date).inDays;
    final recency = age <= InsightRule.freshDays
        ? 1.0
        : age >= InsightRule.staleDays
        ? 0.5
        : 1 -
              0.5 *
                  (age - InsightRule.freshDays) /
                  (InsightRule.staleDays - InsightRule.freshDays);
    confidence =
        math.min(1, sampleCount / InsightRule.fullConfidenceSamples) * recency;
  }

  final focus = _focusChapters(
    worksheets: worksheets,
    overdue: overdue,
    remarks: [for (final s in samples) s.remarks],
  );

  return SubjectInsight(
    subject: name,
    band: band,
    averagePercent: mean,
    latestPercent: latest,
    deltaVsOwnAverage: delta,
    trendPerExam: trend,
    sampleCount: sampleCount,
    completionRate: completionRate,
    overdueCount: overdue.length,
    reasons: [for (final s in signals) s.$2],
    confidence: confidence,
    focusChapters: focus,
    signalScore: score,
  );
}

/// Pending or overdue worksheets' chapters, plus any chapter a remark names,
/// ranked by how often they come up.
List<String> _focusChapters({
  required List<DiaryRecord> worksheets,
  required List<DiaryRecord> overdue,
  required List<String> remarks,
}) {
  // Insertion-ordered so a tie resolves to the chapter seen first.
  final counts = <String, int>{};
  void bump(String chapter) => counts[chapter] = (counts[chapter] ?? 0) + 1;

  for (final w in worksheets) {
    final incomplete =
        w.status == WorksheetStatus.pending || overdue.contains(w);
    if (!incomplete) continue;
    for (final chapter in w.chapters) {
      if (chapter.isNotEmpty) bump(chapter);
    }
  }
  for (final remark in remarks) {
    for (final match in _chapterMention.allMatches(remark)) {
      bump('Chapter ${int.parse(match.group(1)!)}');
    }
  }

  final ranked = counts.entries.toList();
  final order = {for (var i = 0; i < ranked.length; i++) ranked[i].key: i};
  ranked.sort((a, b) {
    final byCount = b.value.compareTo(a.value);
    return byCount != 0 ? byCount : order[a.key]!.compareTo(order[b.key]!);
  });
  return [
    for (final e in ranked.take(InsightRule.maxFocusChapters)) e.key,
  ];
}

/// "Chapter 4", "Ch. 4", "ch4", "Unit 4" — the ways a teacher writes it.
final _chapterMention = RegExp(
  r'\b(?:chapter|chap\.?|ch\.?|unit)\s*(\d{1,2})\b',
  caseSensitive: false,
);

/// Same test as [DiaryRecord.isOverdue], against an injected clock.
bool _isOverdue(DiaryRecord w, DateTime now) =>
    w.isWorksheet &&
    w.status == WorksheetStatus.pending &&
    w.dueDate != null &&
    w.dueDate!.isBefore(now);

double? _mean(List<double> values) =>
    values.isEmpty ? null : values.reduce((a, b) => a + b) / values.length;

/// Ordinary least-squares slope of [values] against their index.
double _slope(List<double> values) {
  final n = values.length;
  final xMean = (n - 1) / 2;
  final yMean = _mean(values)!;
  var num = 0.0;
  var den = 0.0;
  for (var i = 0; i < n; i++) {
    num += (i - xMean) * (values[i] - yMean);
    den += (i - xMean) * (i - xMean);
  }
  return den == 0 ? 0 : num / den;
}

String _pct(double value) => value.round().toString();
