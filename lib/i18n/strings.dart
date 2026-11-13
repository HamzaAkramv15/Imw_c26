import '../data/gem_extras.dart';
import '../data/gem_map_data.dart';
import '../data/gem_regions.dart';
import '../models/map_models.dart';
import '../services/route_finder.dart';
import '../state/app_state.dart';
import 'lang.dart';
import 'translations.dart';

/// All user-visible text, in the language chosen in the settings.
/// English is the source of truth: anything without a translation falls back
/// to English, so nothing ever shows blank (test/i18n_test.dart keeps the
/// tables complete).
class S {
  S._();

  static AppLang get lang => AppState.instance.lang;

  /// Right-to-left (Arabic).
  static bool get rtl => lang.rtl;

  static String _pick(List<String>? row, AppLang l) {
    if (row == null) return '';
    final s = row[l.index];
    return s.isEmpty ? row[0] : s;
  }

  /// Letter-spacing for small capitals: none for Arabic (it would break the
  /// joined letters) or for Japanese, Korean and Chinese.
  static double tracking(double v) => rtl || lang.cjk ? 0 : v;

  static String t(String key, {String? x, int? n}) {
    final row = kUi[key];
    var s = row == null ? key : _pick(row, lang);
    if (x != null) s = s.replaceAll('{x}', x);
    if (n != null) s = s.replaceAll('{n}', '$n');
    return s;
  }

  /// "1 stop" / "3 stops" ([key] has a `{key}_one` row for the singular).
  static String count(String key, int n) {
    if (lang == AppLang.ar) {
      // Arabic has a dual, and plural forms for 3–10; the table row holds the
      // form used from 11 on ("11 محطة"), and _one the singular
      final forms = _arCounts[key];
      if (forms != null && n == 2) return forms.$1;
      if (forms != null && n >= 3 && n <= 10) return forms.$2.replaceAll('{n}', '$n');
    }
    return n == 1 && kUi.containsKey('${key}_one') ? t('${key}_one') : t(key, n: n);
  }

  /// Arabic counted nouns: (dual, 3–10).
  static const Map<String, (String, String)> _arCounts = {
    'stops': ('محطتان', '{n} محطات'),
    'results_n': ('نتيجتان', '{n} نتائج'),
  };

  // ── names ──────────────────────────────────────────────────────
  /// A place, hall or label name in [l] (search needs every language at once).
  static String nameIn(String en, AppLang l) {
    final row = kNames[en];
    if (row != null) return _pick(row, l);
    final g = RegExp(r'^Gallery (\d+)( \(second hall\))?$').firstMatch(en);
    if (g != null) {
      return _pick(kNamePatterns[g.group(2) == null ? 'gallery' : 'gallery_second'], l).replaceAll('{n}', g.group(1)!);
    }
    final p = RegExp(r'^Parking (P\d)$').firstMatch(en);
    if (p != null) return _pick(kNamePatterns['parking'], l).replaceAll('{n}', p.group(1)!);
    return en; // brand names (shops, cafés) read the same in every language
  }

  static String name(String en) => nameIn(en, lang);
  static String place(MapPlace p) => name(p.name);
  static String region(MapRegion r) => name(r.name);
  static String placeId(String id) {
    final p = placeById(id);
    return p == null ? t('your_location') : place(p);
  }

  /// Name of any routing node: a place by name, anything else as "Your location".
  static String nodeName(String id) => placeId(id);

  static String regionId(String id) {
    for (final r in kRegions) {
      if (r.id == id) return region(r);
    }
    return '';
  }

  static String category(PlaceCategory c) => t('cat_${c.name}');
  static String filter(PlaceCategory c) => t('cats_${c.name}');

  /// Every language's words for a category (for search).
  static String categoryAll(PlaceCategory c) => [
    for (final l in AppLang.values) ...[_pick(kUi['cat_${c.name}'], l), _pick(kUi['cats_${c.name}'], l)],
  ].join(' ');

  static String chip(String c) {
    if (kNames.containsKey(c)) return name(c);
    final f = RegExp(r'^(\d)(?:st|nd|rd|th) Floor$').firstMatch(c);
    if (f != null) return floorLabel(int.parse(f.group(1)!));
    return dates(c);
  }

  /// "1550–1069 BC" in the current language's era notation.
  static String dates(String s) {
    final bc = t('bc'), ad = t('ad');
    if (lang.cjk) {
      // 紀元前1550–1069年 · 公元前1550—前1069年 · 기원전 1550–1069년
      final m = RegExp(r'^([\d,]+)\s*(BC)?\s*–\s*([\d,]+)\s*(BC|AD)$').firstMatch(s);
      if (m != null) {
        final a = m.group(1)!, b = m.group(3)!;
        final aEra = m.group(2) != null || m.group(4) == 'BC' ? bc : ad;
        final bEra = m.group(4) == 'BC' ? bc : ad;
        final sp = lang == AppLang.ko ? ' ' : '';
        final yr = lang == AppLang.ko ? '년' : '年';
        return aEra == bEra ? '$aEra$sp$a–$b$yr' : '$aEra$sp$a$yr–$bEra$sp$b$yr';
      }
    }
    return s.replaceAll(' BC', ' $bc').replaceAll(' AD', ' $ad');
  }

