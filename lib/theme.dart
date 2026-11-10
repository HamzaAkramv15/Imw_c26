import 'package:flutter/material.dart';

/// The six colours of the concept board. Everything else is derived from them.
abstract final class Stone {
  static const midnight = Color(0xff1b1f24); // Midnight Stone
  static const sand = Color(0xffede6d6); // Sand
  static const sage = Color(0xff7a8f7d); // Sage
  static const lavender = Color(0xffb7a7e6); // Lavender
  static const slate = Color(0xff6b7280); // Slate
  static const rose = Color(0xffd96b7e); // Rose
}

/// Brand colours used by the data files (eras, pins). They stay `const`;
/// anything that changes between light and dark comes from [GemPalette].
abstract final class GemColors {
  static const ivory = Stone.sand;
  static const map = Stone.sand;
  static const teal = Stone.sage; // era 1, shops, gardens
  static const ink = Stone.midnight;
  static const gold = Color(0xffd8bf86); // sand-gold: highlights, attractions
  static const slate = Stone.slate;
  static const muted = Color(0xff9a9f98);
  static const border = Color(0xff343a41);

  // new, used by the era list and pins
  static const lavender = Stone.lavender;
  static const rose = Stone.rose;
  static const sand = Stone.sand;
}

/// Every colour that differs between day and night, in one place.
@immutable
class GemPalette {
  const GemPalette({
    required this.dark,
    required this.bg,
    required this.surface,
    required this.surfaceHi,
    required this.glass,
    required this.ink,
    required this.muted,
    required this.line,
    required this.accent,
    required this.onAccent,
    required this.gold,
    required this.sage,
    required this.lavender,
    required this.rose,
    required this.route,
    required this.routeCase,
    required this.mapBg,
    required this.paper,
    required this.solid,
    required this.rim,
    required this.pinService,
    required this.shadow,
  });

  final bool dark;

  /// Scaffold / sheet background.
  final Color bg;

  /// Cards, pills, buttons that float over the map.
  final Color surface;

  /// A step above [surface] (chips, inputs, pressed states).
  final Color surfaceHi;

  /// Translucent surface for bars that sit over the map.
  final Color glass;

  /// Primary text and icons.
  final Color ink;
  final Color muted;

  /// Hairlines and borders.
  final Color line;

  /// Filled buttons, selected states.
  final Color accent;
  final Color onAccent;
  final Color gold;
  final Color sage;
  final Color lavender;
  final Color rose;

  /// Walking route line, and the thin outline that separates it from the map.
  final Color route;
  final Color routeCase;

  /// Empty space around the plan.
  final Color mapBg;

  /// Kept for older code: the colour the highlight veil fades to.
  final Color paper;

  /// Side faces of the 2.5D walls, and the highlight along their top edge.
  final Color solid;
  final Color rim;

  /// Background of service / parking / dark-era pins.
  final Color pinService;
  final Color shadow;

  static const night = GemPalette(
    dark: true,
    bg: Color(0xff14171b),
    surface: Color(0xff1b1f24),
    surfaceHi: Color(0xff262b32),
    glass: Color(0xe61b1f24),
    ink: Color(0xffede6d6),
    muted: Color(0xff9a9f98),
    line: Color(0xff343a41),
    accent: Color(0xff63806e), // the "Navigate here" button
    onAccent: Color(0xfff4f0e4),
    gold: Color(0xffd8bf86),
    sage: Color(0xff7a8f7d),
    lavender: Color(0xffb7a7e6),
    rose: Color(0xffd96b7e),
    route: Color(0xff5fd0b4),
    routeCase: Color(0xff0c1210),
    mapBg: Color(0xff101316),
    paper: Color(0xff14171b),
    solid: Color(0xff3a3f46),
    rim: Color(0xfff3ecda),
    pinService: Color(0xff4a515a),
    shadow: Color(0xff000000),
  );

  static const day = GemPalette(
    dark: false,
    bg: Color(0xffede6d6),
    surface: Color(0xfff7f2e6),
    surfaceHi: Color(0xffe3dac4),
    glass: Color(0xe6f7f2e6),
    ink: Color(0xff1b1f24),
    muted: Color(0xff6b7280),
    line: Color(0xffd2c8b0),
    accent: Color(0xff4f6b58),
    onAccent: Colors.white,
    gold: Color(0xff9c7a2c),
    sage: Color(0xff61796a),
    lavender: Color(0xff8b79c9),
    rose: Color(0xffc0485e),
    route: Color(0xff1f8f7b),
    routeCase: Color(0xfff7f2e6),
    mapBg: Color(0xffe4dcc8),
    paper: Color(0xffede6d6),
    solid: Color(0xffb9ae94),
    rim: Color(0xffffffff),
    pinService: Color(0xff1b1f24),
    shadow: Color(0xff382a0e),
  );

  /// Pin / chip colour for an era or accent that is [GemColors.ink] by
  /// default, which would vanish on the dark map.
  Color pin(Color c) => dark && c == GemColors.ink ? pinService : c;
}

extension GemContext on BuildContext {
  GemPalette get pal => Theme.of(this).brightness == Brightness.dark ? GemPalette.night : GemPalette.day;
}

abstract final class GemTheme {
  static ThemeData get light => _build(GemPalette.day, Brightness.light);
  static ThemeData get dark => _build(GemPalette.night, Brightness.dark);

  /// Kept so older code that read `GemTheme.data` still compiles.
  static ThemeData get data => dark;

  static ThemeData _build(GemPalette p, Brightness b) => ThemeData(
    brightness: b,
    scaffoldBackgroundColor: p.bg,
    canvasColor: p.bg,
    colorScheme: ColorScheme.fromSeed(seedColor: Stone.sage, brightness: b).copyWith(
      primary: p.accent,
      onPrimary: p.onAccent,
      surface: p.surface,
      onSurface: p.ink,
    ),
    dividerColor: p.line,
    splashFactory: InkSparkle.splashFactory,
    fontFamily: 'Georgia',
    useMaterial3: true,
  );
}
