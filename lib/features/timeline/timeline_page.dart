import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../core/config/feature_flags.dart';
import '../../core/format.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/attachment_image.dart';
import '../../core/widgets/app_icons.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/chips.dart';
import '../../core/widgets/layout.dart';
import '../../core/services/attachment_actions.dart';
import '../../core/widgets/pressable.dart';
import '../../core/widgets/states.dart';
import '../../core/widgets/stroke_icon.dart';
import '../../core/widgets/toast.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../ai/ai_widgets.dart';
import '../children/child_switcher_sheet.dart';
import '../result/result_card.dart';
import '../search/search_page.dart';
import '../settings/year_switcher_sheet.dart';
import '../viewer/viewer_page.dart';
import 'timeline_filter_sheet.dart';

/// Academic timeline: every record grouped by day (or chapter), with the
/// child / year / filter chips above it.
class TimelinePage extends StatelessWidget {
  const TimelinePage({super.key});

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final state = AppScope.of(context);
    // "Marks" is a results filter, not a record type: the timeline swaps to
    // report cards grouped by day, so the chip the design offers does
    // something rather than filtering to nothing.
    final showMarks = kShowExamMarks && state.filter.type == 'Marks';
    final groups = showMarks ? const <_TimelineGroup>[] : _getGroups(state);
    final marks = showMarks ? _filteredResults(state) : const <ExamResult>[];

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
                  if (showMarks)
                    if (marks.isEmpty)
                      const EmptyStateView(
                        title: 'No marks yet',
                        description:
                            'Add exam marks to start tracking performance.',
                      )
                    else
                      for (final (heading, items) in _byDay(marks)) ...[
                        SectionLabel(heading),
                        const SizedBox(height: 10),
                        for (final result in items) ...[
                          ResultCard(result: result),
                          const SizedBox(height: 10),
                        ],
                        const SizedBox(height: 6),
                      ]
                  else if (groups.isEmpty)
                    const EmptyStateView(
                      title: 'Nothing here yet',
                      description:
                          "Your child's academic journey will appear here.",
                    )
                  else
                    for (final group in groups) ...[
                      if (!group.isChapter) ...[
                        SectionLabel(group.title),
                        const SizedBox(height: 10),
                      ],
                      for (final record in group.records) ...[
                        TimelineCard(record: record, groupTitle: group.title),
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
    // The real clock, not the design's sample "today": the default filter is
    // "This week", and a pinned date hid every record a parent saved after
    // the week the prototype was drawn in.
    final now = state.now;

    return state.recordsByDateDesc.where((record) {
      if (filter.subject != 'All' && record.subject != filter.subject) {
        return false;
      }
      if (filter.type != 'All') {
        final wanted = switch (filter.type) {
          'Worksheet' => RecordType.worksheet,
          'Exam' => RecordType.exam,
          _ => RecordType.classwork,
        };
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

  /// Results under the same date filter as records; subject and sort do not
  /// apply, since a report card spans every subject.
  List<ExamResult> _filteredResults(AppState state) {
    final filter = state.filter;
    final now = state.now;
    return state.resultsByDateDesc.where((r) {
      return switch (filter.date) {
        'Today' => AppDate.sameDay(r.date, now),
        'This week' => now.difference(r.date).inDays.abs() <= 7,
        'This month' => r.date.year == now.year && r.date.month == now.month,
        _ => true,
      };
    }).toList();
  }

  static List<(String, List<ExamResult>)> _byDay(List<ExamResult> results) {
    final groups = <(String, List<ExamResult>)>[];
    for (final r in results) {
      final heading = AppDate.dayHeading(r.date);
      if (groups.isNotEmpty && groups.last.$1 == heading) {
        groups.last.$2.add(r);
      } else {
        groups.add((heading, [r]));
      }
    }
    return groups;
  }

  List<_TimelineGroup> _getGroups(AppState state) {
    final records = _applyFilter(state);
    final filter = state.filter;

    if (filter.sortBy == 'Chapter') {
      // Natural order on the chapter number ("Chapter 4" before "Chapter
      // 10"), alphabetical when there is none, empty chapters last, newest
      // first within a chapter. The number is extracted once per record
      // rather than inside the comparator: a year of records is ~N log N
      // comparisons, and each used to compile the pattern afresh.
      final keyed = [
        for (final r in records)
          (
            record: r,
            label: r.chapterLabel,
            number: int.tryParse(
              _chapterNumber.firstMatch(r.chapterLabel)?.group(0) ?? '',
            ),
          ),
      ];
      keyed.sort((a, b) {
        if (a.label.isEmpty && b.label.isEmpty) return 0;
        if (a.label.isEmpty) return 1;
        if (b.label.isEmpty) return -1;
        if (a.number != null && b.number != null) {
          final cmp = a.number!.compareTo(b.number!);
          if (cmp != 0) return cmp;
        }
        final cmpStr = a.label.compareTo(b.label);
        if (cmpStr != 0) return cmpStr;
        return b.record.date.compareTo(a.record.date);
      });
      records
        ..clear()
        ..addAll(keyed.map((k) => k.record));

      // Group by chapter
      final groups = <_TimelineGroup>[];
      for (final record in records) {
        final chap = record.chapterLabel.isEmpty
            ? 'No Chapter'
            : record.chapterLabel;
        if (groups.isNotEmpty && groups.last.title == chap) {
          groups.last.records.add(record);
        } else {
          groups.add(
            _TimelineGroup(title: chap, records: [record], isChapter: true),
          );
        }
      }
      return groups;
    } else {
      // Default: records are already sorted by date descending via recordsByDateDesc
      final groups = <_TimelineGroup>[];
      for (final record in records) {
        final dayHeading = AppDate.dayHeading(record.date);
        if (groups.isNotEmpty && groups.last.title == dayHeading) {
          groups.last.records.add(record);
        } else {
          groups.add(_TimelineGroup(title: dayHeading, records: [record]));
        }
      }
      return groups;
    }
  }
}

/// First run of digits in a chapter label — "Chapter 4" → 4.
final _chapterNumber = RegExp(r'\d+');

extension on DiaryRecord {
  int get year => date.year;
}

class _TimelineGroup {
  _TimelineGroup({
    required this.title,
    required this.records,
    this.isChapter = false,
  });

  final String title;
  final List<DiaryRecord> records;

  /// True when [title] is a chapter heading rather than a day heading.
  final bool isChapter;
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
    }) => PressDip(
      child: Material(
        color: accent ? k.priC : k.surf,
        shape: StadiumBorder(side: BorderSide(color: accent ? k.priBd : k.bd3)),
        clipBehavior: Clip.antiAlias,
        child: AppInkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
  const TimelineCard({super.key, required this.record, this.groupTitle});

  final DiaryRecord record;

  /// Heading of the section this card sits under, when it has one.
  final String? groupTitle;

  Attachment? get _previewAttachment => switch (record.type) {
    RecordType.exam => record.examTimetable ?? record.attachments.firstOrNull,
    RecordType.classwork => record.attachments.firstOrNull,
    RecordType.worksheet =>
      record.attachments.firstOrNull ?? record.answerKey ?? record.hardWords,
  };

  Future<void> _openAttachment(BuildContext context) async {
    final attachment = _previewAttachment;
    if (attachment == null) return;

    if (attachment.isPdf) {
      try {
        await AttachmentActions.open(attachment);
      } catch (error) {
        if (!context.mounted) return;
        AppToast.failure(context, error, title: "Couldn't open file");
      }
      return;
    }

    final files = switch (record.type) {
      RecordType.exam => [
        if (record.examTimetable != null) record.examTimetable!,
        ...record.attachments,
      ],
      RecordType.classwork => [...record.attachments],
      RecordType.worksheet => [
        ...record.attachments,
        if (record.answerKey != null) record.answerKey!,
        if (record.hardWords != null) record.hardWords!,
      ],
    };
    final imagesOnly = files.where((f) => !f.isPdf).toList();
    if (imagesOnly.isEmpty) return;
    final newIndex = imagesOnly.indexOf(attachment);

    Navigator.of(context).pushNamed(
      Routes.viewer,
      arguments: ViewerArgs(
        attachments: imagesOnly,
        initialIndex: newIndex >= 0 ? newIndex : 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final state = AppScope.of(context);
    final subject = state.subjectByName(record.subject);
    final root = Navigator.of(context, rootNavigator: true);
    final chapter = record.chapterLabel;
    final showChapter = chapter.isNotEmpty;
    final showTitle =
        record.title.isNotEmpty &&
        record.title != chapter &&
        record.title != groupTitle;

    return AppCard(
      shadow: true,
      onTap: () => root.pushNamed(switch (record.type) {
        RecordType.worksheet => Routes.worksheetDetail,
        RecordType.classwork => Routes.classworkDetail,
        RecordType.exam => Routes.examDetail,
      }, arguments: record.id),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            attachmentThumb(
              context,
              _previewAttachment,
              radius: 14,
              width: 88,
              height: 92,
              showCaption: false,
              onTap: () => _openAttachment(context),
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
                  if (showChapter) ...[
                    const SizedBox(height: 5),
                    Text(
                      chapter,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: k.tx3,
                      ),
                    ),
                  ],
                  const SizedBox(height: 5),
                  Text(
                    switch (record.type) {
                      RecordType.worksheet => 'Worksheet',
                      RecordType.classwork => 'Classwork',
                      RecordType.exam => 'Exam',
                    },
                    style: TextStyle(
                      fontSize: showTitle ? 12 : 15.5,
                      fontWeight: showTitle ? FontWeight.w700 : FontWeight.w600,
                      height: showTitle ? null : 1.3,
                      color: showTitle ? k.tx6 : k.tx,
                    ),
                  ),
                  if (showTitle) ...[
                    const SizedBox(height: 5),
                    // Subject omitted: it is the overline directly above.
                    Text(
                      record.title,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ],
                  const Spacer(),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (record.isAiGenerated) const AiBadge(),
                      if (record.hasAnswerKey)
                        StatusPill(
                          label: 'Answer key',
                          background: k.surf2,
                          foreground: k.tx3,
                          leading: StrokeIcon(
                            AppIcons.attachment,
                            size: 12,
                            color: k.tx3,
                            strokeWidth: 2.2,
                          ),
                        )
                      else if (record.attachments.isNotEmpty)
                        StatusPill(
                          label: record.isWorksheet
                              ? AppFormat.attachmentCount(record.fileCount)
                              : AppFormat.photoCount(record.attachments.length),
                          background: k.surf2,
                          foreground: k.tx3,
                          leading: StrokeIcon(
                            record.isWorksheet
                                ? AppIcons.attachment
                                : AppIcons.camera,
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
      ),
    );
  }
}
