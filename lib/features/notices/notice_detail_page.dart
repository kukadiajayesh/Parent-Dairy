import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../core/format.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_icons.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/chips.dart';
import '../../core/widgets/fields.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/sheets.dart';
import '../../core/widgets/states.dart';
import '../../core/widgets/stroke_icon.dart';
import '../../core/widgets/toast.dart';
import '../../data/analytics/notice_reminders.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import 'notice_widgets.dart';

/// One captured notice (prompt 03 §E.2): the full text with the matched
/// phrases highlighted, the extraction — every field editable — the
/// reminders it would arm, and Confirm / Convert / Ignore.
///
/// Nothing here arms an alarm until the parent taps Confirm; a
/// low-confidence notice sits with its reminder list drawn but unarmed.
class NoticeDetailPage extends StatefulWidget {
  const NoticeDetailPage({super.key, required this.noticeId});

  final String noticeId;

  @override
  State<NoticeDetailPage> createState() => _NoticeDetailPageState();
}

class _NoticeDetailPageState extends State<NoticeDetailPage> {
  NoticeExtraction? _draft;
  String? _childId;
  bool _touched = false;
  bool _busy = false;

  /// Reminder moments the parent switched off before confirming.
  final Set<DateTime> _disabled = {};

  CapturedNotice? _notice(AppState state) => state.noticeById(widget.noticeId);

  NoticeExtraction _extractionOf(CapturedNotice n) =>
      _draft ??
      n.extraction ??
      NoticeExtraction(kind: NoticeKind.unknown, title: n.displayTitle, confidence: 0);

  void _edit(NoticeExtraction value) => setState(() {
    _draft = value;
    _touched = true;
    _disabled.clear();
  });

  List<DateTime> _times(AppState state, NoticeExtraction e) =>
      NoticeReminders.timesFor(e, now: DateTime.now(), offsets: state.noticeOffsets);

