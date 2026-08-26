import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../core/format.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/attachment_image.dart';
import '../../core/widgets/app_icons.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/chips.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/states.dart';
import '../../core/widgets/stroke_icon.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../worksheet/worksheets_list_page.dart';

/// Classwork grouped by subject. Each entry leads with its photo.
class ClassworkListPage extends StatelessWidget {
  const ClassworkListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final state = AppScope.of(context);
    final groups = state.groupBySubject(state.classwork, 'entry');

    return Scaffold(
      backgroundColor: k.bg,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: k.bg,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              titleSpacing: 20,
              automaticallyImplyLeading: false,
              title: Row(
                children: [
                  AppIconButton(
                    onTap: () => Navigator.of(context).pop(),
                    child: StrokeIcon(AppIcons.back, size: 22, color: k.tx),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'Classwork',
                    style: TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                ],
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
              sliver: SliverList.list(
                children: [
                  const SubjectFilterChips(),
                  const SizedBox(height: 16),
                  if (groups.isEmpty)
                    const EmptyListNotice(
                      title: 'No classwork here',
                      description: 'Nothing saved for this subject yet.',
                    )
                  else
                    for (final group in groups) ...[
                      SubjectGroupHeader(group: group),
                      const SizedBox(height: 12),
                      for (final record in group.items) ...[
                        _ClassworkCard(record: record),
                        const SizedBox(height: 12),
                      ],
                      const SizedBox(height: 12),
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

class _ClassworkCard extends StatelessWidget {
  const _ClassworkCard({required this.record});

  final DiaryRecord record;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    return AppCard(
      padding: EdgeInsets.zero,
      clip: true,
      onTap: () => Navigator.of(context, rootNavigator: true)
          .pushNamed(Routes.classworkDetail, arguments: record.id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          attachmentThumb(
            context,
            record.attachments.firstOrNull,
            radius: 0,
            height: 150,
            showCaption: false,
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        record.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        AppDate.full(record.date),
                        style: TextStyle(fontSize: 12.5, color: k.tx4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                StatusPill(
                  label: '${record.attachments.length}',
                  background: k.surf2,
                  foreground: k.tx3,
                  leading:
                      StrokeIcon(AppIcons.camera, size: 12, color: k.tx3),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
