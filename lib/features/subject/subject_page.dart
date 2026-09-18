import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../core/config/feature_flags.dart';
import '../../core/format.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/attachment_image.dart';
import '../../core/widgets/app_icons.dart';
import '../../core/widgets/chips.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/pressable.dart';
import '../../core/widgets/states.dart';
import '../../core/widgets/stroke_icon.dart';
import '../../data/analytics/subject_insights.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../performance/charts.dart';
import '../performance/insight_widgets.dart';
import '../worksheet/worksheets_list_page.dart';

/// Subject detail with Overview / Worksheets / Classwork tabs.
///
/// The design reaches this screen from the Performance tab and adds Exams and
/// Marks tabs plus a marks summary header — all gated on [kShowExamMarks].
class SubjectPage extends StatefulWidget {
  const SubjectPage({super.key, required this.subjectName});

  final String subjectName;

  @override
  State<SubjectPage> createState() => _SubjectPageState();
}

class _SubjectPageState extends State<SubjectPage> {
  String _tab = 'Overview';

  List<String> get _tabs => [
        'Overview',
        'Worksheets',
        'Classwork',
        if (kShowExamMarks) ...['Exams', 'Marks'],
      ];

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final state = AppScope.of(context);
    final subject = state.subjectByName(widget.subjectName);

    final worksheets = state.worksheets
        .where((r) => r.subject == subject.name)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final classwork = state.classwork
        .where((r) => r.subject == subject.name)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final pending = worksheets
        .where((w) => w.status == WorksheetStatus.pending)
        .length;
    final exams = state.records
        .where((r) => r.isExam && r.subject == subject.name)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final insight = kShowExamMarks ? state.insightFor(subject.name) : null;

    return Scaffold(
      backgroundColor: k.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ScreenHeader(title: subject.name),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
                children: [
                  _SubjectHeaderCard(
                    subject: subject,
                    worksheets: worksheets.length,
                    classwork: classwork.length,
                    insight: insight,
                  ),
                  const SizedBox(height: 18),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    child: Row(
                      children: [
                        for (final tab in _tabs) ...[
                          AppChip(
                            label: tab,
                            selected: _tab == tab,
                            selectedBackground: k.priC,
                            selectedBorder: k.priBd,
                            selectedForeground: k.priInk,
                            onTap: () => setState(() => _tab = tab),
                          ),
                          const SizedBox(width: 8),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (_tab == 'Overview')
                    _Overview(
                      subject: subject,
                      latest: [...worksheets, ...classwork]
                        ..sort((a, b) => b.date.compareTo(a.date)),
                      pending: pending,
                      insight: insight,
                    )
                  else if (_tab == 'Marks')
                    _MarksTab(subject: subject, insight: insight)
                  else
                    _RecordList(
                      label: _tab,
                      subjectName: subject.name,
                      records: switch (_tab) {
                        'Worksheets' => worksheets,
                        'Exams' => exams,
                        _ => classwork,
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubjectHeaderCard extends StatelessWidget {
  const _SubjectHeaderCard({
    required this.subject,
    required this.worksheets,
    required this.classwork,
    this.insight,
  });

  final Subject subject;
  final int worksheets;
  final int classwork;
  final SubjectInsight? insight;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    // The design shows an average-marks figure here. With marks recorded
    // that is what leads; without any, the honest headline is how much of
    // this subject the diary actually holds.
    final average = insight?.averagePercent;
    final total = worksheets + classwork;
    final headline = average == null ? '$total' : '${average.round()}%';
    final caption = average == null
        ? '$worksheets worksheet${worksheets == 1 ? '' : 's'} · '
              '$classwork classwork'
        : '${confidenceLabel(insight!)} · '
              '$worksheets worksheet${worksheets == 1 ? '' : 's'}';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: subject.hue.tint(k),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: k.surf,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(
              subject.abbr,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: subject.hue.ink(k),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  headline,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    height: 1,
                    color: subject.hue.ink(k),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: subject.hue.ink(k).withValues(alpha: .85),
                  ),
                ),
              ],
            ),
          ),
          if (insight != null && insight!.band != InsightBand.unknown) ...[
            const SizedBox(width: 10),
            InsightBandPill(insight!.band),
          ],
        ],
      ),
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({
    required this.subject,
    required this.latest,
    required this.pending,
    this.insight,
  });

  final Subject subject;
  final List<DiaryRecord> latest;
  final int pending;
  final SubjectInsight? insight;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final root = Navigator.of(context, rootNavigator: true);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Latest activity'),
        const SizedBox(height: 10),
        if (latest.isEmpty)
          EmptyListNotice(
            title: 'Nothing saved yet',
            description: 'Records filed under ${subject.name} appear here.',
          )
        else
          for (final record in latest.take(3)) ...[
            AppCard(
              radius: 16,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              onTap: () => root.pushNamed(
                record.isWorksheet
                    ? Routes.worksheetDetail
                    : Routes.classworkDetail,
                arguments: record.id,
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: subject.hue.tint(k),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: StrokeIcon(
                      record.isWorksheet ? AppIcons.document : AppIcons.camera,
                      size: 18,
                      color: subject.hue.ink(k),
                      strokeWidth: 1.9,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          record.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${record.isWorksheet ? 'Worksheet' : 'Classwork'}'
                          ' · ${AppDate.short(record.date)}',
                          style: TextStyle(fontSize: 12, color: k.tx4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
        if (pending > 0) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: k.warnC,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Dot(color: k.warn, size: 8),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '$pending pending worksheet${pending == 1 ? '' : 's'}',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: k.warnInk,
                    ),
                  ),
                ),
                AppInkWell(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const WorksheetsListPage(),
                    ),
                  ),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    child: Text(
                      'View',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: k.warnInk,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        // "Latest marks" and the trend chart sit here behind showExamMarks.
        if (insight != null && insight!.sampleCount > 0) ...[
          const SizedBox(height: 22),
          const SectionLabel('Latest marks'),
          const SizedBox(height: 10),
          _InsightSummary(subject: subject, insight: insight!),
        ],
      ],
    );
  }
}

/// Band, average, latest and the reasons — the same verdict the Performance
/// tab shows, in the subject's own colour.
class _InsightSummary extends StatelessWidget {
  const _InsightSummary({required this.subject, required this.insight});

