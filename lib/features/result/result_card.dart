import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../core/format.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/app_icons.dart';
import '../../core/widgets/chips.dart';
import '../../core/widgets/layout.dart';
import '../../core/widgets/stroke_icon.dart';
import '../../data/models.dart';
import '../performance/insight_widgets.dart';

/// One report card in a list: overall percent tile, label, date and subject
/// count. Used by the Performance tab, the home dashboard, the timeline's
/// Marks filter and search — one shape everywhere.
class ResultCard extends StatelessWidget {
  const ResultCard({super.key, required this.result, this.onTap});

  final ExamResult result;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final root = Navigator.of(context, rootNavigator: true);
    final overall = result.overallPercent;
    final n = result.gradedSubjectCount;

    return AppCard(
      radius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap:
          onTap ??
          () => root.pushNamed(Routes.resultDetail, arguments: result.id),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: overall == null ? k.surf2 : k.priC,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              percentLabel(overall),
              style: TextStyle(
                fontSize: overall == null ? 16 : 14,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
                color: overall == null ? k.tx4 : k.priInk,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.examLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${AppDate.short(result.date)} · '
                  '$n subject${n == 1 ? '' : 's'} scored',
                  style: TextStyle(fontSize: 12, color: k.tx4),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (result.needsReview)
            StatusPill(
              label: 'Review',
              background: k.warnC,
              foreground: k.warnInk,
              dotColor: k.warn,
            )
          else if (result.source != ResultSource.manual)
            StatusPill(
              label: result.source.label,
              background: k.surf2,
              foreground: k.tx3,
            ),
          const SizedBox(width: 6),
          StrokeIcon(AppIcons.forward, size: 16, color: k.tx5),
        ],
      ),
    );
  }
}
