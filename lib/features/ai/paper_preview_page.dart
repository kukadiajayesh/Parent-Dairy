import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/routes.dart';
import '../../core/services/ai/paper_pdf.dart';
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
import '../../data/app_state.dart';
import '../../data/models_ai.dart';
import 'ai_widgets.dart';

class PaperPreviewArgs {
  const PaperPreviewArgs({required this.paper, required this.config});
  final GeneratedPaper paper;
  final PaperConfig config;
}

/// The paper as it will print: per-question edit, regenerate, delete and
/// flag, then Save — which renders the PDF, files a worksheet record and
/// offers Print / Share.
class PaperPreviewPage extends StatefulWidget {
  const PaperPreviewPage({super.key, required this.args});

  final PaperPreviewArgs args;

  @override
  State<PaperPreviewPage> createState() => _PaperPreviewPageState();
}

class _PaperPreviewPageState extends State<PaperPreviewPage> {
  late GeneratedPaper _paper = widget.args.paper;
  late bool _includeKey = widget.args.config.includeAnswerKey;
  final Set<String> _busy = {};
  bool _saving = false;

  String _keyFor(int s, int q) => '$s:$q';

  Future<void> _edit(int s, int q) async {
    final question = _paper.sections[s].questions[q];
    final text = TextEditingController(text: question.text);
    final answer = TextEditingController(text: question.answer);
    final explanation = TextEditingController(text: question.explanation);
    final marks = TextEditingController(text: '${question.marks}');
    final saved = await AppSheet.show<bool>(
      context,
      (sheetContext) => AppSheet(
        title: 'Question ${question.number}',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(label: 'Question', controller: text, maxLines: 4, minHeight: 80),
            const SizedBox(height: 12),
            AppTextField(label: 'Answer', controller: answer, maxLines: 2, minHeight: 56),
            const SizedBox(height: 12),
            AppTextField(label: 'Explanation', controller: explanation, maxLines: 3, minHeight: 66),
            const SizedBox(height: 12),
            AppTextField(label: 'Marks', controller: marks, keyboardType: TextInputType.number),
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
        _paper = _paper.replaceQuestion(
          s,
          q,
          question.copyWith(
            text: text.text.trim(),
            answer: answer.text.trim(),
            explanation: explanation.text.trim(),
            marks: int.tryParse(marks.text.trim()) ?? question.marks,
          ),
        );
      });
    }
    text.dispose();
    answer.dispose();
    explanation.dispose();
    marks.dispose();
  }

  Future<void> _regenerate(int s, int q) async {
    final state = AppScope.read(context);
    if (!await ensureAiReady(context)) return;
    if (!mounted) return;
    final key = _keyFor(s, q);
    final question = _paper.sections[s].questions[q];
    setState(() => _busy.add(key));
    try {
      final replacement = await state.ai.regenerateQuestion(
        paper: _paper,
        question: question,
        config: widget.args.config,
        child: state.activeChild,
      );
      if (!mounted) return;
      setState(() => _paper = _paper.replaceQuestion(s, q, replacement));
    } catch (error) {
      if (!mounted) return;
      AppToast.failure(context, error, title: "Couldn't replace the question");
    } finally {
      if (mounted) setState(() => _busy.remove(key));
    }
  }

  void _delete(int s, int q) => setState(() => _paper = _paper.replaceQuestion(s, q, null));

  void _flag(int s, int q) {
    final question = _paper.sections[s].questions[q];
    setState(
      () => _paper = _paper.replaceQuestion(s, q, question.copyWith(flagged: !question.flagged)),
    );
  }

  Future<void> _save() async {
    final state = AppScope.read(context);
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final fonts = await PaperFonts.load();
      final paper = _paper.copyWith(totalMarks: _paper.computedMarks);
      final bytes = await PaperPdf.renderPaper(paper, fonts: fonts, includeAnswerKey: _includeKey);
      final record = await state.saveGeneratedPaper(
        paper: paper,
        config: widget.args.config,
        pdfBytes: bytes,
      );
      if (!mounted) return;
      final path = record.attachments.firstOrNull?.localPath;
      final next = await AppSheet.show<String>(
        context,
        (sheetContext) => AppSheet(
          title: 'Saved to the diary',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${paper.title} is filed as a worksheet with an AI badge.',
                style: TextStyle(fontSize: 13.5, height: 1.45, color: sheetContext.t.tx3),
              ),
              const SizedBox(height: 14),
              AppFilledButton(
                label: 'Print',
                height: 50,
                elevated: false,
                icon: const StrokeIcon(AppIcons.print, size: 18),
                onPressed: () => Navigator.of(sheetContext).pop('print'),
              ),
              const SizedBox(height: 8),
              AppOutlinedButton(
                label: 'Share PDF',
                height: 50,
                icon: const StrokeIcon(AppIcons.share, size: 18),
                onPressed: () => Navigator.of(sheetContext).pop('share'),
              ),
              const SizedBox(height: 8),
              AppTonalButton(
                label: 'Open the worksheet',
                height: 48,
                borderRadius: 14,
                background: sheetContext.t.surf2,
                hoverBackground: sheetContext.t.hov,
                foreground: sheetContext.t.tx2,
                onPressed: () => Navigator.of(sheetContext).pop('open'),
              ),
            ],
          ),
        ),
      );
      if (!mounted) return;
      switch (next) {
        case 'print':
          await Printing.layoutPdf(onLayout: (_) async => bytes, name: '${paper.title}.pdf');
        case 'share':
          if (path != null) {
            await SharePlus.instance.share(
              ShareParams(
                files: [XFile(path, mimeType: 'application/pdf')],
                subject: paper.title,
              ),
            );
          }
        case 'open':
          navigator.pushReplacementNamed(Routes.worksheetDetail, arguments: record.id);
          return;
      }
      if (!mounted) return;
      navigator.pop();
      AppToast.showOn(
        messenger,
        context,
        title: 'Practice saved',
        description: '${paper.title} is on the timeline.',
      );
    } catch (error) {
      if (!mounted) return;
      AppToast.failure(context, error, title: "Couldn't save the paper");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final paper = _paper;
    final flagged = paper.questions.where((q) => q.flagged).length;

    return Scaffold(
      backgroundColor: k.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: ScreenHeader(title: 'Review', leadingIsClose: true),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                children: [
                  AiNotice(PaperPdf.aiBanner, model: paper.model),
                  if (paper.isPartial) ...[
                    const SizedBox(height: 10),
                    InlineErrorBanner(
                      title: 'Some questions are missing',
                      description: paper.sections.isEmpty
                          ? 'Gemini returned no sections. Try again with fewer questions.'
                          : '${paper.droppedQuestions} could not be read and are marked below.',
                      actionLabel: 'OK',
                    ),
                  ],
                  const SizedBox(height: 14),
                  Text(
                    paper.title,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.3, height: 1.25),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${paper.grade.isEmpty ? '' : '${paper.grade} · '}${paper.subject} · '
                    '${paper.computedMarks} marks · ${paper.durationMinutes} min · '
                    '${paper.questionCount} questions'
                    '${flagged > 0 ? ' · $flagged flagged' : ''}',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: k.tx3),
                  ),
                  if (paper.instructions.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    for (final line in paper.instructions)
                      Text('· $line', style: TextStyle(fontSize: 13, height: 1.4, color: k.tx2)),
                  ],
                  for (var s = 0; s < paper.sections.length; s++) ...[
                    const SizedBox(height: 18),
                    SectionLabel('${paper.sections[s].name} · ${paper.sections[s].marks} marks'),
                    if (paper.sections[s].instructions.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        paper.sections[s].instructions,
                        style: TextStyle(fontSize: 12.5, color: k.tx4),
                      ),
                    ],
                    const SizedBox(height: 10),
                    for (var q = 0; q < paper.sections[s].questions.length; q++) ...[
                      _QuestionCard(
                        question: paper.sections[s].questions[q],
                        busy: _busy.contains(_keyFor(s, q)),
                        onEdit: () => _edit(s, q),
                        onRegenerate: () => _regenerate(s, q),
                        onDelete: () => _delete(s, q),
                        onFlag: () => _flag(s, q),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (paper.sections[s].droppedQuestions > 0)
                      EmptyListNotice(
                        title: '${paper.sections[s].droppedQuestions} missing',
                        description: 'Gemini returned these in a shape the app could not read.',
                      ),
                  ],
                  const SizedBox(height: 14),
                  SettingsGroup(
                    children: [
                      SettingsRow(
                        label: 'Include answer key in the PDF',
                        showChevron: false,
                        trailing: AppSwitch(
                          value: _includeKey,
                          onChanged: (v) => setState(() => _includeKey = v),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            StickyFooter(
              child: AppFilledButton(
                label: _saving ? 'Saving…' : 'Save as worksheet',
                onPressed: _saving || paper.questionCount == 0 ? null : _save,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.question,
    required this.busy,
    required this.onEdit,
    required this.onRegenerate,
    required this.onDelete,
    required this.onFlag,
  });

  final PaperQuestion question;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onRegenerate;
  final VoidCallback onDelete;
  final VoidCallback onFlag;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final q = question;
    return AppCard(
      radius: 16,
      borderColor: q.flagged ? k.warn : null,
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${q.number}.', style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(q.text, style: const TextStyle(fontSize: 14.5, height: 1.4)),
              ),
              const SizedBox(width: 8),
              Text('[${q.marks}]', style: TextStyle(fontSize: 12.5, color: k.tx4)),
            ],
          ),
          if (q.options.isNotEmpty) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 22),
              child: Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  for (var i = 0; i < q.options.length; i++)
                    Text(
                      '(${String.fromCharCode(97 + i)}) ${q.options[i]}',
                      style: TextStyle(fontSize: 13.5, color: k.tx2),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 22),
            child: Text(
              'Answer: ${q.answer}${q.explanation.isEmpty ? '' : ' — ${q.explanation}'}',
              style: TextStyle(fontSize: 12.5, height: 1.4, color: k.secInk2),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              StatusPill(label: q.type.label, background: k.surf2, foreground: k.tx3),
              if (q.chapter.isNotEmpty) ...[
                const SizedBox(width: 6),
                StatusPill(label: q.chapter, background: k.surf2, foreground: k.tx3),
              ],
              const Spacer(),
              if (busy)
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else ...[
                AppIconButton(size: 34, tooltip: 'Edit', onTap: onEdit, child: StrokeIcon(AppIcons.editSimple, size: 17, color: k.tx3)),
                AppIconButton(size: 34, tooltip: 'Regenerate', onTap: onRegenerate, child: StrokeIcon(AppIcons.rotate, size: 17, color: k.tx3)),
                AppIconButton(
                  size: 34,
                  tooltip: q.flagged ? 'Unflag' : 'Flag',
                  onTap: onFlag,
                  child: StrokeIcon(AppIcons.warningTriangle, size: 17, color: q.flagged ? k.warn : k.tx3),
                ),
                AppIconButton(size: 34, tooltip: 'Delete', hoverBackground: k.errC, onTap: onDelete, child: StrokeIcon(AppIcons.trash, size: 17, color: k.err)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
