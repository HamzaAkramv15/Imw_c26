import 'package:flutter/material.dart';


class RoutePainter extends CustomPainter {
  RoutePainter({
    required this.points,
    required this.mapSize,
    this.animationValue = 1.0,
    this.widthScale = 1.0,
    this.showStart = true,
    this.showEnd = true,
    required this.line,
    required this.casing,
    required this.dot,
  });

  /// Palette colours: the route line, the outline that separates it from the
  /// map, and the start / end markers.
  final Color line;
  final Color casing;
  final Color dot;

  final List<Offset> points;
  final Size mapSize;
  final double animationValue;

  /// Multiply every stroke by this. The canvas passes `1 / zoom` so the line
  /// keeps the same thickness on screen while you pinch in and out.
  final double widthScale;
  final bool showStart;
  final bool showEnd;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2 || mapSize == Size.zero) return;
    final k = widthScale;

    final abs = [
      for (final p in points) Offset(p.dx * mapSize.width, p.dy * mapSize.height),
    ];

    final totalLen = _totalLength(abs);
    final drawLen = totalLen * animationValue.clamp(0.0, 1.0);
    final path = Path()..moveTo(abs[0].dx, abs[0].dy);
    double drawn = 0;
    for (int i = 1; i < abs.length; i++) {
      final prev = abs[i - 1];
      final curr = abs[i];
      final seg = (curr - prev).distance;
      if (drawn + seg <= drawLen) {
        path.lineTo(curr.dx, curr.dy);
        drawn += seg;
      } else {
        final t = seg == 0 ? 0.0 : (drawLen - drawn) / seg;
        path.lineTo(prev.dx + (curr.dx - prev.dx) * t, prev.dy + (curr.dy - prev.dy) * t);
        break;
      }
    }

    Paint stroke(Color c, double w, {double blur = 0}) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * k
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = blur > 0 ? MaskFilter.blur(BlurStyle.normal, blur * k) : null;

    canvas.drawPath(path, stroke(line.withValues(alpha: 0.16), 15)); // soft halo (no blur: far cheaper per frame)
    canvas.drawPath(path, stroke(casing.withValues(alpha: 0.9), 8)); // contrast underlay
    canvas.drawPath(path, stroke(line, 5)); // main line
    canvas.drawPath(path, stroke(casing, 1.4)); // centre highlight

    if (showStart) _dot(canvas, abs.first, dot, 9 * k);
    if (showEnd && animationValue >= 0.999) _dot(canvas, abs.last, dot, 11 * k);
  }

  void _dot(Canvas canvas, Offset o, Color c, double radius) {
    canvas.drawCircle(o, radius + 2 * widthScale, Paint()..color = casing.withValues(alpha: 0.5));
    canvas.drawCircle(o, radius, Paint()..color = c);
    canvas.drawCircle(o, radius * 0.4, Paint()..color = casing);
  }

  double _totalLength(List<Offset> pts) {
    double t = 0;
    for (int i = 1; i < pts.length; i++) {
      t += (pts[i] - pts[i - 1]).distance;
    }
    return t;
  }

  @override
  bool shouldRepaint(covariant RoutePainter old) =>
      old.animationValue != animationValue ||
      old.points != points ||
      old.mapSize != mapSize ||
      old.widthScale != widthScale ||
      old.line != line;
}
