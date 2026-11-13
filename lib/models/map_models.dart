import 'package:flutter/material.dart';

/// Even-odd test: whether [p] lies inside [poly].
bool pointInPolygon(Offset p, List<Offset> poly) {
  var inside = false;
  for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    final a = poly[i], b = poly[j];
    if ((a.dy > p.dy) != (b.dy > p.dy) && p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx) {
      inside = !inside;
    }
  }
  return inside;
}

/// Every kind of marker that appears on the GEM maps.
enum PlaceCategory {
  gallery,
  attraction,
  restaurant,
  shop,
  facility,
  parking,
  garden,
  building,
  entrance,
}

/// Icons used on the maps. Drawn by `GemGlyph` (widgets/gem_glyph.dart).
enum PlaceGlyph {
  // markers from the map legends
  ticket,
  arrowUp,
  palm,
  parking,
  star,
  // services
  restroom,
  wheelchair,
  headphones,
  prayer,
  lift,
  info,
  atm,
  clinic,
  ankh, // GEM Gift Shop
  eye, // GEM Artspace
  // food & shops (picked by name, see kNameGlyphs)
  coffee,
  cake,
  iceCream,
  bakery,
  cookie,
  jewelry,
  grocery,
  store,
  // UI only
  museum,
  gallery,
  food,
  bag,
  grid,
}

extension PlaceCategoryX on PlaceCategory {
  // Names: S.category / S.filter (lib/i18n), in every language.

  /// Icon used when a place doesn't set its own `glyph`.
  PlaceGlyph get glyph => switch (this) {
    PlaceCategory.gallery => PlaceGlyph.gallery,
    PlaceCategory.attraction => PlaceGlyph.star,
    PlaceCategory.restaurant => PlaceGlyph.food,
    PlaceCategory.shop => PlaceGlyph.bag,
    PlaceCategory.facility => PlaceGlyph.info,
    PlaceCategory.parking => PlaceGlyph.parking,
    PlaceCategory.garden => PlaceGlyph.palm,
    PlaceCategory.building => PlaceGlyph.museum,
    PlaceCategory.entrance => PlaceGlyph.arrowUp,
  };

  /// Crowded categories: smaller pins, only shown once the map is zoomed in
  /// (or when their filter is active).
  bool get isDense =>
      this == PlaceCategory.restaurant ||
      this == PlaceCategory.shop ||
      this == PlaceCategory.facility;

  /// Categories that get a filter pill, in display order.
  static const filterable = [
    PlaceCategory.gallery,
    PlaceCategory.attraction,
    PlaceCategory.restaurant,
    PlaceCategory.shop,
    PlaceCategory.facility,
    PlaceCategory.garden,
    PlaceCategory.parking,
  ];
}

/// Icon per restaurant / shop, so the map shows WHAT it is, not a number.
const Map<String, PlaceGlyph> kNameGlyphs = {
  'Zooba': PlaceGlyph.food,
  'Bittersweet': PlaceGlyph.cake,
  'Ladurée': PlaceGlyph.bakery,
  '30 North': PlaceGlyph.coffee,
  'Starbucks': PlaceGlyph.coffee,
  'Dolato': PlaceGlyph.iceCream,
  "Beano's": PlaceGlyph.coffee,
  'Mandarin Koueider': PlaceGlyph.cookie,
  'Okhtein': PlaceGlyph.bag,
  'Dima': PlaceGlyph.store,
  'Kahhal Looms': PlaceGlyph.store,
  'Atef Wassef': PlaceGlyph.store,
  'Nakhla': PlaceGlyph.store,
  'Azza Fahmy': PlaceGlyph.jewelry,
  'Nuniz': PlaceGlyph.store,
  'Premium Mart': PlaceGlyph.grocery,
  'Nefertari': PlaceGlyph.store,
};

@immutable
class MapPlace {
  const MapPlace({
    required this.id,
    required this.name,
    required this.position,
    required this.category,
    this.number,
    this.glyph,
    this.accent,
    this.description,
    this.chips = const [],
    this.linkedMapId,
  });

  final String id;
  final String name;

  /// Normalised (0..1) position on the map.
  final Offset position;
  final PlaceCategory category;

  /// The number printed on the pin (gallery 01, attraction 7, shop 3 …).
  final String? number;

  /// Overrides the category's default icon.
  final PlaceGlyph? glyph;

  /// Pin colour override (used for the four gallery eras).
  final Color? accent;
  final String? description;
  final List<String> chips;

  /// Opens another map from the detail sheet.
  final String? linkedMapId;

  PlaceGlyph get effectiveGlyph => glyph ?? kNameGlyphs[name] ?? category.glyph;
}

@immutable
class GemMap {
  const GemMap({
    required this.id,
    required this.title,
    required this.shortTitle,
    required this.asset,
    required this.imageSize,
    required this.places,
    required this.entranceId,
  });

  final String id;
  final String title;
  final String shortTitle;

