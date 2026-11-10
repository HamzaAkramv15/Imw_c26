import 'dart:ui';

import 'package:flutter/painting.dart';

/// Hieroglyph-inspired signs, drawn on a 100 x 100 box.
/// Path syntax (absolute only): M x y · L x y · C x1 y1 x2 y2 x y · Q x1 y1 x y · Z · O cx cy r (circle).
/// A part is (filled?, path). The same data is previewed by tools/glyphs.py.
const Map<String, List<(bool, String)>> kGlyphs = {
  'ankh': <(bool, String)>[(false, 'M50 6 C 76 6 76 50 50 50 C 24 50 24 6 50 6 Z'),(false, 'M50 50 L50 96'),(false, 'M22 62 L78 62')],
  'djed': <(bool, String)>[(false, 'M50 8 L50 92'),(false, 'M34 8 L66 8'),(false, 'M30 22 L70 22'),(false, 'M30 36 L70 36'),(false, 'M34 50 L66 50'),(false, 'M26 92 L74 92')],
  'was': <(bool, String)>[(false, 'M50 24 L50 78'),(false, 'M50 78 L36 96'),(false, 'M50 78 L64 96'),(false, 'M50 24 C50 10 36 6 30 14'),(false, 'M50 24 L66 8'),(false, 'M30 14 L24 22')],
  'wedjat': <(bool, String)>[(false, 'M6 46 C26 26 58 26 80 44 C60 58 28 60 6 46 Z'),(true, 'O 44 44 8'),(false, 'M12 30 C34 12 62 12 84 28'),(false, 'M80 44 L94 50'),(false, 'M42 58 L42 76 C42 90 28 92 20 84'),(false, 'M58 56 L64 74 C68 84 82 86 86 78 C90 70 78 64 72 70')],
  'shen': <(bool, String)>[(false, 'M50 14 C84 14 84 78 50 78 C16 78 16 14 50 14 Z'),(false, 'M24 86 L76 86'),(false, 'M50 78 L50 86')],
  'scarab': <(bool, String)>[(false, 'M50 26 C72 26 80 52 72 74 C66 90 34 90 28 74 C20 52 28 26 50 26 Z'),(false, 'M38 26 C42 12 58 12 62 26'),(false, 'M30 44 C14 34 4 46 8 62'),(false, 'M70 44 C86 34 96 46 92 62'),(false, 'M50 26 L50 86'),(false, 'M32 62 L14 76'),(false, 'M68 62 L86 76'),(false, 'M33 50 L16 54'),(false, 'M67 50 L84 54')],
  'neb': <(bool, String)>[(false, 'M12 40 L88 40'),(false, 'M12 40 C16 84 84 84 88 40'),(false, 'M50 40 L50 78')],
  'cobra': <(bool, String)>[(false, 'M40 10 C26 12 24 34 38 48 L62 48 C76 34 74 12 60 10 C54 6 46 6 40 10 Z'),(false, 'M50 48 C34 64 72 70 58 84 C50 94 30 92 18 86'),(true, 'O 44 22 2.5'),(true, 'O 56 22 2.5')],
  'sun': <(bool, String)>[(false, 'O 50 50 22'),(true, 'O 50 50 7'),(false, 'M50 8 L50 20 M50 80 L50 92 M8 50 L20 50 M80 50 L92 50 M20 20 L28 28 M80 20 L72 28 M20 80 L28 72 M80 80 L72 72')],
  'lotus': <(bool, String)>[(false, 'M50 90 C26 80 18 50 32 20 C44 36 48 62 50 90 Z'),(false, 'M50 90 C74 80 82 50 68 20 C56 36 52 62 50 90 Z'),(false, 'M50 90 C36 62 36 30 50 8 C64 30 64 62 50 90 Z'),(false, 'M28 94 L72 94')],
  'feather': <(bool, String)>[(false, 'M50 6 C70 24 70 60 50 80'),(false, 'M50 6 C30 24 30 60 50 80'),(false, 'M50 6 L50 96'),(false, 'M50 30 L66 22 M50 44 L67 36 M50 58 L64 52 M50 30 L34 22 M50 44 L33 36 M50 58 L36 52')],
  'bread': <(bool, String)>[(false, 'M14 74 C14 40 86 40 86 74 Z'),(false, 'M34 74 L34 54 M66 74 L66 54')],
};

