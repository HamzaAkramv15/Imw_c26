import 'package:flutter/material.dart';

import '../models/map_models.dart';
import '../theme.dart';
import 'gem_glyph.dart';

/// The marker artwork for a place, in the new palette:
///
/// * gallery     – round, era colour (sage / lavender / rose / sand), number
/// * attraction  – sand-gold square, star, number on top
/// * food        – clay square, white icon
/// * shop        – sage square, white icon
/// * service     – slate square, white icon (information desk: gold, dark icon)
/// * parking     – slate square, white "P"
/// * garden      – deep sage square, palm
/// * entrance    – lavender square, dark arrow / ticket
///
/// Used by the map pins, the detail sheet and the search list, so a place
/// looks the same everywhere. [bare] draws only the icon (no background):
/// the map pin supplies its own drop-shaped background.
class PlaceBadge extends StatelessWidget {
  const PlaceBadge({super.key, required this.place, this.size = 28, this.bare = false, this.hot = false});

  final MapPlace place;
  final double size;
  final bool bare;

  /// Selected / destination: drawn in rose.
  final bool hot;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final bg = hot ? pal.rose : background(place, pal);
    final fg = hot ? Colors.white : foreground(place, pal);
    if (bare) {
      return SizedBox(width: size, height: size, child: Center(child: _content(fg)));
    }
    final circle = place.category == PlaceCategory.gallery;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(size * 0.26),
      ),
      child: _content(fg),
    );
  }

  Widget _content(Color fg) {
    switch (place.category) {
      case PlaceCategory.gallery:
        return Text(
          place.number ?? '',
          style: TextStyle(color: fg, fontSize: size * 0.4, fontWeight: FontWeight.w800, fontStyle: FontStyle.italic, height: 1),
        );
      case PlaceCategory.attraction:
        return Stack(
          alignment: Alignment.center,
          children: [
            GemGlyph(PlaceGlyph.star, color: Colors.white, size: size * 0.92),
            Padding(
              padding: EdgeInsets.only(top: size * 0.04),
              child: Text(
                place.number ?? '',
                style: TextStyle(color: Stone.midnight, fontSize: size * ((place.number ?? '').length > 1 ? 0.28 : 0.34), fontWeight: FontWeight.w800, height: 1),
              ),
            ),
          ],
        );
      default:
        return GemGlyph(place.effectiveGlyph, color: fg, size: size * 0.62);
    }
  }

  static bool _isInfo(MapPlace p) => p.category == PlaceCategory.facility && p.effectiveGlyph == PlaceGlyph.info;

  static Color background(MapPlace p, GemPalette pal) => switch (p.category) {
    PlaceCategory.gallery => pal.pin(p.accent ?? GemColors.ink),
    PlaceCategory.attraction => GemColors.gold,
    PlaceCategory.restaurant => const Color(0xffb85c49),
    PlaceCategory.shop => pal.dark ? const Color(0xff6f8a78) : const Color(0xff5c7766),
    PlaceCategory.facility when _isInfo(p) => GemColors.gold,
    PlaceCategory.facility || PlaceCategory.parking => pal.pinService,
    PlaceCategory.garden => pal.dark ? const Color(0xff55705f) : const Color(0xff4d6657),
    PlaceCategory.entrance => pal.dark ? Stone.lavender : const Color(0xff7a68b8),
    PlaceCategory.building => GemColors.gold,
  };

  static Color foreground(MapPlace p, GemPalette pal) {
    final bg = background(p, pal);
    if (p.category == PlaceCategory.attraction) return Colors.white;
    if (_isInfo(p) || p.category == PlaceCategory.building) return Stone.midnight;
    return bg.computeLuminance() > 0.45 ? Stone.midnight : Colors.white;
  }
}
