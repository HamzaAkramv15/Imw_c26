import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/map_models.dart';
import '../theme.dart';
import 'place_badge.dart';

/// A tappable map marker: a drop-shaped pin (the tip is the exact spot), the
/// place's icon inside, a "pinned" bookmark dot, and a rose highlight when it
/// is selected or the destination of the route.
class MapPin extends StatelessWidget {
  const MapPin({
    super.key,
    required this.place,
    required this.isSelected,
    required this.isPinned,
    required this.onTap,
    this.isTarget = false,
  });

  final MapPlace place;
  final bool isSelected;
  final bool isPinned;
  final bool isTarget;
  final VoidCallback onTap;

  /// Diameter of the head, in logical pixels.
  static double sizeFor(MapPlace p) => p.category.isDense ? 28 : 34;

  @override
  Widget build(BuildContext context) {
    final d = sizeFor(place);
    final pal = context.pal;
    final hot = isSelected || isTarget;
    final color = hot ? pal.rose : PlaceBadge.background(place, pal);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedScale(
        scale: isSelected ? 1.3 : 1,
        alignment: Alignment.bottomCenter,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutBack,
        child: SizedBox(
          width: d,
          height: d * 1.32,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // contact shadow where the tip touches the plan
              Positioned(
                left: d * 0.22,
                right: d * 0.22,
                bottom: -2,
                height: 6,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.38), borderRadius: BorderRadius.circular(6)),
                ),
              ),
              Positioned.fill(
                child: CustomPaint(
                  painter: _DropPainter(
                    color: color,
                    border: pal.dark ? const Color(0xfff4efe2) : Colors.white,
                    glow: hot ? pal.rose : null,
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                width: d,
                height: d,
                child: PlaceBadge(place: place, size: d, bare: true, hot: hot),
              ),
              if (isPinned)
                Positioned(
                  top: -3,
                  right: -3,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(color: pal.gold, shape: BoxShape.circle, border: Border.all(color: pal.bg, width: 1.5)),
                    child: const Icon(Icons.bookmark, color: Colors.black87, size: 8),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DropPainter extends CustomPainter {
  const _DropPainter({required this.color, required this.border, this.glow});
  final Color color;
  final Color border;
  final Color? glow;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height, r = w / 2;
    final head = Offset(r, r);
    final path = Path()
      ..moveTo(r, h)
      ..cubicTo(r - r * 0.18, h - r * 0.6, 0, r * 1.25, 0, r)
      ..arcTo(Rect.fromCircle(center: head, radius: r), math.pi, math.pi, false)
      ..cubicTo(w, r * 1.25, r + r * 0.18, h - r * 0.6, r, h)
      ..close();
    if (glow != null) {
      canvas.drawPath(path, Paint()..color = glow!.withValues(alpha: 0.35)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7));
    }
    canvas.drawPath(path.shift(const Offset(0, 1.5)), Paint()..color = Colors.black.withValues(alpha: 0.28));
    canvas.drawPath(path, Paint()..color = color);
    canvas.drawPath(
      path,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_DropPainter old) => old.color != color || old.border != border || old.glow != glow;
}
