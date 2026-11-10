import '../data/gem_extras.dart';
import '../data/gem_map_data.dart';
import '../models/map_models.dart';
import '../services/route_finder.dart';
import '../state/app_state.dart';

/// All user-visible text. English is the source of truth; Arabic falls back
/// to English wherever a translation is missing, so nothing ever shows blank.
class S {
  S._();

  static bool get ar => AppState.instance.isArabic;

  static const Map<String, List<String>> _t = {
    'app_title': ['GRAND EGYPTIAN MUSEUM', 'المتحف المصري الكبير'],
    'search_hint': ['Search museum…', 'ابحث في المتحف…'],
    'search_tooltip': ['Search museum', 'بحث'],
    'no_results': ['No results', 'لا توجد نتائج'],
    'all': ['All', 'الكل'],
    'pin': ['Pin', 'تثبيت'],
    'pinned': ['Pinned', 'مثبّت'],
    'start_route': ['Start route', 'ابدأ المسار'],
    'routing': ['Routing…', 'جارٍ التوجيه…'],
    'open_plan': ['Open plan', 'افتح المخطط'],
    'im_here': ["I'm here", 'أنا هنا'],
    'you_are_here': ['You are here', 'أنت هنا'],
    'location_set': ['Location set: {x}', 'تم ضبط موقعك: {x}'],
    'no_path': ['No path found to this location.', 'لا يوجد مسار إلى هذا المكان.'],
    'no_step_free': ['No step-free route found.', 'لا يوجد مسار بدون سلالم.'],
    'already_here': ['You are already here.', 'أنت هنا بالفعل.'],
    'route_to': ['Route to {x}', 'المسار إلى {x}'],
    'directions': ['Directions', 'الاتجاهات'],
    'avoid_stairs': ['Avoid stairs', 'تجنّب السلالم'],
    'step_free_on': ['Step-free routes on', 'المسارات بدون سلالم مفعّلة'],
    'recenter': ['Recenter', 'إعادة التوسيط'],
    'clear_route': ['Clear route', 'إلغاء المسار'],
    'language': ['Language', 'اللغة'],
    'my_tour': ['My tour', 'جولتي'],
    'tour': ['Tour', 'جولة'],
    'tour_empty': ['Pin places on the map to build a tour.', 'ثبّت أماكن على الخريطة لتكوين جولة.'],
    'optimize': ['Best order', 'أفضل ترتيب'],
    'start_tour': ['Start tour', 'ابدأ الجولة'],
    'stops': ['{n} stops', '{n} محطات'],
    'skipped': ['No route to: {x}', 'لا يوجد مسار إلى: {x}'],
    'from_here': ['Starting from {x}', 'نقطة البداية: {x}'],
    'continue_on': ['Continue on {x}', 'تابع في {x}'],
    'timeline': ['Timeline', 'الخط الزمني'],
    'galleries_n': ['Galleries {x}', 'القاعات {x}'],
    'floor': ['Floor', 'الدور'],
    'close': ['Close', 'إغلاق'],
    'region_route': ['Route here', 'المسار إلى هنا'],
    // directions
    'step_start': ['Start at {x}', 'ابدأ من {x}'],
    'step_start_plain': ['Start', 'ابدأ'],
    'step_left': ['Turn left', 'انعطف يسارًا'],
    'step_left_at': ['Turn left near {x}', 'انعطف يسارًا عند {x}'],
    'step_right': ['Turn right', 'انعطف يمينًا'],
    'step_right_at': ['Turn right near {x}', 'انعطف يمينًا عند {x}'],
    'step_enter': ['Enter the {x}', 'ادخل إلى {x}'],
    'step_stairs': ['Take the stairs up to {x}', 'اصعد السلالم إلى {x}'],
    'step_lift': ['Take the lift to {x}', 'استخدم المصعد إلى {x}'],
    'step_arrive': ['Arrive at {x}', 'وصلت إلى {x}'],
    'step_arrive_plain': ['You have arrived', 'لقد وصلت'],
    'step_stop': ['Stop {n}: {x}', 'المحطة {n}: {x}'],
    'where_are_you': ['Where are you?', 'أين أنت؟'],
    'where_hint': ["There's no GPS indoors, so tell me where you're standing. Routes will start from there.", 'لا يوجد GPS داخل المتحف، أخبرني أين تقف وسيبدأ المسار من هناك.'],
    'pick_on_map': ['Pick on the map', 'اختر على الخريطة'],
    'pick_hint': ['Tap the map where you are', 'المس الخريطة حيث تقف'],
    'at_entrance': ["I'm at an entrance", 'أنا عند مدخل'],
    'search_place': ['Or search a place next to you', 'أو ابحث عن مكان بجانبك'],
    'your_location': ['Your location', 'موقعك'],
    'locate_me': ['Where am I?', 'أين أنا؟'],
    'fit_map': ['Fit map', 'ملاءمة الخريطة'],
    'rotate_map': ['Turn map 90°', 'تدوير الخريطة ٩٠°'],
    'back_to': ['Back to {x}', 'العودة إلى {x}'],
    'change': ['Change', 'تغيير'],
    'cancel': ['Cancel', 'إلغاء'],
    'tour_origin_unset': ['Tap to set where you are', 'المس لتحديد موقعك'],
    'search_ph': ['Search places, galleries, shops…', 'ابحث عن أماكن وقاعات ومتاجر…'],
    'popular': ['Popular', 'الأكثر طلبًا'],
    'no_results_hint': ['Try a name, a number, or a type like “food” or “restroom”.', 'جرّب اسمًا أو رقمًا أو نوعًا مثل «مطعم» أو «دورات مياه».'],
    'f_all': ['All', 'الكل'],
    'f_halls': ['Halls', 'القاعات الكبرى'],
    'no_n': ['No. {n}', 'رقم {n}'],
    'step_free_off': ['Step-free routes off', 'تم إيقاف المسارات بدون سلالم'],
    'step_exit': ['Leave the {x}', 'اخرج من {x}'],
    'step_stairs_down': ['Take the stairs down to {x}', 'انزل السلالم إلى {x}'],
    'step_lift_down': ['Take the lift down to {x}', 'استخدم المصعد للنزول إلى {x}'],
    'to_x': ['To {x}', 'إلى {x}'],
    'step_free_badge': ['Step-free', 'بدون سلالم'],
    'in_map': ['In {x}', 'في {x}'],
    'show_directions': ['Directions', 'الاتجاهات'],
    'results_n': ['{n} results', '{n} نتيجة'],
    // settings & map controls
    'settings': ['Settings', 'الإعدادات'],
    'appearance': ['Appearance', 'المظهر'],
    'theme_system': ['Auto', 'تلقائي'],
    'theme_light': ['Light', 'فاتح'],
    'theme_dark': ['Dark', 'داكن'],
    'zoom_in': ['Zoom in', 'تكبير'],
    'zoom_out': ['Zoom out', 'تصغير'],
    'step_free_hint': ['Avoid stairs when planning routes', 'تجنّب السلالم عند تخطيط المسار'],
    'rotate_hint': ['Turn the plan to fill a tall screen', 'أدر المخطط ليملأ الشاشة الطويلة'],
    'start': ['Start', 'ابدأ'],
    'current_location': ['Current location', 'الموقع الحالي'],
    'where_now': ['Where are you right now?', 'أين أنت الآن؟'],
    'quick_spots': ['Quick picks', 'اختيارات سريعة'],
    'or_search': ['Or search', 'أو ابحث'],
    'nearby_hint': ['A shop, gallery, restroom… anything you can see', 'متجر، قاعة، دورات مياه… أي شيء تراه'],
    'carvings': ['The carvings', 'النقوش'],
    'carvings_hint': ['What the signs around the plan mean', 'ماذا تعني الرموز حول المخطط'],
    'carvings_intro': ['The border of every plan carries wishes the ancient Egyptians carved for those they loved. Each edge repeats its own phrase.', 'يحمل إطار كل مخطط أمنيات نقشها المصريون القدماء لمن أحبوهم. وتكرر كل حافة عبارتها.'],
    'signs': ['The signs', 'الرموز'],
    'edge_top': ['Top edge', 'الحافة العليا'],
    'edge_right': ['Right edge', 'الحافة اليمنى'],
    'edge_bottom': ['Bottom edge', 'الحافة السفلى'],
    'edge_left': ['Left edge', 'الحافة اليسرى'],
    'about_museum': ['About this museum', 'عن المتحف'],
    'about_hint': ['Egypt was never just a past', 'لم تكن مصر يومًا مجرد ماضٍ'],
    'discover_story': ['Discover its story', 'اكتشف قصته'],
    'floor_0': ['the ground floor', 'الدور الأرضي'],
    'floor_1': ['the 1st floor', 'الدور الأول'],
    'floor_2': ['the 2nd floor', 'الدور الثاني'],
    'floor_3': ['the 3rd floor', 'الدور الثالث'],
  };

