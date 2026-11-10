import 'package:flutter/material.dart';

import '../models/map_models.dart';
import '../theme.dart';
import 'gem_map_data.dart';

// ─────────────────────────────────────────────────────────────────
//  Everything that sits ON TOP of gem_map_data.dart: floors, links
//  between maps, on-map labels, Arabic names, scale. Edit freely.
// ─────────────────────────────────────────────────────────────────

/// Per-map facts. `mpp` = metres per SVG unit.
///
/// ⚠ ESTIMATES. Calibrate by measuring one real distance on each map
/// (e.g. walk the ticket gate → main entrance), then set
/// mpp = real metres / distance in map units. Only the distances and
/// walking times depend on it — routes are correct regardless.
typedef MapMeta = ({int level, String tag, String tagAr, double mpp});
const Map<String, MapMeta> kMapMeta = {
  'gem_complex': (level: 0, tag: 'Site', tagAr: 'الموقع', mpp: 1.1),
  'main_building': (level: 0, tag: 'Ground', tagAr: 'الأرضي', mpp: 0.28),
  'main_galleries': (level: 3, tag: 'Level 3', tagAr: 'الدور 3', mpp: 0.2),
  'tutankhamun': (level: 3, tag: 'Level 3', tagAr: 'الدور 3', mpp: 0.12),
};

extension GemMapMeta on GemMap {
  int get level => kMapMeta[id]?.level ?? 0;
  String get levelTag => kMapMeta[id]?.tag ?? '';
  String get levelTagAr => kMapMeta[id]?.tagAr ?? '';
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

/// `gem://at/mb_entrance`, `gem:mb_entrance` or just `mb_entrance` → place id.
/// Hook for QR codes stuck on walls: scan → [placeIdFromCode] → "I'm here".
String? placeIdFromCode(String raw) {
  final s = raw.trim();
  final m = RegExp(r'^(?:gem://at/|gem:)?([A-Za-z0-9_]+)$').firstMatch(s);
  final id = m?.group(1);
  return (id != null && _placeIndex.containsKey(id)) ? id : null;
}

// ── links between maps ───────────────────────────────────────────
const List<Portal> kPortals = [
  // outside → inside
  Portal('jc_door', 'mb_entrance', PortalKind.door, meters: 25),
  // Grand Stairs / lifts up to the 3rd-floor galleries
  Portal('jb_sA', 'mg_entrance', PortalKind.stairs, meters: 140),
  Portal('mb_lift1', 'mg_entrance', PortalKind.lift, meters: 70),
  // The Tutankhamun Galleries are a hall INSIDE the Main Galleries: you walk
  // to its doorway on the galleries plan, then step into its own plan.
  Portal('mg_tut', 'tg_entrance', PortalKind.door, meters: 15),
  Portal('mg_tut', 'tg_exit', PortalKind.door, meters: 15),
  // attractions drawn on the ground plan but located on upper floors
  Portal('mb_lift1', 'mb_6', PortalKind.lift, meters: 40),
  Portal('mb_lift1', 'mb_7', PortalKind.lift, meters: 40),
  Portal('mb_lift1', 'mb_8', PortalKind.lift, meters: 40),
  Portal('mb_lift1', 'mb_9', PortalKind.lift, meters: 55),
];

/// Edges of the ground-plan graph that are flights of the Grand Stairs.
/// (The lowest stretch, jb_sA → jb_sB, is the ground-level foot of the
/// stairs where the Senwosret I statues stand, so it stays step-free.)
const Set<String> kStairEdges = {
  'jb_lM|jb_sC',
  'jb_gB|jb_sC',
  'jb_gA|jb_sC',
  'jb_h6|jb_sB',
  'jb_h3|jb_sD',
  'jb_h2|jb_uC',
  'jb_lL|jb_sD',
  'jb_h5|jb_sC',
  'jb_lM|jb_uA',
  'jb_sA|jb_uC',
  'jb_sB|jb_uA',
  'jb_sC|jb_uA',
  'jb_sB|jb_sC',
  'jb_sC|jb_sD',
  'jb_sD|jb_sE',
};

/// "Route to X" really means "route to Y" (the pin is only a pointer to
/// another map).
const Map<String, String> kRouteRedirects = {
  'mb_10': 'mg_tut',
  'mb_11': 'mg_entrance',
};

/// Maps that are OUTSIDE (a door that leads to one of them is an exit).
const Set<String> kOutdoorMaps = {'gem_complex'};

/// Maps that are halls inside another map: no tab of their own, opened from
/// a pin on their parent map, with a "back" pill.
const Map<String, String> kSubMapParent = {'tutankhamun': 'main_galleries'};

/// Which floor a place is on, when it isn't the floor of its map.
const Map<String, int> kPlaceFloor = {
  'mb_6': 1,
  'mb_7': 1,
  'mb_8': 1,
  'mb_9': 2,
  'mb_10': 3,
  'mg_tut': 3,
  'mb_11': 3,
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
    MapLabel('Cairo - Alexandria Desert Road', 'طريق القاهرة - الإسكندرية الصحراوي', _px(360, 1046, 1790, 1080), style: LabelStyle.road, rotation: 0.4),
    MapLabel('Cairo - Alexandria Desert Road', 'طريق القاهرة - الإسكندرية الصحراوي', _px(975, 1043, 1790, 1080), style: LabelStyle.road, rotation: -0.5),
    MapLabel('Ring Road', 'الطريق الدائري', _px(1522, 925, 1790, 1080), style: LabelStyle.road, rotation: -57),
    MapLabel('Giza Pyramids', 'أهرامات الجيزة', _px(257, 668, 1790, 1080)),
  ],
  'main_building': [
    MapLabel('Main Entrance', 'المدخل الرئيسي', _px(940, 700, 1625, 885)),
  ],
  'main_galleries': [
    MapLabel('Beliefs', 'المعتقدات', _px(1323, 144, 1400, 1080), style: LabelStyle.theme),
    MapLabel('Kingship', 'الملكية', _px(1158, 471, 1400, 1080), style: LabelStyle.theme),
    MapLabel('Society', 'المجتمع', _px(1178, 707, 1400, 1080), style: LabelStyle.theme),
    MapLabel('Exit', 'المخرج', _px(925, 869, 1400, 1080)),
  ],
  'tutankhamun': [],
};

