import 'package:flutter/material.dart';

import '../../core/errors/app_failure.dart';
import '../../core/services/ai/gemini_client.dart';
import '../../core/services/ai/paper_pdf.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/sheets.dart';
import '../../core/widgets/states.dart';
import '../../core/widgets/toast.dart';
import '../../data/app_state.dart';
import '../../data/models_ai.dart';
import 'ai_widgets.dart';

/// Generates a worked answer key over a scanned paper's structured
/// questions (not its images), shows it, and attaches it as the record's
/// answer key PDF — asking before replacing one the parent attached.
class AnswerKeyPage extends StatefulWidget {
  const AnswerKeyPage({super.key, required this.recordId});

  final String recordId;

  @override
  State<AnswerKeyPage> createState() => _AnswerKeyPageState();
}

class _AnswerKeyPageState extends State<AnswerKeyPage> {
  AnswerKey? _key;
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
        .where((g) => g.kind == GeneratedKind.answerKey)
        .firstOrNull;
    if (existing != null) _key = existing.asAnswerKey;
  }

  @override
  void dispose() {
    _cancel?.cancel();
    super.dispose();
  }

  Future<void> _generate() async {
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
      final key = await state.ai.answerKey(
        paper: scanned.asScannedPaper,
        subject: record.subject,
        child: state.activeChild,
        cancel: cancel,
      );
      if (!mounted) return;
      setState(() => _key = key);
    } catch (error) {
      final failure = AppFailure.from(error);
      if (!mounted || failure.isCancellation) return;
      setState(() => _failure = failure);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _save() async {
    final state = AppScope.read(context);
    final record = state.recordById(widget.recordId);
    final scanned = state.scannedPaperFor(widget.recordId);
    final key = _key;
    if (record == null || scanned == null || key == null) return;

    if (record.answerKey != null) {
      // Never overwrite a key the parent attached without asking.
      final ok = await confirmDelete(
        context,
        title: 'Replace the answer key?',
        description: 'This exam already has an answer key attached. Replace it '
            'with the AI-generated one?',
        confirmLabel: 'Replace',
      );
      if (!ok || !mounted) return;
    }

    setState(() => _saving = true);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final fonts = await PaperFonts.load();
      final paper = scanned.asScannedPaper;
      final bytes = await PaperPdf.renderAnswerKey(
        paper,
        key,
        fonts: fonts,
        title: 'Answer key · ${record.title}',
      );
      await state.saveAnswerKey(record: record, paper: paper, key: key, pdfBytes: bytes);
      if (!mounted) return;
      navigator.pop();
      AppToast.showOn(
        messenger,
        context,
        title: 'Answer key attached',
        description: 'Badged AI-generated · verify before use.',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.failure(context, error, title: "Couldn't attach the key");
    }
  }

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final state = AppScope.of(context);
    final record = state.recordById(widget.recordId);
    final scanned = state.scannedPaperFor(widget.recordId);
    final key = _key;

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
              child: ScreenHeader(title: 'Answer key', subtitle: record.title),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  if (_running)
                    AiProgressView(
                      title: 'Working out the answers',
                      stage: '${paper.questions.length} questions · text only, no pages resent',
                      onCancel: () => _cancel?.cancel(),
                    )
                  else if (_failure != null)
                    AiFailureView(
                      failure: _failure!,
                      onRetry: _generate,
                      onCancel: () => setState(() => _failure = null),
                    )
                  else if (key == null)
                    EmptyStateView(
                      title: 'No answer key yet',
                      description:
                          'Gemini writes a worked solution and marking scheme '
                          'for each of the ${paper.questions.length} questions.',
                      actionLabel: 'Generate answer key',
                      onAction: _generate,
                    )
                  else ...[
                    AiNotice('AI-generated · verify before use', model: key.model),
                    const SizedBox(height: 14),
                    for (final q in paper.questions) ...[
                      _AnswerCard(question: q, entry: key.forNumber(q.number)),
                      const SizedBox(height: 8),
                    ],
                    const SizedBox(height: 8),
                    AppOutlinedButton(label: 'Regenerate', height: 48, onPressed: _generate),
                  ],
                ],
              ),
            ),
            if (key != null && !_running)
              StickyFooter(
                child: AppFilledButton(
                  label: _saving
                      ? 'Attaching…'
                      : record.answerKey == null
                      ? 'Attach as answer key'
                      : 'Replace answer key',
                  onPressed: _saving ? null : _save,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AnswerCard extends StatelessWidget {
  const _AnswerCard({required this.question, required this.entry});

  final ScannedQuestion question;
  final AnswerKeyEntry? entry;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final a = entry;
    return AppCard(
      radius: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${question.number}. ${question.text}',
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, height: 1.4),
                ),
              ),
              if (a != null) ...[const SizedBox(width: 8), ConfidencePill(a.confidence)],
            ],
          ),
          const SizedBox(height: 6),
          if (a == null)
            Text('No answer returned for this question.', style: TextStyle(fontSize: 13, color: k.warnInk))
          else ...[
            Text(a.answer, style: TextStyle(fontSize: 14, height: 1.45, color: k.secInk2, fontWeight: FontWeight.w600)),
            for (var i = 0; i < a.workedSolution.length; i++)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text('${i + 1}. ${a.workedSolution[i]}', style: TextStyle(fontSize: 13, height: 1.4, color: k.tx2)),
              ),
            if (a.markingScheme.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Marking: ${a.markingScheme.map((m) => '${m.points % 1 == 0 ? m.points.toInt() : m.points} for ${m.reason}').join('; ')}',
                style: TextStyle(fontSize: 12.5, height: 1.4, color: k.tx3),
              ),
            ],
            if (a.commonMistakes.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Watch for: ${a.commonMistakes.join('; ')}', style: TextStyle(fontSize: 12.5, height: 1.4, color: k.tx4)),
            ],
          ],
        ],
      ),
    );
  }
}
