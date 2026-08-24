import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../core/format.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_icons.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/chips.dart';
import '../../core/widgets/image_slot.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/sheets.dart';
import '../../core/widgets/states.dart';
import '../../core/widgets/stroke_icon.dart';
import '../../core/widgets/toast.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../viewer/viewer_page.dart';

/// Worksheet detail: subject tag, status, dates, notes, attachment gallery,
/// answer key and the "Mark completed" action.
class WorksheetDetailPage extends StatelessWidget {
  const WorksheetDetailPage({super.key, required this.recordId});

  final String recordId;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final state = AppScope.of(context);
    final record = state.recordById(recordId);

    if (record == null) {
      // The record was deleted while this screen was on the stack.
      return Scaffold(backgroundColor: k.bg, body: const SizedBox.shrink());
    }

    final subject = state.subjectByName(record.subject);
    final completed = record.status == WorksheetStatus.completed;

    Future<void> delete() async {
      if (!await confirmDelete(context)) return;
      if (!context.mounted) return;
      state.deleteRecord(record.id);
      Navigator.of(context).pop();
      AppToast.show(
        context,
        title: 'Record deleted',
        description: '${record.title} was removed.',
        kind: ToastKind.warn,
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
                    tooltip: 'Share',
                    onTap: () {},
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
                    ImageSlot(
                      placeholder: record.attachments.first.meta,
                      radius: 18,
                      height: 280,
                      onTap: () => _openViewer(context, record, 0),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 76,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: record.attachments.length + 1,
                        separatorBuilder: (_, _) => const SizedBox(width: 10),
                        itemBuilder: (context, index) {
                          if (index == record.attachments.length) {
                            return InkWell(
                              onTap: () => _openViewer(context, record, 0),
                              borderRadius: BorderRadius.circular(12),
                              child: DashedContainer(
                                radius: 12,
                                padding: EdgeInsets.zero,
                                color: k.bd4,
                                background: k.surf2,
                                child: SizedBox(
                                  width: 76,
                                  height: 76,
                                  child: Center(
                                    child: StrokeIcon(
                                      AppIcons.plus,
                                      size: 20,
                                      color: k.tx4,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }
                          return ImageSlot(
                            placeholder: '${index + 1}',
                            radius: 12,
                            width: 76,
                            height: 76,
                            onTap: () => _openViewer(context, record, index),
                          );
                        },
                      ),
                    ),
                  ],
                  if (record.answerKey != null) ...[
                    const SizedBox(height: 18),
                    const SectionLabel('Answer key'),
                    const SizedBox(height: 10),
                    AppCard(
                      radius: 16,
                      onTap: () => _openViewer(
                        context,
                        record,
                        record.attachments.length,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 52,
                            height: 52,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: k.surf2,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'PDF',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: k.tx3,
                              ),
                            ),
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
                    ),
                  ],
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
                      onPressed: () {
                        state.deleteRecord(record.id);
                        state.addRecord(
                          DiaryRecord(
                            id: record.id,
                            type: record.type,
                            subject: record.subject,
                            title: record.title,
                            date: record.date,
                            dueDate: record.dueDate,
                            notes: record.notes,
                            attachments: record.attachments,
                            answerKey: record.answerKey,
                          ),
                        );
                      },
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

  void _openViewer(BuildContext context, DiaryRecord record, int index) {
    Navigator.of(context).pushNamed(
      Routes.viewer,
      arguments: ViewerArgs(
        attachments: [
          ...record.attachments,
          if (record.answerKey != null) record.answerKey!,
        ],
        initialIndex: index,
      ),
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
