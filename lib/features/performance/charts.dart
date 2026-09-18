import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_tokens.dart';

/// One x-axis point on the trend line.
typedef TrendPoint = ({String label, double value});

/// Percent-over-time line, drawn by hand against [AppTokens] rather than a
/// charting package: two charts do not justify a dependency, and a painter
/// picks up both themes for free.
class TrendLineChart extends StatelessWidget {
  const TrendLineChart({
    super.key,
    required this.points,
    this.height = 150,
    this.color,
    this.emptyLabel = 'Two or more results draw a trend line.',
  });

  final List<TrendPoint> points;
  final double height;
  final Color? color;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    if (points.length < 2) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            emptyLabel,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: k.tx4),
          ),
        ),
      );
    }
    final style = DefaultTextStyle.of(context).style;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _TrendPainter(
          points: points,
          line: color ?? k.priFill,
          grid: k.bd3,
          gridLabel: k.tx5,
          axisLabel: k.tx3,
          dotFill: k.surf,
          fontFamily: style.fontFamily,
        ),
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.points,
    required this.line,
    required this.grid,
    required this.gridLabel,
    required this.axisLabel,
    required this.dotFill,
    required this.fontFamily,
  });

  final List<TrendPoint> points;
  final Color line, grid, gridLabel, axisLabel, dotFill;
  final String? fontFamily;

  static const _left = 30.0;
  static const _bottom = 22.0;
  static const _top = 8.0;

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Rect.fromLTRB(_left, _top, size.width, size.height - _bottom);
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;

    // 0 / 50 / 100 guide lines. A percent axis is always 0–100, so the
    // reader never has to work out the scale.
    for (final tick in const [0, 50, 100]) {
      final y = plot.bottom - plot.height * tick / 100;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
      _text(
        canvas,
        '$tick',
        Offset(0, y - 6),
        gridLabel,
        10,
        width: _left - 6,
        align: TextAlign.right,
      );
    }

    final step = points.length == 1 ? 0.0 : plot.width / (points.length - 1);
    final offsets = [
      for (var i = 0; i < points.length; i++)
        Offset(
          plot.left + step * i,
          plot.bottom - plot.height * points[i].value.clamp(0, 100) / 100,
        ),
    ];

    final path = Path()..moveTo(offsets.first.dx, offsets.first.dy);
    for (final o in offsets.skip(1)) {
      path.lineTo(o.dx, o.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    final fill = Paint()..color = dotFill;
    final ring = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    for (final o in offsets) {
      canvas.drawCircle(o, 4, fill);
      canvas.drawCircle(o, 4, ring);
    }

    // Label every point when there is room, else first / middle / last.
    final labelWidth = math.max(step, 44.0);
    final show = points.length <= 6
        ? List<int>.generate(points.length, (i) => i)
        : {0, points.length ~/ 2, points.length - 1}.toList();
    for (final i in show) {
      _text(
        canvas,
        points[i].label,
        Offset(offsets[i].dx - labelWidth / 2, plot.bottom + 6),
        axisLabel,
        10.5,
        width: labelWidth,
        align: TextAlign.center,
      );
    }
  }

  void _text(
    Canvas canvas,
    String text,
    Offset at,
    Color color,
    double size, {
    required double width,
    required TextAlign align,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: FontWeight.w600,
          fontFamily: fontFamily,
        ),
      ),
      textAlign: align,
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(minWidth: width, maxWidth: width);
    painter.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.points != points || old.line != line || old.grid != grid;
}

/// One horizontal bar: subject label, filled track, percent. The track is a
/// painter so the fill is a crisp rounded rect in either theme.
class PercentBar extends StatelessWidget {
  const PercentBar({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    this.trailing,
  });

  final String label;

  /// 0–100, or null for "no data" (drawn as an empty track).
  final double? value;
  final Color color;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final k = context.t;
    return Row(
      children: [
        SizedBox(
          width: 92,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: k.tx2,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: SizedBox(
            height: 12,
            child: CustomPaint(
              painter: _BarPainter(
                fraction: value == null ? 0 : value!.clamp(0, 100) / 100,
                fill: color,
                track: k.surf2,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 44,
          child: Text(
            trailing ?? (value == null ? '—' : '${value!.round()}%'),
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: value == null ? k.tx5 : k.tx,
            ),
          ),
        ),
      ],
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.fraction,
    required this.fill,
    required this.track,
  });

  final double fraction;
  final Color fill, track;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = Radius.circular(size.height / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, radius),
      Paint()..color = track,
    );
    if (fraction <= 0) return;
    final width = math.max(size.height, size.width * fraction);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, width, size.height),
        radius,
      ),
      Paint()..color = fill,
    );
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.fraction != fraction || old.fill != fill || old.track != track;
}
