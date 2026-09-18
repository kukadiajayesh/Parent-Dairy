import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../core/errors/app_failure.dart';
import '../../core/format.dart';
import '../../core/services/ai/ai_attachments.dart';
import '../../core/services/ai/gemini_client.dart';
import '../../core/services/image_service.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_icons.dart';
import '../../core/widgets/attachment_image.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/fields.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/sheets.dart';
import '../../core/widgets/states.dart';
import '../../core/widgets/stroke_icon.dart';
import '../../core/widgets/toast.dart';
import '../../data/app_state.dart';
import '../../data/models_ai.dart';
import '../picker/attachment_source_row.dart';
import '../picker/picker_page.dart';
import 'ai_widgets.dart';

enum _Step { capture, extracting, review }

/// Capture → extract → review → save (prompt 02 §D). Nothing is written
/// before the parent confirms the review.
class ScanPaperPage extends StatefulWidget {
  const ScanPaperPage({super.key});

  @override
  State<ScanPaperPage> createState() => _ScanPaperPageState();
}

class _ScanPaperPageState extends State<ScanPaperPage> {
  _Step _step = _Step.capture;
  final List<PickedAttachment> _pages = [];
  bool _withAnswers = false;
  CancellationToken? _cancel;
  String _stage = '';
  AppFailure? _failure;

  ScannedPaper? _paper;
  String _subject = '';
  final _examType = TextEditingController();
  DateTime _date = DateUtils.dateOnly(DateTime.now());
  bool _saving = false;

