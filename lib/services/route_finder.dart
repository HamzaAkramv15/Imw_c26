import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/gem_extras.dart';
import '../data/gem_paths.dart';
import '../models/map_models.dart';

// ═══════════════════════════════════════════════════════════════
//  Results
// ═══════════════════════════════════════════════════════════════

enum StepKind { start, left, right, enterBuilding, exitBuilding, stairs, lift, arrive, stop }

@immutable
class RouteStep {
  const RouteStep(
    this.kind, {
    required this.mapId,
    this.position,
    this.targetId,
    this.refMapId,
    this.floor = 0,
    this.down = false,
    this.index = 0,
    this.meters = 0,
  });

  final StepKind kind;
  final String mapId;
  final Offset? position;

  /// Place named in the instruction ("turn left near …", "arrive at …").
  final String? targetId;

  /// Map being entered (for [StepKind.enterBuilding]).
  final String? refMapId;
  final int floor;

  /// Stairs / lift go DOWN to [floor] (otherwise up).
  final bool down;

  /// Stop number in a tour.
  final int index;

  /// Walking distance until the next instruction.
  final double meters;

  RouteStep withMeters(double m) => RouteStep(
    kind,
    mapId: mapId,
    position: position,
    targetId: targetId,
    refMapId: refMapId,
    floor: floor,
    down: down,
    index: index,
    meters: m,
  );

  IconData get icon => switch (kind) {
    StepKind.start => Icons.trip_origin,
    StepKind.left => Icons.turn_left,
    StepKind.right => Icons.turn_right,
    StepKind.enterBuilding => Icons.login,
    StepKind.exitBuilding => Icons.logout,
    StepKind.stairs => Icons.stairs,
    StepKind.lift => Icons.elevator,
    StepKind.arrive => Icons.flag,
    StepKind.stop => Icons.place,
  };
}

/// The part of a route that lies on one map.
@immutable
class RouteLeg {
  const RouteLeg(this.mapId, this.points, this.nodeIds, {this.nextMapId, this.portal});
  final String mapId;

  /// Normalised points on [mapId].
  final List<Offset> points;
  final List<String> nodeIds;

  /// Set when the route leaves this map here (through a door, stairs or lift).
  final String? nextMapId;
  final Portal? portal;
}

@immutable
class RouteResult {
  const RouteResult({
    required this.legs,
    required this.steps,
    required this.meters,
    required this.seconds,
    required this.usesStairs,
  });
  final List<RouteLeg> legs;
  final List<RouteStep> steps;
  final double meters;
  final double seconds;
  final bool usesStairs;

  Duration get walkTime => Duration(seconds: seconds.round());
  List<RouteLeg> legsOn(String mapId) => [for (final l in legs) if (l.mapId == mapId) l];
}

@immutable
class TourResult {
  const TourResult({required this.order, required this.route, required this.skipped});

  /// Stop ids in visiting order.
  final List<String> order;
  final RouteResult route;

  /// Stops that cannot be reached with the current options.
  final List<String> skipped;
}

// ═══════════════════════════════════════════════════════════════
//  The graph: every map, plus the portals that join them
// ═══════════════════════════════════════════════════════════════

class _Node {
  _Node(this.id, this.mapId, this.pos);
  final String id;
  final String mapId;
  final Offset pos;
}

class _Edge {
  _Edge(this.to, this.meters, this.cost, {this.stairs = false, this.portal, this.via = const []});
  final String to;

  /// Bend points between the two nodes (wall-aware path), normalised.
  final List<Offset> via;
  final double meters; // real length, used for distance/time
  final double cost; // what the router minimises (stairs are penalised)
  final bool stairs;
  final Portal? portal;
}

class MuseumGraph {
  MuseumGraph(
    this.maps, {
    this.portals = const [],
    this.stairEdges = const {},
    this.redirects = const {},
    this.placeFloors = const {},
  }) {
    _build();
  }

  final Map<String, GemMap> maps;
  final List<Portal> portals;
  final Set<String> stairEdges;
  final Map<String, String> redirects;
  final Map<String, int> placeFloors;

  /// Average walking speed, m/s.
  static const double walkSpeed = 1.25;
  static const double _stairsPenalty = 2.5;
  static const double _liftWaitSeconds = 40;

  final Map<String, _Node> _nodes = {};
  final Map<String, List<_Edge>> _adj = {};
  final Map<String, MapPlace> _places = {};

