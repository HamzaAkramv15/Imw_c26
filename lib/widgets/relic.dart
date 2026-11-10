import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme.dart';
import 'glyphs.dart';

// ═══════════════════════════════════════════════════════════════
//  "A relic of something much bigger."
//
//  The museum plan is drawn as one fragment cut from a vast temple wall:
//   * around it, the wall goes on — courses of sandstone blocks, columns of
//     hieroglyph-like carving, pyramids on the horizon, a sun disc (day) or
//     a star-filled Giza night (dark mode);
//   * the plan sits on a chipped slab whose rim carries a carved frieze
//     (ankh · eye of Horus · djed · lotus · scarab).
//  The wall is static (painted once and cached), the slab is baked into one
//  bitmap — neither costs anything while you pan and zoom.
// ═══════════════════════════════════════════════════════════════

/// Width (map units) of the carved band around the plan.
const double kSlabBand = 38;

/// Extra stone beyond the band, ragged edge included.
const double kSlabMargin = 30;

/// Total outset of the slab from the artwork bounds.
const double kSlabOutset = kSlabBand + kSlabMargin;

// ── the scene behind everything (screen space, static) ────────────
//
//  Day: papyrus sky, a haloed sun, sandstone pyramids with a lit and a shaded
//  face, dunes, palms, and a carved pillar at each edge.
//  Night: warm black sky, gold moon and stars, gold-lit pyramids, palms.
//  Painted once inside a RepaintBoundary; gradients only (no blur filters), so
//  it costs nothing while the plan is panned or zoomed.
class RelicBackdropPainter extends CustomPainter {
  const RelicBackdropPainter(this.pal);
  final GemPalette pal;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final dark = pal.dark;
    final w = size.width, h = size.height;

