import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/chips.dart';
import '../../core/widgets/layout.dart';
import '../../data/models.dart';

/// Kind → tint. One place, so a chip on a row and a chip on the detail
/// screen never disagree.
({Color bg, Color ink, Color dot}) noticeKindColors(BuildContext context, NoticeKind kind) {
  final k = context.t;
  return switch (kind) {
    NoticeKind.exam => (bg: k.warnC, ink: k.warnInk, dot: k.warn),
    NoticeKind.assignment => (bg: k.priC, ink: k.priInk, dot: k.pri),
    NoticeKind.activity => (bg: k.secC, ink: k.secInk, dot: k.sec),
    NoticeKind.meeting => (bg: k.subComC, ink: k.subComInk, dot: k.subComInk),
    NoticeKind.holiday => (bg: k.subHinC, ink: k.subHinInk, dot: k.subHinInk),
    NoticeKind.fee => (bg: k.errC, ink: k.errInk, dot: k.err),
    NoticeKind.announcement || NoticeKind.unknown => (bg: k.surf2, ink: k.tx3, dot: k.tx5),
  };
}

class NoticeKindChip extends StatelessWidget {
  const NoticeKindChip(this.kind, {super.key, this.fontSize = 11});

  final NoticeKind kind;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final c = noticeKindColors(context, kind);
    return StatusPill(label: kind.label, background: c.bg, foreground: c.ink, dotColor: c.dot, fontSize: fontSize);
  }
}

/// Green, amber or grey: the extractor's confidence at a glance.
class ConfidenceDot extends StatelessWidget {
  const ConfidenceDot(this.confidence, {super.key, this.size = 9});

  final double confidence;
  final double size;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final color = confidence >= 0.8 ? k.sec : (confidence >= 0.5 ? k.warn : k.tx5);
    return Tooltip(
      message: '${(confidence * 100).round()}% sure',
      child: Dot(color: color, size: size),
    );
  }
}

/// A 38dp app icon, or the app's monogram when the icon is not to hand.
class AppIconTile extends StatelessWidget {
  const AppIconTile({super.key, required this.label, this.iconPng, this.size = 38});

  final String label;
  final Uint8List? iconPng;
  final double size;

  @override
  Widget build(BuildContext context) {
    final bytes = iconPng;
    if (bytes == null) {
      return Monogram(initials: AppFormat.initials(label), size: size, fontSize: size * .34);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * .3),
      child: Image.memory(bytes, width: size, height: size, fit: BoxFit.cover, gaplessPlayback: true),
    );
  }
}

/// One notice in a list (§E): app icon, title, kind chip, date, confidence.
class NoticeRow extends StatelessWidget {
  const NoticeRow({super.key, required this.notice, required this.onTap, this.iconPng});

  final CapturedNotice notice;
  final VoidCallback onTap;
  final Uint8List? iconPng;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final date = notice.date;
    return AppCard(
      radius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: onTap,
      child: Row(
        children: [
          AppIconTile(label: notice.appLabel, iconPng: iconPng),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  notice.displayTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, height: 1.3),
                ),
                const SizedBox(height: 4),
                Text(
                  '${notice.appLabel} · ${AppDate.short(notice.postedAt)}'
                  '${notice.status == NoticeStatus.needsReview ? '' : ' · ${notice.status.label}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: k.tx4),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    NoticeKindChip(notice.kind),
                    if (date != null)
                      Text(
                        AppDate.dueLabel(date),
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: k.tx3),
                      ),
                    ConfidenceDot(notice.confidence, size: 8),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The notice text with the extractor's matched phrases highlighted, so a
/// parent can see *why* it was read the way it was.
class HighlightedText extends StatelessWidget {
  const HighlightedText(this.text, {super.key, this.phrases = const []});

  final String text;
  final List<String> phrases;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    final base = TextStyle(fontSize: 14, height: 1.55, color: k.tx2);
    final mark = base.copyWith(
      color: k.priInk,
      fontWeight: FontWeight.w700,
      backgroundColor: k.priC,
    );
    final needles = phrases.where((p) => p.trim().length >= 2).toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    if (needles.isEmpty || text.isEmpty) return Text(text, style: base);

    final pattern = RegExp(needles.map(RegExp.escape).join('|'), caseSensitive: false);
    final spans = <TextSpan>[];
    var cursor = 0;
    for (final m in pattern.allMatches(text)) {
      if (m.start > cursor) spans.add(TextSpan(text: text.substring(cursor, m.start)));
      spans.add(TextSpan(text: m.group(0), style: mark));
      cursor = m.end;
    }
    if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor)));
    return Text.rich(TextSpan(style: base, children: spans));
  }
}