  static String mapTitle(GemMap m) => kUi.containsKey('map_${m.id}') ? t('map_${m.id}') : m.title;
  static String mapShort(GemMap m) => kUi.containsKey('mapshort_${m.id}') ? t('mapshort_${m.id}') : m.shortTitle;

  /// The level badge of a map ("Level 3" → the local name of that floor).
  static String levelTag(GemMap m) => m.id == 'gem_complex' ? t('site') : floorLabel(m.level);
  static String era(Era e) => t('era_${e.id}');
  static String label(MapLabel l) => name(l.text);

  static String description(MapPlace p) {
    final row = kDescriptions[p.id] ??
        (p.id.startsWith('tg_') && p.category == PlaceCategory.attraction ? kDescriptions['tg_highlight'] : null) ??
        _eraDescription(p);
    if (row != null) return _pick(row, lang);
    return lang == AppLang.en ? (p.description ?? '') : '';
  }

  static List<String>? _eraDescription(MapPlace p) {
    final g = RegExp(r'^Gallery (\d+)').firstMatch(p.name);
    if (g == null) return null;
    final n = int.parse(g.group(1)!);
    for (final e in kEras) {
      final lo = int.parse(e.galleries.substring(0, 2)), hi = int.parse(e.galleries.substring(3));
      if (n >= lo && n <= hi) return kDescriptions[e.id];
    }
    return null;
  }

  // ── numbers ────────────────────────────────────────────────────
  static String distance(double meters) {
    final m = (meters / 5).round() * 5; // never pretend to be more exact than the estimate
    return t('unit_m', n: m < 5 ? 5 : m);
  }

  static String minutes(Duration d) => t('unit_min', n: (d.inSeconds / 60).ceil().clamp(1, 999));

  static String list(Iterable<String> items) => items.join(t('list_sep'));

  /// A floor's local name, for use inside a sentence ("ground floor", "2階").
  static String floorName(int f) => t('floor_${f.clamp(0, 3)}');

  /// A floor's local name on its own (a chip, a badge): capitalised.
  static String floorLabel(int f) {
    final s = floorName(f);
    return s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
  }

  /// Russian floors in the locative (the ground floor is the "first").
  static const _ruFloorIn = ['первом этаже', 'втором этаже', 'третьем этаже', 'четвёртом этаже'];

  // ── directions ─────────────────────────────────────────────────
  static String step(RouteStep s) {
    final near = s.targetId == null ? null : placeId(s.targetId!);
    switch (s.kind) {
      case StepKind.start:
        return near == null ? t('step_start_plain') : t('step_start', x: near);
      case StepKind.left:
        return near == null ? t('step_left') : t('step_left_at', x: near);
      case StepKind.right:
        return near == null ? t('step_right') : t('step_right_at', x: near);
      case StepKind.enterBuilding:
        final m = s.refMapId == null ? null : allMaps[s.refMapId!];
        return t('step_enter', x: m == null ? '' : mapTitle(m));
      case StepKind.exitBuilding:
        final m = s.refMapId == null ? null : allMaps[s.refMapId!];
        return t('step_exit', x: m == null ? '' : mapTitle(m));
      case StepKind.enterRoom:
        return t('step_room', x: s.targetId != null ? placeId(s.targetId!) : regionId(s.regionId ?? ''));
      case StepKind.door || StepKind.passage:
        // through an opening, and into the room behind it when that is named
        final into = s.targetId != null ? placeId(s.targetId!) : (s.regionId != null ? regionId(s.regionId!) : null);
        final key = s.kind == StepKind.door ? 'step_door' : 'step_passage';
        return into == null ? t(key) : t('${key}_into', x: into);
      case StepKind.steps:
        final into = s.targetId != null ? placeId(s.targetId!) : (s.regionId != null ? regionId(s.regionId!) : null);
        return into == null ? t('step_steps') : t('step_steps_into', x: into);
      case StepKind.levelReached:
        // Russian needs the floor in the locative here ("на втором этаже")
        return t('step_now_on', x: lang == AppLang.ru ? _ruFloorIn[s.floor.clamp(0, 3)] : floorName(s.floor));
      case StepKind.stairs:
        return t(s.down ? 'step_stairs_down' : 'step_stairs', x: floorName(s.floor));
      case StepKind.lift:
        return t(s.down ? 'step_lift_down' : 'step_lift', x: floorName(s.floor));
      case StepKind.travelator:
        return t(s.down ? 'step_travelator_down' : 'step_travelator', x: floorName(s.floor));
      case StepKind.arrive:
        return near == null ? t('step_arrive_plain') : t('step_arrive', x: near);
      case StepKind.stop:
        return t('step_stop', n: s.index, x: near ?? '');
    }
  }
}