  /// Path of the vector map (`assets/maps/dark/*.svg`, recoloured at load time).
  /// Its viewBox is exactly [imageSize], so every coordinate can be read
  /// straight off the artwork. (`assets/maps/light/` holds the original plan
  /// colours; only the tools read those.)
  final String asset;

  /// Size of the SVG viewBox in its own units (same numbers the PNGs had).
  final Size imageSize;
  final List<MapPlace> places;
  final String entranceId;


  MapPlace? placeById(String id) {
    for (final p in places) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Categories present on this map, in filter-pill order.
  List<PlaceCategory> get categories => [
    for (final c in PlaceCategoryX.filterable)
      if (places.any((p) => p.category == c)) c,
  ];
}

// ═══════════════════════════════════════════════════════════════
//  Regions: areas you can tap, highlight and fade the map around
// ═══════════════════════════════════════════════════════════════

enum RegionKind { garden, building, parking, attraction, hall, gallery, zone }

@immutable
class MapRegion {
  const MapRegion({
    required this.id,
    required this.mapId,
    required this.name,
    required this.kind,
    required this.points,
    required this.labelAt,
    this.placeId,
    this.group,
    this.showLabel = true,
  });

  final String id;
  final String mapId;
  final String name;
  final RegionKind kind;

  /// Polygon, normalised (0..1) like [MapPlace.position].
  final List<Offset> points;
  final Offset labelAt;

  /// The place this region belongs to (tapping the region opens that place).
  final String? placeId;

  /// Free grouping key: `era1`..`era4` for galleries, `zone` for exhibition zones.
  final String? group;
  final bool showLabel;

  bool contains(Offset p) => pointInPolygon(p, points);

  double get area {
    var s = 0.0;
    for (var i = 0, j = points.length - 1; i < points.length; j = i++) {
      s += points[j].dx * points[i].dy - points[i].dx * points[j].dy;
    }
    return s.abs() / 2;
  }

  Path toPath(Size size) {
    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = points[i].dx * size.width, y = points[i].dy * size.height;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    return path..close();
  }
}

// ═══════════════════════════════════════════════════════════════
//  Labels that used to be baked into the PNGs
// ═══════════════════════════════════════════════════════════════

enum LabelStyle { road, theme, note }

@immutable
class MapLabel {
  const MapLabel(
    this.text,
    this.position, {
    this.style = LabelStyle.note,
    this.rotation = 0,
    this.minZoom = 0,
  });
  /// English text; translated by name (S.label).
  final String text;
  final Offset position;
  final LabelStyle style;

  /// Degrees, clockwise.
  final double rotation;

  /// Only shown once the map is zoomed in this far (1 = fitted to screen).
  final double minZoom;
}

// ═══════════════════════════════════════════════════════════════
//  Navigation: the walkable graph (generated, lib/data/gem_nav.dart),
//  doors, and the portals that join maps and levels
// ═══════════════════════════════════════════════════════════════

/// A routing node: a place (on the floor in front of its pin), a door or a waypoint.
@immutable
class NavNode {
  const NavNode(this.mapId, this.position);
  final String mapId;

  /// Normalised (0..1) position on [mapId].
  final Offset position;
}

/// A walkable connection between two nodes of one map, laid along the floor.
@immutable
class NavEdge {
  const NavEdge(this.a, this.b, this.via, {this.stairs = false});
  final String a;
  final String b;

  /// Bend points from [a] to [b], normalised.
  final List<Offset> via;

  /// Climbs treads drawn on the plan (never part of a step-free route).
  final bool stairs;
}

/// What an opening in a wall is, as far as the plan shows.
///   door: a doorway in a wall;  passage: a stretch the plan leaves without a wall.
enum DoorKind { door, passage }

/// A doorway: a gap in a wall that routes pass through. [a]–[b] spans the
/// opening (normalised). `verified: false` marks an opening the plan does not
/// draw, placed where the plan's aisles meet the wall. The walls (drawn and in
/// the routing grid) are open within half of |a - b| of its centre.
@immutable
class MapDoor {
  const MapDoor(this.id, this.mapId, this.a, this.b, {this.kind = DoorKind.door, this.verified = true});
  final String id;
  final String mapId;
  final Offset a;
  final Offset b;
  final DoorKind kind;
  final bool verified;

  Offset get center => Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
}

/// How a portal is crossed. A travelator is the moving walkway beside the
/// Grand Staircase.
enum PortalKind { door, stairs, lift, travelator }

@immutable
class Portal {
  const Portal(this.a, this.b, this.kind, {this.meters = 30, this.stepFreeVerified = true});

  /// Node ids (places or doors) on each side. May be on different maps.
  final String a;
  final String b;
  final PortalKind kind;

  /// Walking length of the link (stairs are further penalised by the router).
  final double meters;

  /// False when no reliable source confirms wheelchair use (the travelator):
  /// such a portal is left out of step-free routes.
  final bool stepFreeVerified;

  /// Usable on a step-free (wheelchair) route.
  bool get stepFree => kind != PortalKind.stairs && stepFreeVerified;
}
