import 'package:flutter/material.dart';

import '../data/gem_extras.dart';
import '../data/gem_map_data.dart';
import '../data/gem_regions.dart';
import '../data/gem_stories.dart';
import '../i18n/strings.dart';
import '../models/map_models.dart';

/// One searchable thing: a place or a named hall/zone.
class SearchEntry {
  SearchEntry({
    required this.title,
    required this.titleLower,
    required this.altLower,
    required this.subtitle,
    required this.categoryKey,
    required this.categoryLower,
    required this.mapLower,
    required this.extraLower,
    required this.storyLower,
    required this.number,
    required this.mapId,
    this.place,
    this.region,
  });

  final String title;
  final String titleLower;

  /// The name in the OTHER language, so English and Arabic both find it.
  final String altLower;
  final String subtitle;
  final String categoryKey;
  final String categoryLower;
  final String mapLower;

  /// Synonyms in both languages ("toilet", "حمام", "coffee", "قهوة"…).
  final String extraLower;

  /// The story text of the place, in both languages (lowest-priority match).
  final String storyLower;

  /// Number shown on the pin without leading zeros ('05' → '5'), or ''.
  final String number;
  final String mapId;
  final MapPlace? place;
  final MapRegion? region;
}

class SearchEngine {
  /// Order the groups are shown in.
  static const order = ['entrance', 'attraction', 'gallery', 'restaurant', 'shop', 'facility', 'parking', 'garden', 'building', 'hall'];

  static String groupLabel(String key) => switch (key) {
    'hall' => S.t('f_halls'),
    _ => S.category(PlaceCategory.values.firstWhere((c) => c.name == key)),
  };

  /// Lower-cases and folds text so Arabic and English typing both match:
  /// Arabic-Indic and Persian digits become 0-9; diacritics and tatweel are
  /// dropped; alef / ya / ta-marbuta / hamza variants are merged.
  static String norm(String s) => _norm(s);

  static const Map<int, int> _fold = {
    0x0622: 0x0627, 0x0623: 0x0627, 0x0625: 0x0627, 0x0671: 0x0627, // آ أ إ ٱ -> ا
    0x0649: 0x064A, 0x0626: 0x064A, // ى ئ -> ي
    0x0629: 0x0647, // ة -> ه
    0x0624: 0x0648, // ؤ -> و
  };

  static String _norm(String s) {
    final b = StringBuffer();
    for (final r in s.toLowerCase().trim().runes) {
      var c = r;
      if (c >= 0x0660 && c <= 0x0669) {
        c = c - 0x0660 + 0x30; // Arabic-Indic digits
      } else if (c >= 0x06F0 && c <= 0x06F9) {
        c = c - 0x06F0 + 0x30; // Persian digits
      } else if ((c >= 0x064B && c <= 0x065F) || c == 0x0670 || c == 0x0640 || c == 0x200E || c == 0x200F || c == 0x061C) {
        continue; // diacritics, tatweel, direction marks
      } else {
        c = _fold[c] ?? c;
      }
      b.writeCharCode(c);
    }
    return b.toString();
  }

