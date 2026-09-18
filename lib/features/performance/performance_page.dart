import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_icons.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/chips.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/pressable.dart';
import '../../core/widgets/states.dart';
import '../../core/widgets/stroke_icon.dart';
import '../../data/analytics/subject_insights.dart';
import '../../data/app_state.dart';
import '../../data/models.dart';
import '../children/child_switcher_sheet.dart';
import '../ai/generate_paper_page.dart';
import '../result/result_card.dart';
import '../settings/year_switcher_sheet.dart';
import '../subject/subject_page.dart';
import 'charts.dart';
import 'insight_widgets.dart';

/// Performance tab: subject-by-subject averages, the overall trend across
/// results, the weak subjects with their reasons, and every result of the
/// year. Reads only [AppState.subjectInsights], which is memoised, so this
/// screen never recomputes the rule on a rebuild.
class PerformancePage extends StatelessWidget {
  const PerformancePage({super.key});

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final state = AppScope.of(context);
    final root = Navigator.of(context, rootNavigator: true);
    final results = state.insightResults;
    final loading =
        results.isEmpty &&
        (state.isLoadingResults || state.isLoadingAllYearResults);
    final error = state.lastError;

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
                'Performance',
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
                  background: k.priC,
                  hoverBackground: k.priCH,
                  tooltip: 'Add marks',
                  onTap: () => root.pushNamed(Routes.addResult),
                  child: StrokeIcon(AppIcons.plus, size: 20, color: k.priInk),
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
                  const _ScopeRow(),
                  const SizedBox(height: 18),
                  if (error != null && results.isEmpty)
                    ErrorStateView(
                      title: "Couldn't load marks",
                      description: error.message,
                      actionLabel: 'Retry',
                      onAction: state.retryStreams,
                      onCancel: state.clearError,
                    )
                  else if (loading)
                    const Skeletons(child: _PerformanceSkeleton())
                  else if (results.isEmpty)
                    EmptyStateView(
                      title: 'No marks yet',
                      description:
                          'Add exam marks to start tracking performance.',
                      actionLabel: 'Add Marks',
                      onAction: () => root.pushNamed(Routes.addResult),
                    )
                  else
                    _Dashboard(results: results),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Child · year · all-years toggle. The first two open the same switcher
/// sheets the timeline uses; the third is local to this tab.
class _ScopeRow extends StatelessWidget {
  const _ScopeRow();

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final state = AppScope.of(context);

    Widget chip({
      required String label,
      required VoidCallback onTap,
      bool caret = true,
    }) => PressDip(
      child: Material(
        color: k.surf,
        shape: StadiumBorder(side: BorderSide(color: k.bd3)),
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
                    color: k.tx2,
                  ),
                ),
                if (caret) ...[
                  const SizedBox(width: 6),
                  StrokeIcon(AppIcons.caretDown, size: 14, color: k.tx2),
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
          AppChip(
            label: 'All years',
            selected: state.insightsAllYears,
            fontSize: 12.5,
            selectedBackground: k.priC,
            selectedBorder: k.priBd,
            selectedForeground: k.priInk,
            onTap: () => state.setInsightsAllYears(!state.insightsAllYears),
          ),
        ],
      ),
    );
  }
}

class _Dashboard extends StatelessWidget {
  const _Dashboard({required this.results});