  // ── build ──────────────────────────────────────────────────────
  void _build() {
    for (final m in maps.values) {
      for (final p in m.places) {
        _nodes[p.id] = _Node(p.id, m.id, p.position);
        _places[p.id] = p;
      }
      m.junctions.forEach((id, pos) => _nodes[id] = _Node(id, m.id, pos));
    }
    for (final m in maps.values) {
      for (final e in m.edges) {
        _link(e.$1, e.$2, stairs: stairEdges.contains('${e.$1}|${e.$2}') || stairEdges.contains('${e.$2}|${e.$1}'));
      }
      for (final p in m.places.where((p) => p.autoConnect)) {
        final linked = kPinLinks[p.id];
        if (linked != null && m.junctions.containsKey(linked)) {
          _link(p.id, linked);
          continue;
        }
        String? best;
        var bd = double.infinity;
        for (final j in m.junctions.entries) {
          final d = _unitDist(m, p.position, j.value);
          if (d < bd) {
            bd = d;
            best = j.key;
          }
        }
        if (best != null) _link(p.id, best);
      }
    }
    for (final pt in portals) {
      _link(pt.a, pt.b, meters: pt.meters, portal: pt, stairs: pt.kind == PortalKind.stairs);
    }
  }

  double _unitDist(GemMap m, Offset a, Offset b) {
    final dx = (a.dx - b.dx) * m.imageSize.width;
    final dy = (a.dy - b.dy) * m.imageSize.height;
    return math.sqrt(dx * dx + dy * dy);
  }

  double _polyLength(GemMap m, List<Offset> pts) {
    var d = 0.0;
    for (var i = 1; i < pts.length; i++) {
      d += _unitDist(m, pts[i - 1], pts[i]);
    }
    return d;
  }

  void _link(String a, String b, {double? meters, bool stairs = false, Portal? portal}) {
    final na = _nodes[a], nb = _nodes[b];
    if (na == null || nb == null) return;
    final m = maps[na.mapId]!;
    var via = const <Offset>[];
    if (portal == null && na.mapId == nb.mapId) {
      final fwd = a.compareTo(b) < 0;
      final stored = kEdgePaths[fwd ? '$a|$b' : '$b|$a'];
      if (stored != null) via = fwd ? stored : stored.reversed.toList();
    }
    final len = meters ?? _polyLength(m, [na.pos, ...via, nb.pos]) * m.metersPerPixel;
    final cost = stairs ? len * _stairsPenalty : len;
    _adj.putIfAbsent(a, () => []).add(_Edge(b, len, cost, stairs: stairs, portal: portal, via: via));
    _adj.putIfAbsent(b, () => []).add(_Edge(a, len, cost, stairs: stairs, portal: portal, via: via.reversed.toList()));
  }

  // ── helpers ────────────────────────────────────────────────────
  bool has(String id) => _nodes.containsKey(id);

  /// Position (normalised) and map of any node (place or junction).
  Offset? positionOf(String id) => _nodes[id]?.pos;
  String? mapOf(String id) => _nodes[id]?.mapId;

  /// Closest routable node (place or junction) to a point on a map.
  String? nearestNodeId(String mapId, Offset pos) {
    final m = maps[mapId];
    if (m == null) return null;
    String? best;
    var bd = double.infinity;
    for (final n in _nodes.values.where((n) => n.mapId == mapId)) {
      final d = _unitDist(m, n.pos, pos);
      if (d < bd) {
        bd = d;
        best = n.id;
      }
    }
    return best;
  }

  int _floorOf(String nodeId) => placeFloors[nodeId] ?? maps[_nodes[nodeId]!.mapId]!.level;

  _Edge? _edge(String a, String b) {
    _Edge? best;
    for (final e in _adj[a] ?? const <_Edge>[]) {
      if (e.to == b && (best == null || e.cost < best.cost)) best = e;
    }
    return best;
  }

  String? _nearPlace(String mapId, Offset pos, double maxUnits) {
    final m = maps[mapId]!;
    String? best;
    var bd = maxUnits;
    for (final p in m.places) {
      if (p.category == PlaceCategory.facility || p.category == PlaceCategory.parking) continue;
      final d = _unitDist(m, p.position, pos);
      if (d < bd) {
        bd = d;
        best = p.id;
      }
    }
    return best;
  }