  Future<void> _pickDate(NoticeExtraction e) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: e.date ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (picked == null) return;
    _edit(e.withDate(picked));
  }

  Future<String?> _pickChild(AppState state) async {
    final names = [for (final c in state.children) c.name];
    final current = state.children.where((c) => c.id == _childId).firstOrNull?.name ?? '';
    final choice = await pickOption(context, title: 'Which child is this about?', options: names, current: current);
    if (choice == null) return null;
    return state.children.firstWhere((c) => c.name == choice).id;
  }

  Future<void> _confirm(AppState state, CapturedNotice n) async {
    final e = _extractionOf(n);
    var childId = _childId ?? n.childId;
    // §F: a multi-child family is asked once; the answer becomes the app's
    // default.
    if (childId == null && state.children.length > 1) {
      childId = await _pickChild(state);
      if (childId == null || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      final times = _times(state, e).where((t) => !_disabled.contains(t)).toList();
      await state.confirmNotice(n.id, extraction: e, childId: childId, reminderTimes: times);
      if (!mounted) return;
      setState(() {
        _draft = null;
        _touched = false;
        _disabled.clear();
        _busy = false;
      });
      AppToast.show(
        context,
        title: times.isEmpty ? 'Confirmed' : 'Reminder${times.length == 1 ? '' : 's'} set',
        description: times.isEmpty
            ? 'Saved under Upcoming without an alarm.'
            : 'First one ${AppDate.dueLabel(times.first)} at ${_clock(times.first)}.',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      AppToast.failure(context, error, title: "Couldn't confirm");
    }
  }

  Future<void> _ignore(AppState state, CapturedNotice n) async {
    setState(() => _busy = true);
    try {
      await state.ignoreNotice(n.id);
      if (!mounted) return;
      Navigator.of(context).maybePop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      AppToast.failure(context, error, title: "Couldn't ignore that");
    }
  }

  Future<void> _undo(AppState state, CapturedNotice n) async {
    try {
      await state.undoNoticeAutoArm(n.id);
      if (!mounted) return;
      AppToast.show(context, title: 'Reminders removed', description: 'Back in your inbox to review.');
    } catch (error) {
      if (!mounted) return;
      AppToast.failure(context, error, title: "Couldn't undo");
    }
  }

  Future<void> _convert(AppState state, CapturedNotice n) async {
    final e = _extractionOf(n);
    if (_touched) await state.updateNotice(n.id, extraction: e, childId: _childId);
    if (!mounted) return;
    final root = Navigator.of(context, rootNavigator: true);
    if (e.kind == NoticeKind.exam) {
      // An exam record needs its timetable image, so the form opens
      // prefilled and links back once saved.
      final saved = await root.pushNamed<Object?>(Routes.addExam, arguments: state.draftRecordFor(n.copyWith(extraction: e)));
      if (saved is DiaryRecord) await state.linkNoticeToRecord(n.id, saved);
      return;
    }
    setState(() => _busy = true);
    try {
      final record = await state.convertNoticeToWorksheet(n.id);
      if (!mounted) return;
      setState(() => _busy = false);
      AppToast.show(
        context,
        title: 'Worksheet saved',
        description: record.title,
        actionLabel: 'View',
        onAction: () => root.pushNamed(Routes.worksheetDetail, arguments: record.id),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      AppToast.failure(context, error, title: "Couldn't save the record");
    }
  }

  Future<void> _delete(AppState state, CapturedNotice n) async {
    final ok = await confirmDelete(
      context,
      title: 'Delete this notice?',
      description: 'The captured text is removed and any reminder set from it is cancelled.',
    );
    if (!ok || !mounted) return;
    try {
      await state.deleteNotice(n.id);
      if (!mounted) return;
      Navigator.of(context).maybePop();
    } catch (error) {
      if (!mounted) return;
      AppToast.failure(context, error, title: "Couldn't delete");
    }
  }

  static String _clock(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.hour < 12 ? 'am' : 'pm'}';
  }

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final state = AppScope.of(context);
    final n = _notice(state);

    if (n == null) {
      return Scaffold(
        backgroundColor: k.bg,
        body: SafeArea(
          child: Column(
            children: [
              const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: ScreenHeader(title: 'Notice')),
              Padding(
                padding: const EdgeInsets.all(20),
                child: state.isLoadingNotices
                    ? const Skeletons(child: SkeletonBox(height: 160, radius: 20))
                    : ErrorStateView(
                        title: 'Notice not found',
                        description: 'It may have been deleted, or it has not synced to this phone yet.',
                        actionLabel: 'Retry',
                        onAction: state.retryNotices,
                        onCancel: () => Navigator.of(context).maybePop(),
                      ),
              ),
            ],
          ),
        ),
      );
    }

    final e = _extractionOf(n);
    final times = _times(state, e);
    final childId = _childId ?? n.childId;
    final child = state.children.where((c) => c.id == childId).firstOrNull;
    final canConvert = e.kind == NoticeKind.exam || e.kind == NoticeKind.assignment;
    final now = DateTime.now();

    return Scaffold(
      backgroundColor: k.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ScreenHeader(
                title: 'Notice',
                subtitle: '${n.appLabel} · ${AppDate.full(n.postedAt)}',
                actions: [
                  AppIconButton(
                    tooltip: 'Delete',
                    onTap: _busy ? null : () => _delete(state, n),
                    child: StrokeIcon(AppIcons.trash, size: 20, color: k.err),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  if (n.canUndoAutoArm(now)) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(color: k.secC, borderRadius: BorderRadius.circular(14)),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Reminders were added automatically. Not right?',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: k.secInk),
                            ),
                          ),
                          SectionAction(label: 'Undo', onTap: () => _undo(state, n)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (n.status == NoticeStatus.converted && n.linkedRecordId != null) ...[
                    AppCard(
                      radius: 14,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      onTap: () => Navigator.of(context, rootNavigator: true).pushNamed(
                        e.kind == NoticeKind.exam ? Routes.examDetail : Routes.worksheetDetail,
                        arguments: n.linkedRecordId,
                      ),
                      child: Row(
                        children: [
                          StrokeIcon(AppIcons.document, size: 18, color: k.priInk),
                          const SizedBox(width: 10),
                          const Expanded(
                            child: Text('Saved as a record — open it', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                          ),
                          StrokeIcon(AppIcons.forward, size: 16, color: k.tx5),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          n.displayTitle,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.3, height: 1.25),
                        ),
                      ),
                      const SizedBox(width: 10),
                      StatusPill(
                        label: n.status.label,
                        background: n.status == NoticeStatus.confirmed ? k.secC : k.surf2,
                        foreground: n.status == NoticeStatus.confirmed ? k.secInk : k.tx3,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const SectionLabel('Message'),
                  const SizedBox(height: 8),
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (n.title.trim().isNotEmpty) ...[
                          HighlightedText(n.title, phrases: e.matchedPhrases),
                          const SizedBox(height: 6),
                        ],
                        HighlightedText(n.body, phrases: e.matchedPhrases),
                        if (n.truncated) ...[
                          const SizedBox(height: 8),
                          Text('Message was longer; the first 4000 characters are kept.', style: TextStyle(fontSize: 12, color: k.tx4)),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  SectionLabel(
                    'Detected',
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ConfidenceDot(e.confidence),
                        const SizedBox(width: 6),
                        Text(
                          '${(e.confidence * 100).round()}% · ${e.fromModel ? 'Gemini' : 'rules'}',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: k.tx4),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  const FieldLabel('Kind'),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final kind in NoticeKind.values.where((x) => x != NoticeKind.unknown))
                        AppChip(
                          label: kind.label,
                          selected: e.kind == kind,
                          selectedBackground: noticeKindColors(context, kind).bg,
                          selectedBorder: noticeKindColors(context, kind).dot,
                          selectedForeground: noticeKindColors(context, kind).ink,
                          onTap: () => _edit(e.copyWith(kind: kind)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const FieldLabel('Subject'),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      AppChip(label: 'None', selected: e.subject == null, onTap: () => _edit(e.copyWith(clearSubject: true))),
                      for (final s in state.subjects)
                        SubjectChip(
                          name: s.name,
                          hue: s.hue,
                          selected: e.subject == s.name,
                          onTap: () => _edit(e.copyWith(subject: s.name)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  PickerField(
                    label: e.kind.isDue ? 'Due date' : 'Date',
                    value: e.date == null
                        ? 'Pick a date'
                        : '${AppDate.dueLabel(e.date!)}${e.endAt == null ? '' : ' → ${AppDate.dueLabel(e.endAt!)}'}'
                            '${e.allDay ? '' : ' · ${_clock(e.date!)}'}',
                    isPlaceholder: e.date == null,
                    trailing: PickerTrailing.calendar,
                    onTap: () => _pickDate(e),
                  ),
                  if (e.alternateDates.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text('Also mentioned:', style: TextStyle(fontSize: 12, color: k.tx4)),
                        for (final d in e.alternateDates)
                          AppChip(
                            label: AppDate.short(d),
                            selected: false,
                            fontSize: 12,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            onTap: () => _edit(e.withDate(d)),
                          ),
                      ],
                    ),
                  ],
                  if (state.children.length > 1) ...[
                    const SizedBox(height: 14),
                    PickerField(
                      label: 'Child',
                      value: child?.name ?? 'Choose a child',
                      isPlaceholder: child == null,
                      onTap: () async {
                        final id = await _pickChild(state);
                        if (id != null) setState(() => _childId = id);
                      },
                    ),
                  ],
                  const SizedBox(height: 18),
                  const SectionLabel('Reminders'),
                  const SizedBox(height: 8),
                  if (e.date == null)
                    const EmptyListNotice(title: 'No date yet', description: 'Pick a date above to add reminders.')
                  else if (times.isEmpty)
                    const EmptyListNotice(title: 'Nothing to remind', description: 'Every reminder for this date is already in the past.')
                  else
                    SettingsGroup(
                      children: [
                        for (final t in times)
                          SettingsRow(
                            label: '${AppDate.dueLabel(t)} · ${_clock(t)}',
                            subtitle: n.isArmed && !_touched
                                ? 'Scheduled'
                                : (_disabled.contains(t) ? 'Off' : 'Will be set on confirm'),
                            showChevron: false,
                            trailing: AppSwitch(
                              value: !_disabled.contains(t),
                              width: 48,
                              height: 28,
                              onChanged: (v) => setState(() {
                                _touched = true;
                                v ? _disabled.remove(t) : _disabled.add(t);
                              }),
                            ),
                          ),
                      ],
                    ),
                  const SizedBox(height: 6),
                  Text(
                    'Offsets per kind can be changed in Settings → Notification capture.',
                    style: TextStyle(fontSize: 12, color: k.tx4),
                  ),
                ],
              ),
            ),
            StickyFooter(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (n.status == NoticeStatus.ignored)
                    AppFilledButton(
                      label: 'Restore to inbox',
                      onPressed: _busy ? null : () => state.restoreNotice(n.id),
                    )
                  else
                    AppFilledButton(
                      label: _busy
                          ? 'Saving…'
                          : (n.needsReview ? 'Confirm' : (_touched ? 'Save changes' : 'Confirmed')),
                      onPressed: _busy || (!n.needsReview && !_touched) ? null : () => _confirm(state, n),
                    ),
                  if (n.status != NoticeStatus.ignored) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        if (canConvert && n.status != NoticeStatus.converted) ...[
                          Expanded(
                            child: AppOutlinedButton(
                              label: e.kind == NoticeKind.exam ? 'Convert to exam' : 'Convert to worksheet',
                              height: 48,
                              onPressed: _busy ? null : () => _convert(state, n),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: AppTonalButton(
                            label: 'Ignore',
                            height: 48,
                            background: k.surf2,
                            hoverBackground: k.hov,
                            foreground: k.tx2,
                            onPressed: _busy ? null : () => _ignore(state, n),
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
