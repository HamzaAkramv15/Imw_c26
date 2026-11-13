import 'package:flutter_test/flutter_test.dart';
import 'package:imo/data/gem_map_data.dart';
import 'package:imo/services/route_finder.dart';

/// Directions a visitor can follow: few, distinct and meaningful. Checked on
/// every journey between the highlights, galleries and entrances.
void main() {
  final graph = MuseumGraph(allMaps);
  final ids = [
    for (final m in allMaps.values)
      for (final p in m.places)
        if (p.category.name == 'attraction' || p.category.name == 'gallery' || p.category.name == 'entrance') p.id,
  ];
  final routes = <(String, String, RouteResult)>[];
  for (final a in ids) {
    for (final b in ids) {
      if (a == b) continue;
      final r = graph.find(a, b);
      if (r != null) routes.add((a, b, r));
    }
  }

  bool isTurn(StepKind k) => k == StepKind.left || k == StepKind.right;

  test('there are journeys to check', () => expect(routes.length, greaterThan(200)));

  test('a turn never names the start or the destination as its landmark', () {
    for (final (a, b, r) in routes) {
      for (final s in r.steps.where((s) => isTurn(s.kind))) {
        expect(s.targetId, isNot(anyOf(a, b)), reason: '$a → $b');
      }
    }
  });

  test('the same turn at the same landmark is not said twice in a row', () {
    for (final (a, b, r) in routes) {
      final turns = r.steps.where((s) => isTurn(s.kind)).toList();
      for (var i = 1; i < r.steps.length; i++) {
        final x = r.steps[i - 1], y = r.steps[i];
        if (isTurn(x.kind) && isTurn(y.kind)) {
          expect(x.kind == y.kind && x.targetId == y.targetId && x.meters < 40, isFalse, reason: '$a → $b');
        }
      }
      expect(turns.length, lessThanOrEqualTo(r.steps.length));
    }
  });

  test('a doorway is not announced right before entering the room behind it', () {
    for (final (a, b, r) in routes) {
      for (var i = 1; i < r.steps.length; i++) {
        final x = r.steps[i - 1], y = r.steps[i];
        final door = x.kind == StepKind.door || x.kind == StepKind.passage;
        expect(door && y.kind == StepKind.enterRoom && x.meters < 6, isFalse, reason: "$a → $b ${x.meters}");
      }
    }
  });

  test('on average, no more than one instruction every 20 m', () {
    var steps = 0, meters = 0.0;
    for (final (_, _, r) in routes) {
      steps += r.steps.length;
      meters += r.meters;
    }
    expect(meters / steps, greaterThan(20));
  });

  test('every instruction has its place on the map', () {
    for (final (a, b, r) in routes) {
      for (final s in r.steps) {
        expect(s.position, isNotNull, reason: '$a → $b ${s.kind}');
        expect(allMaps.containsKey(s.mapId), isTrue);
      }
    }
  });
}
