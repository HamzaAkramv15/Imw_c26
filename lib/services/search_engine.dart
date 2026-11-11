import 'package:flutter/material.dart';

import '../data/gem_extras.dart';
import '../data/gem_map_data.dart';
import '../data/gem_nav.dart';
import '../data/gem_regions.dart';
import '../data/gem_stories.dart';
import '../i18n/lang.dart';
import '../i18n/strings.dart';
import '../i18n/translations.dart';
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

  /// The name in every other language, so a name typed in any of them finds it.
  final String altLower;
  final String subtitle;
  final String categoryKey;
  final String categoryLower;
  final String mapLower;

  /// Synonyms in every language ("toilet", "حمام", "Toilette", "トイレ"…).
  final String extraLower;

  /// The story text of the place, in English and Arabic (lowest-priority match).
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

  /// Lower-cases and folds text so typing in any of the eight languages matches:
  ///  * Arabic-Indic, Persian and full-width digits become 0-9; full-width
  ///    Latin becomes ASCII;
  ///  * Arabic diacritics and tatweel are dropped; alef / ya / ta-marbuta /
  ///    hamza variants are merged;
  ///  * Latin accents are dropped (é → e, ä → a, ß → ss), ё → е;
  ///  * hiragana becomes katakana (とけい finds トケイ).
  static String norm(String s) => _norm(s);

  static const Map<int, int> _fold = {
    0x0622: 0x0627, 0x0623: 0x0627, 0x0625: 0x0627, 0x0671: 0x0627, // آ أ إ ٱ -> ا
    0x0649: 0x064A, 0x0626: 0x064A, // ى ئ -> ي
    0x0629: 0x0647, // ة -> ه
    0x0624: 0x0648, // ؤ -> و
    0x0451: 0x0435, // ё -> е
    0x2019: 0x27, 0x2018: 0x27, // ’ ‘ -> '
    0x3000: 0x20, // ideographic space
  };

  /// Latin letters with diacritics -> base letter (the ones French and German use).
  static const String _accented = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿ';
  static const String _plain = 'aaaaaaceeeeiiiinooooouuuuyy';

  static String _norm(String s) {
    final b = StringBuffer();
    for (final r in s.toLowerCase().trim().runes) {
      var c = r;
      if (c >= 0x0660 && c <= 0x0669) {
        c = c - 0x0660 + 0x30; // Arabic-Indic digits
      } else if (c >= 0x06F0 && c <= 0x06F9) {
        c = c - 0x06F0 + 0x30; // Persian digits
      } else if (c >= 0xFF01 && c <= 0xFF5E) {
        c = c - 0xFF01 + 0x21; // full-width ASCII (０-９, Ａ-Ｚ)
        if (c >= 0x41 && c <= 0x5A) c += 0x20;
      } else if (c >= 0x3041 && c <= 0x3096) {
        c += 0x60; // hiragana -> katakana
      } else if ((c >= 0x064B && c <= 0x065F) || c == 0x0670 || c == 0x0640 || c == 0x200E || c == 0x200F || c == 0x061C) {
        continue; // diacritics, tatweel, direction marks
      } else if (c == 0xDF) {
        b.write('ss'); // ß
        continue;
      } else if (c == 0x153) {
        b.write('oe'); // œ
        continue;
      } else {
        final i = _accented.indexOf(String.fromCharCode(c));
        c = i >= 0 ? _plain.codeUnitAt(i) : (_fold[c] ?? c);
      }
      b.writeCharCode(c);
    }
    return b.toString();
  }

  /// [en] in every language, for matching.
  static String _allNames(String en) => [for (final l in AppLang.values) S.nameIn(en, l)].join(' | ');

  static String _allMapTitles(GemMap m) =>
      [m.title, for (final l in AppLang.values) kUi['map_${m.id}']?[l.index] ?? ''].join(' ');

  /// Search words in every language for the kind of place it is.
  static String _keywords(MapPlace p) {
    final g = p.effectiveGlyph;
    final byGlyph = switch (g) {
      PlaceGlyph.restroom => 'toilet wc bathroom restroom حمام دورة مياه دورات تواليت toilette toiletten klo toilettes sanitaires туалет уборная トイレ 化粧室 お手洗い 화장실 厕所 洗手间 卫生间',
      PlaceGlyph.wheelchair => 'accessible disabled wheelchair step-free كرسي متحرك ذوي الهمم اعاقة rollstuhl barrierefrei stufenlos fauteuil handicap pmr accessible коляска инвалид доступная среда 車いす 車椅子 バリアフリー 휠체어 장애인 轮椅 无障碍',
      PlaceGlyph.prayer => 'mosque prayer pray مسجد مصلي صلاه gebet gebetsraum moschee priere mosquee молельная намаз мечеть 礼拝 祈祷 기도 예배 祈祷 礼拜',
      PlaceGlyph.lift => 'elevator lift مصعد اسانسير aufzug fahrstuhl ascenseur лифт エレベーター 엘리베이터 승강기 电梯 升降梯',
      PlaceGlyph.info => 'information help desk assistance استعلامات معلومات مساعده auskunft hilfe info accueil renseignements aide справка информация помощь 案内 インフォメーション 안내 도움 问询 咨询 服务台',
      PlaceGlyph.atm => 'cash bank money atm صراف بنك فلوس geldautomat bargeld distributeur argent банкомат деньги 現金 お金 현금 돈 取款 现金 提款机',
      PlaceGlyph.clinic => 'medical doctor first aid clinic عياده اسعاف طبيب arzt erste hilfe sanitater medecin infirmerie secours врач медпункт аптечка 医務室 救護 医者 의무실 응급 의사 医务室 急救 医生',
      PlaceGlyph.headphones => 'audio guide tour earphones headphones سماعات جوله مرشد audioguide kopfhorer fuhrung casque audioguide visite аудиогид наушники экскурсия イヤホン 音声ガイド 이어폰 오디오 가이드 耳机 语音导览',
      PlaceGlyph.ticket => 'ticket tickets booking تذاكر تذكره شباك حجز eintritt karten kasse billet billetterie билет касса チケット 切符 入場券 티켓 매표 门票 售票',
      PlaceGlyph.parking => 'car parking park موقف سيارات جراج انتظار parkplatz auto voiture stationnement парковка стоянка машина 駐車場 車 주차 주차장 停车 停车场',
      PlaceGlyph.coffee => 'coffee cafe tea قهوه كافيه شاي kaffee tee cafe the кофе кафе чай コーヒー カフェ 紅茶 커피 카페 차 咖啡 茶',
      PlaceGlyph.cake || PlaceGlyph.bakery || PlaceGlyph.cookie || PlaceGlyph.iceCream => 'dessert sweets cake bakery ice cream حلويات كيك مخبز ايس كريم kuchen eis backerei patisserie gateau glace десерт торт мороженое スイーツ ケーキ アイス 디저트 케이크 아이스크림 甜点 蛋糕 冰淇淋',
      PlaceGlyph.food => 'food eat restaurant lunch dinner اكل مطعم غداء عشاء وجبه essen restaurant mittagessen manger dejeuner repas еда ресторан обед 食事 レストラン ランチ 음식 식당 점심 餐厅 吃饭 午餐',
      PlaceGlyph.jewelry => 'jewelry jewellery gold silver مجوهرات ذهب فضه schmuck bijoux or argent украшения золото серебро ジュエリー 宝飾 금 은 보석 珠宝 首饰 金 银',
      PlaceGlyph.grocery => 'market supermarket groceries سوبر ماركت بقاله markt supermarkt epicerie магазин продукты マーケット 売店 마트 편의점 超市 便利店',
      _ => '',
    };
    final byCat = switch (p.category) {
      PlaceCategory.restaurant => 'food eat restaurant cafe مطعم مطاعم اكل كافيه essen cafe restaurant manger еда кафе ресторан 飲食 レストラン カフェ 음식 카페 식당 餐饮 餐厅',
      PlaceCategory.shop => 'shop shops store gift souvenir متجر متاجر محل هدايا تذكارات laden geschaft geschenk souvenir boutique cadeau магазин сувенир подарок ショップ お土産 売店 상점 기념품 선물 商店 纪念品 礼品',
      PlaceCategory.garden => 'garden park green حديقه حدائق garten park jardin parc сад парк 庭園 公園 정원 공원 花园 公园',
      PlaceCategory.parking => 'parking car موقف سيارات parkplatz stationnement парковка 駐車場 주차장 停车场',
      PlaceCategory.entrance => 'entrance exit gate door مدخل مخرج بوابه eingang ausgang tor entree sortie porte вход выход ворота 入口 出口 ゲート 입구 출구 게이트 入口 出口 大门',
      PlaceCategory.attraction => 'highlight attraction sight must see معلم المعالم مميز sehenswurdigkeit highlight incontournable chef-doeuvre достопримечательность шедевр 見どころ 名品 하이라이트 명소 亮点 必看',
      PlaceCategory.gallery => 'gallery hall room قاعه قاعات saal galerie salle galerie зал галерея 展示室 ギャラリー 전시실 갤러리 展厅 展馆',
      PlaceCategory.facility => 'service services خدمه خدمات service dienst услуги サービス 편의 시설 服务',
      PlaceCategory.building => 'building مبنى gebaude batiment здание 建物 건물 建筑',
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
      final floor = kPlaceFloor[p.id];
      final st = storyFor(p.id);
      out.add(
        SearchEntry(
          title: S.place(p),
          titleLower: _norm(S.place(p)),
          altLower: _norm(_allNames(p.name)),
          subtitle: [S.category(p.category), S.mapShort(owner), if (floor != null && floor > 0) S.floorLabel(floor)].join(' · '),
          categoryKey: p.category.name,
          categoryLower: _norm(S.categoryAll(p.category)),
          mapLower: _norm(_allMapTitles(owner)),
          extraLower: _keywords(p),
          storyLower: st == null ? '' : _norm(st.allText),
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
            altLower: _norm(_allNames(r.name)),
            subtitle: '${S.t('f_halls')} · ${S.mapShort(owner)}',
            categoryKey: 'hall',
            categoryLower: _norm([for (final l in AppLang.values) kUi['f_halls']![l.index]].join(' ')),
            mapLower: _norm(_allMapTitles(owner)),
            extraLower: _norm('hall zone room gallery قاعه قاعات منطقه halle bereich salle zone зал зона ホール ゾーン 홀 구역 大厅 展区'),
            storyLower: () {
              final st = storyFor(r.id);
              return st == null ? '' : _norm(st.allText);
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
