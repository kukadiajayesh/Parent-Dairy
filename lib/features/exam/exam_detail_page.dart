import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../core/format.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_icons.dart';
import '../../core/widgets/attachment_image.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/chips.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/sheets.dart';
import '../../core/widgets/stroke_icon.dart';
import '../../core/widgets/toast.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../data/models_ai.dart';
import '../ai/ai_widgets.dart';
import '../viewer/viewer_page.dart';

/// Exam detail: subject tag, exam type, date, timetable image and the
/// previous-exam-papers gallery.
class ExamDetailPage extends StatelessWidget {
  const ExamDetailPage({super.key, required this.recordId});

  final String recordId;

  // Exam attachments are always images (enforced by the add-exam picker), so
  // this always opens the in-app gallery viewer — never an external PDF app.
  void _openAttachment(BuildContext context, DiaryRecord record, int index) {
    final files = [
      if (record.examTimetable != null) record.examTimetable!,
      ...record.attachments,
    ];
    Navigator.of(context).pushNamed(
      Routes.viewer,
      arguments: ViewerArgs(attachments: files, initialIndex: index),
    );
  }

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final state = AppScope.of(context);
    final record = state.recordById(recordId);

    if (record == null) {
      return Scaffold(backgroundColor: k.bg, body: const SizedBox.shrink());
    }

    final subject = state.subjectByName(record.subject);
    final scanned = state.aiAvailable ? state.scannedPaperFor(record.id) : null;
    final graded = scanned == null
        ? null
        : state
              .generatedForRecord(record.id)
              .where((g) => g.kind == GeneratedKind.gradedPaper)
              .firstOrNull;

    Future<void> delete() async {
      if (!await confirmDelete(context)) return;
      if (!context.mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      await state.deleteRecord(record.id);
      if (!context.mounted) return;
      Navigator.of(context).pop();
      AppToast.showOn(
        messenger,
        context,
        title: 'Record deleted',
        description: '${record.examType} was removed.',
        kind: ToastKind.warn,
        actionLabel: 'Undo',
        onAction: () => state.restoreRecord(record.id),
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
                      Routes.addExam,
                      arguments: record,
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
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      SubjectTag(name: record.subject, hue: subject.hue),
                      if (record.isAiGenerated) const AiBadge(label: 'Scanned'),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    record.examType,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    AppDate.full(record.date),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: k.tx3,
                    ),
                  ),
                  if (scanned != null) ...[
                    const SizedBox(height: 18),
                    const SectionLabel('From the scan'),
                    const SizedBox(height: 10),
                    _AiAction(
                      title: record.answerKey == null
                          ? 'Generate answer key'
                          : 'Answer key attached',
                      description: record.answerKey == null
                          ? 'Worked solutions and a marking scheme for every question'
                          : 'AI-generated · verify before use · tap to view or replace',
                      onTap: () => Navigator.of(context).pushNamed(
                        Routes.answerKey,
                        arguments: record.id,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _AiAction(
                      title: graded == null ? 'Grade this paper' : 'Graded',
                      description: scanned.asScannedPaper.hasStudentAnswers
                          ? (graded == null
                                ? 'Mark each handwritten answer and save the total as a result'
                                : 'Saved as a result that needs your review · tap to revisit')
                          : 'Scanned without answers — rescan the completed paper to grade it',
                      onTap: () => Navigator.of(context).pushNamed(
                        Routes.gradePaper,
                        arguments: record.id,
                      ),
                    ),
                  ],
                  if (record.examTimetable != null) ...[
                    const SizedBox(height: 18),
                    const SectionLabel('Exam timetable'),
                    const SizedBox(height: 10),
                    attachmentThumb(
                      context,
                      record.examTimetable,
                      radius: 18,
                      height: 240,
                      onTap: () => _openAttachment(context, record, 0),
                    ),
                  ],
                  if (record.attachments.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    SectionLabel(
                      record.isAiGenerated
                          ? 'Pages · ${record.attachments.length}'
                          : 'Previous papers · ${record.attachments.length}',
                    ),
                    const SizedBox(height: 10),
                    GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 3,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      children: [
                        for (var i = 0; i < record.attachments.length; i++)
                          attachmentThumb(
                            context,
                            record.attachments[i],
                            radius: 14,
                            onTap: () => _openAttachment(
                              context,
                              record,
                              (record.examTimetable != null ? 1 : 0) + i,
                            ),
                          ),
                      ],
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

class _AiAction extends StatelessWidget {
  const _AiAction({
    required this.title,
    required this.description,
    required this.onTap,
  });

  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    return AppCard(
      radius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: k.priC,
              borderRadius: BorderRadius.circular(12),
            ),
            child: StrokeIcon(AppIcons.sparkle, size: 20, color: k.priInk),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(fontSize: 12.5, height: 1.35, color: k.tx3),
                ),
              ],
            ),
          ),
          StrokeIcon(AppIcons.forward, size: 16, color: k.tx4),
        ],
      ),
    );
  }
}
