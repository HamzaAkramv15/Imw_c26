import 'package:flutter_test/flutter_test.dart';
import 'package:imo/data/gem_extras.dart';
import 'package:imo/data/gem_map_data.dart';
import 'package:imo/data/gem_nav.dart';
import 'package:imo/models/map_models.dart';
import 'package:imo/services/route_finder.dart';

void main() {
  final graph = MuseumGraph(allMaps);

  group('graph', () {
    test('every place is reachable from the ticket gate', () {
      expect(graph.unreachableFrom('cx_ticket'), isEmpty);
    });

    test('every place is reachable step-free (lifts, level floor)', () {
      expect(graph.unreachableFrom('cx_ticket', avoidStairs: true), isEmpty);
    });

    test('every place is reachable from every entrance and back', () {
      for (final from in ['mb_entrance', 'mg_entrance', 'tg_entrance', 'tg_exit']) {
        expect(graph.unreachableFrom(from), isEmpty, reason: from);
      }
    });

    test('edges and portals only reference known nodes', () {
      for (final e in kNavEdges) {
        expect(graph.has(e.a) && graph.has(e.b), isTrue, reason: '${e.a}-${e.b}');
        expect(graph.mapOf(e.a), graph.mapOf(e.b), reason: 'an edge never jumps between maps');
      }
      for (final p in kPortals) {
        expect(graph.has(p.a) && graph.has(p.b), isTrue, reason: '${p.a}-${p.b}');
      }
    });

    test('every door is a routing node on its map', () {
      for (final d in kDoors) {
        expect(graph.mapOf(d.id), d.mapId, reason: d.id);
      }
    });

    test('no waypoint is a dead end', () {
      final degree = <String, int>{};
      for (final e in kNavEdges) {
        degree[e.a] = (degree[e.a] ?? 0) + 1;
        degree[e.b] = (degree[e.b] ?? 0) + 1;
      }
      final dead = [
        for (final n in kNavNodes.keys)
          if (n.startsWith('w_') && (degree[n] ?? 0) < 2) n,
      ];
      expect(dead, isEmpty);
    });
  });

  group('routes', () {
    test('ticket gate to the colossus enters the main building through its door', () {
      final r = graph.find('cx_ticket', 'mb_1')!;
      expect(r.steps.first.kind, StepKind.start);
      expect(r.steps.last.kind, StepKind.arrive);
      expect(r.steps.any((s) => s.kind == StepKind.enterBuilding), isTrue);
      expect(r.legs.map((l) => l.mapId).toList(), ['gem_complex', 'main_building']);
      expect(r.usesStairs, isFalse);
    });

    test('standard route up to the galleries takes the staircase or the walkway', () {
      final r = graph.find('cx_ticket', 'mg_07')!;
      expect(r.steps.any((s) => s.kind == StepKind.stairs || s.kind == StepKind.travelator), isTrue);
      expect(r.legs.last.mapId, 'main_galleries');
    });

    test('step-free route up to the galleries takes the lift, never stairs or walkway', () {
      final r = graph.find('cx_ticket', 'mg_07', avoidStairs: true)!;
      expect(r.stepFree, isTrue);
      expect(r.usesStairs, isFalse);
      expect(r.usesTravelator, isFalse);
      expect(r.steps.where((s) => s.kind == StepKind.lift), isNotEmpty);
      expect(r.steps.where((s) => s.kind == StepKind.stairs || s.kind == StepKind.travelator), isEmpty);
    });

    test('step-free routes to every place avoid treads and the staircase', () {
      for (final p in allPlaces) {
        final r = graph.find('cx_ticket', p.id, avoidStairs: true);
        if (r == null) continue; // the place is the start itself or redirects to it
        expect(r.usesStairs, isFalse, reason: p.id);
        expect(r.usesTravelator, isFalse, reason: p.id);
      }
    });

    test('a level change on one plan starts a new leg (no line across the plan)', () {
      final r = graph.find('mb_entrance', 'mb_9', avoidStairs: true)!;
      final legs = r.legsOn('main_building');
      expect(legs.length, 2);
      expect(legs.first.portal?.kind, PortalKind.lift);
    });

    test('leaving the Tutankhamun Galleries to the car park', () {
      final r = graph.find('tg_mask', 'cx_parking_main')!;
      expect(r.legs.first.mapId, 'tutankhamun');
      expect(r.legs.last.mapId, 'gem_complex');
      expect(r.steps.any((s) => s.kind == StepKind.exitBuilding), isTrue);
    });

    test('the Glass Hall shops are reached through an opening in the hall wall', () {
      final r = graph.find('mb_entrance', 'mb_s5')!;
      expect(r.unverifiedDoors, isTrue);
      expect(r.steps.any((s) => s.kind == StepKind.door), isTrue);
    });

    test('after the staircase, walkway or lift the level reached is confirmed', () {
      for (final stepFree in [false, true]) {
        final r = graph.find('cx_ticket', 'mg_07', avoidStairs: stepFree)!;
        final i = r.steps.indexWhere((s) =>
            s.kind == StepKind.stairs || s.kind == StepKind.travelator || s.kind == StepKind.lift);
        expect(i, greaterThan(0), reason: 'stepFree=$stepFree');
        final change = r.steps[i];
        expect(change.down, isFalse);
        final next = r.steps[i + 1];
        expect(next.kind, StepKind.levelReached);
        expect(next.floor, change.floor);
        expect(next.mapId, 'main_galleries');
      }
    });

    test('treads inside the Main Galleries: "take the steps" on standard routes only', () {
      final r = graph.find('mg_entrance', 'mg_05')!;
      expect(r.usesStairs, isTrue);
      expect(r.steps.where((s) => s.kind == StepKind.steps), isNotEmpty);
      final sf = graph.find('mg_entrance', 'mg_05', avoidStairs: true)!;
      expect(sf.usesStairs, isFalse);
      expect(sf.steps.where((s) => s.kind == StepKind.steps), isEmpty);
    });

    test('the Grand Hall opens onto the foot of the Grand Staircase', () {
      final r = graph.find('mb_entrance', 'mb_7')!;
      expect(r.steps.any((s) => s.kind == StepKind.passage), isTrue);
    });

    test('lifts, clinic and prayer room are reached through the door at the wheelchair-access marker', () {
      final r = graph.find('mb_entrance', 'mb_lift1', avoidStairs: true)!;
      expect(r.legs.single.nodeIds, contains('mb_access_door'));
      expect(r.unverifiedDoors, isTrue);
    });

    test('redirected pins route to the place they point at', () {
      final r = graph.find('mb_entrance', 'mb_10')!;
      expect(r.steps.last.targetId, 'mg_tut');
    });

    test('distances and times are positive and consistent', () {
      final r = graph.find('cx_ticket', 'tg_mask')!;
      expect(r.meters, greaterThan(100));
      expect(r.seconds, greaterThanOrEqualTo(r.meters / MuseumGraph.walkSpeed));
      final sum = r.steps.fold(0.0, (a, s) => a + s.meters);
      expect(sum, closeTo(r.meters, 1));
    });

    test('route points stay inside the map', () {
      final r = graph.find('cx_parking_main', 'mg_12')!;
      for (final leg in r.legs) {
        for (final p in leg.points) {
          expect(p.dx, inInclusiveRange(0, 1));
          expect(p.dy, inInclusiveRange(0, 1));
        }
      }
    });

    test('same start and destination give no route', () {
      expect(graph.find('mb_1', 'mb_1'), isNull);
    });
  });

  group('tours', () {
    test('a tour visits every reachable stop once', () {
      final t = graph.tour('cx_ticket', ['tg_mask', 'mb_1', 'mg_05', 'mb_r1'])!;
      expect(t.order.toSet(), {'tg_mask', 'mb_1', 'mg_05', 'mb_r1'});
      expect(t.skipped, isEmpty);
      expect(t.route.steps.where((s) => s.kind == StepKind.stop).length, 4);
    });

    test('best order is never longer than the pinned order', () {
      const stops = ['mg_12', 'mb_1', 'mg_01', 'cx_obelisk'];
      final best = graph.tour('cx_ticket', stops)!;
      final pinned = graph.tour('cx_ticket', stops, optimize: false)!;
      expect(best.route.meters, lessThanOrEqualTo(pinned.route.meters + 1));
    });
  });

  test('nearestNodeId only returns connected nodes of that map', () {
    final id = graph.nearestNodeId('main_galleries', const Offset(0.5, 0.5))!;
    expect(graph.mapOf(id), 'main_galleries');
    expect(graph.find(id, 'mg_entrance'), isNotNull);
  });
}
