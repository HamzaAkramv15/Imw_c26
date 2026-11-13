import 'package:flutter_test/flutter_test.dart';
import 'package:imo/i18n/lang.dart';
import 'package:imo/services/search_engine.dart';
import 'package:imo/state/app_state.dart';

/// Visitors spell Egyptian names many ways, and type on the move.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => AppState.instance.setLang(AppLang.en));

  String? top(String q) {
    final groups = SearchEngine.search(SearchEngine.build(), q);
    if (groups.isEmpty) return null;
    // the best hit overall
    final all = [for (final g in groups) ...g.items];
    return (all.first.place?.id ?? all.first.region?.id);
  }

  test('other spellings of names find the place', () {
    expect(top('merneptah'), 'mb_2');
    expect(top('sesostris'), 'mb_4');
    expect(top('senusret'), 'mb_4');
    expect(top('cheops'), 'cx_boats');
    expect(top('saqqara'), isNotNull);
    expect(top('ramses tanis'), isNotNull);
  });

  test('a typo still finds the place', () {
    expect(top('tutankamon'), isNotNull);
    expect(top('obelsk'), 'cx_obelisk');
    expect(top('merenptha'), 'mb_2');
  });

  test('typo matching does not flood unrelated words', () {
    expect(top('zzzzz'), isNull);
    expect(SearchEngine.search(SearchEngine.build(), 'xqzvw'), isEmpty);
  });

  test('every language finds the Prayer Room by its usual word', () {
    for (final (l, q) in [(AppLang.en, 'prayer'), (AppLang.ar, 'مصلى'), (AppLang.de, 'gebetsraum'), (AppLang.fr, 'prière'), (AppLang.ru, 'молельная'), (AppLang.ja, '礼拝'), (AppLang.ko, '기도실'), (AppLang.zh, '祈祷')]) {
      AppState.instance.setLang(l);
      expect(top(q), 'mb_prayer', reason: '${l.code} $q');
    }
  });
}