// ── gallery eras (timeline bar + region colours) ─────────────────
typedef Era = ({String id, String name, String nameAr, String range, String galleries, Color color});
const List<Era> kEras = [
  (id: 'era1', name: 'Prehistoric – Old Kingdom', nameAr: 'ما قبل التاريخ – الدولة القديمة', range: '700,000 – 2034 BC', galleries: '01–03', color: GemColors.teal),
  (id: 'era2', name: 'Middle Kingdom', nameAr: 'الدولة الوسطى', range: '2034 – 1550 BC', galleries: '04–06', color: GemColors.slate),
  (id: 'era3', name: 'New Kingdom', nameAr: 'الدولة الحديثة', range: '1550 – 1069 BC', galleries: '07–09', color: GemColors.gold),
  (id: 'era4', name: 'Late & Graeco-Roman', nameAr: 'العصر المتأخر واليوناني الروماني', range: '1069 BC – 394 AD', galleries: '10–12', color: GemColors.ink),
];

Color regionAccent(MapRegion r) {
  for (final e in kEras) {
    if (e.id == r.group) return e.color;
  }
  return switch (r.kind) {
    RegionKind.parking => GemColors.ink,
    RegionKind.garden => GemColors.teal,
    RegionKind.hall || RegionKind.zone => GemColors.gold,
    _ => GemColors.teal,
  };
}