  static String t(String key, {String? x, int? n}) {
    final pair = _t[key];
    var s = pair == null ? key : pair[ar ? 1 : 0];
    if (x != null) s = s.replaceAll('{x}', x);
    if (n != null) s = s.replaceAll('{n}', '$n');
    return s;
  }

  // ── names ──────────────────────────────────────────────────────
  static String _name(String en) => nameIn(en, arabic: ar);

  /// The name in a chosen language, whatever language the app is in now
  /// (search needs both at once).
  static String nameIn(String en, {required bool arabic}) {
    if (!arabic) return en;
    final hit = kArByName[en];
    if (hit != null) return hit;
    final g = RegExp(r'^Gallery (\d+)(.*)$').firstMatch(en);
    if (g != null) return 'قاعة ${g.group(1)}${g.group(2)!.isEmpty ? '' : ' (القاعة الثانية)'}';
    final p = RegExp(r'^Parking (P\d)$').firstMatch(en);
    if (p != null) return 'موقف ${p.group(1)}';
    return en;
  }

  static String place(MapPlace p) => _name(p.name);
  static String region(MapRegion r) => _name(r.name);
  static String placeId(String id) {
    final p = placeById(id);
    return p == null ? t('your_location') : place(p);
  }

  /// Name of any routing node: a place by name, a bare junction as "Your location".
  static String nodeName(String id) => placeId(id);