  ({Map<String, double> dist, Map<String, String> prev}) _dijkstra(
    String from, {
    required bool avoidStairs,
    String? stopAt,
  }) {
    final dist = <String, double>{for (final k in _nodes.keys) k: double.infinity};
    final prev = <String, String>{};
    final open = _nodes.keys.toSet();
    dist[from] = 0;
    while (open.isNotEmpty) {
      String? u;
      var best = double.infinity;
      for (final k in open) {
        final d = dist[k]!;
        if (d < best) {
          best = d;
          u = k;
        }
      }
      if (u == null || u == stopAt) break;
      open.remove(u);
      for (final e in _adj[u] ?? const <_Edge>[]) {
        if (avoidStairs && e.stairs) continue;
        if (!open.contains(e.to)) continue;
        final alt = best + e.cost;
        if (alt < dist[e.to]!) {
          dist[e.to] = alt;
          prev[e.to] = u;
        }
      }
    }
    return (dist: dist, prev: prev);
  }

  // ── single route ───────────────────────────────────────────────
  RouteResult? find(String from, String to, {bool avoidStairs = false}) {
    to = redirects[to] ?? to;
    if (from == to || !_nodes.containsKey(from) || !_nodes.containsKey(to)) return null;
    final r = _dijkstra(from, avoidStairs: avoidStairs, stopAt: to);
    if (r.dist[to]!.isInfinite) return null;
    final ids = <String>[to];
    var cur = to;
    while (cur != from) {
      cur = r.prev[cur]!;
      ids.add(cur);
    }
    return _assemble(ids.reversed.toList());
  }

  RouteResult _assemble(List<String> ids) {
    final legs = <RouteLeg>[];
    final raw = <(RouteStep, double)>[]; // step + cumulative metres where it happens
    var meters = 0.0, seconds = 0.0;
    var usesStairs = false;

    var curMap = _nodes[ids.first]!.mapId;
    var legIds = <String>[ids.first];
    var legPts = <Offset>[_nodes[ids.first]!.pos];

    raw.add((
      RouteStep(StepKind.start, mapId: curMap, position: _nodes[ids.first]!.pos, targetId: _places.containsKey(ids.first) ? ids.first : null),
      0,
    ));

    void closeLeg({String? next, Portal? portal}) {
      legs.add(RouteLeg(curMap, List.of(legPts), List.of(legIds), nextMapId: next, portal: portal));
    }

    for (var i = 1; i < ids.length; i++) {
      final a = ids[i - 1], b = ids[i];
      final e = _edge(a, b)!;
      final na = _nodes[a]!, nb = _nodes[b]!;
      meters += e.meters;
      seconds += e.meters / walkSpeed;
      if (e.stairs) usesStairs = true;

      if (e.portal != null) {
        final kind = e.portal!.kind;
        final goesDown = _floorOf(b) < _floorOf(a);
        final leaving = kOutdoorMaps.contains(nb.mapId) && !kOutdoorMaps.contains(na.mapId) || kSubMapParent[na.mapId] == nb.mapId;
        final step = switch (kind) {
          PortalKind.door => RouteStep(leaving ? StepKind.exitBuilding : StepKind.enterBuilding, mapId: na.mapId, position: na.pos, refMapId: leaving ? na.mapId : nb.mapId),
          PortalKind.stairs => RouteStep(StepKind.stairs, mapId: na.mapId, position: na.pos, floor: _floorOf(b), down: goesDown),
          PortalKind.lift => RouteStep(StepKind.lift, mapId: na.mapId, position: na.pos, floor: _floorOf(b), down: goesDown),
        };
        if (kind == PortalKind.lift) seconds += _liftWaitSeconds;
        raw.add((step, meters - e.meters));
        if (na.mapId != nb.mapId) {
          closeLeg(next: nb.mapId, portal: e.portal);
          curMap = nb.mapId;
          legIds = <String>[b];
          legPts = <Offset>[nb.pos];
        } else {
          legIds.add(b);
          legPts.add(nb.pos);
        }
        continue;
      }

      legIds.add(b);
      legPts
        ..addAll(e.via)
        ..add(nb.pos);
      // Turn detection at b (needs a walkable edge after it).
      if (i + 1 < ids.length) {
        final next = _edge(b, ids[i + 1]);
        if (next != null && next.portal == null) {
          final m = maps[nb.mapId]!;
          final pIn = e.via.isNotEmpty ? e.via.last : na.pos;
          final nc = _nodes[ids[i + 1]]!;
          final pOut = next.via.isNotEmpty ? next.via.first : nc.pos;
          final va = Offset((nb.pos.dx - pIn.dx) * m.imageSize.width, (nb.pos.dy - pIn.dy) * m.imageSize.height);
          final vb = Offset((pOut.dx - nb.pos.dx) * m.imageSize.width, (pOut.dy - nb.pos.dy) * m.imageSize.height);
          if (va.distance > 10 && vb.distance > 10) {
            final cross = va.dx * vb.dy - va.dy * vb.dx; // y points down → positive = turning right
            final dot = va.dx * vb.dx + va.dy * vb.dy;
            final angle = math.atan2(cross, dot);
            if (angle.abs() > 0.6) {
              raw.add((
                RouteStep(
                  angle > 0 ? StepKind.right : StepKind.left,
                  mapId: nb.mapId,
                  position: nb.pos,
                  targetId: _nearPlace(nb.mapId, nb.pos, 80 * 1.0),
                ),
                meters,
              ));
            }
          }
        }
      }
    }
    closeLeg();

    final last = ids.last;
    raw.add((
      RouteStep(StepKind.arrive, mapId: _nodes[last]!.mapId, position: _nodes[last]!.pos, targetId: _places.containsKey(last) ? last : null),
      meters,
    ));

    final steps = <RouteStep>[
      for (var i = 0; i < raw.length; i++)
        raw[i].$1.withMeters(i + 1 < raw.length ? raw[i + 1].$2 - raw[i].$2 : 0),
    ];
    return RouteResult(legs: legs, steps: steps, meters: meters, seconds: seconds, usesStairs: usesStairs);
  }