  final Subject subject;
  final SubjectInsight insight;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final state = AppScope.of(context);
    final points = <TrendPoint>[
      for (final r in state.insightResults.toList()
        ..sort((a, b) => a.date.compareTo(b.date)))
        for (final s in r.scores)
          if (s.subject == subject.name && !s.absent && s.percent != null)
            (label: r.examLabel, value: s.percent!),
    ];

    return AppCard(
      radius: 18,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                percentLabel(insight.averagePercent),
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  height: 1,
                  color: subject.hue.ink(k),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'average · latest ${percentLabel(insight.latestPercent)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: k.tx4),
                ),
              ),
              InsightBandPill(insight.band),
            ],
          ),
          const SizedBox(height: 12),
          TrendLineChart(points: points, color: subject.hue.dot(k)),
          if (insight.reasons.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final reason in insight.reasons.take(2))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '· $reason',
                  style: TextStyle(fontSize: 13, height: 1.4, color: k.tx2),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Every score this subject has, newest first, above the trend line.
class _MarksTab extends StatelessWidget {
  const _MarksTab({required this.subject, this.insight});

  final Subject subject;
  final SubjectInsight? insight;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final state = AppScope.of(context);
    final root = Navigator.of(context, rootNavigator: true);
    final rows = <(ExamResult, SubjectScore)>[
      for (final r in state.insightResults)
        for (final s in r.scores)
          if (s.subject == subject.name) (r, s),
    ]..sort((a, b) => b.$1.date.compareTo(a.$1.date));

    if (rows.isEmpty) {
      return EmptyListNotice(
        title: 'No marks yet',
        description: 'Marks entered for ${subject.name} appear here.',
      );
    }

    final average = insight?.averagePercent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (insight != null && insight!.sampleCount > 0) ...[
          _InsightSummary(subject: subject, insight: insight!),
          const SizedBox(height: 18),
        ],
        SectionLabel('Marks · ${subject.name}'),
        const SizedBox(height: 10),
        for (final (result, score) in rows) ...[
          AppCard(
            radius: 16,
            onTap: () =>
                root.pushNamed(Routes.resultDetail, arguments: result.id),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result.examLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          AppDate.short(result.date),
                          if (score.hasMarks)
                            '${score.marks!.round()} / ${score.maxMarks!.round()}',
                          if (score.hasGrade) 'Grade ${score.grade}',
                          if (score.absent) 'Absent',
                        ].join(' · '),
                        style: TextStyle(fontSize: 12, color: k.tx4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      score.absent ? 'Absent' : percentLabel(score.percent),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.3,
                        color: score.percent == null ? k.tx4 : k.tx,
                      ),
                    ),
                    if (score.percent != null && average != null && rows.length > 1)
                      Text(
                        deltaLabel(score.percent! - average),
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: score.percent! < average ? k.err : k.secInk2,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _RecordList extends StatelessWidget {
  const _RecordList({
    required this.label,
    required this.subjectName,
    required this.records,
  });

  final String label;
  final String subjectName;
  final List<DiaryRecord> records;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final root = Navigator.of(context, rootNavigator: true);

    if (records.isEmpty) {
      return EmptyListNotice(
        title: 'No ${label.toLowerCase()} yet',
        description: 'Nothing filed under $subjectName so far.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel('$label · $subjectName'),
        const SizedBox(height: 10),
        for (final record in records) ...[
          AppCard(
            radius: 16,
            onTap: () => root.pushNamed(
              switch (record.type) {
                RecordType.worksheet => Routes.worksheetDetail,
                RecordType.classwork => Routes.classworkDetail,
                RecordType.exam => Routes.examDetail,
              },
              arguments: record.id,
            ),
            child: Row(
              children: [
                attachmentThumb(
                  context,
                  record.examTimetable ??
                      record.attachments.firstOrNull ??
                      record.answerKey,
                  radius: 12,
                  width: 52,
                  height: 52,
                  showCaption: false,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        record.isExam ? record.examType : record.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${AppDate.short(record.date)} · '
                        '${switch (record.type) {
                          RecordType.worksheet => AppFormat.fileCount(record.fileCount),
                          RecordType.classwork => AppFormat.photoCount(record.attachments.length),
                          RecordType.exam => AppFormat.fileCount(record.allFiles.length),
                        }}',
                        style: TextStyle(fontSize: 12, color: k.tx4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                if (record.isWorksheet)
                  StatusPill(
                    label: record.status == WorksheetStatus.completed
                        ? 'Done'
                        : 'Pending',
                    background: record.status == WorksheetStatus.completed
                        ? k.subSciC
                        : k.warnC,
                    foreground: record.status == WorksheetStatus.completed
                        ? k.subSciInk
                        : k.warnInk,
                  )
                else
                  StatusPill(
                    label: record.isExam ? 'Exam' : 'Photos',
                    background: record.isExam ? k.warnC : k.surf2,
                    foreground: record.isExam ? k.warnInk : k.tx3,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}