    // sky
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, h),
          dark
              ? const [Color(0xff070605), Color(0xff14100b), Color(0xff1d160d), Color(0xff0e0c09)]
              : const [Color(0xffe9d6ac), Color(0xfff5e8c9), Color(0xfff1e0b8), Color(0xffe3cc9a)],
          const [0, .38, .7, 1],
        ),
    );

    // sun / moon with halo
    final sun = Offset(w * .62, h * .17);
    final haloColor = dark ? const Color(0xffd9ac5a) : const Color(0xffffe7a8);
    canvas.drawCircle(
      sun,
      w * .55,
      Paint()
        ..shader = ui.Gradient.radial(sun, w * .55, [haloColor.withValues(alpha: dark ? .20 : .55), haloColor.withValues(alpha: 0)]),
    );
    canvas.drawCircle(sun, w * .075, Paint()..color = (dark ? const Color(0xffe8cf93) : const Color(0xfffff4cf)).withValues(alpha: dark ? .85 : .95));

    if (dark) {
      final r = math.Random(7);
      final star = Paint();
      for (var i = 0; i < 90; i++) {
        final x = r.nextDouble() * w, y = r.nextDouble() * h * .45;
        star.color = const Color(0xffefe3c0).withValues(alpha: .10 + r.nextDouble() * .35);
        canvas.drawCircle(Offset(x, y), .5 + r.nextDouble() * 1.0, star);
      }
    } else {
      // long soft cloud streaks
      final cl = Paint()..color = Colors.white.withValues(alpha: .28);
      final r = math.Random(3);
      for (var i = 0; i < 7; i++) {
        final cx = r.nextDouble() * w, cy = h * (.05 + r.nextDouble() * .30);
        canvas.drawOval(Rect.fromCenter(center: Offset(cx, cy), width: w * (.35 + r.nextDouble() * .4), height: 7 + r.nextDouble() * 9), cl);
      }
    }

    // papyrus fibre: faint horizontal courses, so the whole screen reads as one aged sheet
    final fibre = Paint()
      ..color = (dark ? Colors.white : const Color(0xff6b5a34)).withValues(alpha: dark ? .025 : .05)
      ..strokeWidth = 1;
    for (var y = 6.0; y < h; y += 23) {
      canvas.drawLine(Offset(0, y), Offset(w, y + (y % 7) - 3), fibre);
    }

    // pyramids on the horizon (far set, mid set), each with a lit and a shaded face
    final horizon = h * .43;
    void pyramid(double cx, double bw, double ph, double baseY, double haze) {
      final apex = Offset(cx, baseY - ph);
      final lit = (dark ? const Color(0xffb9904a) : const Color(0xffe2c48a));
      final shade = (dark ? const Color(0xff3a2c18) : const Color(0xffbf9f66));
      canvas.drawPath(Path()..moveTo(cx - bw / 2, baseY)..lineTo(apex.dx, apex.dy)..lineTo(cx + bw * .08, baseY)..close(), Paint()..color = Color.lerp(lit, pal.paper, haze)!.withValues(alpha: dark ? .55 : .9));
      canvas.drawPath(Path()..moveTo(apex.dx, apex.dy)..lineTo(cx + bw / 2, baseY)..lineTo(cx + bw * .08, baseY)..close(), Paint()..color = Color.lerp(shade, pal.paper, haze)!.withValues(alpha: dark ? .70 : .9));
      // masonry courses on the lit face
      final course = Paint()
        ..color = (dark ? Colors.black : const Color(0xff7a643a)).withValues(alpha: dark ? .18 : .12)
        ..strokeWidth = 1;
      for (var i = 1; i < 9; i++) {
        final t = i / 9;
        final y = apex.dy + (baseY - apex.dy) * t;
        final lx = apex.dx - (bw / 2) * t, rx = apex.dx + bw * .08 * t;
        canvas.drawLine(Offset(lx, y), Offset(rx, y), course);
      }
    }

    pyramid(w * .20, w * .46, h * .15, horizon, .35);
    pyramid(w * .70, w * .74, h * .26, horizon + 2, 0);
    pyramid(w * .46, w * .30, h * .10, horizon, .5);

    // dunes in front of the pyramids
    Path dune(double y0, double a1, double a2) => Path()
      ..moveTo(0, y0)
      ..cubicTo(w * .25, y0 - a1, w * .55, y0 + a2, w, y0 - a1 * .4)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(dune(horizon + 4, 26, 18), Paint()..color = (dark ? const Color(0xff1a140c) : const Color(0xffe2c995)).withValues(alpha: dark ? .95 : .85));
    canvas.drawPath(dune(h * .90, 30, 22), Paint()..color = (dark ? const Color(0xff120e08) : const Color(0xffd6b97d)).withValues(alpha: .9));

    // palms: right of the horizon, and both bottom corners
    final palmColor = dark ? const Color(0xff2a2013) : const Color(0xff7a6a3a);
    _palm(canvas, Offset(w * .93, horizon + 6), h * .13, palmColor.withValues(alpha: dark ? .9 : .75), -.18);
    _palm(canvas, Offset(w * .86, horizon + 12), h * .09, palmColor.withValues(alpha: dark ? .8 : .6), .12);
    _palm(canvas, Offset(w * .05, h * .98), h * .17, palmColor, .16);
    _palm(canvas, Offset(w * .13, h * 1.0), h * .11, palmColor.withValues(alpha: .85), -.1);
    _palm(canvas, Offset(w * .96, h * .99), h * .15, palmColor, -.14);

    // columns of carving near both edges
    _column(canvas, size, 14, dark);
    _column(canvas, size, size.width - 14, dark);

    // vignette: pulls the eye to the plan
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          rect.center,
          size.longestSide * .78,
          [const Color(0x00000000), dark ? const Color(0xaa000000) : const Color(0x303d2f12)],
          const [.55, 1],
        ),
    );
  }

  /// A palm: leaning trunk and a crown of curved, tapering leaves.
  void _palm(Canvas canvas, Offset base, double height, Color color, double lean) {
    final top = base + Offset(height * lean, -height);
    final trunk = Path()
      ..moveTo(base.dx - 3, base.dy)
      ..quadraticBezierTo(base.dx + height * lean * .1, base.dy - height * .55, top.dx - 1.6, top.dy)
      ..lineTo(top.dx + 1.6, top.dy)
      ..quadraticBezierTo(base.dx + height * lean * .1 + 6, base.dy - height * .55, base.dx + 3, base.dy)
      ..close();
    canvas.drawPath(trunk, Paint()..color = color);
    final leaf = Paint()..color = color;
    for (var i = 0; i < 9; i++) {
      final a = -math.pi * (.08 + i * .105); // fan across the top
      final len = height * (.42 + (i.isEven ? .06 : -.02));
      final tip = top + Offset(math.cos(a) * len, math.sin(a) * len * .8 + len * .30);
      final mid = top + Offset(math.cos(a) * len * .55, math.sin(a) * len * .95 - len * .08);
      final n = Offset(-math.sin(a), math.cos(a)) * (len * .07);
      canvas.drawPath(
        Path()
          ..moveTo(top.dx, top.dy)
          ..quadraticBezierTo(mid.dx + n.dx, mid.dy + n.dy, tip.dx, tip.dy)
          ..quadraticBezierTo(mid.dx - n.dx, mid.dy - n.dy, top.dx, top.dy)
          ..close(),
        leaf,
      );
    }
  }

  void _column(Canvas canvas, Size size, double x, bool dark) {
    final p = Paint()
      ..color = (dark ? const Color(0xffd9ac5a) : const Color(0xff7a643a)).withValues(alpha: dark ? .14 : .20)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    const order = ['ankh', 'djed', 'wedjat', 'scarab', 'cobra', 'shen', 'sun', 'lotus', 'feather', 'neb'];
    var i = 0;
    for (var y = 36.0; y < size.height - 36; y += 38, i++) {
      canvas.save();
      canvas.translate(x, y);
      paintGlyph(canvas, order[i % order.length], 22, p.color, pen: 1.3);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant RelicBackdropPainter old) => old.pal != pal;
}