// ── Arabic (names are looked up by their English text) ───────────
const Map<String, String> kArByName = {
  'Ticketing & Entrance': 'التذاكر والمدخل',
  'Main Building': 'المبنى الرئيسي',
  'Hanging Obelisk': 'المسلة المعلقة',
  'Events Area': 'منطقة الفعاليات',
  "Khufu's Boats Museum": 'متحف مراكب خوفو',
  'Pyramids Steps': 'درج الأهرامات',
  'Conservation Centre': 'مركز الترميم',
  'Sculpture Garden': 'حديقة التماثيل',
  'Palm Garden': 'حديقة النخيل',
  'Terraced Gardens': 'الحدائق المتدرجة',
  'West Garden': 'الحديقة الغربية',
  'East Garden': 'الحديقة الشرقية',
  'Main Parking': 'الموقف الرئيسي',
  'Main Entrance': 'المدخل الرئيسي',
  'Entrance': 'المدخل',
  'Exit': 'المخرج',
  'Colossal Statue of Ramesses II': 'تمثال رمسيس الثاني الضخم',
  'Victory Column of Merenpetah': 'عمود النصر لمرنبتاح',
  'Ptolemaic King and Queen Statues': 'تمثالا الملك والملكة البطلميان',
  'Senwosret I Statues': 'تماثيل سنوسرت الأول',
  'Ramesses II Statue (San El-Hagar)': 'تمثال رمسيس الثاني (صان الحجر)',
  'Temporary Exhibition': 'المعرض المؤقت',
  'Mixed Reality Hall': 'قاعة الواقع المختلط',
  "Children's Museum": 'متحف الطفل',
  'Tutankhamun Galleries': 'قاعات توت عنخ آمون',
  'Main Galleries': 'قاعات العرض الرئيسية',
  'Clinic': 'العيادة',
  'Restroom': 'دورات المياه',
  'Prayer Room': 'المصلى',
  'Lift': 'مصعد',
  'Wheelchair Access': 'إتاحة الكراسي المتحركة',
  'GEM Gift Shop': 'متجر هدايا المتحف',
  'ATM': 'ماكينة صراف آلي',
  'GEM Artspace': 'مساحة فنية',
  'Tour Earphones Desk': 'مكتب سماعات الجولة',
  'Information Desk': 'مكتب الاستعلامات',
  'Model boat': 'نموذج مركب',
  'Gilded shrine': 'مقصورة مذهبة',
  'Alabaster vase': 'مزهرية من المرمر',
  'Stone bowl': 'وعاء حجري',
  'Coffin 1': 'التابوت 1',
  'Coffin 2': 'التابوت 2',
  'Coffin 3': 'التابوت 3',
  'Golden funerary mask': 'القناع الذهبي',
  'Golden throne': 'العرش الذهبي',
  // regions
  'Grand Stairs': 'الدرج الكبير',
  'Grand Hall': 'القاعة الكبرى',
  'Glass Hall': 'القاعة الزجاجية',
  'Lifestyle': 'أسلوب الحياة',
  'Discovery': 'الاكتشاف',
  'Funeral': 'الجنازة',
  'Funeral (start)': 'الجنازة (البداية)',
  'Identity': 'الهوية',
  'Reception': 'الاستقبال',
  'Society': 'المجتمع',
  'Kingship': 'الملكية',
  'Beliefs': 'المعتقدات',
};

const Map<String, String> kArCategory = {
  'Gallery': 'قاعة عرض',
  'Attraction': 'معلم',
  'Food': 'مطاعم ومقاهٍ',
  'Retail shop': 'متجر',
  'Service': 'خدمة',
  'Parking': 'موقف سيارات',
  'Garden': 'حديقة',
  'Building': 'مبنى',
  'Entrance': 'مدخل',
  'Galleries': 'قاعات العرض',
  'Attractions': 'المعالم',
  'Shops': 'المتاجر',
  'Services': 'الخدمات',
  'Gardens': 'الحدائق',
  'Buildings': 'المباني',
  'Entrances': 'المداخل',
};

const Map<String, String> kArChip = {
  '1st Floor': 'الدور الأول',
  '2nd Floor': 'الدور الثاني',
  '3rd Floor': 'الدور الثالث',
  'Grand Hall': 'القاعة الكبرى',
  'Upper Floors': 'الأدوار العليا',
  'Grand Stairs': 'الدرج الكبير',
  'Glass Hall': 'القاعة الزجاجية',
  'Society': 'المجتمع',
  'Kingship': 'الملكية',
  'Beliefs': 'المعتقدات',
  'Open floor plan': 'مخطط مفتوح',
  'Lifestyle': 'أسلوب الحياة',
  'Discovery': 'الاكتشاف',
  'Funeral': 'الجنازة',
  'Funeral (start)': 'الجنازة (البداية)',
  'Identity': 'الهوية',
};
