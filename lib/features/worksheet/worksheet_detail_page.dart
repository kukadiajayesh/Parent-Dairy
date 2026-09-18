import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../core/format.dart';
import '../../core/services/attachment_actions.dart';
import '../../core/services/image_service.dart';
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
import '../ai/generate_paper_page.dart';
import '../picker/attachment_source_row.dart';
import '../picker/picker_page.dart';
import '../viewer/viewer_page.dart';

/// Worksheet detail: subject tag, status, dates, notes, attachment gallery,
/// answer key and the "Mark completed" action.
class WorksheetDetailPage extends StatefulWidget {
  const WorksheetDetailPage({super.key, required this.recordId});

  final String recordId;

  @override
  State<WorksheetDetailPage> createState() => _WorksheetDetailPageState();
}

class _WorksheetDetailPageState extends State<WorksheetDetailPage> {
  bool _attachingAnswerKey = false;
  bool _attachingHardWords = false;

  Future<void> _pickAnswerKey(DiaryRecord record, AttachmentSource source) async {
    final picked = await Navigator.of(context).push<List<PickedAttachment>>(
      MaterialPageRoute(
        builder: (_) =>
            PickerPage(initialSource: source, allowMultiple: false),
        settings: const RouteSettings(name: Routes.picker),
      ),
    );
    if (picked == null || picked.isEmpty || !mounted) return;

    setState(() => _attachingAnswerKey = true);
    final state = AppScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await state.saveRecord(record, newAnswerKey: picked.first);
      if (!mounted) return;
      AppToast.showOn(
        messenger,
        context,
        title: 'Answer key attached',
        description: '${record.title} now has an answer key.',
      );
    } catch (error) {
      if (!mounted) return;
      AppToast.failure(context, error, title: "Couldn't attach answer key");
    } finally {
      if (mounted) setState(() => _attachingAnswerKey = false);
    }
  }

  Future<void> _pickHardWords(DiaryRecord record, AttachmentSource source) async {
    final picked = await Navigator.of(context).push<List<PickedAttachment>>(
      MaterialPageRoute(
        builder: (_) =>
            PickerPage(initialSource: source, allowMultiple: false),
        settings: const RouteSettings(name: Routes.picker),
      ),
    );
    if (picked == null || picked.isEmpty || !mounted) return;

    setState(() => _attachingHardWords = true);
    final state = AppScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await state.saveRecord(record, newHardWords: picked.first);
      if (!mounted) return;
      AppToast.showOn(
        messenger,
        context,
        title: 'Hard words attached',
        description: '${record.title} now has a hard-words file.',
      );
    } catch (error) {
      if (!mounted) return;
      AppToast.failure(context, error, title: "Couldn't attach hard words");
    } finally {
      if (mounted) setState(() => _attachingHardWords = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final state = AppScope.of(context);
    final record = state.recordById(widget.recordId);

    if (record == null) {
      // The record was deleted while this screen was on the stack.
      return Scaffold(backgroundColor: k.bg, body: const SizedBox.shrink());
    }

    final subject = state.subjectByName(record.subject);
    final completed = record.status == WorksheetStatus.completed;

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
        description: '${record.title} was removed.',
        kind: ToastKind.warn,
        // Soft delete (§30) makes Undo a real restore, not a re-create.
        actionLabel: 'Undo',
        onAction: () => state.restoreRecord(record.id),
      );
    }

    Future<void> share() async {
      try {
        await AttachmentActions.shareRecord(record);
      } catch (error) {
        if (!context.mounted) return;
        AppToast.failure(context, error, title: "Couldn't share");
      }
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
                  if (state.aiAvailable && record.attachments.isNotEmpty)
                    AppIconButton(
                      tooltip: 'Make a similar worksheet',
                      onTap: () => Navigator.of(context).pushNamed(
                        Routes.aiGenerate,
                        arguments: GenerateArgs(
                          subject: record.subject,
                          chapters: record.chapters,
                          output: PaperOutput.worksheet,
                          sourceRecordIds: [record.id],
                        ),
                      ),
                      child: StrokeIcon(AppIcons.sparkle, size: 19, color: k.priInk),
                    ),
                  AppIconButton(
                    tooltip: 'Share',
                    onTap: share,
                    child: StrokeIcon(AppIcons.share, size: 19, color: k.tx2),
                  ),
                  AppIconButton(
                    tooltip: 'Edit',
                    onTap: () => Navigator.of(context).pushReplacementNamed(
                      Routes.addWorksheet,
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
                      if (record.isAiGenerated) const AiBadge(label: 'AI-generated'),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: completed ? k.secC : k.warnC,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Dot(
                              color: completed ? k.secFill : k.warn,
                              size: 7,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              record.status.label,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: completed ? k.secInk : k.warnInk,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    record.title,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Wrap rather than Row: a completed worksheet adds a third
                  // column, which will not fit across on a narrow phone.
                  Wrap(
                    spacing: 18,
                    runSpacing: 10,
                    children: [
                      _MetaColumn(
                        label: 'Given',
                        value: AppDate.full(record.date),
                      ),
                      if (record.dueDate != null)
                        _MetaColumn(
                          label: 'Due',
                          value: AppDate.full(record.dueDate!),
                          valueColor: completed ? null : k.err,
                        ),
                      if (record.completedDate != null)
                        _MetaColumn(
                          label: 'Done',
                          value: AppDate.full(record.completedDate!),
                          valueColor: k.sec,
                        ),
                    ],
                  ),
                  if (record.chapters.length > 1) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final chapter in record.chapters)
                          AppChip(label: chapter, selected: true),
                      ],
                    ),
                  ],
                  if (record.notes.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: k.surf2,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        record.notes,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.55,
                          color: k.tx2,
                        ),
                      ),
                    ),
                  ],
                  if (record.attachments.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    SectionLabel(
                      'Worksheet · ${record.attachments.length} '
                      'page${record.attachments.length == 1 ? '' : 's'}',
                    ),
                    const SizedBox(height: 10),
                    attachmentThumb(
                      context,
                      record.attachments.first,
                      radius: 18,
                      height: 280,
                      onTap: () => _openAttachment(context, record, 0),
                    ),
                    if (record.attachments.length > 1) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 76,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: record.attachments.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 10),
                          itemBuilder: (context, index) {
                            return attachmentThumb(
                              context,
                              record.attachments[index],
                              radius: 12,
                              width: 76,
                              height: 76,
                              onTap: () =>
                                  _openAttachment(context, record, index),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const SectionLabel('Answer key'),
                      if (record.answerKey != null)
                        AppIconButton(
                          size: 32,
                          borderRadius: 10,
                          tooltip: 'Replace',
                          onTap: _attachingAnswerKey
                              ? null
                              : () => _showAnswerKeySourceSheet(record),
                          child: StrokeIcon(
                            AppIcons.editSimple,
                            size: 16,
                            color: k.tx3,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (record.answerKey != null)
                    AppCard(
                      radius: 16,
                      onTap: () => _openAttachment(
                        context,
                        record,
                        record.attachments.length,
                      ),
                      child: Row(
                        children: [
                          attachmentThumb(
                            context,
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
                                  record.answerKey!.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  record.answerKey!.meta,
                                  style:
                                      TextStyle(fontSize: 12, color: k.tx4),
                                ),
                              ],
                            ),
                          ),
                          StrokeIcon(AppIcons.forward, size: 18, color: k.tx4),
                        ],
                      ),
                    )
                  else if (_attachingAnswerKey)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else
                    AttachmentSourceRow(
                      onPick: (source) => _pickAnswerKey(record, source),
                    ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const SectionLabel('Hard words'),
                      if (record.hardWords != null)
                        AppIconButton(
                          size: 32,
                          borderRadius: 10,
                          tooltip: 'Replace',
                          onTap: _attachingHardWords
                              ? null
                              : () => _showHardWordsSourceSheet(record),
                          child: StrokeIcon(
                            AppIcons.editSimple,
                            size: 16,
                            color: k.tx3,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (record.hardWords != null)
                    AppCard(
                      radius: 16,
                      onTap: () => AttachmentActions.open(record.hardWords!),
                      child: Row(
                        children: [
                          attachmentThumb(
                            context,
                            record.hardWords,
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
                                  record.hardWords!.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  record.hardWords!.meta,
                                  style:
                                      TextStyle(fontSize: 12, color: k.tx4),
                                ),
                              ],
                            ),
                          ),
                          StrokeIcon(AppIcons.forward, size: 18, color: k.tx4),
                        ],
                      ),
                    )
                  else if (_attachingHardWords)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else
                    AttachmentSourceRow(
                      onPick: (source) => _pickHardWords(record, source),
                    ),
                ],
              ),
            ),
            StickyFooter(
              child: completed
                  ? AppTonalButton(
                      label: 'Mark pending',
                      background: k.surf2,
                      hoverBackground: k.hov,
                      foreground: k.tx2,
                      onPressed: () =>
                          state.markCompleted(record.id, completed: false),
                    )
                  : AppFilledButton(
                      label: 'Mark completed',
                      color: k.secFill,
                      hoverColor: k.secFillH,
                      icon: const StrokeIcon(
                        AppIcons.check,
                        size: 19,
                        strokeWidth: 2.3,
                      ),
                      onPressed: () {
                        state.markCompleted(record.id);
                        AppToast.show(
                          context,
                          title: 'Worksheet completed',
                          description: '${record.title} is marked done.',
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAnswerKeySourceSheet(DiaryRecord record) async {
    final source = await showModalBottomSheet<AttachmentSource>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionLabel('Replace answer key'),
              const SizedBox(height: 14),
              AttachmentSourceRow(
                emphasizeFirst: true,
                onPick: (s) => Navigator.of(sheetContext).pop(s),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null || !mounted) return;
    await _pickAnswerKey(record, source);
  }

  Future<void> _showHardWordsSourceSheet(DiaryRecord record) async {
    final source = await showModalBottomSheet<AttachmentSource>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionLabel('Replace hard words'),
              const SizedBox(height: 14),
              AttachmentSourceRow(
                emphasizeFirst: true,
                onPick: (s) => Navigator.of(sheetContext).pop(s),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null || !mounted) return;
    await _pickHardWords(record, source);
  }

  /// A PDF opens directly in the device's own viewer; an image opens the
  /// in-app gallery viewer as before.
  Future<void> _openAttachment(
    BuildContext context,
    DiaryRecord record,
    int index,
  ) async {
    final files = [
      ...record.attachments,
      if (record.answerKey != null) record.answerKey!,
    ];
    final attachment = files[index];
    if (attachment.isPdf) {
      try {
        await AttachmentActions.open(attachment);
      } catch (error) {
        if (!context.mounted) return;
        AppToast.failure(context, error, title: "Couldn't open file");
      }
      return;
    }
    final imagesOnly = files.where((f) => !f.isPdf).toList();
    final newIndex = imagesOnly.indexOf(attachment);
    Navigator.of(context).pushNamed(
      Routes.viewer,
      arguments: ViewerArgs(attachments: imagesOnly, initialIndex: newIndex >= 0 ? newIndex : 0),
    );
  }
}

class _MetaColumn extends StatelessWidget {
  const _MetaColumn({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: .8,
            color: k.tx4,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}