  final List<ExamResult> results;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final state = AppScope.of(context);
    final insights = state.subjectInsights;
    final weak = state.weakSubjects;
    final byDate = results.toList()..sort((a, b) => a.date.compareTo(b.date));
    final trend = <TrendPoint>[
      for (final r in byDate)
        if (r.overallPercent != null)
          (label: r.examLabel, value: r.overallPercent!),
    ];
    final latest = byDate.last;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _OverallCard(latest: latest, count: results.length, trend: trend),
        const SizedBox(height: 22),
        const SectionLabel('By subject'),
        const SizedBox(height: 12),
        AppCard(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
          child: Column(
            children: [
              for (final i in insights) ...[
                PercentBar(
                  label: i.subject,
                  value: i.averagePercent,
                  color: state.subjectByName(i.subject).hue.dot(k),
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
        const SizedBox(height: 22),
        SectionLabel(
          'Needs attention',
          trailing: state.aiAvailable && weak.isNotEmpty
              ? SectionAction(
                  label: 'Focus plan',
                  onTap: () => Navigator.of(context, rootNavigator: true)
                      .pushNamed(Routes.focusPlan),
                )
              : null,
        ),
        const SizedBox(height: 12),
        if (weak.isEmpty)
          const EmptyListNotice(
            title: 'Nothing needs attention',
            description:
                'No subject is averaging below the mark or slipping behind.',
          )
        else
          for (final i in weak) ...[
            WeakSubjectCard(insight: i),
            const SizedBox(height: 10),
          ],
        const SizedBox(height: 12),
        SectionLabel('Results · ${results.length}'),
        const SizedBox(height: 12),
        for (final r in state.insightsAllYears
            ? (results.toList()..sort((a, b) => b.date.compareTo(a.date)))
            : state.resultsByDateDesc) ...[
          ResultCard(result: r),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _OverallCard extends StatelessWidget {
  const _OverallCard({
    required this.latest,
    required this.count,
    required this.trend,
  });

  final ExamResult latest;
  final int count;
  final List<TrendPoint> trend;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final overall = latest.overallPercent;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: k.priC,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                percentLabel(overall),
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.8,
                  height: 1,
                  color: k.priInk,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Text(
                    overall == null
                        ? '${latest.examLabel} · not scored'
                        : 'Latest · ${latest.examLabel}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: k.priInk2,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '$count result${count == 1 ? '' : 's'} this period',
            style: TextStyle(fontSize: 12, color: k.priInk2),
          ),
          const SizedBox(height: 12),
          DefaultTextStyle.merge(
            style: TextStyle(color: k.priInk),
            child: TrendLineChart(
              points: trend,
              height: 140,
              color: k.priFill,
            ),
          ),
        ],
      ),
    );
  }
}

/// A weak subject with the two heaviest reasons and its actions. Also used
/// by the smoke test as the thing that must render at phone width.
class WeakSubjectCard extends StatelessWidget {
  const WeakSubjectCard({super.key, required this.insight});

  final SubjectInsight insight;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final state = AppScope.of(context);
    final subject = state.subjectByName(insight.subject);

    return AppCard(
      radius: 18,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Dot(color: subject.hue.dot(k), size: 9),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  insight.subject,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: InsightBandPill(insight.band),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                percentLabel(insight.averagePercent),
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  height: 1,
                  color: k.err,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'average · ${confidenceLabel(insight)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: k.tx4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final reason in insight.reasons.take(2))
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Dot(color: k.err, size: 6),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      reason,
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.4,
                        color: k.tx2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (insight.focusChapters.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final chapter in insight.focusChapters)
                  StatusPill(
                    label: chapter,
                    background: k.surf2,
                    foreground: k.tx3,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: AppTonalButton(
                  label: 'View subject',
                  height: 44,
                  fontSize: 13.5,
                  borderRadius: 13,
                  background: k.priC,
                  hoverBackground: k.priCH,
                  foreground: k.priInk,
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SubjectPage(subjectName: insight.subject),
                    ),
                  ),
                ),
              ),
              // Pre-filled with the subject and its focus chapters; the
              // generator's consent gate runs on the next screen.
              if (state.aiAvailable) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: AppOutlinedButton(
                    label: 'Generate practice',
                    height: 44,
                    borderRadius: 13,
                    onPressed: () => Navigator.of(context, rootNavigator: true)
                        .pushNamed(
                          Routes.aiGenerate,
                          arguments: GenerateArgs(
                            subject: insight.subject,
                            chapters: insight.focusChapters,
                          ),
                        ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _PerformanceSkeleton extends StatelessWidget {
  const _PerformanceSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SkeletonBox(height: 220, radius: 20),
        const SizedBox(height: 22),
        const SkeletonBox(width: 90, height: 11, tone: SkeletonTone.solid),
        const SizedBox(height: 12),
        AppCard(
          child: Column(
            children: [
              for (var i = 0; i < 4; i++) ...[
                Row(
                  children: [
                    const SkeletonBox(width: 80, height: 12),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SkeletonBox(
                        height: 12,
                        radius: 6,
                        tone: i.isEven ? SkeletonTone.solid : SkeletonTone.soft,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const SkeletonBox(width: 34, height: 12),
                  ],
                ),
                if (i < 3) const SizedBox(height: 12),
              ],
            ],
          ),
        ),
        const SizedBox(height: 22),
        const SkeletonBox(width: 120, height: 11, tone: SkeletonTone.solid),
        const SizedBox(height: 12),
        const SkeletonBox(height: 150, radius: 18),
      ],
    );
  }
}