  @override
  void dispose() {
    _cancel?.cancel();
    _examType.dispose();
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

  Future<void> _rotate(int index) async {
    try {
      final rotated = await ImageService.rotate(_pages[index]);
      if (!mounted) return;
      setState(() => _pages[index] = rotated);
    } catch (error) {
      if (mounted) AppToast.failure(context, error);
    }
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
      final paper = await state.ai.scanPaper(
        pages: files,
        withAnswers: _withAnswers,
        child: state.activeChild,
        cancel: cancel,
        onStage: (s) {
          if (mounted) setState(() => _stage = s);
        },
      );
      if (!mounted) return;
      final detected = paper.detected;
      final known = state.subjectNames;
      setState(() {
        _paper = paper;
        _subject = known.firstWhere(
          (s) => s.toLowerCase() == detected.subject.toLowerCase(),
          orElse: () => known.isEmpty ? detected.subject : state.suggestedSubject,
        );
        if (_examType.text.isEmpty) _examType.text = detected.examType;
        if (detected.date != null) _date = DateUtils.dateOnly(detected.date!);
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

  Future<void> _editQuestion(int s, int q) async {
    final paper = _paper!;
    final question = paper.sections[s].questions[q];
    final number = TextEditingController(text: question.number);
    final text = TextEditingController(text: question.text);
    final marks = TextEditingController(text: question.marks == null ? '' : _trim(question.marks!));
    final answer = TextEditingController(text: question.studentAnswer ?? '');
    final saved = await AppSheet.show<bool>(
      context,
      (sheetContext) => AppSheet(
        title: 'Question ${question.number}',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: AppTextField(label: 'Number', controller: number)),
                const SizedBox(width: 10),
                Expanded(
                  child: AppTextField(
                    label: 'Marks',
                    controller: marks,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AppTextField(label: 'Question', controller: text, maxLines: 4, minHeight: 80),
            if (paper.hasStudentAnswers) ...[
              const SizedBox(height: 12),
              AppTextField(label: "Child's answer (as written)", controller: answer, maxLines: 3, minHeight: 66),
            ],
            const SizedBox(height: 16),
            AppFilledButton(
              label: 'Save',
              height: 50,
              elevated: false,
              onPressed: () => Navigator.of(sheetContext).pop(true),
            ),
          ],
        ),
      ),
    );
    if (saved == true && mounted) {
      setState(() {
        _paper = paper.replaceQuestion(
          s,
          q,
          question.copyWith(
            number: number.text.trim(),
            text: text.text.trim(),
            marks: double.tryParse(marks.text.trim()),
            clearMarks: marks.text.trim().isEmpty,
            studentAnswer: answer.text.trim().isEmpty ? null : answer.text.trim(),
            // The parent looked at it: no longer flagged.
            confidence: 1,
            needsReview: false,
          ),
        );
      });
    }
    number.dispose();
    text.dispose();
    marks.dispose();
    answer.dispose();
  }

  Future<void> _pickSubject() async {
    final state = AppScope.read(context);
    final choice = await pickOption(
      context,
      title: 'Subject',
      options: state.subjectNames,
      current: _subject,
    );
    if (choice != null && mounted) setState(() => _subject = choice);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _save() async {
    final paper = _paper;
    if (paper == null) return;
    if (_examType.text.trim().isEmpty || _subject.isEmpty) {
      AppToast.show(
        context,
        title: 'Almost there',
        description: 'Give the exam a type and a subject before saving.',
        kind: ToastKind.warn,
        actionLabel: 'Dismiss',
      );
      return;
    }
    final state = AppScope.read(context);
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final saved = await state.saveScannedPaper(
        paper: paper.copyWith(
          detected: DetectedExam(
            subject: _subject,
            examType: _examType.text.trim(),
            date: _date,
            grade: paper.detected.grade,
            totalMarks: paper.detected.totalMarks,
            durationMinutes: paper.detected.durationMinutes,
            confidence: paper.detected.confidence,
          ),
        ),
        pages: _pages,
        subject: _subject,
        examType: _examType.text.trim(),
        date: _date,
      );
      if (!mounted) return;
      navigator.pushReplacementNamed(Routes.examDetail, arguments: saved.record.id);
      AppToast.showOn(
        messenger,
        context,
        title: 'Paper saved',
        description: '${paper.questions.length} questions filed under $_subject. '
            'Generate an answer key or grade it from here.',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.failure(context, error, title: "Couldn't save the paper");
    }
  }

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final k = context.t;
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
                  _Step.capture => 'Scan exam paper',
                  _Step.extracting => 'Reading paper',
                  _Step.review => 'Check the questions',
                },
                subtitle: _step == _Step.review ? 'Nothing is saved until you confirm' : null,
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
                _Step.extracting => _buildExtracting(k),
                _Step.review => _buildReview(k),
              },
            ),
            if (_step == _Step.capture)
              StickyFooter(
                child: AppFilledButton(
                  label: 'Read ${_pages.length} page${_pages.length == 1 ? '' : 's'}',
                  onPressed: _pages.isEmpty ? null : _extract,
                ),
              )
            else if (_step == _Step.review)
              StickyFooter(
                child: AppFilledButton(
                  label: _saving ? 'Saving…' : 'Confirm & save exam',
                  onPressed: _saving ? null : _save,
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
        'Photograph every page in order. Gemini reads the questions into a '
        'list you check before anything is saved.',
      ),
      const SizedBox(height: 18),
      SectionLabel('Pages · ${_pages.length}'),
      const SizedBox(height: 10),
      if (_pages.isEmpty)
        const EmptyListNotice(
          title: 'No pages yet',
          description: 'Add the paper from the camera, gallery or a PDF.',
        )
      else
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: _pages.length,
          onReorderItem: (from, to) => setState(() {
            _pages.insert(to, _pages.removeAt(from));
          }),
          itemBuilder: (context, index) {
            final page = _pages[index];
            return Padding(
              key: ValueKey(page.path),
              padding: const EdgeInsets.only(bottom: 8),
              child: AppCard(
                radius: 14,
                padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
                child: Row(
                  children: [
                    pickedAttachmentThumb(context, page, radius: 10, width: 48, height: 60, showCaption: false),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Page ${index + 1}',
                        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (!page.isPdf)
                      AppIconButton(
                        size: 36,
                        tooltip: 'Rotate',
                        onTap: () => _rotate(index),
                        child: StrokeIcon(AppIcons.rotate, size: 18, color: k.tx3),
                      ),
                    AppIconButton(
                      size: 36,
                      tooltip: 'Remove',
                      hoverBackground: k.errC,
                      onTap: () => setState(() => _pages.removeAt(index)),
                      child: StrokeIcon(AppIcons.close, size: 18, color: k.err),
                    ),
                    ReorderableDragStartListener(
                      index: index,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        child: StrokeIcon(AppIcons.dragHandle, size: 18, color: k.tx5),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      const SizedBox(height: 10),
      AttachmentSourceRow(emphasizeFirst: true, onPick: _addPages),
      const SizedBox(height: 18),
      SettingsGroup(
        children: [
          SettingsRow(
            label: "Pages include my child's answers",
            subtitle: 'Turn on for a completed paper you want graded',
            showChevron: false,
            trailing: AppSwitch(value: _withAnswers, onChanged: (v) => setState(() => _withAnswers = v)),
            onTap: () => setState(() => _withAnswers = !_withAnswers),
          ),
        ],
      ),
    ],
  );

  Widget _buildExtracting(AppTokens k) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
    children: [
      if (_failure == null)
        AiProgressView(
          title: 'Reading ${_pages.length} page${_pages.length == 1 ? '' : 's'}',
          stage: _stage,
          onCancel: () => _cancel?.cancel(),
        )
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

  Widget _buildReview(AppTokens k) {
    final paper = _paper!;
    // Uncertain rows first, so the parent's attention lands where it is
    // needed; stable within each group so the paper still reads in order.
    final rows = <(int, int, ScannedQuestion)>[
      for (var s = 0; s < paper.sections.length; s++)
        for (var q = 0; q < paper.sections[s].questions.length; q++) (s, q, paper.sections[s].questions[q]),
    ]..sort((a, b) {
        if (a.$3.wantsReview == b.$3.wantsReview) return 0;
        return a.$3.wantsReview ? -1 : 1;
      });
    final review = paper.reviewCount;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        AiNotice(
          review == 0
              ? 'Every question was read clearly. Check the details, then confirm.'
              : '$review question${review == 1 ? ' needs' : 's need'} a look — '
                    'Gemini was unsure. Tap to fix.',
          model: paper.model,
        ),
        if (paper.unreadableRegions.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final r in paper.unreadableRegions)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                'Page ${r.pageIndex + 1}: ${r.note}',
                style: TextStyle(fontSize: 12.5, color: k.warnInk),
              ),
            ),
        ],
        const SizedBox(height: 18),
        PickerField(label: 'Subject', value: _subject.isEmpty ? 'Choose' : _subject, isPlaceholder: _subject.isEmpty, onTap: _pickSubject),
        const SizedBox(height: 14),
        AppTextField(label: 'Exam type', controller: _examType, hintText: 'Unit Test 2'),
        const SizedBox(height: 14),
        PickerField(label: 'Date', value: AppDate.full(_date), trailing: PickerTrailing.calendar, onTap: _pickDate),
        const SizedBox(height: 18),
        SectionLabel('Questions · ${paper.questions.length} · ${_trim(paper.totalMarks)} marks'),
        const SizedBox(height: 10),
        if (paper.questions.isEmpty)
          const EmptyListNotice(
            title: 'No questions read',
            description: 'Try clearer photos, one page at a time.',
          ),
        for (final (s, q, question) in rows) ...[
          _ScannedRow(
            question: question,
            page: question.pageIndex < _pages.length ? _pages[question.pageIndex] : null,
            showAnswer: paper.hasStudentAnswers,
            onTap: () => _editQuestion(s, q),
            onDelete: () => setState(() => _paper = paper.replaceQuestion(s, q, null)),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _ScannedRow extends StatelessWidget {
  const _ScannedRow({
    required this.question,
    required this.page,
    required this.showAnswer,
    required this.onTap,
    required this.onDelete,
  });

  final ScannedQuestion question;
  final PickedAttachment? page;
  final bool showAnswer;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final q = question;
    return AppCard(
      radius: 14,
      borderColor: q.wantsReview ? k.warn : null,
      padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          pickedAttachmentThumb(context, page, radius: 8, width: 40, height: 50, showCaption: false),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(q.number, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                    const SizedBox(width: 8),
                    Text(
                      q.marks == null ? '— marks' : '${_ScanPaperPageState._trim(q.marks!)} marks',
                      style: TextStyle(fontSize: 12, color: k.tx4),
                    ),
                    const Spacer(),
                    ConfidencePill(q.confidence, forceReview: q.needsReview),
                  ],
                ),
                const SizedBox(height: 4),
                Text(q.text, style: const TextStyle(fontSize: 13.5, height: 1.4)),
                if (showAnswer) ...[
                  const SizedBox(height: 4),
                  Text(
                    q.studentAnswer == null ? 'Answer: (blank)' : 'Answer: ${q.studentAnswer}',
                    style: TextStyle(fontSize: 12.5, height: 1.4, color: k.secInk2),
                  ),
                ],
              ],
            ),
          ),
          AppIconButton(
            size: 32,
            tooltip: 'Remove',
            hoverBackground: k.errC,
            onTap: onDelete,
            child: StrokeIcon(AppIcons.close, size: 16, color: k.tx4),
          ),
        ],
      ),
    );
  }
}
