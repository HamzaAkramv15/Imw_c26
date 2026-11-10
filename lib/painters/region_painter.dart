import 'package:flutter/material.dart';

import '../data/gem_extras.dart';
import '../models/map_models.dart';

/// Precomputed (once per selection, NOT per frame) shapes for [RegionPainter].
/// `Path.combine` is expensive, so the canvas builds this when the highlighted
/// set changes and reuses it while you pan and zoom.
class RegionFocus {
  RegionFocus(this.regions, this.veil, this.paths);
  final List<MapRegion> regions;
  final Path? veil;
  final Map<String, Path> paths;

  static RegionFocus build(List<MapRegion> all, Set<String> highlighted, String? selectedId, Size size) {
    final focus = [for (final r in all) if (r.id == selectedId || highlighted.contains(r.id)) r];
    if (focus.isEmpty) return RegionFocus(const [], null, const {});
    final paths = {for (final r in focus) r.id: r.toPath(size)};
    final union = Path();
    for (final p in paths.values) {
      union.addPath(p, Offset.zero);
    }
    final full = Path()..addRect(Offset.zero & size);
    return RegionFocus(focus, Path.combine(PathOperation.difference, full, union), paths);
  }
}

/// Paints region highlights over the vector map. When something is
/// highlighted or selected, everything else is veiled so the eye goes there.
class RegionPainter extends CustomPainter {
  RegionPainter({
    required this.focus,
    required this.selectedId,
    required this.hairline,
    required this.veil,
    this.debugRegions = const [],
  });

  final RegionFocus focus;
  final String? selectedId;

  /// `1 / zoom`: multiply pixel widths by this to get constant on-screen width.
  final double hairline;
  final List<MapRegion> debugRegions;

  /// Colour that fades everything except the highlighted regions.
  final Color veil;

  @override
  void paint(Canvas canvas, Size size) {
    if (focus.veil != null) {
      canvas.drawPath(focus.veil!, Paint()..color = veil.withValues(alpha: 0.62));
      for (final r in focus.regions) {
        final accent = regionAccent(r);
        final sel = r.id == selectedId;
        final path = focus.paths[r.id]!;
        canvas.drawPath(path, Paint()..color = accent.withValues(alpha: sel ? 0.34 : 0.26));
        canvas.drawPath(
          path,
          Paint()
            ..color = accent
            ..style = PaintingStyle.stroke
            ..strokeJoin = StrokeJoin.round
            ..strokeWidth = (sel ? 3.2 : 2.2) * hairline,
        );
      }
    }
    for (final r in debugRegions) {
      canvas.drawPath(
        r.toPath(size),
        Paint()
          ..color = Colors.red.withValues(alpha: .7)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 * hairline,
      );
    }
  }

  @override
  bool shouldRepaint(covariant RegionPainter old) =>
      old.focus != focus || old.selectedId != selectedId || old.hairline != hairline || old.veil != veil || old.debugRegions != debugRegions;
}
