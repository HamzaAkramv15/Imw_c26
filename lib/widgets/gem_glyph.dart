import 'package:flutter/material.dart';

import '../models/map_models.dart';

/// Draws one [PlaceGlyph] in a single colour.
///
/// Icons that exist in Material Icons use those; the ones that only exist on
/// the GEM map legends (palm, ankh, Eye of Horus, ticket "T") are drawn as
/// vectors on a 24×24 grid so they stay crisp at any zoom.
class GemGlyph extends StatelessWidget {
  const GemGlyph(this.glyph, {super.key, required this.color, this.size = 20});

  final PlaceGlyph glyph;
  final Color color;
  final double size;

  static const _material = <PlaceGlyph, IconData>{
    PlaceGlyph.arrowUp: Icons.arrow_upward_rounded,
    PlaceGlyph.star: Icons.star_rounded,
    PlaceGlyph.restroom: Icons.wc,
    PlaceGlyph.wheelchair: Icons.accessible,
    PlaceGlyph.headphones: Icons.headphones,
    PlaceGlyph.prayer: Icons.mosque,
    PlaceGlyph.lift: Icons.elevator,
    PlaceGlyph.info: Icons.info_outline_rounded,
    PlaceGlyph.atm: Icons.atm,
    PlaceGlyph.clinic: Icons.medical_services,
    PlaceGlyph.museum: Icons.museum_outlined,
    PlaceGlyph.gallery: Icons.account_balance,
    PlaceGlyph.food: Icons.restaurant,
    PlaceGlyph.bag: Icons.shopping_bag_outlined,
    PlaceGlyph.grid: Icons.grid_view,
    PlaceGlyph.coffee: Icons.coffee,
    PlaceGlyph.cake: Icons.cake,
    PlaceGlyph.iceCream: Icons.icecream,
    PlaceGlyph.bakery: Icons.bakery_dining,
    PlaceGlyph.cookie: Icons.cookie,
    PlaceGlyph.jewelry: Icons.diamond_outlined,
    PlaceGlyph.grocery: Icons.local_grocery_store,
    PlaceGlyph.store: Icons.storefront,
  };

  @override
  Widget build(BuildContext context) {
    final icon = _material[glyph];
    if (icon != null) return Icon(icon, color: color, size: size);

    if (glyph == PlaceGlyph.parking) {
      return SizedBox.square(
        dimension: size,
        child: FittedBox(
          child: Text(
            'P',
            style: TextStyle(
              color: color,
              fontFamily: 'Arial',
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
        ),
      );
    }

    return CustomPaint(
      size: Size.square(size),
      painter: _VectorGlyphPainter(glyph, color),
    );
  }
}

class _VectorGlyphPainter extends CustomPainter {
  const _VectorGlyphPainter(this.glyph, this.color);
  final PlaceGlyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 2;
    final fill = Paint()..color = color;

    switch (glyph) {
      case PlaceGlyph.palm:
        // trunk
        canvas.drawPath(
          Path()
            ..moveTo(12, 10)
            ..quadraticBezierTo(13.5, 16, 11.5, 22),
          stroke..strokeWidth = 2.2,
        );
        // five fronds
        stroke.strokeWidth = 1.9;
        for (final f in const [
          (Offset(7, 6), Offset(2, 10.5)),
          (Offset(9, 3), Offset(5, 4)),
          (Offset(12.5, 2), Offset(12.5, 1.5)),
          (Offset(15, 3), Offset(19, 4)),
          (Offset(17, 6), Offset(22, 10.5)),
        ]) {
          canvas.drawPath(
            Path()
              ..moveTo(12, 10)
              ..quadraticBezierTo(f.$1.dx, f.$1.dy, f.$2.dx, f.$2.dy),
            stroke,
          );
        }
        canvas.drawCircle(const Offset(10.6, 11.4), 1.1, fill);
        canvas.drawCircle(const Offset(13.4, 11.4), 1.1, fill);

      case PlaceGlyph.ankh:
        stroke.strokeWidth = 2.3;
        canvas.drawOval(
          Rect.fromCenter(
            center: const Offset(12, 7.2),
            width: 7.4,
            height: 8.8,
          ),
          stroke,
        );
        canvas.drawLine(const Offset(12, 11.6), const Offset(12, 22), stroke);
        canvas.drawLine(
          const Offset(6.2, 13.4),
          const Offset(17.8, 13.4),
          stroke,
        );

      case PlaceGlyph.eye:
        stroke.strokeWidth = 1.8;
        // eye outline
        canvas.drawPath(
          Path()
            ..moveTo(2, 11)
            ..quadraticBezierTo(12, 2.5, 22, 11)
            ..quadraticBezierTo(12, 17, 2, 11),
          stroke,
        );
        // eyebrow
        canvas.drawPath(
          Path()
            ..moveTo(4, 6.5)
            ..quadraticBezierTo(12, 0.5, 20, 6.5),
          stroke,
        );
        canvas.drawCircle(const Offset(12, 10.4), 2.4, fill);
        // tear + curl
        canvas.drawPath(
          Path()
            ..moveTo(12, 15)
            ..lineTo(12, 19.5)
            ..quadraticBezierTo(12, 22, 16.5, 21),
          stroke,
        );

      case PlaceGlyph.ticket:
        stroke.strokeWidth = 1.9;
        canvas.drawCircle(const Offset(12, 12), 9, stroke);
        stroke.strokeWidth = 2.4;
        canvas.drawLine(const Offset(7.6, 8), const Offset(16.4, 8), stroke);
        canvas.drawLine(const Offset(12, 8), const Offset(12, 17), stroke);

      default:
        break;
    }
  }

  @override
  bool shouldRepaint(_VectorGlyphPainter old) =>
      old.glyph != glyph || old.color != color;
}
