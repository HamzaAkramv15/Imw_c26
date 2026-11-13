import 'package:flutter_test/flutter_test.dart';
import 'package:imo/data/gem_extras.dart';
import 'package:imo/data/gem_map_data.dart';
import 'package:imo/i18n/lang.dart';
import 'package:imo/services/route_finder.dart';
import 'package:imo/services/search_engine.dart';
import 'package:imo/state/app_state.dart';

/// Lists of places come nearest first, by walking distance from where the
/// visitor said they are; without a position they keep the museum's order.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => AppState.instance.setLang(AppLang.en));
  final graph = MuseumGraph(allMaps);
  final all = SearchEngine.build();

  List<String> highlights(Map<String, double>? near) => [
    for (final e in SearchEngine.suggestions(all, near: near).firstWhere((g) => g.key == 'attraction').items) e.place!.id,
  ];

  test('walking distances: zero where you stand, growing with the walk', () {
    final m = graph.metersFrom('mb_entrance');
    expect(m['mb_entrance'], 0);
    // the colossus in the Grand Hall is closer than the galleries upstairs
    expect(m['mb_1']!, lessThan(m['mg_07']!));
    // a route's own length agrees with the table
    expect(m['mb_5']!, closeTo(graph.find('mb_entrance', 'mb_5')!.meters, 1));
    // a pin that redirects to another plan gets that plan's distance
    expect(m['mb_10'], isNotNull);
  });

  test('highlights come nearest first, and the order follows the visitor', () {
    for (final from in ['mb_entrance', 'mg_12', 'tg_mask', 'cx_ticket']) {
      final near = graph.metersFrom(from);
      final ids = highlights(near);
      final d = [for (final id in ids) near[id] ?? double.infinity];
      for (var i = 1; i < d.length; i++) {
        expect(d[i], greaterThanOrEqualTo(d[i - 1]), reason: 'from $from: ${ids[i - 1]} then ${ids[i]}');
      }
    }
    expect(highlights(graph.metersFrom('mb_entrance')).first, isNot(highlights(graph.metersFrom('tg_mask')).first));
  });

  test('without a position the museum order is kept', () {
    final plain = highlights(null);
    expect(plain, [for (final p in allPlaces) if (p.category.name == 'attraction') p.id]);
  });

  test('"restroom" lists the nearest restroom first', () {
    for (final from in ['mb_entrance', 'mb_r1', 'mb_4']) {
      final near = graph.metersFrom(from);
      final items = [for (final g in SearchEngine.search(all, 'restroom', near: near)) ...g.items];
      final wc = [for (final e in items) if (e.place?.name == 'Restroom') e];
      expect(wc, isNotEmpty);
      final best = wc.map((e) => near[e.place!.id] ?? double.infinity).reduce((a, b) => a < b ? a : b);
      expect(near[wc.first.place!.id], best, reason: 'from $from');
    }
  });

  test('step-free distances avoid the stairs (never shorter than the standard walk)', () {
    final std = graph.metersFrom('mb_entrance');
    final free = graph.metersFrom('mb_entrance', avoidStairs: true);
    for (final id in ['mg_07', 'tg_mask']) {
      expect(free[id]!, greaterThanOrEqualTo(std[id]! - 1), reason: id);
    }
  });

  test('an unknown position gives nothing rather than a guess', () {
    expect(graph.metersFrom('nowhere'), isEmpty);
  });
}
