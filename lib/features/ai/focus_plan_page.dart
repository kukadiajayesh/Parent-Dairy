import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../core/errors/app_failure.dart';
import '../../core/services/ai/gemini_client.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/chips.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/states.dart';
import '../../data/analytics/subject_insights.dart';
import '../../data/app_state.dart';
import '../../data/models_ai.dart';
import '../performance/insight_widgets.dart';
import 'ai_widgets.dart';
import 'generate_paper_page.dart';

/// The deterministic verdict first, the generated advice second, clearly
/// attributed (prompt 02 §F). Gemini only explains; the ranking is
/// `subjectInsights`'.
class FocusPlanPage extends StatefulWidget {
  const FocusPlanPage({super.key});

  @override
  State<FocusPlanPage> createState() => _FocusPlanPageState();
}

class _FocusPlanPageState extends State<FocusPlanPage> {
  FocusPlan? _plan;
  CancellationToken? _cancel;
  AppFailure? _failure;
  bool _running = false;

  @override
  void dispose() {
    _cancel?.cancel();
    super.dispose();
  }

  Future<void> _explain() async {
    if (!await ensureAiReady(context)) return;
    if (!mounted) return;
    final state = AppScope.read(context);
    final cancel = CancellationToken();
    setState(() {
      _cancel = cancel;
      _failure = null;
      _running = true;
    });
    try {
      final weak = state.weakSubjects;
      final watch = state.subjectInsights.where((i) => i.band == InsightBand.watch);
      final plan = await state.ai.focusPlan(
        insights: [...weak, ...watch],
        chaptersBySubject: state.chaptersBySubject,
        child: state.activeChild,
        cancel: cancel,
      );
      if (!mounted) return;
      setState(() => _plan = plan);
    } catch (error) {
      final failure = AppFailure.from(error);
      if (!mounted || failure.isCancellation) return;
      setState(() => _failure = failure);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  void _practice(FocusSubject subject) {
    final s = subject.practiceSuggestion;
    Navigator.of(context).pushNamed(
      Routes.aiGenerate,
      arguments: GenerateArgs(
        subject: subject.subject,
        chapters: (s?.chapters.isNotEmpty ?? false) ? s!.chapters : subject.focusChapters,
        output: s?.type ?? PaperOutput.quiz,
        questionCount: s?.questionCount,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final state = AppScope.of(context);
    final weak = state.weakSubjects;
    final watch = state.subjectInsights.where((i) => i.band == InsightBand.watch).toList();
    final plan = _plan;

    return Scaffold(
      backgroundColor: k.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: ScreenHeader(title: 'Focus plan'),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                children: [
                  const SectionLabel('The numbers'),
                  const SizedBox(height: 6),
                  Text(
                    'Worked out by the app from the marks you entered — the same '
                    'rule every time, no AI involved.',
                    style: TextStyle(fontSize: 12.5, height: 1.4, color: k.tx4),
                  ),
                  const SizedBox(height: 10),
                  if (weak.isEmpty && watch.isEmpty)
                    const EmptyListNotice(
                      title: 'Nothing needs attention',
                      description: 'No subject is averaging below the mark or slipping behind.',
                    )
                  else
                    for (final i in [...weak, ...watch]) ...[
                      _InsightRow(insight: i),
                      const SizedBox(height: 8),
                    ],
                  const SizedBox(height: 22),
                  const SectionLabel('The advice'),
                  const SizedBox(height: 10),
                  if (_running)
                    AiProgressView(
                      title: 'Writing the plan',
                      stage: 'Only the numbers above are sent — no pages, no name.',
                      onCancel: () => _cancel?.cancel(),
                    )
                  else if (_failure != null)
                    AiFailureView(
                      failure: _failure!,
                      onRetry: _explain,
                      onCancel: () => setState(() => _failure = null),
                    )
                  else if (plan == null)
                    EmptyStateView(
                      title: 'Explain this with Gemini',
                      description: weak.isEmpty && watch.isEmpty
                          ? 'There is nothing to explain yet — add a few results first.'
                          : 'Turn the verdict above into plain language and a two-week plan.',
                      actionLabel: weak.isEmpty && watch.isEmpty ? null : 'Write a focus plan',
                      onAction: _explain,
                    )
                  else ...[
                    AiNotice(plan.summary, model: plan.model),
                    const SizedBox(height: 12),
                    for (final s in plan.subjects) ...[
                      _PlanCard(subject: s, onPractice: () => _practice(s)),
                      const SizedBox(height: 10),
                    ],
                    AppOutlinedButton(label: 'Write it again', height: 48, onPressed: _explain),
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

class _InsightRow extends StatelessWidget {
  const _InsightRow({required this.insight});
  final SubjectInsight insight;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final state = AppScope.of(context);
    final subject = state.subjectByName(insight.subject);
    return AppCard(
      radius: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Dot(color: subject.hue.dot(k), size: 9),
              const SizedBox(width: 8),
              Expanded(child: Text(insight.subject, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800))),
              Text(
                percentLabel(insight.averagePercent),
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: k.err),
              ),
              const SizedBox(width: 8),
              InsightBandPill(insight.band),
            ],
          ),
          for (final reason in insight.reasons.take(2)) ...[
            const SizedBox(height: 4),
            Text('· $reason', style: TextStyle(fontSize: 13, height: 1.4, color: k.tx2)),
          ],
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.subject, required this.onPractice});
  final FocusSubject subject;
  final VoidCallback onPractice;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final s = subject;
    return AppCard(
      radius: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.subject, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: -0.2)),
          const SizedBox(height: 4),
          Text(s.why, style: TextStyle(fontSize: 13.5, height: 1.45, color: k.tx2)),
          if (s.focusChapters.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final c in s.focusChapters) StatusPill(label: c, background: k.surf2, foreground: k.tx3)],
            ),
          ],
          for (final w in s.plan) ...[
            const SizedBox(height: 10),
            Text('Week ${w.week}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: .4, color: k.tx4)),
            for (final a in w.actions)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text('· $a', style: TextStyle(fontSize: 13.5, height: 1.4, color: k.tx2)),
              ),
          ],
          const SizedBox(height: 12),
          AppTonalButton(
            label: s.practiceSuggestion == null
                ? 'Generate practice'
                : 'Generate ${s.practiceSuggestion!.questionCount}-question '
                      '${s.practiceSuggestion!.type.label.toLowerCase()}',
            height: 44,
            fontSize: 13.5,
            borderRadius: 13,
            background: k.priC,
            hoverBackground: k.priCH,
            foreground: k.priInk,
            onPressed: onPractice,
          ),
        ],
      ),
    );
  }
}
