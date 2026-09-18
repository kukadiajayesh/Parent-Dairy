import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../core/errors/app_failure.dart';
import '../../core/format.dart';
import '../../core/services/ai/ai_attachments.dart';
import '../../core/services/ai/gemini_client.dart';
import '../../core/services/ai/subject_matcher.dart';
import '../../core/services/image_service.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_icons.dart';
import '../../core/widgets/attachment_image.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/chips.dart';
import '../../core/widgets/fields.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/states.dart';
import '../../core/widgets/stroke_icon.dart';
import '../../core/widgets/toast.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../../data/models_ai.dart';
import '../performance/insight_widgets.dart';
import '../picker/attachment_source_row.dart';
import '../picker/picker_page.dart';
import 'ai_widgets.dart';

enum _Step { capture, extracting, review }

/// Photograph a report card → Gemini reads it → the parent reviews every
/// row (subject mapping, marks, grade) → saved as an [ExamResult] that
/// needs review (prompt 02 §E).
class ScanResultPage extends StatefulWidget {
  const ScanResultPage({super.key, this.initialFiles});

  /// From the share sheet: a card that arrived as an image.
  final List<PickedAttachment>? initialFiles;

  @override
  State<ScanResultPage> createState() => _ScanResultPageState();
}

class _ScanResultPageState extends State<ScanResultPage> {
  _Step _step = _Step.capture;
  late final List<PickedAttachment> _pages = [...?widget.initialFiles];
  CancellationToken? _cancel;
  String _stage = '';
  AppFailure? _failure;

  ReportCardExtraction? _card;
  final _label = TextEditingController();
  final _attendance = TextEditingController();
  final _remarks = TextEditingController();
  DateTime _date = DateUtils.dateOnly(DateTime.now());
  final List<_RowDraft> _rows = [];
  bool _saving = false;