  /// Search words in both languages for the kind of place it is.
  static String _keywords(MapPlace p) {
    final g = p.effectiveGlyph;
    final byGlyph = switch (g) {
      PlaceGlyph.restroom => 'toilet wc bathroom restroom حمام دورة مياه دورات تواليت',
      PlaceGlyph.wheelchair => 'accessible disabled wheelchair step-free كرسي متحرك ذوي الهمم اعاقة',
      PlaceGlyph.prayer => 'mosque prayer pray مسجد مصلي صلاه',
      PlaceGlyph.lift => 'elevator lift مصعد اسانسير',
      PlaceGlyph.info => 'information help desk assistance استعلامات معلومات مساعده',
      PlaceGlyph.atm => 'cash bank money atm صراف بنك فلوس',
      PlaceGlyph.clinic => 'medical doctor first aid clinic عياده اسعاف طبيب',
      PlaceGlyph.headphones => 'audio guide tour earphones headphones سماعات جوله مرشد',
      PlaceGlyph.ticket => 'ticket tickets booking تذاكر تذكره شباك حجز',
      PlaceGlyph.parking => 'car parking park موقف سيارات جراج انتظار',
      PlaceGlyph.coffee => 'coffee cafe tea قهوه كافيه شاي',
      PlaceGlyph.cake || PlaceGlyph.bakery || PlaceGlyph.cookie || PlaceGlyph.iceCream => 'dessert sweets cake bakery ice cream حلويات كيك مخبز ايس كريم',
      PlaceGlyph.food => 'food eat restaurant lunch dinner اكل مطعم غداء عشاء وجبه',
      PlaceGlyph.jewelry => 'jewelry jewellery gold silver مجوهرات ذهب فضه',
      PlaceGlyph.grocery => 'market supermarket groceries سوبر ماركت بقاله',
      _ => '',
    };
    final byCat = switch (p.category) {
      PlaceCategory.restaurant => 'food eat restaurant cafe مطعم مطاعم اكل كافيه',
      PlaceCategory.shop => 'shop shops store gift souvenir متجر متاجر محل هدايا تذكارات',
      PlaceCategory.garden => 'garden park green حديقه حدائق',
      PlaceCategory.parking => 'parking car موقف سيارات',
      PlaceCategory.entrance => 'entrance exit gate door مدخل مخرج بوابه',
      PlaceCategory.attraction => 'highlight attraction sight must see معلم المعالم مميز',
      PlaceCategory.gallery => 'gallery hall room قاعه قاعات',
      PlaceCategory.facility => 'service services خدمه خدمات',
      PlaceCategory.building => 'building مبنى',
    };
    return _norm('$byGlyph $byCat');
  }

  static String _stripZeros(String n) => n.replaceFirst(RegExp(r'^0+(?=\d)'), '');

  /// Everything searchable, in the current language. [regions] adds halls/zones
  /// (they can be opened but are not routing nodes).
  static List<SearchEntry> build({bool regions = true}) {
    final out = <SearchEntry>[];
    for (final p in allPlaces) {
      final owner = allMaps[mapIdOfPlace(p.id)]!;
      final ar = S.nameIn(p.name, arabic: true);
      final en = p.name;
      final floor = kPlaceFloor[p.id];
      final st = storyFor(p.id);
      out.add(
        SearchEntry(
          title: S.place(p),
          titleLower: _norm(S.ar ? ar : en),
          altLower: _norm(S.ar ? en : ar),
          subtitle: [S.category(p.category), S.mapShort(owner), if (floor != null && floor > 0) S.floorName(floor).replaceFirst('the ', '')].join(' · '),
          categoryKey: p.category.name,
          categoryLower: _norm('${p.category.label} ${p.category.filterLabel} ${kArCategory[p.category.label] ?? ''} ${kArCategory[p.category.filterLabel] ?? ''}'),
          mapLower: _norm('${owner.title} ${S.mapTitle(owner)}'),
          extraLower: _keywords(p),
          storyLower: st == null ? '' : _norm('${st.hook} ${st.hookAr} ${st.story} ${st.storyAr}'),
          number: _stripZeros(p.number ?? ''),
          mapId: owner.id,
          place: p,
        ),
      );
    }
    if (regions) {
      for (final r in kRegions) {
        if (r.placeId != null) continue; // those are reachable as places
        final owner = allMaps[r.mapId]!;
        out.add(
          SearchEntry(
            title: S.region(r),
            titleLower: _norm(S.region(r)),
            altLower: _norm(S.ar ? r.name : S.nameIn(r.name, arabic: true)),
            subtitle: '${S.t('f_halls')} · ${S.mapShort(owner)}',
            categoryKey: 'hall',
            categoryLower: _norm('hall zone ${S.t('f_halls')}'),
            mapLower: _norm('${owner.title} ${S.mapTitle(owner)}'),
            extraLower: _norm('hall zone room gallery قاعه قاعات منطقه'),
            storyLower: () {
              final st = storyFor(r.id);
              return st == null ? '' : _norm('${st.hook} ${st.hookAr} ${st.story} ${st.storyAr}');
            }(),
            number: '',
            mapId: owner.id,
            region: r,
          ),
        );
      }
    }
    return out;
  }

  static List<String> tokens(String q) => _norm(q).split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();

  static final _digits = RegExp(r'^\d+$');

