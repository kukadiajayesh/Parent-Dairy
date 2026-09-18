import 'package:flutter/material.dart';

import '../../core/errors/app_failure.dart';
import '../../core/format.dart';
import '../../core/services/ai/ai_attachments.dart';
import '../../core/services/ai/gemini_client.dart';
import '../../core/services/ai/subject_matcher.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_icons.dart';
import '../../core/widgets/attachment_image.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/chips.dart';
import '../../core/widgets/fields.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/sheets.dart';
import '../../core/widgets/states.dart';
import '../../core/widgets/stroke_icon.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../data/models_ai.dart';
import 'ai_widgets.dart';

class ScanTimetableArgs {
  const ScanTimetableArgs({required this.timetable, this.examTypeHint = ''});

  /// The staged timetable image from the Add Exam form.
  final Attachment timetable;
  final String examTypeHint;
}

/// One reviewed row, mapped to a subject the diary knows.
class TimetableRow {
  const TimetableRow({required this.subject, required this.date, this.printed = '', this.notes = ''});

  final String subject;
  final DateTime date;
  final String printed;
  final String notes;
}

/// What the parent confirmed: the exam label and the rows to create.
class TimetableReview {
  const TimetableReview({required this.examLabel, required this.rows, required this.model});

  final String examLabel;
  final List<TimetableRow> rows;
  final String model;

  /// The whole schedule as text, for every record's notes.
  String get scheduleNotes => [
    for (final r in rows)
      '${AppDate.dueLabel(r.date)}${_clock(r.date)} · ${r.subject}${r.notes.isEmpty ? '' : ' (${r.notes})'}',
  ].join('\n');

  static String _clock(DateTime t) {
    if (t.hour == 0 && t.minute == 0) return '';
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return ' $h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'am' : 'pm'}';
  }
}

enum _Step { extracting, review }

/// Gemini reads a photographed date sheet → the parent maps each row to a
/// subject and checks its date → the Add Exam form gets the rows back.
/// Nothing is saved from here; the form saves.
class ScanTimetablePage extends StatefulWidget {
  const ScanTimetablePage({super.key, required this.args});

  final ScanTimetableArgs args;

  @override
  State<ScanTimetablePage> createState() => _ScanTimetablePageState();
}