  // ── tours ──────────────────────────────────────────────────────
  /// Orders [stops] (nearest-neighbour + 2-opt on real walking distances)
  /// and joins them into one route starting at [start].
  TourResult? tour(String start, List<String> stops, {bool avoidStairs = false, bool optimize = true}) {
    final ids = <String>[];
    for (final s in stops) {
      final id = redirects[s] ?? s;
      if (id != start && !ids.contains(id) && _nodes.containsKey(id)) ids.add(id);
    }
    if (ids.isEmpty || !_nodes.containsKey(start)) return null;

    final all = [start, ...ids];
    final d = <String, Map<String, double>>{for (final a in all) a: _dijkstra(a, avoidStairs: avoidStairs).dist};
    final reachable = [for (final s in ids) if (d[start]![s]!.isFinite) s];
    final skipped = [for (final s in ids) if (!d[start]![s]!.isFinite) s];
    if (reachable.isEmpty) return null;

    double cost(List<String> o) {
      var c = d[start]![o.first]!;
      for (var i = 0; i + 1 < o.length; i++) {
        c += d[o[i]]![o[i + 1]]!;
      }
      return c;
    }

    var order = List<String>.of(reachable);
    if (optimize && order.length > 1) {
      // nearest neighbour
      final left = List<String>.of(reachable);
      order = [];
      var at = start;
      while (left.isNotEmpty) {
        left.sort((a, b) => d[at]![a]!.compareTo(d[at]![b]!));
        at = left.removeAt(0);
        order.add(at);
      }
      // 2-opt
      var improved = true;
      while (improved) {
        improved = false;
        for (var i = 0; i < order.length - 1; i++) {
          for (var j = i + 1; j < order.length; j++) {
            final cand = [
              ...order.sublist(0, i),
              ...order.sublist(i, j + 1).reversed,
              ...order.sublist(j + 1),
            ];
            if (cost(cand) + 1e-6 < cost(order)) {
              order = cand;
              improved = true;
            }
          }
        }
      }
    }

    final legs = <RouteLeg>[];
    final steps = <RouteStep>[];
    var meters = 0.0, seconds = 0.0;
    var stairs = false;
    var from = start;
    for (var i = 0; i < order.length; i++) {
      final r = find(from, order[i], avoidStairs: avoidStairs);
      if (r == null) continue;
      legs.addAll(r.legs);
      for (final s in r.steps) {
        if (s.kind == StepKind.start && i > 0) continue;
        if (s.kind == StepKind.arrive) {
          steps.add(RouteStep(StepKind.stop, mapId: s.mapId, position: s.position, targetId: s.targetId, index: i + 1));
        } else {
          steps.add(s);
        }
      }
      meters += r.meters;
      seconds += r.seconds;
      stairs = stairs || r.usesStairs;
      from = order[i];
    }
    return TourResult(
      order: order,
      skipped: skipped,
      route: RouteResult(legs: legs, steps: steps, meters: meters, seconds: seconds, usesStairs: stairs),
    );
  }
}