/// What each sign meant to the ancient Egyptians (used by the carvings sheet).
const Map<String, List<String>> kGlyphMeaning = {
  'ankh': ['Life', 'الحياة'],
  'djed': ['Stability', 'الثبات'],
  'wedjat': ['Prosperity & health (Eye of Horus)', 'الازدهار والصحة (عين حورس)'],
  'was': ['Power & dominion', 'القوة والسلطان'],
  'scarab': ['Rebirth (Khepri, the rising sun)', 'البعث والتجدد (خبري، شمس الفجر)'],
  'lotus': ['Creation & rebirth', 'الخلق والتجدد'],
  'feather': ['Truth & balance (Maat)', 'الحقيقة والعدل (ماعت)'],
  'cobra': ['Forever (djet)', 'إلى الأبد (جت)'],
  'shen': ['Eternity & protection', 'الخلود والحماية'],
  'sun': ['The eternal cycle (neheh)', 'دورة الأبد (نحح)'],
  'neb': ['All, every, lord', 'كل، جميع، سيّد'],
  'bread': ['Offering', 'قربان'],
};

/// One wish carved along each side of the slab, as a sequence of signs.
class FriezeLine {
  const FriezeLine(this.signs, this.en, this.ar);
  final List<String> signs;
  final String en;
  final String ar;
}

const FriezeLine kFriezeTop = FriezeLine(['ankh', 'djed', 'wedjat'], 'Life · Stability · Prosperity & Health', 'الحياة · الثبات · الازدهار والصحة');
const FriezeLine kFriezeRight = FriezeLine(['scarab', 'lotus', 'feather'], 'Rebirth · Creation · Truth', 'البعث · الخلق · الحق');
const FriezeLine kFriezeBottom = FriezeLine(['cobra', 'shen', 'sun'], 'Forever and ever', 'إلى الأبد وما بعد الأبد');
const FriezeLine kFriezeLeft = FriezeLine(['ankh', 'neb', 'cobra'], 'Given life, for all eternity', 'مُنِحَ الحياة لكل الأبد');

/// The two sentences engraved in the slab margins.
const String kCaptionTopEn = 'MAY YOU BE GIVEN LIFE, STABILITY, PROSPERITY AND HEALTH';
const String kCaptionTopAr = 'مُنِحتَ الحياةَ والثباتَ والازدهارَ والصحةَ';
const String kCaptionBottomEn = 'FOREVER AND EVER · GIVEN EVERLASTING LIFE FOR ALL ETERNITY';
const String kCaptionBottomAr = 'إلى الأبد وما بعد الأبد · مُنِحَ الحياة الخالدة لكل الأبد';

final Map<String, List<(bool, Path)>> _cache = {};

List<(bool, Path)> _parts(String key) => _cache.putIfAbsent(key, () {
  final glyph = kGlyphs[key];
  if (glyph == null) {
    return const <(bool, Path)>[];
  }

  final out = <(bool, Path)>[];
  for (final (bool fill, String d) in glyph) {
    out.add((fill, _parse(d)));
  }
  return out;
});

Path _parse(String d) {
  final tok = RegExp(r'[MLCQZO]|-?\d+(?:\.\d+)?').allMatches(d).map((m) => m.group(0)!).toList();
  final p = Path();
  var i = 0;
  double n() => double.parse(tok[i++]);
  while (i < tok.length) {
    switch (tok[i++]) {
      case 'M':
        p.moveTo(n(), n());
      case 'L':
        p.lineTo(n(), n());
      case 'C':
        p.cubicTo(n(), n(), n(), n(), n(), n());
      case 'Q':
        p.quadraticBezierTo(n(), n(), n(), n());
      case 'Z':
        p.close();
      case 'O':
        final cx = n(), cy = n(), r = n();
        p.addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r));
    }
  }
  return p;
}

/// Draws sign [key] centred on the origin, fitting an [s] x [s] box, with the
/// pen width [pen] given in the same units as [s].
void paintGlyph(Canvas c, String key, double s, Color color, {double pen = 1.5}) {
  final k = s / 100;
  c.save();
  c.scale(k);
  c.translate(-50, -50);
  final stroke = Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..strokeWidth = pen / k;
  final fill = Paint()..color = color;
  for (final (f, path) in _parts(key)) {
    c.drawPath(path, f ? fill : stroke);
  }
  c.restore();
}