class _ScanTimetablePageState extends State<ScanTimetablePage> {
  _Step _step = _Step.extracting;
  CancellationToken? _cancel;
  String _stage = '';
  AppFailure? _failure;
  TimetableExtraction? _read;
  final _label = TextEditingController();
  final List<_RowDraft> _rows = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _extract());
  }

  @override
  void dispose() {
    _cancel?.cancel();
    _label.dispose();
    super.dispose();
  }

  Future<void> _extract() async {
    if (!mounted) return;
    if (!await ensureAiReady(context)) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    if (!mounted) return;
    final state = AppScope.read(context);
    final cancel = CancellationToken();
    setState(() {
      _cancel = cancel;
      _failure = null;
      _stage = 'Preparing the image…';
      _step = _Step.extracting;
    });
    try {
      final files = await AiAttachments.fromAttachments([widget.args.timetable]);
      final read = await state.ai.scanTimetable(
        pages: files,
        child: state.activeChild,
        subjects: state.subjectNames,
        cancel: cancel,
        onStage: (s) {
          if (mounted) setState(() => _stage = s);
        },
      );
      if (!mounted) return;
      final known = state.subjectNames;
      setState(() {
        _read = read;
        _label.text = read.examLabel.isNotEmpty ? read.examLabel : widget.args.examTypeHint;
        _rows
          ..clear()
          ..addAll([
            for (final e in read.sorted)
              _RowDraft(e, subject: SubjectMatcher.match(e.subject, known)),
          ]);
        _step = _Step.review;
      });
    } catch (error) {
      final failure = AppFailure.from(error);
      if (!mounted) return;
      if (failure.isCancellation) {
        Navigator.of(context).pop();
        return;
      }
      setState(() => _failure = failure);
    }
  }

  Future<void> _pickSubject(_RowDraft row) async {
    final state = AppScope.read(context);
    final choice = await pickOption(
      context,
      title: 'Subject for "${row.entry.subject}"',
      options: state.subjectNames,
      current: row.subject ?? '',
    );
    if (choice == null || !mounted) return;
    setState(() => row.subject = choice);
  }

  Future<void> _pickDate(_RowDraft row) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: row.date ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (picked == null || !mounted) return;
    setState(() {
      final t = row.entry.startTime;
      row.date = t == null ? picked : DateTime(picked.year, picked.month, picked.day, t.$1, t.$2);
    });
  }

  void _done() {
    final rows = [
      for (final r in _rows)
        if (r.include && r.subject != null && r.date != null)
          TimetableRow(subject: r.subject!, date: r.date!, printed: r.entry.subject, notes: r.entry.notes),
    ]..sort((a, b) => a.date.compareTo(b.date));
    Navigator.of(context).pop(
      TimetableReview(examLabel: _label.text.trim(), rows: rows, model: _read?.model ?? ''),
    );
  }

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final ready = _rows.where((r) => r.include && r.subject != null && r.date != null).length;
    final incomplete = _rows.where((r) => r.include && (r.subject == null || r.date == null)).length;

    return Scaffold(
      backgroundColor: k.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ScreenHeader(
                title: _step == _Step.extracting ? 'Reading the timetable' : 'Check the timetable',
                subtitle: _step == _Step.review ? 'One exam is created per row you keep' : null,
                leadingIsClose: true,
                onBack: () {
                  _cancel?.cancel();
                  Navigator.of(context).pop();
                },
              ),
            ),
            Expanded(
              child: _step == _Step.extracting
                  ? ListView(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                      children: [
                        if (_failure == null)
                          AiProgressView(title: 'Reading the timetable', stage: _stage, onCancel: () => _cancel?.cancel())
                        else
                          AiFailureView(
                            failure: _failure!,
                            onRetry: _extract,
                            onCancel: () => Navigator.of(context).pop(),
                          ),
                      ],
                    )
                  : _buildReview(k),
            ),
            if (_step == _Step.review)
              StickyFooter(
                child: AppFilledButton(
                  label: ready == 0
                      ? 'Nothing to set'
                      : 'Set $ready exam${ready == 1 ? '' : 's'}',
                  onPressed: ready == 0 || incomplete > 0 || _label.text.trim().isEmpty ? null : _done,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildReview(AppTokens k) {
    final read = _read!;
    final incomplete = _rows.where((r) => r.include && (r.subject == null || r.date == null)).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        AiNotice(
          'Read by Gemini. Map each row to a subject and check its date '
          'before setting — a wrong exam date is worse than none.',
          model: read.model,
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            attachmentThumb(context, widget.args.timetable, radius: 12, width: 52, height: 52, showCaption: false),
            const SizedBox(width: 12),
            Expanded(
              child: AppTextField(
                label: 'Exam',
                controller: _label,
                hintText: 'Unit Test 2, Half Yearly…',
                onChanged: (_) => setState(() {}),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        SectionLabel(
          'Rows · ${_rows.length}',
          trailing: incomplete == 0
              ? null
              : Text(
                  '$incomplete to fix',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: k.warnInk),
                ),
        ),
        const SizedBox(height: 10),
        if (_rows.isEmpty)
          const EmptyListNotice(
            title: 'No rows read',
            description: 'Try a sharper photo with the whole table in frame.',
          ),
        for (final row in _rows) ...[
          _RowCard(row: row, onSubject: () => _pickSubject(row), onDate: () => _pickDate(row), onToggle: () => setState(() => row.include = !row.include)),
          const SizedBox(height: 8),
        ],
        if (read.droppedRows > 0 || read.unreadable.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            [
              if (read.droppedRows > 0) '${read.droppedRows} row${read.droppedRows == 1 ? '' : 's'} had no subject and were left out.',
              if (read.unreadable.isNotEmpty) 'Could not read: ${read.unreadable}',
            ].join(' '),
            style: TextStyle(fontSize: 12, height: 1.4, color: k.tx4),
          ),
        ],
      ],
    );
  }
}

class _RowDraft {
  _RowDraft(this.entry, {this.subject}) : date = entry.startsAt;

  final TimetableEntry entry;
  String? subject;
  DateTime? date;
  bool include = true;
}

class _RowCard extends StatelessWidget {
  const _RowCard({required this.row, required this.onSubject, required this.onDate, required this.onToggle});

  final _RowDraft row;
  final VoidCallback onSubject;
  final VoidCallback onDate;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final state = AppScope.of(context);
    final needs = row.subject == null || row.date == null;
    final date = row.date;
    return AppCard(
      radius: 16,
      borderColor: row.include && needs ? k.warn : null,
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Opacity(
        opacity: row.include ? 1 : .5,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          row.entry.subject,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: k.tx4),
                        ),
                      ),
                      ConfidencePill(row.entry.confidence, forceReview: needs),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (row.subject == null)
                        AppChip(label: 'Pick subject', selected: false, onTap: row.include ? onSubject : null)
                      else
                        SubjectChip(
                          name: row.subject!,
                          hue: state.subjectByName(row.subject!).hue,
                          selected: true,
                          onTap: row.include ? onSubject : null,
                        ),
                      AppChip(
                        label: date == null
                            ? 'Pick date'
                            : '${AppDate.dueLabel(date)}${row.entry.startTime == null ? '' : ' · ${_clock(date)}'}',
                        selected: date != null,
                        selectedBackground: k.surf2,
                        selectedBorder: k.bd4,
                        selectedForeground: k.tx,
                        onTap: row.include ? onDate : null,
                      ),
                    ],
                  ),
                  if (row.entry.notes.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(row.entry.notes, style: TextStyle(fontSize: 12, color: k.tx4)),
                  ],
                ],
              ),
            ),
            AppIconButton(
              size: 34,
              borderRadius: 10,
              tooltip: row.include ? 'Leave out' : 'Include',
              onTap: onToggle,
              child: StrokeIcon(row.include ? AppIcons.close : AppIcons.plus, size: 17, color: row.include ? k.tx4 : k.pri),
            ),
          ],
        ),
      ),
    );
  }

  static String _clock(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'am' : 'pm'}';
  }
}
