import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../core/format.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/subject_hue.dart';
import '../../core/widgets/app_icons.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/chips.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/sheets.dart';
import '../../core/widgets/stroke_icon.dart';
import '../../core/widgets/toast.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../performance/insight_widgets.dart';

/// The report card as saved: every subject with its percent and how it sits
/// against that subject's own average, the teacher's remarks, where the
/// numbers came from, and edit / delete.
class ResultDetailPage extends StatelessWidget {
  const ResultDetailPage({super.key, required this.resultId});

  final String resultId;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final state = AppScope.of(context);
    final result = state.resultById(resultId);

    if (result == null) {
      // Deleted underneath us (or not arrived yet): the caller pops.
      return Scaffold(backgroundColor: k.bg, body: const SizedBox.shrink());
    }

    final overall = result.overallPercent;
    final linked = result.examRecordId == null
        ? null
        : state.recordById(result.examRecordId!);

    Future<void> delete() async {
      final confirmed = await confirmDelete(
        context,
        title: 'Delete these marks?',
        description:
            'This report card will be removed from the Performance tab. '
            'You can undo straight away.',
      );
      if (!confirmed || !context.mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      try {
        await state.deleteResult(result.id);
      } catch (error) {
        if (!context.mounted) return;
        AppToast.failure(context, error, title: "Couldn't delete marks");
        return;
      }
      if (!context.mounted) return;
      Navigator.of(context).pop();
      AppToast.showOn(
        messenger,
        context,
        title: 'Marks deleted',
        description: '${result.examLabel} was removed.',
        kind: ToastKind.warn,
        actionLabel: 'Undo',
        onAction: () => state.restoreResult(result.id),
      );
    }

    return Scaffold(
      backgroundColor: k.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ScreenHeader(
                actions: [
                  AppIconButton(
                    tooltip: 'Edit',
                    onTap: () => Navigator.of(context).pushReplacementNamed(
                      Routes.addResult,
                      arguments: result,
                    ),
                    child: StrokeIcon(AppIcons.edit, size: 19, color: k.tx2),
                  ),
                  AppIconButton(
                    tooltip: 'Delete',
                    hoverBackground: k.errC,
                    onTap: delete,
                    child: StrokeIcon(AppIcons.trash, size: 19, color: k.err),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      StatusPill(
                        label: result.source.label,
                        background: result.source == ResultSource.manual
                            ? k.secC
                            : k.surf2,
                        foreground: result.source == ResultSource.manual
                            ? k.secInk
                            : k.tx3,
                        dotColor: result.source == ResultSource.manual
                            ? k.sec
                            : null,
                      ),
                      if (result.needsReview)
                        StatusPill(
                          label: 'Needs review',
                          background: k.warnC,
                          foreground: k.warnInk,
                          dotColor: k.warn,
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    result.examLabel,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${AppDate.full(result.date)} · ${result.academicYearId}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: k.tx3,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: k.priC,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        _Stat(
                          value: percentLabel(overall),
                          label: 'overall',
                          big: true,
                        ),
                        const SizedBox(width: 22),
                        _Stat(
                          value: '${result.gradedSubjectCount}',
                          label: 'scored',
                        ),
                        if (result.attendancePercent != null) ...[
                          const SizedBox(width: 22),
                          _Stat(
                            value: percentLabel(result.attendancePercent),
                            label: 'attendance',
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (linked != null) ...[
                    const SizedBox(height: 12),
                    AppCard(
                      radius: 14,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      onTap: () => Navigator.of(context).pushNamed(
                        Routes.examDetail,
                        arguments: linked.id,
                      ),
                      child: Row(
                        children: [
                          StrokeIcon(AppIcons.calendar, size: 18, color: k.tx3),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Exam · ${linked.examType} · ${linked.subject}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          StrokeIcon(AppIcons.forward, size: 16, color: k.tx5),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  const SectionLabel('Subjects'),
                  const SizedBox(height: 10),
                  for (final score in result.scores) ...[
                    _ScoreCard(score: score),
                    const SizedBox(height: 10),
                  ],
                  if (result.teacherRemarks.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const SectionLabel("Teacher's remarks"),
                    const SizedBox(height: 10),
                    AppCard(
                      radius: 16,
                      child: Text(
                        result.teacherRemarks,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.5,
                          color: k.tx2,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.big = false});

  final String value;
  final String label;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: big ? 32 : 20,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.6,
            height: 1,
            color: k.priInk,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: k.priInk2,
          ),
        ),
      ],
    );
  }
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({required this.score});

  final SubjectScore score;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final state = AppScope.of(context);
    final known = state.subjectNames.contains(score.subject);
    final subject = state.subjectByName(score.subject);
    final insight = state.insightFor(score.subject);
    final percent = score.percent;
    final delta = (percent == null || insight?.averagePercent == null)
        ? null
        : percent - insight!.averagePercent!;

    final String headline;
    if (score.absent) {
      headline = 'Absent';
    } else if (score.hasMarks) {
      headline =
          '${_trim(score.marks!)} / ${_trim(score.maxMarks!)}';
    } else if (score.hasGrade) {
      headline = score.grade!;
    } else {
      headline = '—';
    }

    return AppCard(
      radius: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SubjectTag(name: score.subject, hue: subject.hue),
                ),
              ),
              if (score.classRank != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: StatusPill(
                    label: 'Rank ${score.classRank}',
                    background: k.surf2,
                    foreground: k.tx3,
                  ),
                ),
              Text(
                percent == null ? headline : '${percent.round()}%',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: score.absent ? k.tx4 : k.tx,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  [
                    if (percent != null) headline,
                    if (score.hasGrade && score.hasMarks) 'Grade ${score.grade}',
                    if (score.isDerivedPercent)
                      'approx. from grade ${score.grade}',
                  ].join(' · '),
                  style: TextStyle(fontSize: 12.5, color: k.tx4),
                ),
              ),
              if (delta != null && insight!.sampleCount > 1)
                Text(
                  deltaLabel(delta, suffix: 'own avg'),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: delta < 0 ? k.err : k.secInk2,
                  ),
                ),
            ],
          ),
          if (score.remarks.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              score.remarks,
              style: TextStyle(fontSize: 13.5, height: 1.4, color: k.tx2),
            ),
          ],
          if (!known) ...[
            const SizedBox(height: 10),
            AppTonalButton(
              label: 'Add ${score.subject} as a subject',
              height: 40,
              fontSize: 13,
              borderRadius: 12,
              background: k.surf2,
              hoverBackground: k.hov,
              foreground: k.tx2,
              onPressed: () async {
                try {
                  await state.addSubject(
                    Subject(
                      name: score.subject,
                      abbr: AppFormat.initials(score.subject),
                      hue: SubjectHue.stone,
                      order: 0,
                    ),
                  );
                  if (!context.mounted) return;
                  AppToast.show(
                    context,
                    title: 'Subject added',
                    description:
                        '${score.subject} now appears in every subject list.',
                  );
                } catch (error) {
                  if (!context.mounted) return;
                  AppToast.failure(
                    context,
                    error,
                    title: "Couldn't add subject",
                  );
                }
              },
            ),
          ],
        ],
      ),
    );
  }

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
}
