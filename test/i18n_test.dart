import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:imo/data/gem_extras.dart';
import 'package:imo/data/gem_regions.dart';
import 'package:imo/data/gem_stories.dart';
import 'package:imo/data/gem_stories_i18n.dart';
import 'package:imo/i18n/lang.dart';
import 'package:imo/i18n/strings.dart';
import 'package:imo/i18n/translations.dart';
import 'package:imo/models/map_models.dart';
import 'package:imo/services/search_engine.dart';
import 'package:imo/state/app_state.dart';
import 'package:imo/state/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Shop and café brands keep their own name in every language.
const _brands = {
  'Zooba', 'Bittersweet', 'Ladurée', '30 North', 'Starbucks', 'Dolato', "Beano's", 'Mandarin Koueider',
  'Okhtein', 'Dima', 'Kahhal Looms', 'Atef Wassef', 'Nakhla', 'Azza Fahmy', 'Nuniz', 'Premium Mart', 'Nefertari',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.init();
  });
  tearDown(() => AppState.instance.setLang(AppLang.en));

  test('every story is written in every language, paragraph for paragraph', () {
    for (final id in kStories.keys) {
      final st = storyFor(id)!;
      for (final l in AppLang.values) {
        expect(st.availableIn(l), isTrue, reason: '$id ${l.code}');
        expect(st.hookIn(l), isNotEmpty, reason: '$id ${l.code}');
        expect(st.storyIn(l).split('\n\n').length, st.story.split('\n\n').length, reason: '$id ${l.code}');
        expect(st.closingIn(l).isEmpty, st.closing.isEmpty, reason: '$id ${l.code}');
      }
    }
    for (final table in kStoryI18n.values) {
      expect(table.length + kStoryAliases.length, kStories.length);
    }
  });

  test('a gallery region reads its gallery\'s story in the app language', () {
    final st = storyFor('mg_zone_07')!;
    expect(st.storyIn(AppLang.ja), isNot(st.story));
    expect(st.storyIn(AppLang.ja), contains('デイル・エル・メディーナ'));
  });

  test('every table row has one non-empty text per language', () {
    for (final table in [kUi, kNames, kNamePatterns, kDescriptions, kEpilogue]) {
      table.forEach((key, row) {
        expect(row.length, AppLang.values.length, reason: key);
        for (final l in AppLang.values) {
          expect(row[l.index].trim(), isNotEmpty, reason: '$key [${l.code}]');
        }
      });
    }
  });

  test('placeholders survive translation', () {
    kUi.forEach((key, row) {
      for (final ph in ['{x}', '{n}']) {
        if (row[0].contains(ph)) {
          for (final l in AppLang.values) {
            expect(row[l.index], contains(ph), reason: '$key [${l.code}]');
          }
        }
      }
    });
  });

  test('every key the code asks for exists', () {
    final used = <String>{};
    final rx = RegExp(r"""S\.t\(\s*(?:[^'()]*\?\s*)?'([a-z0-9_]+)'(?:\s*:\s*'([a-z0-9_]+)')?""");
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      for (final m in rx.allMatches(f.readAsStringSync())) {
        used.add(m.group(1)!);
        if (m.group(2) != null) used.add(m.group(2)!);
      }
    }
    expect(used, isNotEmpty);
    expect(used.where((k) => !kUi.containsKey(k)), isEmpty);
  });

  test('every place, hall and plan label has a name in every language', () {
    final names = {
      for (final p in allPlaces) p.name,
      for (final r in kRegions) r.name,
      for (final ls in kLabels.values)
        for (final l in ls) l.text,
    }.difference(_brands);
    // a name either has its own row (some read the same in a language, like
    // "ATM" in Japanese) or follows a numbered pattern ("Gallery 05")
    for (final n in names) {
      expect(kNames.containsKey(n) || S.nameIn(n, AppLang.ar) != n, isTrue, reason: '"$n" has no translations');
    }
  });

  test('categories, maps, eras and floors are translated', () {
    for (final l in AppLang.values) {
      AppState.instance.setLang(l);
      for (final c in PlaceCategory.values) {
        expect(S.category(c), isNot(startsWith('cat_')));
        expect(S.filter(c), isNot(startsWith('cats_')));
      }
      for (final e in kEras) {
        expect(S.era(e), isNot(startsWith('era_')));
      }
      for (var f = 0; f <= 3; f++) {
        expect(S.floorLabel(f), isNotEmpty);
      }
    }
  });

  test('Arabic is right-to-left, the others left-to-right', () {
    for (final l in AppLang.values) {
      expect(l.rtl, l == AppLang.ar);
    }
    AppState.instance.setLang(AppLang.ar);
    expect(S.rtl, isTrue);
    expect(S.t('directions'), 'الاتجاهات');
    expect(S.tracking(1.6), 0, reason: 'letter-spacing would break Arabic joining');
  });

  test('dates follow each language', () {
    AppState.instance.setLang(AppLang.de);
    expect(S.chip('1550–1069 BC'), '1550–1069 v. Chr.');
    AppState.instance.setLang(AppLang.ja);
    expect(S.chip('1550–1069 BC'), '紀元前1550–1069年');
    AppState.instance.setLang(AppLang.zh);
    expect(S.chip('1069 BC–394 AD'), '公元前1069年–公元394年');
  });

  test('switching language changes the texts everywhere it is read', () {
    AppState.instance.setLang(AppLang.fr);
    expect(S.t('start_route'), 'Lancer l’itinéraire');
    expect(S.name('Restroom'), 'Toilettes');
    expect(S.nameIn('Gallery 05', AppLang.fr), 'Salle 05');
    AppState.instance.setLang(AppLang.ko);
    expect(S.name('Lift'), '엘리베이터');
    expect(Store.get('lang'), 'ko', reason: 'the choice is saved');
  });

  group('search in every language', () {
    List<String> top(String q) {
      final all = SearchEngine.build();
      return [for (final g in SearchEngine.search(all, q)) for (final e in g.items) e.place?.id ?? e.region?.id ?? ''];
    }

    test('names typed in any language find the place', () {
      AppState.instance.setLang(AppLang.en);
      expect(top('トイレ'), contains('mb_wc1'));
      expect(top('화장실'), contains('mb_wc1'));
      expect(top('洗手间'), contains('mb_wc1'));
      expect(top('туалет'), contains('mb_wc1'));
      expect(top('Aufzug'), contains('mb_lift1'));
      expect(top('rollstuhl'), contains('mb_access1'));
      expect(top('مصعد'), contains('mb_lift1'));
      expect(top('ツタンカーメン').first, anyOf('mb_10', 'mg_tut'));
    });

    test('accents, kana and digit forms are folded', () {
      expect(SearchEngine.norm('Écoute'), 'ecoute');
      expect(SearchEngine.norm('Straße'), 'strasse');
      expect(SearchEngine.norm('ёлка'), 'елка');
      expect(SearchEngine.norm('とけい'), SearchEngine.norm('トケイ'));
      expect(SearchEngine.norm('１２'), '12');
      expect(SearchEngine.norm('١٢'), '12');
    });
  });
}
