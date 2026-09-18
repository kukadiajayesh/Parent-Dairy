import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../core/errors/app_failure.dart';
import '../../core/services/ai/gemini_client.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/chips.dart';
import '../../core/widgets/fields.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/sheets.dart';
import '../../core/widgets/states.dart';
import '../../core/widgets/toast.dart';
import '../../data/app_state.dart';
import '../../data/models_ai.dart';
import '../performance/insight_widgets.dart';
import 'ai_widgets.dart';

/// Grades a scanned *completed* paper question by question, lets the parent
/// adjust every mark, and saves the total as an [ExamResult] that needs
/// review — the link between "scan a paper" and "find weak subjects".
class GradePaperPage extends StatefulWidget {
  const GradePaperPage({super.key, required this.recordId});

  final String recordId;

  @override
  State<GradePaperPage> createState() => _GradePaperPageState();
}

class _GradePaperPageState extends State<GradePaperPage> {
  GradedPaper? _graded;
  CancellationToken? _cancel;
  AppFailure? _failure;
  bool _running = false;
  bool _saving = false;
  bool _seeded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_seeded) return;
    _seeded = true;
    final state = AppScope.of(context);
    final existing = state
        .generatedForRecord(widget.recordId)
        .where((g) => g.kind == GeneratedKind.gradedPaper)
        .firstOrNull;
    if (existing != null) _graded = existing.asGradedPaper;
  }

  @override
  void dispose() {
    _cancel?.cancel();
    super.dispose();
  }

  Future<void> _grade() async {
    if (!await ensureAiReady(context)) return;
    if (!mounted) return;
    final state = AppScope.read(context);
    final scanned = state.scannedPaperFor(widget.recordId);
    final record = state.recordById(widget.recordId);
    if (scanned == null || record == null) return;
    final cancel = CancellationToken();
    setState(() {
      _cancel = cancel;
      _failure = null;
      _running = true;
    });
    try {
      final graded = await state.ai.gradePaper(
        paper: scanned.asScannedPaper,
        subject: record.subject,
        child: state.activeChild,
        cancel: cancel,
      );
      if (!mounted) return;
      setState(() => _graded = graded);
    } catch (error) {
      final failure = AppFailure.from(error);
      if (!mounted || failure.isCancellation) return;
      setState(() => _failure = failure);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _adjust(int index) async {
    final graded = _graded!;
    final q = graded.questions[index];
    final awarded = TextEditingController(text: _trim(q.awarded));
    var verdict = q.verdict;
    final saved = await AppSheet.show<bool>(
      context,
      (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheet) => AppSheet(
          title: 'Question ${q.number}',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppTextField(
                label: 'Marks awarded (out of ${_trim(q.outOf)})',
                controller: awarded,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final v in Verdict.values)
                    AppChip(
                      label: v.label,
                      selected: verdict == v,
                      onTap: () => setSheet(() => verdict = v),
                    ),
                ],
              ),
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
      ),
    );
    if (saved == true && mounted) {
      final value = (double.tryParse(awarded.text.trim()) ?? q.awarded).clamp(0, q.outOf).toDouble();
      setState(() {
        _graded = graded.replace(index, q.copyWith(awarded: value, verdict: verdict));
      });
    }
    awarded.dispose();
  }

  Future<void> _save() async {
    final state = AppScope.read(context);
    final record = state.recordById(widget.recordId);
    final graded = _graded;
    if (record == null || graded == null) return;
    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await state.saveGradedPaper(
        record: record,
        graded: graded,
        examLabel: record.examType.isEmpty ? record.title : record.examType,
      );
      if (!mounted) return;
      navigator.pushReplacementNamed(Routes.resultDetail, arguments: result.id);
      AppToast.showOn(
        messenger,
        context,
        title: 'Result saved for review',
        description: '${percentLabel(graded.percent)} in ${record.subject}. '
            'Confirm it to count it in the Performance tab.',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.failure(context, error, title: "Couldn't save the result");
    }
  }

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final state = AppScope.of(context);
    final record = state.recordById(widget.recordId);
    final scanned = state.scannedPaperFor(widget.recordId);
    final graded = _graded;

    if (record == null || scanned == null) {
      return Scaffold(backgroundColor: k.bg, body: const SizedBox.shrink());
    }
    final paper = scanned.asScannedPaper;

    return Scaffold(
      backgroundColor: k.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ScreenHeader(title: 'Grade this paper', subtitle: record.title),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  if (!paper.hasStudentAnswers)
                    const EmptyListNotice(
                      title: 'No answers on this scan',
                      description:
                          'This paper was scanned without the child\'s answers. '
                          'Scan the completed paper with "Pages include answers" on.',
                    )
                  else if (_running)
                    AiProgressView(
                      title: 'Marking ${paper.questions.length} answers',
                      stage: 'Handwriting recognition is imperfect — every mark is a draft you confirm.',
                      onCancel: () => _cancel?.cancel(),
                    )
                  else if (_failure != null)
                    AiFailureView(
                      failure: _failure!,
                      onRetry: _grade,
                      onCancel: () => setState(() => _failure = null),
                    )
                  else if (graded == null)
                    EmptyStateView(
                      title: 'Not graded yet',
                      description:
                          'Gemini marks each of the ${paper.questions.length} '
                          'answers and explains why. You confirm every mark before '
                          'it becomes a result.',
                      actionLabel: 'Grade with Gemini',
                      onAction: _grade,
                    )
                  else ...[
                    AiNotice(
                      'Draft marks from handwriting — tap any question to adjust '
                      'before saving.',
                      model: graded.model,
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(color: k.priC, borderRadius: BorderRadius.circular(20)),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            percentLabel(graded.percent),
                            style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -0.8, height: 1, color: k.priInk),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 3),
                              child: Text(
                                '${_trim(graded.awarded)} of ${_trim(graded.outOf)} marks · '
                                '${graded.questions.where((q) => q.verdict == Verdict.correct).length} correct',
                                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: k.priInk2),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    for (var i = 0; i < graded.questions.length; i++) ...[
                      _GradedRow(
                        graded: graded.questions[i],
                        question: paper.questions.where((q) => q.number == graded.questions[i].number).firstOrNull,
                        onTap: () => _adjust(i),
                      ),
                      const SizedBox(height: 8),
                    ],
                    const SizedBox(height: 8),
                    AppOutlinedButton(label: 'Grade again', height: 48, onPressed: _grade),
                  ],
                ],
              ),
            ),
            if (graded != null && !_running)
              StickyFooter(
                child: AppFilledButton(
                  label: _saving ? 'Saving…' : 'Save as result',
                  onPressed: _saving ? null : _save,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _GradedRow extends StatelessWidget {
  const _GradedRow({required this.graded, required this.question, required this.onTap});

  final GradedQuestion graded;
  final ScannedQuestion? question;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final g = graded;
    final (bg, ink, dot) = switch (g.verdict) {
      Verdict.correct => (k.secC, k.secInk, k.sec),
      Verdict.partial => (k.warnC, k.warnInk, k.warn),
      Verdict.incorrect => (k.errC, k.errInk, k.err),
      Verdict.blank => (k.surf2, k.tx3, k.tx5),
    };
    return AppCard(
      radius: 14,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(g.number, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  question?.text ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, height: 1.35, color: k.tx2),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${_GradePaperPageState._trim(g.awarded)}/${_GradePaperPageState._trim(g.outOf)}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              StatusPill(label: g.verdict.label, background: bg, foreground: ink, dotColor: dot),
              if (g.topic.isNotEmpty) ...[
                const SizedBox(width: 6),
                Flexible(child: StatusPill(label: g.topic, background: k.surf2, foreground: k.tx3)),
              ],
            ],
          ),
          if (g.reason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(g.reason, style: TextStyle(fontSize: 12.5, height: 1.4, color: k.tx3)),
          ],
        ],
      ),
    );
  }
}
