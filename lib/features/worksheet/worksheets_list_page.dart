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
import '../search/search_page.dart';
import '../subject/subject_page.dart';

/// Worksheets grouped by subject, filtered by status and subject chips.
class WorksheetsListPage extends StatelessWidget {
  const WorksheetsListPage({super.key});

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final state = AppScope.of(context);

    final filtered = state.worksheets.where((w) {
      final status = state.worksheetStatusFilter;
      return status == 'All' || w.status.label == status;
    }).toList();
    final groups = state.groupBySubject(filtered, 'worksheet');

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
                    'Worksheets',
                    style: TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.4,
                    ),
                  ),
                ],
              ),
              actions: [
                AppIconButton(
                  size: 42,
                  borderRadius: 14,
                  background: k.surf2,
                  hoverBackground: k.hov,
                  tooltip: 'Search',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const SearchPage()),
                  ),
                  child: StrokeIcon(AppIcons.search, size: 20, color: k.tx2),
                ),
                const SizedBox(width: 20),
              ],
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
              sliver: SliverList.list(
                children: [
                  Row(
                    children: [
                      for (final status in ['All', 'Pending', 'Completed']) ...[
                        AppChip(
                          label: status,
                          selected: state.worksheetStatusFilter == status,
                          onTap: () => state.setWorksheetStatusFilter(status),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  const SubjectFilterChips(),
                  const SizedBox(height: 16),
                  if (groups.isEmpty)
                    const EmptyListNotice(
                      title: 'No worksheets here',
                      description:
                          'Nothing matches this subject and status yet.',
                    )
                  else
                    for (final group in groups) ...[
                      SubjectGroupHeader(group: group),
                      const SizedBox(height: 10),
                      for (final record in group.items) ...[
                        _WorksheetRow(record: record),
                        const SizedBox(height: 10),
                      ],
                      const SizedBox(height: 14),
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

/// Subject chip row shared by the worksheets and classwork lists.
class SubjectFilterChips extends StatelessWidget {
  const SubjectFilterChips({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        AppChip(
          label: 'All',
          selected: state.listSubject == 'All',
          fontSize: 12.5,
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          onTap: () => state.setListSubject('All'),
        ),
        for (final subject in state.subjects)
          SubjectChip(
            name: subject.name,
            hue: subject.hue,
            selected: state.listSubject == subject.name,
            fontSize: 12.5,
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            onTap: () => state.setListSubject(subject.name),
          ),
      ],
    );
  }
}

/// Subject divider: coloured dot, uppercase name, rule, and the group count.
class SubjectGroupHeader extends StatelessWidget {
  const SubjectGroupHeader({super.key, required this.group, this.onTap});

  final SubjectGroup group;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      child: Row(
        children: [
          Dot(color: group.subject.hue.dot(k), size: 9),
          const SizedBox(width: 9),
          Text(
            group.subject.name.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: .7,
              color: group.subject.hue.ink(k),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(child: Container(height: 1, color: k.bd2)),
          const SizedBox(width: 9),
          Text(
            group.count,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: k.tx4,
            ),
          ),
        ],
      ),
    );

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      // The design reaches Subject detail from the Performance tab, which this
      // build excludes; the group header is the natural replacement entry.
      onTap: onTap ??
          () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SubjectPage(subjectName: group.subject.name),
                ),
              ),
      child: content,
    );
  }
}

class _WorksheetRow extends StatelessWidget {
  const _WorksheetRow({required this.record});

  final DiaryRecord record;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final completed = record.status == WorksheetStatus.completed;
    // The title is the chosen chapter, so the subtitle only needs the dates —
    // repeating the chapter here would just echo the heading above it.
    final dates = completed && record.completedDate != null
        ? 'Given ${AppDate.short(record.date)} · done '
            '${AppDate.short(record.completedDate!)}'
        : 'Given ${AppDate.short(record.date)}'
            '${record.dueDate == null ? '' : ' · due ${AppDate.short(record.dueDate!)}'}';

    return AppCard(
      onTap: () => Navigator.of(context, rootNavigator: true)
          .pushNamed(Routes.worksheetDetail, arguments: record.id),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.title,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(dates, style: TextStyle(fontSize: 12.5, color: k.tx3)),
                  const Spacer(),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      StatusPill(
                        label: record.status.label,
                        background: completed ? k.subSciC : k.warnC,
                        foreground: completed ? k.subSciInk : k.warnInk,
                        dotColor:
                            completed ? const Color(0xFF3E8168) : k.warn,
                      ),
                      StatusPill(
                        label: AppFormat.fileCount(record.fileCount),
                        background: k.surf2,
                        foreground: k.tx3,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            attachmentThumb(
              context,
              record.attachments.firstOrNull,
              radius: 14,
              width: 76,
              height: 92,
              showCaption: false,
            ),
          ],
        ),
      ),
    );
  }
}
