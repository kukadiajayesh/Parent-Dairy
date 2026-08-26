import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../core/config/feature_flags.dart';
import '../../core/format.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_icons.dart';
import '../../core/widgets/attachment_image.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/chips.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/states.dart';
import '../../core/widgets/stroke_icon.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../shell/shell_scope.dart';
import '../children/child_switcher_sheet.dart';
import '../search/search_page.dart';
import '../settings/year_switcher_sheet.dart';
import '../worksheet/worksheets_list_page.dart';

/// Home dashboard: greeting, child/year switcher, quick actions, pending
/// worksheets and recent activity.
/// Greets by the actual time of day rather than assuming morning — parents
/// file worksheets after school as often as before it.
String _greeting() {
  final hour = DateTime.now().hour;
  if (hour < 12) return 'Good morning,';
  if (hour < 17) return 'Good afternoon,';
  return 'Good evening,';
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final state = AppScope.of(context);
    final pending = state.pendingWorksheets;
    final recent = state.recordsByDateDesc.take(5).toList();

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
              toolbarHeight: 60,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _greeting(),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: k.tx4,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    state.parentName,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
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
                const SizedBox(width: 8),
                AppIconButton(
                  size: 42,
                  borderRadius: 14,
                  background: k.surf2,
                  hoverBackground: k.hov,
                  tooltip: 'Settings',
                  onTap: () =>
                      ShellScope.maybeOf(context)?.goToTab('more'),
                  child: StrokeIcon(AppIcons.settings, size: 20, color: k.tx2),
                ),
                const SizedBox(width: 20),
              ],
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 120),
              sliver: SliverList.list(
                children: [
                  const _ChildYearRow(),
                  const SizedBox(height: 22),
                  const SectionLabel('Quick actions'),
                  const SizedBox(height: 12),
                  const _QuickActions(),
                  const SizedBox(height: 22),
                  SectionLabel(
                    'Pending worksheets',
                    trailing: SectionAction(
                      label: 'View all',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const WorksheetsListPage(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (pending.isEmpty)
                    const EmptyListNotice(
                      title: 'Nothing pending',
                      description: 'Every worksheet is marked completed.',
                    )
                  else ...[
                    _PendingBanner(count: pending.length),
                    const SizedBox(height: 12),
                    _PendingCarousel(records: pending),
                  ],
                  const SizedBox(height: 22),
                  SectionLabel(
                    'Recent activity',
                    trailing: SectionAction(
                      label: 'View all',
                      onTap: () =>
                          ShellScope.maybeOf(context)?.goToTab('timeline'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final record in recent) ...[
                    _RecentRow(record: record),
                    const SizedBox(height: 8),
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

class _ChildYearRow extends StatelessWidget {
  const _ChildYearRow();

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final state = AppScope.of(context);
    final child = state.activeChild;

    return Row(
      children: [
        Expanded(
          child: Material(
            color: k.surf,
            shape: StadiumBorder(side: BorderSide(color: k.bd2)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => ChildSwitcherSheet.show(context),
              hoverColor: k.hov2,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
                child: Row(
                  children: [
                    Monogram(initials: child.initials),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            child.name,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              height: 1.2,
                            ),
                          ),
                          Text(
                            '${child.grade} · ${state.activeYear}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: k.tx3),
                          ),
                        ],
                      ),
                    ),
                    StrokeIcon(AppIcons.caretDown, size: 16, color: k.tx3),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Material(
          color: k.surf2,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => YearSwitcherSheet.show(context),
            hoverColor: k.hov,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'YEAR',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .6,
                      color: k.tx4,
                    ),
                  ),
                  Text(
                    state.activeYear,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final root = Navigator.of(context, rootNavigator: true);

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _QuickActionTile(
                label: 'Worksheet',
                tint: k.subMathC,
                icon: AppIcons.document,
                iconColor: k.subMathInk,
                hoverBorder: k.priBd,
                onTap: () => root.pushNamed(Routes.addWorksheet),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _QuickActionTile(
                label: 'Classwork',
                tint: k.subSciC,
                icon: AppIcons.camera,
                iconColor: k.subSciInk,
                hoverBorder: k.sec,
                onTap: () => root.pushNamed(Routes.addClasswork),
              ),
            ),
          ],
        ),
        // Exam and Marks tiles live here in the design, behind showExamMarks.
        const SizedBox(height: 12),
        _AddFromImageBanner(onTap: () => root.pushNamed(Routes.shareImage)),
      ],
    );
  }
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({
    required this.label,
    required this.tint,
    required this.icon,
    required this.iconColor,
    required this.hoverBorder,
    required this.onTap,
  });

  final String label;
  final Color tint;
  final SvgIcon icon;
  final Color iconColor;
  final Color hoverBorder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      radius: 18,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: StrokeIcon(icon, size: 19, color: iconColor),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _AddFromImageBanner extends StatelessWidget {
  const _AddFromImageBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: k.secFill.withValues(alpha: .24),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: k.secFill,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          hoverColor: k.secFillH,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const StrokeIcon(
                    AppIcons.upload,
                    size: 22,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Add from Image',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Share a photo straight into the diary',
                        style:
                            TextStyle(fontSize: 12.5, color: Color(0xFFCADED9)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PendingBanner extends StatelessWidget {
  const _PendingBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: k.warnC,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Dot(color: k.warn, size: 8),
          const SizedBox(width: 8),
          Text(
            '$count worksheet${count == 1 ? '' : 's'} pending',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: k.warnInk,
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingCarousel extends StatelessWidget {
  const _PendingCarousel({required this.records});

  final List<DiaryRecord> records;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final state = AppScope.of(context);
    final root = Navigator.of(context, rootNavigator: true);

    return SizedBox(
      height: 150,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: EdgeInsets.zero,
        itemCount: records.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final record = records[index];
          final subject = state.subjectByName(record.subject);
          return SizedBox(
            width: 196,
            child: AppCard(
              radius: 18,
              onTap: () => root.pushNamed(
                Routes.worksheetDetail,
                arguments: record.id,
              ),
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
                  const SizedBox(height: 8),
                  Expanded(
                    child: Text(
                      record.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          record.dueDate == null
                              ? AppDate.short(record.date)
                              : 'Due ${AppDate.dueLabel(record.dueDate!)}',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: k.tx3,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      StatusPill(
                        label: 'Pending',
                        background: k.warnC,
                        foreground: k.warnInk,
                        dotColor: k.warn,
                        fontSize: 11,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _RecentRow extends StatelessWidget {
  const _RecentRow({required this.record});

  final DiaryRecord record;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final state = AppScope.of(context);
    final subject = state.subjectByName(record.subject);
    final root = Navigator.of(context, rootNavigator: true);

    return AppCard(
      radius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: () => root.pushNamed(
        record.isWorksheet ? Routes.worksheetDetail : Routes.classworkDetail,
        arguments: record.id,
      ),
      child: Row(
        children: [
          record.attachments.isNotEmpty || record.answerKey != null
              ? attachmentThumb(
                  context,
                  record.attachments.firstOrNull ?? record.answerKey,
                  radius: 12,
                  width: 38,
                  height: 38,
                  showCaption: false,
                )
              : SubjectBadge(abbr: subject.abbr, hue: subject.hue),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      record.isWorksheet ? 'WORKSHEET' : 'CLASSWORK',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .4,
                        color: subject.hue.ink(k),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '· ${AppDate.short(record.date)}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: k.tx5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${record.subject} · ${record.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Row(
            children: [
              StrokeIcon(AppIcons.attachment, size: 13, color: k.tx4),
              const SizedBox(width: 4),
              Text(
                '${record.fileCount}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: k.tx4,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Kept here so the flag's effect on the dashboard is greppable.
const bool homeShowsMarksSection = kShowExamMarks;
