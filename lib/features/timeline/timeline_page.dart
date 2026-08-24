import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../core/format.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_icons.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/chips.dart';
import '../../core/widgets/image_slot.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/states.dart';
import '../../core/widgets/stroke_icon.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../children/child_switcher_sheet.dart';
import '../search/search_page.dart';
import '../settings/year_switcher_sheet.dart';
import 'timeline_filter_sheet.dart';

/// Academic timeline: every record grouped by day, newest first, with the
/// child / year / filter chips above it.
class TimelinePage extends StatelessWidget {
  const TimelinePage({super.key});

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final state = AppScope.of(context);
    final days = _groupByDay(_applyFilter(state));

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
              title: const Text(
                'Academic Timeline',
                style: TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
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
                const SizedBox(width: 8),
                AppIconButton(
                  size: 42,
                  borderRadius: 14,
                  background: k.priC,
                  hoverBackground: k.priCH,
                  tooltip: 'Filter',
                  onTap: () => TimelineFilterSheet.show(context),
                  child: StrokeIcon(AppIcons.filter, size: 20, color: k.priInk),
                ),
                const SizedBox(width: 20),
              ],
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
              sliver: SliverList.list(
                children: [
                  if (state.showOfflineBanner) ...[
                    OfflineBanner(onDismiss: state.dismissOfflineBanner),
                    const SizedBox(height: 16),
                  ],
                  const _ScopeChips(),
                  const SizedBox(height: 16),
                  if (days.isEmpty)
                    const EmptyStateView(
                      title: 'Nothing here yet',
                      description:
                          "Your child's academic journey will appear here.",
                    )
                  else
                    for (final day in days) ...[
                      SectionLabel(AppDate.dayHeading(day.date)),
                      const SizedBox(height: 10),
                      for (final record in day.records) ...[
                        TimelineCard(record: record),
                        const SizedBox(height: 10),
                      ],
                      const SizedBox(height: 6),
                    ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<DiaryRecord> _applyFilter(AppState state) {
    final filter = state.filter;
    final now = DateTime(2026, 8, 23); // the design's "today"

    return state.recordsByDateDesc.where((record) {
      if (filter.subject != 'All' && record.subject != filter.subject) {
        return false;
      }
      if (filter.type != 'All') {
        final wanted = filter.type == 'Worksheet'
            ? RecordType.worksheet
            : RecordType.classwork;
        if (record.type != wanted) return false;
      }
      return switch (filter.date) {
        'Today' => AppDate.sameDay(record.date, now),
        'This week' => now.difference(record.date).inDays.abs() <= 7,
        'This month' =>
          record.year == now.year && record.date.month == now.month,
        _ => true,
      };
    }).toList();
  }

  List<_Day> _groupByDay(List<DiaryRecord> records) {
    final days = <_Day>[];
    for (final record in records) {
      if (days.isNotEmpty && AppDate.sameDay(days.last.date, record.date)) {
        days.last.records.add(record);
      } else {
        days.add(_Day(record.date, [record]));
      }
    }
    return days;
  }
}

extension on DiaryRecord {
  int get year => date.year;
}

class _Day {
  _Day(this.date, this.records);
  final DateTime date;
  final List<DiaryRecord> records;
}

class _ScopeChips extends StatelessWidget {
  const _ScopeChips();

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final state = AppScope.of(context);

    Widget chip({
      required String label,
      required VoidCallback onTap,
      bool caret = true,
      bool accent = false,
    }) =>
        Material(
          color: accent ? k.priC : k.surf,
          shape: StadiumBorder(
            side: BorderSide(color: accent ? k.priBd : k.bd3),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: accent ? k.priInk : k.tx2,
                    ),
                  ),
                  if (caret) ...[
                    const SizedBox(width: 6),
                    StrokeIcon(
                      AppIcons.caretDown,
                      size: 14,
                      color: accent ? k.priInk : k.tx2,
                    ),
                  ],
                ],
              ),
            ),
          ),
        );

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          chip(
            label: state.activeChild.name,
            onTap: () => ChildSwitcherSheet.show(context),
          ),
          const SizedBox(width: 8),
          chip(
            label: state.activeYear,
            onTap: () => YearSwitcherSheet.show(context),
          ),
          const SizedBox(width: 8),
          chip(
            label: state.filter.summary,
            caret: false,
            accent: true,
            onTap: () => TimelineFilterSheet.show(context),
          ),
        ],
      ),
    );
  }
}

/// Timeline entry: thumbnail on the left, subject / type / title / meta right.
class TimelineCard extends StatelessWidget {
  const TimelineCard({super.key, required this.record});

  final DiaryRecord record;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final state = AppScope.of(context);
    final subject = state.subjectByName(record.subject);
    final root = Navigator.of(context, rootNavigator: true);

    return AppCard(
      shadow: true,
      onTap: () => root.pushNamed(
        record.isWorksheet ? Routes.worksheetDetail : Routes.classworkDetail,
        arguments: record.id,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ImageSlot(
            placeholder: 'Photo',
            radius: 14,
            width: 88,
            height: 92,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Dot(color: subject.hue.dot(k), size: 9),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        record.subject.toUpperCase(),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: .3,
                          color: subject.hue.ink(k),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  record.isWorksheet ? 'Worksheet' : 'Classwork',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: k.tx6,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  record.title,
                  style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    StatusPill(
                      label: record.isWorksheet
                          ? AppFormat.attachmentCount(record.fileCount)
                          : AppFormat.photoCount(record.attachments.length),
                      background: k.surf2,
                      foreground: k.tx3,
                      leading: StrokeIcon(
                        record.isWorksheet ? AppIcons.attachment : AppIcons.camera,
                        size: 12,
                        color: k.tx3,
                        strokeWidth: record.isWorksheet ? 2.2 : 2,
                      ),
                    ),
                    if (record.isWorksheet &&
                        record.status == WorksheetStatus.pending)
                      StatusPill(
                        label: 'Pending',
                        background: k.warnC,
                        foreground: k.warnInk,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