  @override
  void dispose() {
    _cancel?.cancel();
    _label.dispose();
    _attendance.dispose();
    _remarks.dispose();
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _addPages(AttachmentSource source) async {
    final picked = await Navigator.of(context).push<List<PickedAttachment>>(
      MaterialPageRoute(
        builder: (_) => PickerPage(initialSource: source),
        settings: const RouteSettings(name: Routes.picker),
      ),
    );
    if (picked == null || picked.isEmpty || !mounted) return;
    setState(() => _pages.addAll(picked));
  }

  Future<void> _extract() async {
    if (!await ensureAiReady(context)) return;
    if (!mounted) return;
    final state = AppScope.read(context);
    final cancel = CancellationToken();
    setState(() {
      _cancel = cancel;
      _failure = null;
      _stage = 'Checking pages…';
      _step = _Step.extracting;
    });
    try {
      final files = AiAttachments.fromPicked(_pages);
      await AiAttachments.summarise(files);
      final card = await state.ai.scanReportCard(
        pages: files,
        child: state.activeChild,
        cancel: cancel,
        onStage: (s) {
          if (mounted) setState(() => _stage = s);
        },
      );
      if (!mounted) return;
      final known = state.subjectNames;
      setState(() {
        _card = card;
        _label.text = card.examLabel;
        if (card.date != null) _date = DateUtils.dateOnly(card.date!);
        _attendance.text = card.attendancePercent == null ? '' : _trim(card.attendancePercent!);
        _remarks.text = card.teacherRemarks;
        for (final r in _rows) {
          r.dispose();
        }
        _rows
          ..clear()
          ..addAll([
            for (final s in card.scores)
              _RowDraft(s, suggestion: SubjectMatcher.match(s.subject, known), onChanged: () => setState(() {})),
          ]);
        _step = _Step.review;
      });
    } catch (error) {
      final failure = AppFailure.from(error);
      if (!mounted) return;
      if (failure.isCancellation) {
        setState(() => _step = _Step.capture);
        return;
      }
      setState(() => _failure = failure);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  ExamResult _draft(AppState state) => ExamResult(
    id: '',
    childId: '',
    academicYearId: '',
    examLabel: _label.text.trim(),
    date: _date,
    scores: [for (final r in _rows) r.toScore()],
    attendancePercent: double.tryParse(_attendance.text.trim()),
    teacherRemarks: _remarks.text.trim(),
    source: ResultSource.scanned,
    extractionConfidence: _card?.confidence ?? 0,
    needsReview: true,
    gradeScaleId: state.gradeScale.id,
  );

  Future<void> _save() async {
    final state = AppScope.read(context);
    final invalid = _rows.where((r) => !r.isValid).length;
    if (invalid > 0) {
      AppToast.show(
        context,
        title: 'Check the marked rows',
        description: '$invalid row${invalid == 1 ? ' has' : 's have'} marks that do not add up.',
        kind: ToastKind.warn,
        actionLabel: 'Dismiss',
      );
      return;
    }
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final saved = await state.saveResult(_draft(state));
      if (!mounted) return;
      navigator.pushReplacementNamed(Routes.resultDetail, arguments: saved.id);
      AppToast.showOn(
        messenger,
        context,
        title: 'Report card saved for review',
        description: '${saved.examLabel} · ${percentLabel(saved.overallPercent)} overall. '
            'Confirm it to count it in the Performance tab.',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.failure(context, error, title: "Couldn't save the report card");
    }
  }

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final state = AppScope.of(context);
    final overall = _step == _Step.review ? _draft(state).overallPercent : null;

    return Scaffold(
      backgroundColor: k.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ScreenHeader(
                title: switch (_step) {
                  _Step.capture => 'Scan report card',
                  _Step.extracting => 'Reading the card',
                  _Step.review => 'Check the marks',
                },
                subtitle: _step == _Step.review ? 'Saved as "needs review" until you confirm' : null,
                leadingIsClose: true,
                onBack: () {
                  _cancel?.cancel();
                  Navigator.of(context).pop();
                },
              ),
            ),
            Expanded(
              child: switch (_step) {
                _Step.capture => _buildCapture(k),
                _Step.extracting => _buildExtracting(),
                _Step.review => _buildReview(k, state),
              },
            ),
            if (_step == _Step.capture)
              StickyFooter(
                child: AppFilledButton(
                  label: 'Read report card',
                  onPressed: _pages.isEmpty ? null : _extract,
                ),
              )
            else if (_step == _Step.review)
              StickyFooter(
                child: Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('OVERALL', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: .6, color: k.tx4)),
                        Text(
                          percentLabel(overall),
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.4, height: 1.1, color: overall == null ? k.tx4 : k.priInk),
                        ),
                      ],
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: AppFilledButton(
                        label: _saving ? 'Saving…' : 'Save for review',
                        onPressed: _saving || _label.text.trim().isEmpty || _rows.isEmpty ? null : _save,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCapture(AppTokens k) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
    children: [
      const AiNotice(
        'Photograph the report card. Gemini reads each subject row; you '
        'check every mark before it is saved.',
      ),
      const SizedBox(height: 18),
      SectionLabel('Pages · ${_pages.length}'),
      const SizedBox(height: 10),
      if (_pages.isEmpty)
        const EmptyListNotice(title: 'No pages yet', description: 'Add the card from the camera, gallery or a PDF.')
      else
        SizedBox(
          height: 110,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _pages.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) => Stack(
              children: [
                pickedAttachmentThumb(context, _pages[index], radius: 12, width: 84, height: 110, showCaption: false),
                Positioned(
                  top: 4,
                  right: 4,
                  child: AppIconButton(
                    size: 28,
                    borderRadius: 8,
                    background: k.surf,
                    tooltip: 'Remove',
                    onTap: () => setState(() => _pages.removeAt(index)),
                    child: StrokeIcon(AppIcons.close, size: 14, color: k.err),
                  ),
                ),
              ],
            ),
          ),
        ),
      const SizedBox(height: 12),
      AttachmentSourceRow(emphasizeFirst: true, onPick: _addPages),
    ],
  );

  Widget _buildExtracting() => ListView(
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
    children: [
      if (_failure == null)
        AiProgressView(title: 'Reading the report card', stage: _stage, onCancel: () => _cancel?.cancel())
      else
        AiFailureView(
          failure: _failure!,
          onRetry: _extract,
          onCancel: () => setState(() {
            _failure = null;
            _step = _Step.capture;
          }),
        ),
    ],
  );

  Widget _buildReview(AppTokens k, AppState state) {
    final card = _card!;
    final review = _rows.where((r) => r.wantsReview).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        AiNotice(
          review == 0
              ? 'Every row was read clearly. Check the numbers, then save.'
              : '$review row${review == 1 ? ' needs' : 's need'} a look — marked below.',
          model: card.model,
        ),
        const SizedBox(height: 18),
        AppTextField(label: 'Exam name', controller: _label, hintText: 'Term 1', onChanged: (_) => setState(() {})),
        const SizedBox(height: 14),
        PickerField(label: 'Date', value: AppDate.full(_date), trailing: PickerTrailing.calendar, onTap: _pickDate),
        const SizedBox(height: 18),
        Row(
          children: [
            const Expanded(child: Text('Subjects', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
            Text('Grades use ${state.gradeScale.label}', style: TextStyle(fontSize: 12, color: k.tx4)),
          ],
        ),
        const SizedBox(height: 10),
        for (var i = 0; i < _rows.length; i++) ...[
          _RowCard(
            draft: _rows[i],
            known: state.subjectNames,
            onRemove: () => setState(() => _rows.removeAt(i).dispose()),
          ),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 8),
        AppTextField(
          label: 'Attendance % (optional)',
          controller: _attendance,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        const SizedBox(height: 14),
        AppTextField(label: "Teacher's remarks", controller: _remarks, maxLines: 3, minHeight: 66),
      ],
    );
  }
}

