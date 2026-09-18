import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';
import '../../core/widgets/chips.dart';
import '../../data/analytics/subject_insights.dart';

/// The band's colours in the current theme.
({Color background, Color foreground, Color dot}) bandColors(
  AppTokens k,
  InsightBand band,
) => switch (band) {
  InsightBand.strong => (background: k.secC, foreground: k.secInk, dot: k.sec),
  InsightBand.steady => (background: k.priC, foreground: k.priInk, dot: k.pri),
  InsightBand.watch => (background: k.warnC, foreground: k.warnInk, dot: k.warn),
  InsightBand.weak => (background: k.errC, foreground: k.errInk, dot: k.err),
  InsightBand.unknown => (background: k.surf2, foreground: k.tx3, dot: k.tx5),
};

/// "Needs attention" / "Steady" / … as a [StatusPill].
class InsightBandPill extends StatelessWidget {
  const InsightBandPill(this.band, {super.key, this.fontSize = 11.5});

  final InsightBand band;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final c = bandColors(context.t, band);
    return StatusPill(
      label: band.label,
      background: c.background,
      foreground: c.foreground,
      dotColor: c.dot,
      fontSize: fontSize,
    );
  }
}

/// "Based on 3 results" with a hedge when the sample is thin or stale.
String confidenceLabel(SubjectInsight i) {
  final n = i.sampleCount;
  final base = 'Based on $n result${n == 1 ? '' : 's'}';
  if (n == 0) return 'No marks yet';
  if (i.confidence < 0.5) return '$base · early days';
  return base;
}

String percentLabel(double? value) => value == null ? '—' : '${value.round()}%';

/// "+4 vs avg" / "−6 vs avg" / "at avg", or empty when there is nothing
/// to compare.
String deltaLabel(double? value, {String suffix = 'avg'}) {
  if (value == null) return '';
  final rounded = value.round();
  if (rounded == 0) return 'at $suffix';
  return '${rounded > 0 ? '+' : '−'}${rounded.abs()} vs $suffix';
}
