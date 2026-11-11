import 'package:flutter_test/flutter_test.dart';
import 'package:imo/data/gem_extras.dart';
import 'package:imo/data/gem_map_data.dart';
import 'package:imo/data/gem_rostau.dart';
import 'package:imo/i18n/lang.dart';
import 'package:imo/models/rostau.dart';
import 'package:imo/services/rostau.dart';
import 'package:imo/services/route_finder.dart';
import 'package:imo/state/store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final graph = MuseumGraph(allMaps);
  final planner = RostauPlanner(graph);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Store.init();
    Store.put({'rostau': null});
  });

  group('curated trips', () {
    test('seven trips with unique ids, a title and a phrase in every language', () {
      expect(kRostauTrips.length, 7);
      expect(kRostauTrips.map((t) => t.id).toSet().length, 7);
      for (final t in kRostauTrips) {
        expect(t.title.length, AppLang.values.length, reason: t.id);
        expect(t.phrase.length, AppLang.values.length, reason: t.id);
        expect(t.title.every((s) => s.isNotEmpty) && t.phrase.every((s) => s.isNotEmpty), isTrue, reason: t.id);
        expect(t.titleIn(AppLang.ar), t.title[AppLang.ar.index]);
        expect(t.phraseIn(AppLang.zh), t.phrase[AppLang.zh.index]);
      }
    });

    test('every stop is a known place', () {
      for (final t in kRostauTrips) {
        for (final s in t.stops) {
          expect(placeById(s), isNotNull, reason: '${t.id}: $s');
        }
      }
    });

    test('every trip plans into one walk that visits all its stops, standard and step-free', () {
      for (final t in kRostauTrips) {
        for (final stepFree in [false, true]) {
          final p = planner.plan(t, 'cx_ticket', avoidStairs: stepFree)!;
          expect(p.tour.skipped, isEmpty, reason: '${t.id} stepFree=$stepFree');
          expect(p.tour.order.toSet(), t.stops.toSet(), reason: t.id);
          if (stepFree) expect(p.tour.route.usesStairs, isFalse, reason: t.id);
        }
      }
    });

    test('the planned order is never longer than the listed order', () {
      for (final t in kRostauTrips) {
        final best = graph.tour('cx_ticket', t.stops)!;
        final listed = graph.tour('cx_ticket', t.stops, optimize: false)!;
        expect(best.route.meters, lessThanOrEqualTo(listed.route.meters + 1), reason: t.id);
      }
    });

    test('"on the way" names only attractions off the trip', () {
      for (final t in kRostauTrips) {
        final p = planner.plan(t, 'cx_ticket')!;
        for (final id in p.onTheWay) {
          expect(t.stops, isNot(contains(id)), reason: t.id);
          expect(placeById(id)!.category.name, 'attraction', reason: id);
        }
      }
    });
  });

  group('own trips', () {
    test('are saved, listed, replaced and deleted', () {
      final t = RostauLibrary.save(name: '  My favourites  ', stops: ['mb_1', 'tg_mask'])!;
      expect(t.name, 'My favourites');
      expect(RostauLibrary.custom.single.stops, ['mb_1', 'tg_mask']);
      expect(RostauLibrary.all.length, kRostauTrips.length + 1);
      RostauLibrary.save(id: t.id, name: 'Renamed', stops: ['mb_3']);
      expect(RostauLibrary.byId(t.id)!.titleIn(AppLang.ja), 'Renamed');
      expect(RostauLibrary.custom.single.stops, ['mb_3']);
      RostauLibrary.delete(t.id);
      expect(RostauLibrary.custom, isEmpty);
    });

    test('unknown and repeated places are dropped; empty trips and blank names are refused', () {
      final t = RostauLibrary.save(name: 'x', stops: ['mb_1', 'nowhere', 'mb_1'])!;
      expect(t.stops, ['mb_1']);
      expect(RostauLibrary.save(name: 'x', stops: ['nowhere']), isNull);
      expect(RostauLibrary.save(name: '   ', stops: ['mb_1']), isNull);
    });

    test('a damaged saved entry is skipped, not a crash', () {
      Store.put({
        'rostau': [
          'garbage',
          {'id': 1},
          {'id': 'ok', 'name': 'Fine', 'stops': ['mb_1', 3]},
        ],
      });
      expect(RostauLibrary.custom.map((t) => t.id), ['ok']);
      expect(RostauLibrary.custom.single.stops, ['mb_1']);
    });

    test('survive a round trip through JSON', () {
      final t = RostauTrip.custom('a', 'Name', const ['mb_1']);
      final back = RostauTrip.fromJson(t.toJson())!;
      expect([back.id, back.name, back.stops], ['a', 'Name', ['mb_1']]);
    });
  });
}
