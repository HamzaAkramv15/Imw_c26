import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../i18n/strings.dart';
import '../models/map_models.dart';
import '../models/rostau.dart';
import '../theme.dart';
import 'place_badge.dart';

/// A pin's place in a walk being followed: its number (from 1) of [total],
/// whether it is done, the one to go to now, or still ahead, and whether the
/// walk ends there.
typedef PinStop = ({int number, int total, StopState state, bool last});

/// A tappable map marker: a drop-shaped pin (the tip is the exact spot), the
/// place's icon inside, a "pinned" bookmark dot, and a rose highlight when it
/// is selected or the destination of the route.
///
/// A stop of a walk also carries its number; a stop that is done fades and
/// shows a check, the one to go to now is the largest, rose, and labelled
/// "Next", and the last stop is flagged "End".
class MapPin extends StatelessWidget {
  const MapPin({
    super.key,
    required this.place,
    required this.isSelected,
    required this.isPinned,
    required this.onTap,
    this.isTarget = false,
    this.stop,
  });

  final MapPlace place;
  final bool isSelected;
  final bool isPinned;
  final bool isTarget;
  final PinStop? stop;
  final VoidCallback onTap;

  /// Diameter of the head, in logical pixels.
  static double sizeFor(MapPlace p) => p.category.isDense ? 28 : 34;

  @override
  Widget build(BuildContext context) {
    final d = sizeFor(place);
    final pal = context.pal;
    final st = stop?.state;
    final current = st == StopState.current, done = st == StopState.done;
    final hot = isSelected || isTarget || current;
    final color = hot ? pal.rose : PlaceBadge.background(place, pal);
    final scale = isSelected ? 1.3 : (current ? 1.25 : 1.0);

    Widget pin = SizedBox(
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
    );
    final s = stop;
    if (s != null) {
      final border = Border.all(color: pal.dark ? const Color(0xfff4efe2) : Colors.white, width: 1.5);
      pin = Stack(
        clipBehavior: Clip.none,
        children: [
          // a stop behind the visitor stays readable but steps back
          done ? Opacity(opacity: 0.45, child: pin) : pin,
          // its number, or a check once done
          Positioned(
            top: -5,
            left: -5,
            child: Container(
              width: 18,
              height: 18,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: done ? pal.accent : (current ? pal.ink : pal.surface),
                shape: BoxShape.circle,
                border: border,
              ),
              child: done
                  ? Icon(Icons.check, size: 12, color: pal.onAccent)
                  : Text(
                      '${s.number}',
                      style: TextStyle(fontFamily: 'Arial', fontSize: 10, fontWeight: FontWeight.w800, color: current ? pal.surface : pal.ink),
                    ),
            ),
          ),
          // "Next" over the stop to go to now, "End" over the last one
          if (current || (s.last && !done))
            Positioned(
              left: -60,
              right: -60,
              bottom: d * 1.32 + 3,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: current ? pal.rose : pal.ink,
                    borderRadius: BorderRadius.circular(9),
                    border: border,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (s.last) ...[
                        Icon(Icons.flag, size: 11, color: current ? Colors.white : pal.surface),
                        const SizedBox(width: 3),
                      ],
                      Text(
                        current ? (s.last ? '${S.t('stop_next')} · ${S.t('stop_end')}' : S.t('stop_next')) : S.t('stop_end'),
                        style: TextStyle(fontFamily: 'Arial', fontSize: 10, fontWeight: FontWeight.w800, color: current ? Colors.white : pal.surface),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    }

    return Semantics(
      label: s == null
          ? null
          : [
              S.t('stop_of', n: s.number, x: '${s.total}'),
              if (done) S.t('stop_visited'),
              if (current) S.t('stop_next'),
              if (s.last) S.t('stop_end'),
            ].join(', '),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedScale(
          scale: scale,
          alignment: Alignment.bottomCenter,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutBack,
          child: pin,
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