  static String category(PlaceCategory c) => ar ? (kArCategory[c.label] ?? c.label) : c.label;
  static String filter(PlaceCategory c) => ar ? (kArCategory[c.filterLabel] ?? c.filterLabel) : c.filterLabel;

  static String chip(String c) {
    if (!ar) return c;
    final hit = kArChip[c];
    if (hit != null) return hit;
    return c.replaceAll(' BC', ' ق.م').replaceAll(' AD', ' م');
  }

  static String mapTitle(GemMap m) {
    if (!ar) return m.title;
    return switch (m.id) {
      'gem_complex' => 'مجمع المتحف',
      'main_building' => 'المبنى الرئيسي',
      'main_galleries' => 'قاعات العرض الرئيسية',
      'tutankhamun' => 'قاعات توت عنخ آمون',
      _ => m.title,
    };
  }

  static String mapShort(GemMap m) {
    if (!ar) return m.shortTitle;
    return switch (m.id) {
      'gem_complex' => 'المجمع',
      'main_building' => 'المبنى',
      'main_galleries' => 'القاعات',
      'tutankhamun' => 'توت عنخ آمون',
      _ => m.shortTitle,
    };
  }

  static String levelTag(GemMap m) => ar ? m.levelTagAr : m.levelTag;
  static String era(Era e) => ar ? e.nameAr : e.name;
  static String label(MapLabel l) => ar ? l.textAr : l.text;

  static String description(MapPlace p) {
    if (!ar) return p.description ?? '';
    final d = p.description;
    final g = RegExp(r'^gallery (\d+)', caseSensitive: false).firstMatch(p.name);
    if (g != null) {
      final n = int.parse(g.group(1)!);
      for (final e in kEras) {
        final lo = int.parse(e.galleries.substring(0, 2)), hi = int.parse(e.galleries.substring(3));
        if (n >= lo && n <= hi) return '${e.nameAr} — ${e.range.replaceAll(' BC', ' ق.م').replaceAll(' AD', ' م')}';
      }
    }
    return d ?? '';
  }

  // ── numbers ────────────────────────────────────────────────────
  static String distance(double meters) {
    final m = (meters / 5).round() * 5; // never pretend to be more exact than the estimate
    return ar ? '${m < 5 ? 5 : m} م' : '${m < 5 ? 5 : m} m';
  }

  static String minutes(Duration d) {
    final m = (d.inSeconds / 60).ceil().clamp(1, 999);
    return ar ? '$m د' : '$m min';
  }

  static String floorName(int f) => t('floor_${f.clamp(0, 3)}');

  // ── directions ─────────────────────────────────────────────────
  static String step(RouteStep s) {
    String? near = s.targetId == null ? null : placeId(s.targetId!);
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
      case StepKind.stairs:
        return t(s.down ? 'step_stairs_down' : 'step_stairs', x: floorName(s.floor));
      case StepKind.lift:
        return t(s.down ? 'step_lift_down' : 'step_lift', x: floorName(s.floor));
      case StepKind.arrive:
        return near == null ? t('step_arrive_plain') : t('step_arrive', x: near);
      case StepKind.stop:
        return t('step_stop', n: s.index, x: near ?? '');
    }
  }
}
