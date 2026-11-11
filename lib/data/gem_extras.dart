import 'package:flutter/material.dart';

import '../models/map_models.dart';
import '../theme.dart';
import 'gem_map_data.dart';

// ─────────────────────────────────────────────────────────────────
//  Everything that sits ON TOP of gem_map_data.dart: scale, on-map
//  labels, eras. (Routing and portals: gem_nav.dart, generated.)
// ─────────────────────────────────────────────────────────────────

/// Per-map facts. `mpp` = metres per SVG unit.
///
/// ⚠ ESTIMATES. Calibrate by measuring one real distance on each map
/// (e.g. walk the ticket gate → main entrance), then set
/// mpp = real metres / distance in map units. Only the distances and
/// walking times depend on it — routes are correct regardless.
typedef MapMeta = ({int level, double mpp});
const Map<String, MapMeta> kMapMeta = {
  'gem_complex': (level: 0, mpp: 1.1),
  'main_building': (level: 0, mpp: 0.28),
  'main_galleries': (level: 3, mpp: 0.2),
  'tutankhamun': (level: 3, mpp: 0.12),
};

extension GemMapMeta on GemMap {
  int get level => kMapMeta[id]?.level ?? 0;
  double get metersPerPixel => kMapMeta[id]?.mpp ?? 1.0;
}

// ── lookups across all maps ──────────────────────────────────────
final Map<String, MapPlace> _placeIndex = {
  for (final m in allMaps.values)
    for (final p in m.places) p.id: p,
};
final Map<String, String> _placeMap = {
  for (final m in allMaps.values)
    for (final p in m.places) p.id: m.id,
};

MapPlace? placeById(String id) => _placeIndex[id];
String? mapIdOfPlace(String id) => _placeMap[id];
Iterable<MapPlace> get allPlaces => _placeIndex.values;

/// Maps that are OUTSIDE (a door that leads to one of them is an exit).
const Set<String> kOutdoorMaps = {'gem_complex'};

/// Maps that are halls inside another map: no tab of their own, opened from
/// a pin on their parent map, with a "back" pill.
const Map<String, String> kSubMapParent = {'tutankhamun': 'main_galleries'};

/// Where the artwork actually is inside each map (the SVG canvases have empty margins).
const Map<String, Rect> kContentBounds = {
  'gem_complex': Rect.fromLTRB(0.0000, 0.0000, 0.9978, 0.9972),
  'main_building': Rect.fromLTRB(0.0000, 0.0000, 1.0000, 1.0000),
  'main_galleries': Rect.fromLTRB(0.0000, 0.0000, 0.9200, 1.0000),
  'tutankhamun': Rect.fromLTRB(0.0065, 0.0094, 0.9928, 0.9896),
};

/// Object photos (from the PDF), shown in the detail sheet.
const Map<String, String> kPlaceImage = {
  'tg_boat': 'assets/artifacts/boat.webp',
  'tg_shrine': 'assets/artifacts/shrine.webp',
  'tg_vase': 'assets/artifacts/vase.webp',
  'tg_bowl': 'assets/artifacts/bowl.webp',
  'tg_coffin_a': 'assets/artifacts/coffin_a.webp',
  'tg_coffin_b': 'assets/artifacts/coffin_b.webp',
  'tg_coffin_c': 'assets/artifacts/coffin_c.webp',
  'tg_mask': 'assets/artifacts/mask.webp',
  'tg_throne': 'assets/artifacts/throne.webp',
};

// ── on-map text (was baked into the PNGs) ────────────────────────
Offset _px(double x, double y, double w, double h) => Offset(x / w, y / h);

final Map<String, List<MapLabel>> kLabels = {
  'gem_complex': [
    MapLabel('Cairo - Alexandria Desert Road', _px(360, 1046, 1790, 1080), style: LabelStyle.road, rotation: 0.4),
    MapLabel('Cairo - Alexandria Desert Road', _px(975, 1043, 1790, 1080), style: LabelStyle.road, rotation: -0.5),
    MapLabel('Ring Road', _px(1522, 925, 1790, 1080), style: LabelStyle.road, rotation: -57),
    MapLabel('Giza Pyramids', _px(257, 668, 1790, 1080)),
  ],
  'main_building': [
    MapLabel('Main Entrance', _px(940, 700, 1625, 885)),
  ],
  'main_galleries': [
    MapLabel('Beliefs', _px(1323, 144, 1400, 1080), style: LabelStyle.theme),
    MapLabel('Kingship', _px(1158, 471, 1400, 1080), style: LabelStyle.theme),
    MapLabel('Society', _px(1178, 707, 1400, 1080), style: LabelStyle.theme),
    MapLabel('Exit', _px(925, 869, 1400, 1080)),
  ],
  'tutankhamun': [],
};

// ── gallery eras (timeline bar + region colours) ─────────────────
/// Names are translated by id (S.era).
typedef Era = ({String id, String range, String galleries, Color color});
const List<Era> kEras = [
  (id: 'era1', range: '700,000 – 2034 BC', galleries: '01–03', color: GemColors.teal),
  (id: 'era2', range: '2034 – 1550 BC', galleries: '04–06', color: GemColors.slate),
  (id: 'era3', range: '1550 – 1069 BC', galleries: '07–09', color: GemColors.gold),
  (id: 'era4', range: '1069 BC – 394 AD', galleries: '10–12', color: GemColors.ink),
];