  static int _score(SearchEntry e, List<String> toks) {
    var total = 0;
    for (final t in toks) {
      var best = 0;
      if (_digits.hasMatch(t)) {
        // "5" finds EVERY number 5: gallery 05, attraction 5, shop 5, restaurant 5…
        if (e.number == _stripZeros(t)) {
          best = 95;
        } else if (RegExp('(^|\\D)${RegExp.escape(t)}(\\D|\$)').hasMatch(e.titleLower)) {
          best = 55; // "30 North", "Gallery 05"
        } else if (e.titleLower.contains(t)) {
          best = 20;
        }
      } else {
        if (e.titleLower == t || e.altLower == t) {
          best = 100;
        } else if (e.titleLower.startsWith(t) || e.altLower.startsWith(t)) {
          best = 80;
        } else if (e.titleLower.contains(' $t') || e.altLower.contains(' $t')) {
          best = 65;
        } else if (e.titleLower.contains(t) || e.altLower.contains(t)) {
          best = 45;
        } else if (e.categoryLower.contains(t)) {
          best = 30;
        } else if (e.extraLower.contains(t)) {
          best = 25;
        } else if (e.mapLower.contains(t)) {
          best = 12;
        } else if (e.storyLower.contains(t)) {
          best = 6;
        }
      }
      if (best == 0) return 0; // every word has to match something
      total += best;
    }
    return total;
  }

  /// Matches grouped by type; groups ordered by their best hit.
  static List<({String key, List<SearchEntry> items})> search(List<SearchEntry> all, String query, {String filter = 'all'}) {
    final toks = tokens(query);
    final scored = <(SearchEntry, int)>[];
    for (final e in all) {
      if (filter != 'all' && e.categoryKey != filter) continue;
      final s = toks.isEmpty ? 1 : _score(e, toks);
      if (s > 0) scored.add((e, s));
    }
    scored.sort((a, b) => b.$2 != a.$2 ? b.$2.compareTo(a.$2) : a.$1.title.compareTo(b.$1.title));
    final groups = <String, List<SearchEntry>>{};
    final best = <String, int>{};
    for (final (e, s) in scored) {
      groups.putIfAbsent(e.categoryKey, () => []).add(e);
      best[e.categoryKey] = best[e.categoryKey] == null || s > best[e.categoryKey]! ? s : best[e.categoryKey]!;
    }
    final keys = groups.keys.toList()
      ..sort((a, b) {
        if (toks.isEmpty) return order.indexOf(a).compareTo(order.indexOf(b));
        final d = best[b]!.compareTo(best[a]!);
        return d != 0 ? d : order.indexOf(a).compareTo(order.indexOf(b));
      });
    return [for (final k in keys) (key: k, items: groups[k]!)];
  }

  /// What to show before anything is typed: entrances, key services, highlights.
  static List<({String key, List<SearchEntry> items})> suggestions(List<SearchEntry> all) {
    final seen = <String>{};
    final picks = <SearchEntry>[];
    for (final e in all) {
      final c = e.categoryKey;
      if (c == 'entrance' || c == 'attraction') {
        picks.add(e);
      } else if (c == 'facility' && e.place != null && seen.add(e.place!.name)) {
        picks.add(e); // one of each service: restroom, lift, ATM…
      }
    }
    final groups = <String, List<SearchEntry>>{};
    for (final e in picks) {
      groups.putIfAbsent(e.categoryKey, () => []).add(e);
    }
    final keys = groups.keys.toList()..sort((a, b) => order.indexOf(a).compareTo(order.indexOf(b)));
    return [for (final k in keys) (key: k, items: groups[k]!)];
  }

  /// [title] with the matched words picked out in gold.
  static List<TextSpan> highlight(String title, String query, TextStyle base, TextStyle hit) {
    final toks = tokens(query).where((t) => !_digits.hasMatch(t) || title.contains(t)).toList();
    if (toks.isEmpty) return [TextSpan(text: title, style: base)];
    final folded = _norm(title);
    final lower = folded.length == title.length ? folded : title.toLowerCase();
    final mark = List<bool>.filled(title.length, false);
    for (final t in toks) {
      var i = lower.indexOf(t);
      while (i >= 0) {
        for (var k = i; k < i + t.length && k < mark.length; k++) {
          mark[k] = true;
        }
        i = lower.indexOf(t, i + t.length);
      }
    }
    final spans = <TextSpan>[];
    var start = 0;
    for (var i = 1; i <= title.length; i++) {
      if (i == title.length || mark[i] != mark[start]) {
        spans.add(TextSpan(text: title.substring(start, i), style: mark[start] ? hit : base));
        start = i;
      }
    }
    return spans;
  }
}
