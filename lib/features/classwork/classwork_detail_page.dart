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
import '../viewer/viewer_page.dart';

/// Classwork detail: subject tag, title, date + photo count, notes and the
/// photo grid with an "Open viewer" tile.
class ClassworkDetailPage extends StatelessWidget {
  const ClassworkDetailPage({super.key, required this.recordId});

  final String recordId;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final state = AppScope.of(context);
    final record = state.recordById(recordId);

    if (record == null) {
      return Scaffold(backgroundColor: k.bg, body: const SizedBox.shrink());
    }

    final subject = state.subjectByName(record.subject);

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

    void openViewer(int index) => Navigator.of(context).pushNamed(
          Routes.viewer,
          arguments: ViewerArgs(
            attachments: record.attachments,
            initialIndex: index,
          ),
        );

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
                      Routes.addClasswork,
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
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SubjectTag(name: record.subject, hue: subject.hue),
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
                  Text(
                    '${AppDate.full(record.date)} · '
                    '${AppFormat.photoCount(record.attachments.length)}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: k.tx3,
                    ),
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
                  const SizedBox(height: 18),
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1,
                    children: [
                      for (var i = 0; i < record.attachments.length; i++)
                        ImageSlot(
                          placeholder: record.attachments[i].meta,
                          radius: 16,
                          onTap: () => openViewer(i),
                        ),
                      InkWell(
                        onTap: record.attachments.isEmpty
                            ? null
                            : () => openViewer(0),
                        borderRadius: BorderRadius.circular(16),
                        child: DashedContainer(
                          radius: 16,
                          padding: EdgeInsets.zero,
                          color: k.bd4,
                          background: k.surf2,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              StrokeIcon(
                                AppIcons.searchPlus,
                                size: 22,
                                color: k.tx4,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Open viewer',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: k.tx3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
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