// ── the slab: baked once into a bitmap ────────────────────────────

/// The chipped stone slab that carries the plan, covering [mapBounds] grown by
/// [kSlabOutset] on every side. The artwork bitmap is drawn on top of its
/// middle; only the band and margin show.
///
/// Returned image is [pixelRatio] pixels per map unit.
Future<ui.Image> buildRelicSlab({required Rect mapBounds, required GemPalette pal, required double pixelRatio, required int seed, required bool arabic}) {
  final outer = mapBounds.inflate(kSlabOutset);
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.scale(pixelRatio);
  c.translate(-outer.left, -outer.top);

  final dark = pal.dark;
  final slab = _rag(outer.deflate(6), seed, 11);

  // soft contact shadow (blur-free: stacked translucent copies)
  for (var i = 4; i >= 1; i--) {
    c.drawPath(slab.shift(Offset(0, i * 3.0)), Paint()..color = Colors.black.withValues(alpha: dark ? .12 : .045));
  }
  // stone body with a slow gradient (light falls from the top-left)
  c.drawPath(
    slab,
    Paint()
      ..shader = ui.Gradient.linear(
        outer.topLeft,
        outer.bottomRight,
        dark ? const [Color(0xff2a2218), Color(0xff1b150d)] : const [Color(0xfff1e2bd), Color(0xffdcc592)],
      ),
  );
  c.drawPath(
    slab,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = (dark ? const Color(0xff8a6a30) : const Color(0xffb28538)).withValues(alpha: .9),
  );

  // weathering: hairline cracks and chips
  final r = math.Random(seed);
  final crack = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = .9
    ..strokeCap = StrokeCap.round
    ..color = (dark ? Colors.black : const Color(0xff7a643a)).withValues(alpha: dark ? .35 : .22);
  for (var i = 0; i < 16; i++) {
    final edge = r.nextInt(4);
    final t = r.nextDouble();
    var p = switch (edge) {
      0 => Offset(outer.left + outer.width * t, outer.top + 8),
      1 => Offset(outer.right - 8, outer.top + outer.height * t),
      2 => Offset(outer.left + outer.width * t, outer.bottom - 8),
      _ => Offset(outer.left + 8, outer.top + outer.height * t),
    };
    final path = Path()..moveTo(p.dx, p.dy);
    final dir = switch (edge) { 0 => math.pi / 2, 1 => math.pi, 2 => -math.pi / 2, _ => 0.0 };
    final len = 14 + r.nextDouble() * 26;
    var a = dir;
    for (var s = 0; s < 4; s++) {
      a += (r.nextDouble() - .5) * .9;
      p = p + Offset(math.cos(a), math.sin(a)) * (len / 4);
      path.lineTo(p.dx, p.dy);
    }
    c.drawPath(path, crack);
  }

  // carved band: a groove on each side of the frieze, glyphs between them
  final inner = mapBounds.inflate(4); // just outside the artwork
  final bandOuter = mapBounds.inflate(kSlabBand);
  final groove = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.4
    ..color = (dark ? Colors.black : const Color(0xff6b5630)).withValues(alpha: dark ? .55 : .35);
  final lip = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1
    ..color = (dark ? Colors.white : Colors.white).withValues(alpha: dark ? .06 : .35);
  c.drawRect(inner, groove);
  c.drawRect(bandOuter, groove);
  c.drawRect(inner.shift(const Offset(.9, .9)), lip);
  c.drawRect(bandOuter.shift(const Offset(.9, .9)), lip);

  final glyph = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..color = (dark ? const Color(0xff8b939b) : const Color(0xff7a5f2a)).withValues(alpha: dark ? .62 : .72);
  const gs = 22.0, step = 42.0;
  final mid = (kSlabBand + 4) / 2 - 2; // centre line of the band, measured outward from the artwork
  void along(Offset a, Offset b, double inwardX, double inwardY, FriezeLine line) {
    final len = (b - a).distance;
    final n = (len / step).floor();
    final dir = (b - a) / len;
    for (var i = 0; i < n; i++) {
      final t = (i + .5) * (len / n);
      final pos = a + dir * t + Offset(inwardX, inwardY) * mid;
      c.save();
      c.translate(pos.dx, pos.dy);
      // each wish is read as a repeating phrase: the same signs, in order, again and again
      paintGlyph(c, line.signs[i % line.signs.length], gs, glyph.color, pen: 1.5);
      c.restore();
    }
  }

  final b = mapBounds;
  along(Offset(b.left, b.top), Offset(b.right, b.top), 0, -1, kFriezeTop);
  along(Offset(b.left, b.bottom), Offset(b.right, b.bottom), 0, 1, kFriezeBottom);
  along(Offset(b.left, b.top), Offset(b.left, b.bottom), -1, 0, kFriezeLeft);
  along(Offset(b.right, b.top), Offset(b.right, b.bottom), 1, 0, kFriezeRight);

  // the two engraved sentences, in the margin beyond the band
  void caption(String text, double cy) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: arabic ? 15 : 10.5, letterSpacing: arabic ? 0 : 2.4, fontWeight: FontWeight.w700, color: glyph.color.withValues(alpha: dark ? .55 : .62)),
      ),
      textDirection: arabic ? TextDirection.rtl : TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 1,
    )..layout(maxWidth: mapBounds.width);
    tp.paint(c, Offset(mapBounds.center.dx - tp.width / 2, cy - tp.height / 2));
  }

  final marginMid = kSlabBand + kSlabMargin / 2 + 2;
  caption(arabic ? kCaptionTopAr : kCaptionTopEn, mapBounds.top - marginMid);
  caption(arabic ? kCaptionBottomAr : kCaptionBottomEn, mapBounds.bottom + marginMid);

  // corner rosettes
  final ros = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.4
    ..color = glyph.color;
  for (final o in [b.topLeft, b.topRight, b.bottomLeft, b.bottomRight]) {
    final dx = o.dx == b.left ? -1.0 : 1.0, dy = o.dy == b.top ? -1.0 : 1.0;
    final cc = o + Offset(dx, dy) * (kSlabBand * .5);
    c.drawCircle(cc, 7, ros);
    c.drawCircle(cc, 2.4, Paint()..color = glyph.color);
  }

  final pic = rec.endRecording();
  final w = (outer.width * pixelRatio).ceil(), h = (outer.height * pixelRatio).ceil();
  return pic.toImage(w, h);
}

/// A rectangle whose edges are chipped like worn stone.
Path _rag(Rect r, int seed, double amp) {
  final rnd = math.Random(seed * 31 + 5);
  final pts = <Offset>[];
  void edge(Offset a, Offset b) {
    final len = (b - a).distance;
    final n = math.max(4, (len / 46).round());
    final nrm = Offset(-(b - a).dy, (b - a).dx) / len; // outward-ish normal (sign handled by amplitude)
    for (var i = 0; i < n; i++) {
      final t = i / n;
      final j = (rnd.nextDouble() - .5) * amp;
      final chip = rnd.nextDouble() < .12 ? -amp * .9 : 0.0;
      pts.add(Offset.lerp(a, b, t)! + nrm * (j + chip));
    }
  }

  edge(r.topLeft, r.topRight);
  edge(r.topRight, r.bottomRight);
  edge(r.bottomRight, r.bottomLeft);
  edge(r.bottomLeft, r.topLeft);
  return Path()..addPolygon(pts, true);
}