/// One extracted row under review. Keeps the model's original subject name
/// beside the app's suggestion, and only the parent flips between them.
class _RowDraft {
  _RowDraft(this.extracted, {required this.suggestion, required VoidCallback onChanged})
    : marks = TextEditingController(text: extracted.marks == null ? '' : _ScanResultPageState._trim(extracted.marks!)),
      max = TextEditingController(text: extracted.maxMarks == null ? '' : _ScanResultPageState._trim(extracted.maxMarks!)),
      grade = TextEditingController(text: extracted.grade ?? ''),
      remarks = TextEditingController(text: extracted.remarks),
      absent = extracted.absent,
      useSuggestion = suggestion != null {
    for (final c in [marks, max, grade, remarks]) {
      c.addListener(onChanged);
    }
  }

  final ExtractedScore extracted;
  final String? suggestion;
  final TextEditingController marks, max, grade, remarks;
  bool absent;

  /// True → the mapped subject name is saved; false → the card's own text.
  bool useSuggestion;

  String get subject => useSuggestion && suggestion != null ? suggestion! : extracted.subject;
  bool get isMapped => suggestion != null && suggestion != extracted.subject;

  bool get isValid {
    final m = double.tryParse(marks.text.trim());
    final x = double.tryParse(max.text.trim());
    if (m == null && x == null) return true;
    if (m == null || x == null) return false;
    return m >= 0 && x > 0 && m <= x;
  }

  bool get wantsReview => !isValid || extracted.wantsReview;

  SubjectScore toScore() => SubjectScore(
    subject: subject,
    marks: double.tryParse(marks.text.trim()),
    maxMarks: double.tryParse(max.text.trim()),
    grade: grade.text.trim().isEmpty ? null : grade.text.trim(),
    classRank: extracted.classRank,
    remarks: remarks.text.trim(),
    absent: absent,
  );

  void dispose() {
    marks.dispose();
    max.dispose();
    grade.dispose();
    remarks.dispose();
  }
}

class _RowCard extends StatefulWidget {
  const _RowCard({required this.draft, required this.known, required this.onRemove});

  final _RowDraft draft;
  final List<String> known;
  final VoidCallback onRemove;

  @override
  State<_RowCard> createState() => _RowCardState();
}

class _RowCardState extends State<_RowCard> {
  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final d = widget.draft;
    final state = AppScope.of(context);
    final subject = state.subjectByName(d.subject);
    final known = widget.known.contains(d.subject);
    return AppCard(
      radius: 16,
      borderColor: d.wantsReview ? k.warn : null,
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Dot(color: subject.hue.dot(k), size: 9),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  d.subject,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              if (!known)
                StatusPill(label: 'New', background: k.surf2, foreground: k.tx3)
              else if (!d.isValid)
                StatusPill(label: 'Check marks', background: k.warnC, foreground: k.warnInk, dotColor: k.warn)
              else
                ConfidencePill(d.extracted.confidence),
              const SizedBox(width: 4),
              AppIconButton(
                size: 32,
                borderRadius: 10,
                hoverBackground: k.errC,
                tooltip: 'Remove row',
                onTap: widget.onRemove,
                child: StrokeIcon(AppIcons.close, size: 16, color: k.tx4),
              ),
            ],
          ),
          if (d.isMapped) ...[
            const SizedBox(height: 8),
            // "Maths → Mathematics?" — the app's suggestion, confirmable.
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Card says "${d.extracted.subject}"',
                  style: TextStyle(fontSize: 12.5, color: k.tx4),
                ),
                AppChip(
                  label: '→ ${d.suggestion}',
                  selected: d.useSuggestion,
                  fontSize: 12,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  onTap: () => setState(() => d.useSuggestion = true),
                ),
                AppChip(
                  label: 'Keep as written',
                  selected: !d.useSuggestion,
                  fontSize: 12,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  onTap: () => setState(() => d.useSuggestion = false),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  label: 'Marks',
                  controller: d.marks,
                  minHeight: 48,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppTextField(
                  label: 'Out of',
                  controller: d.max,
                  minHeight: 48,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppTextField(
                  label: 'Grade',
                  controller: d.grade,
                  minHeight: 48,
                  textCapitalization: TextCapitalization.characters,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: AppTextField(label: 'Remarks', controller: d.remarks, minHeight: 48)),
              const SizedBox(width: 12),
              Column(
                children: [
                  const FieldLabel('Absent'),
                  const SizedBox(height: 8),
                  AppSwitch(
                    value: d.absent,
                    width: 48,
                    height: 28,
                    activeColor: k.warn,
                    onChanged: (v) => setState(() => d.absent = v),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
