
import 'package:flutter/material.dart';

/// The design draws every icon as a stroked 24×24 SVG rather than a font glyph.
/// [StrokeIcon] renders those same path strings so the icons are identical to
/// the prototype instead of approximated with Material glyphs.
class StrokeIcon extends StatelessWidget {
  const StrokeIcon(
    this.icon, {
    super.key,
    this.size = 20,
    this.color,
    this.strokeWidth,
  });

  final SvgIcon icon;
  final double size;
  final Color? color;
  final double? strokeWidth;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _StrokeIconPainter(
          icon: icon,
          color: color ?? IconTheme.of(context).color ?? const Color(0xFF1F1B16),
          strokeWidth: strokeWidth ?? icon.strokeWidth,
        ),
      ),
    );
  }
}

/// A 24×24 icon: zero or more path strings plus zero or more circles.
@immutable
class SvgIcon {
  const SvgIcon(
    this.paths, {
    this.circles = const [],
    this.strokeWidth = 2,
    this.filled = false,
  });

  final List<String> paths;
  final List<SvgCircle> circles;
  final double strokeWidth;
  final bool filled;
}

@immutable
class SvgCircle {
  const SvgCircle(this.cx, this.cy, this.r);
  final double cx, cy, r;
}

class _StrokeIconPainter extends CustomPainter {
  _StrokeIconPainter({
    required this.icon,
    required this.color,
    required this.strokeWidth,
  });

  final SvgIcon icon;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 24.0;
    canvas.save();
    canvas.scale(scale);

    final paint = Paint()
      ..color = color
      ..style = icon.filled ? PaintingStyle.fill : PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    for (final d in icon.paths) {
      canvas.drawPath(SvgPath.parse(d), paint);
    }
    for (final c in icon.circles) {
      canvas.drawCircle(Offset(c.cx, c.cy), c.r, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StrokeIconPainter old) =>
      old.icon != icon || old.color != color || old.strokeWidth != strokeWidth;
}

/// Minimal SVG path-data parser covering the commands used by this icon set:
/// M/m, L/l, H/h, V/v, C/c, S/s, Q/q, T/t, A/a and Z/z.
abstract final class SvgPath {
  static final Map<String, Path> _cache = {};

  static Path parse(String d) => _cache.putIfAbsent(d, () => _parse(d));

  static Path _parse(String d) {
    final path = Path();
    final tokens = _tokenize(d);

    var current = Offset.zero;
    var start = Offset.zero;
    Offset? lastCubicControl;
    Offset? lastQuadControl;
    var i = 0;
    var command = '';

    double num() => tokens[i++] as double;

    while (i < tokens.length) {
      final token = tokens[i];
      if (token is String) {
        command = token;
        i++;
      } else if (command == 'M') {
        // Repeated coordinate pairs after a moveto are implicit linetos.
        command = 'L';
      } else if (command == 'm') {
        command = 'l';
      }

      final relative = command == command.toLowerCase();
      final origin = relative ? current : Offset.zero;

      switch (command.toUpperCase()) {
        case 'M':
          current = Offset(num() + origin.dx, num() + origin.dy);
          start = current;
          path.moveTo(current.dx, current.dy);
          lastCubicControl = lastQuadControl = null;
        case 'L':
          current = Offset(num() + origin.dx, num() + origin.dy);
          path.lineTo(current.dx, current.dy);
          lastCubicControl = lastQuadControl = null;
        case 'H':
          current = Offset(num() + origin.dx, current.dy);
          path.lineTo(current.dx, current.dy);
          lastCubicControl = lastQuadControl = null;
        case 'V':
          current = Offset(current.dx, num() + origin.dy);
          path.lineTo(current.dx, current.dy);
          lastCubicControl = lastQuadControl = null;
        case 'C':
          final c1 = Offset(num() + origin.dx, num() + origin.dy);
          final c2 = Offset(num() + origin.dx, num() + origin.dy);
          current = Offset(num() + origin.dx, num() + origin.dy);
          path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, current.dx, current.dy);
          lastCubicControl = c2;
          lastQuadControl = null;
        case 'S':
          final c1 = lastCubicControl == null
              ? current
              : current * 2 - lastCubicControl;
          final c2 = Offset(num() + origin.dx, num() + origin.dy);
          current = Offset(num() + origin.dx, num() + origin.dy);
          path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, current.dx, current.dy);
          lastCubicControl = c2;
          lastQuadControl = null;
        case 'Q':
          final c = Offset(num() + origin.dx, num() + origin.dy);
          current = Offset(num() + origin.dx, num() + origin.dy);
          path.quadraticBezierTo(c.dx, c.dy, current.dx, current.dy);
          lastQuadControl = c;
          lastCubicControl = null;
        case 'T':
          final c =
              lastQuadControl == null ? current : current * 2 - lastQuadControl;
          current = Offset(num() + origin.dx, num() + origin.dy);
          path.quadraticBezierTo(c.dx, c.dy, current.dx, current.dy);
          lastQuadControl = c;
          lastCubicControl = null;
        case 'A':
          final rx = num();
          final ry = num();
          final rotation = num();
          final largeArc = num() != 0;
          final sweep = num() != 0;
          current = Offset(num() + origin.dx, num() + origin.dy);
          path.arcToPoint(
            current,
            radius: Radius.elliptical(rx, ry),
            // Both SVG and Flutter measure this in degrees, clockwise, and
            // SVG's sweep-flag maps straight onto Flutter's `clockwise`.
            rotation: rotation,
            largeArc: largeArc,
            clockwise: sweep,
          );
          lastCubicControl = lastQuadControl = null;
        case 'Z':
          path.close();
          current = start;
          lastCubicControl = lastQuadControl = null;
        default:
          // Unknown command: bail out rather than loop forever.
          return path;
      }
    }
    return path;
  }

  /// Splits path data into command letters and numbers. Handles the compact
  /// forms SVG allows: no separator before a `-`, and `.5.5` meaning `.5 .5`.
  static List<Object> _tokenize(String d) {
    final out = <Object>[];
    final buffer = StringBuffer();

    void flush() {
      if (buffer.isEmpty) return;
      out.add(double.parse(buffer.toString()));
      buffer.clear();
    }

    for (var i = 0; i < d.length; i++) {
      final ch = d[i];
      final code = ch.codeUnitAt(0);
      final isDigit = code >= 0x30 && code <= 0x39;

      if (isDigit) {
        buffer.write(ch);
      } else if (ch == '.') {
        // A second '.' starts a new number: "1.5.5" → 1.5, .5
        if (buffer.toString().contains('.')) flush();
        buffer.write(ch);
      } else if (ch == '-' || ch == '+') {
        // A sign mid-number is an exponent sign; otherwise it starts a number.
        final soFar = buffer.toString();
        if (soFar.isNotEmpty && !soFar.endsWith('e') && !soFar.endsWith('E')) {
          flush();
        }
        buffer.write(ch);
      } else if (ch == 'e' || ch == 'E') {
        if (buffer.isEmpty) {
          flush();
          out.add(ch);
        } else {
          buffer.write(ch);
        }
      } else if (ch == ' ' || ch == ',' || ch == '\n' || ch == '\t' || ch == '\r') {
        flush();
      } else {
        flush();
        out.add(ch);
      }
    }
    flush();
    return out;
  }
}
