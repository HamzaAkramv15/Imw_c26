import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/gem_extras.dart';
import '../data/gem_nav.dart';
import '../data/gem_regions.dart';
import '../models/map_models.dart';

// ═══════════════════════════════════════════════════════════════
//  Results
// ═══════════════════════════════════════════════════════════════

enum StepKind {
  start,
  left,
  right,
  enterBuilding,
  exitBuilding,
  enterRoom,
  door,

  /// Through a stretch the plan leaves without a wall.
  passage,

  /// Over treads the plan draws inside a level (the plan does not say which
  /// end is higher, so no direction is given).
  steps,
  stairs,
  lift,
  travelator,

  /// Confirms the level reached after stairs, a lift or the moving walkway.
  levelReached,
  arrive,
  stop,
}

@immutable
class RouteStep {
  const RouteStep(
    this.kind, {
    required this.mapId,
    this.position,
    this.targetId,
    this.refMapId,
    this.regionId,
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

  /// Map being entered or left (for [StepKind.enterBuilding] / [StepKind.exitBuilding]).
  final String? refMapId;

  /// Hall, gallery or zone being entered (for [StepKind.enterRoom]).
  final String? regionId;
  final int floor;

  /// Stairs / lift / travelator go DOWN to [floor] (otherwise up).
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
    regionId: regionId,
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
    StepKind.enterRoom => Icons.meeting_room_outlined,
    StepKind.door => Icons.door_front_door_outlined,
    StepKind.passage => Icons.crop_free,
    StepKind.steps => Icons.stairs_outlined,
    StepKind.stairs => Icons.stairs,
    StepKind.lift => Icons.elevator,
    StepKind.travelator => Icons.moving,
    StepKind.levelReached => Icons.check_circle_outline,
    StepKind.arrive => Icons.flag,
    StepKind.stop => Icons.place,
  };
}

/// The part of a route that lies on one map, between two level changes.
@immutable
class RouteLeg {
  const RouteLeg(this.mapId, this.points, this.nodeIds, {this.nextMapId, this.portal, this.exitStep});
  final String mapId;

  /// Normalised points on [mapId].
  final List<Offset> points;
  final List<String> nodeIds;

  /// Set when the route continues on another map (through a door, stairs or lift).
  final String? nextMapId;

  /// The portal taken at the end of this leg (also set for a level change that
  /// stays on the same plan, e.g. the lift up to the Children's Museum).
  final Portal? portal;

  /// The instruction for that portal ("Take the lift up to the 2nd floor"),
  /// shown on the map where the leg ends.
  final RouteStep? exitStep;
}

@immutable
class RouteResult {
  const RouteResult({
    required this.legs,
    required this.steps,
    required this.meters,
    required this.seconds,
    required this.usesStairs,
    this.stepFree = false,
    this.usesTravelator = false,
    this.unverifiedDoors = false,
  });
  final List<RouteLeg> legs;
  final List<RouteStep> steps;
  final double meters;
  final double seconds;

  /// Climbs treads or takes the Grand Staircase somewhere along the way.
  final bool usesStairs;

  /// Planned with the step-free profile (lifts and level floor only).
  final bool stepFree;

  /// Rides the moving walkway beside the Grand Staircase.
  final bool usesTravelator;

  /// Passes an opening the official plan does not draw (see MapDoor.verified).
  final bool unverifiedDoors;

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
//  The graph
// ═══════════════════════════════════════════════════════════════

class _Node {
  _Node(this.id, this.mapId, this.pos);
  final String id;
  final String mapId;
  final Offset pos;
}

class _Edge {
  _Edge(this.to, this.meters, this.cost, {this.via = const [], this.stairs = false, this.portal});
  final String to;

  /// Bend points between the two nodes, normalised, ordered towards [to].
  final List<Offset> via;
  final double meters; // real length, used for distance and time
  final double cost; // what the router minimises
  final bool stairs;
  final Portal? portal;

  bool usableStepFree() => portal == null ? !stairs : portal!.stepFree;
}

/// A binary min-heap of (cost, node) pairs.
class _Heap {
  final List<double> _k = [];
  final List<String> _v = [];
  bool get isEmpty => _k.isEmpty;

  void push(double k, String v) {
    _k.add(k);
    _v.add(v);
    var i = _k.length - 1;
    while (i > 0) {
      final p = (i - 1) >> 1;
      if (_k[p] <= _k[i]) break;
      _swap(i, p);
      i = p;
    }
  }

  (double, String) pop() {
    final top = (_k.first, _v.first);
    final lk = _k.removeLast(), lv = _v.removeLast();
    if (_k.isNotEmpty) {
      _k[0] = lk;
      _v[0] = lv;
      var i = 0;
      while (true) {
        final l = 2 * i + 1, r = l + 1;
        var m = i;
        if (l < _k.length && _k[l] < _k[m]) m = l;
        if (r < _k.length && _k[r] < _k[m]) m = r;
        if (m == i) break;
        _swap(i, m);
        i = m;
      }
    }
    return top;
  }

  void _swap(int a, int b) {
    final k = _k[a], v = _v[a];
    _k[a] = _k[b];
    _v[a] = _v[b];
    _k[b] = k;
    _v[b] = v;
  }
}

/// Every map's walkable graph (generated from the plans, see tools/build_nav.py)
/// joined by the portals. Two profiles: standard, and step-free (no treads, no
/// staircase, no travelator: lifts and level floor only).
class MuseumGraph {
  MuseumGraph(
    this.maps, {
    this.nodes = kNavNodes,
    List<NavEdge>? edges,
    this.portals = kPortals,
    this.redirects = kRouteRedirects,
    this.placeFloors = kPlaceFloor,
    this.doors = kDoors,
  }) {
    _build(edges ?? kNavEdges);
  }

  final Map<String, GemMap> maps;
  final Map<String, NavNode> nodes;
  final List<Portal> portals;
  final Map<String, String> redirects;
  final Map<String, int> placeFloors;
  final List<MapDoor> doors;

  /// Average walking speed, m/s.
  static const double walkSpeed = 1.25;

  /// Treads cost more than level floor (effort), so a level detour of up to
  /// that much is preferred.
  static const double _treadPenalty = 1.6;
  static const double _staircasePenalty = 2.5;
  static const double _liftWaitSeconds = 40;
  static const double _turnAngle = 0.6; // radians, ~35°
  static const double _minTurnSegment = 12; // map units

  final Map<String, _Node> _nodes = {};
  final Map<String, List<_Edge>> _adj = {};
  final Map<String, MapPlace> _places = {};
  late final Map<String, MapDoor> _doorById = {for (final d in doors) d.id: d};

  // ── build ──────────────────────────────────────────────────────
  void _build(List<NavEdge> edges) {
    for (final m in maps.values) {
      for (final p in m.places) {
        _places[p.id] = p;
        // a place off the walkable floor of its plan (upper level) still needs
        // a node: its portals reach it
        _nodes[p.id] = _Node(p.id, m.id, nodes[p.id]?.position ?? p.position);
      }
    }
    nodes.forEach((id, n) {
      if (maps.containsKey(n.mapId)) _nodes[id] = _Node(id, n.mapId, n.position);
    });
    for (final e in edges) {
      final a = _nodes[e.a], b = _nodes[e.b];
      if (a == null || b == null || a.mapId != b.mapId) continue;
      final m = maps[a.mapId]!;
      final meters = _polyLength(m, [a.pos, ...e.via, b.pos]) * m.metersPerPixel;
      final cost = e.stairs ? meters * _treadPenalty : meters;
      _adj.putIfAbsent(e.a, () => []).add(_Edge(e.b, meters, cost, via: e.via, stairs: e.stairs));
      _adj.putIfAbsent(e.b, () => []).add(_Edge(e.a, meters, cost, via: e.via.reversed.toList(), stairs: e.stairs));
    }
    for (final pt in portals) {
      if (!_nodes.containsKey(pt.a) || !_nodes.containsKey(pt.b)) continue;
      final cost = switch (pt.kind) {
        PortalKind.stairs => pt.meters * _staircasePenalty,
        PortalKind.lift => pt.meters + _liftWaitSeconds * walkSpeed,
        PortalKind.door || PortalKind.travelator => pt.meters,
      };
      final stairs = pt.kind == PortalKind.stairs;
      _adj.putIfAbsent(pt.a, () => []).add(_Edge(pt.b, pt.meters, cost, stairs: stairs, portal: pt));
      _adj.putIfAbsent(pt.b, () => []).add(_Edge(pt.a, pt.meters, cost, stairs: stairs, portal: pt));
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

  // ── lookups ────────────────────────────────────────────────────
  bool has(String id) => _nodes.containsKey(id);

  /// Position (normalised) and map of any node.
  Offset? positionOf(String id) => _nodes[id]?.pos;
  String? mapOf(String id) => _nodes[id]?.mapId;

  /// Closest routable node to a point on a map (only nodes that have a
  /// connection, so a tap never lands on an unreachable pin).
  String? nearestNodeId(String mapId, Offset pos) {
    final m = maps[mapId];
    if (m == null) return null;
    String? best;
    var bd = double.infinity;
    for (final n in _nodes.values) {
      if (n.mapId != mapId || (_adj[n.id]?.isEmpty ?? true)) continue;
      final d = _unitDist(m, n.pos, pos);
      if (d < bd) {
        bd = d;
        best = n.id;
      }
    }
    return best;
  }

  int _floorOf(String nodeId) => placeFloors[nodeId] ?? maps[_nodes[nodeId]!.mapId]!.level;

  _Edge? _edge(String a, String b, bool stepFree) {
    _Edge? best;
    for (final e in _adj[a] ?? const <_Edge>[]) {
      if (e.to != b || (stepFree && !e.usableStepFree())) continue;
      if (best == null || e.cost < best.cost) best = e;
    }
    return best;
  }

  String? _nearPlace(String mapId, Offset pos, double maxUnits) {
    final m = maps[mapId]!;
    String? best;
    var bd = maxUnits;
    for (final p in m.places) {
      if (p.category == PlaceCategory.facility || p.category == PlaceCategory.parking) continue;
      if (placeFloors.containsKey(p.id)) continue; // not on this level
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
    required bool stepFree,
    String? stopAt,
  }) {
    final dist = <String, double>{from: 0};
    final prev = <String, String>{};
    final done = <String>{};
    final heap = _Heap()..push(0, from);
    while (!heap.isEmpty) {
      final (d, u) = heap.pop();
      if (!done.add(u)) continue;
      if (u == stopAt) break;
      for (final e in _adj[u] ?? const <_Edge>[]) {
        if (stepFree && !e.usableStepFree()) continue;
        final alt = d + e.cost;
        if (alt < (dist[e.to] ?? double.infinity)) {
          dist[e.to] = alt;
          prev[e.to] = u;
          heap.push(alt, e.to);
        }
      }
    }
    return (dist: dist, prev: prev);
  }

  /// Ids of places that cannot be reached from [from] with the profile.
  List<String> unreachableFrom(String from, {bool avoidStairs = false}) {
    final d = _dijkstra(from, stepFree: avoidStairs).dist;
    return [
      for (final id in _places.keys)
        if (!d.containsKey(redirects[id] ?? id)) id,
    ];
  }

  // ── single route ───────────────────────────────────────────────
  RouteResult? find(String from, String to, {bool avoidStairs = false}) {
    to = redirects[to] ?? to;
    from = redirects[from] ?? from;
    if (from == to || !_nodes.containsKey(from) || !_nodes.containsKey(to)) return null;
    final r = _dijkstra(from, stepFree: avoidStairs, stopAt: to);
    if (!r.dist.containsKey(to)) return null;
    final ids = <String>[to];
    while (ids.last != from) {
      ids.add(r.prev[ids.last]!);
    }
    return _assemble(ids.reversed.toList(), avoidStairs);
  }

  MapRegion? _roomAt(String mapId, Offset p) {
    MapRegion? best;
    for (final r in regionsFor(mapId)) {
      if (r.kind != RegionKind.gallery && r.kind != RegionKind.hall && r.kind != RegionKind.zone) continue;
      if (r.contains(p) && (best == null || r.area < best.area)) best = r;
    }
    return best;
  }

  RouteResult _assemble(List<String> ids, bool stepFree) {
    final legs = <RouteLeg>[];
    final raw = <(RouteStep, double)>[]; // step + cumulative metres where it happens
    var meters = 0.0, seconds = 0.0;
    var usesStairs = false, travelator = false, unverified = false;

    final first = _nodes[ids.first]!;
    var curMap = first.mapId;
    var legIds = <String>[ids.first];
    var legPts = <Offset>[first.pos];
    var legStart = 0.0; // metres at the start of the current leg
    var legMeters = <double>[0]; // cumulative metres at each leg point
    String? room = _roomAt(curMap, first.pos)?.id;
    var onSteps = false; // the previous edge climbed treads

    raw.add((
      RouteStep(StepKind.start, mapId: curMap, position: first.pos, targetId: _places.containsKey(ids.first) ? ids.first : null),
      0,
    ));

    void closeLeg({String? next, Portal? portal, RouteStep? exit}) {
      _turns(curMap, legPts, legMeters, legStart, raw);
      legs.add(RouteLeg(curMap, List.of(legPts), List.of(legIds), nextMapId: next, portal: portal, exitStep: exit));
    }

    for (var i = 1; i < ids.length; i++) {
      final a = ids[i - 1], b = ids[i];
      final e = _edge(a, b, stepFree)!;
      final na = _nodes[a]!, nb = _nodes[b]!;
      if (e.stairs) usesStairs = true;

      if (e.portal != null) {
        final kind = e.portal!.kind;
        if (kind == PortalKind.travelator) travelator = true;
        final goesDown = _floorOf(b) < _floorOf(a);
        final leaving = kOutdoorMaps.contains(nb.mapId) && !kOutdoorMaps.contains(na.mapId) || kSubMapParent[na.mapId] == nb.mapId;
        final step = switch (kind) {
          PortalKind.door => RouteStep(leaving ? StepKind.exitBuilding : StepKind.enterBuilding, mapId: na.mapId, position: na.pos, refMapId: leaving ? na.mapId : nb.mapId),
          PortalKind.stairs => RouteStep(StepKind.stairs, mapId: na.mapId, position: na.pos, floor: _floorOf(b), down: goesDown),
          PortalKind.lift => RouteStep(StepKind.lift, mapId: na.mapId, position: na.pos, floor: _floorOf(b), down: goesDown),
          PortalKind.travelator => RouteStep(StepKind.travelator, mapId: na.mapId, position: na.pos, floor: _floorOf(b), down: goesDown),
        };
        raw.add((step, meters));
        meters += e.meters;
        seconds += e.meters / walkSpeed + (kind == PortalKind.lift ? _liftWaitSeconds : 0);
        // on the other side: say which level the visitor is now on
        if (kind != PortalKind.door && _floorOf(a) != _floorOf(b)) {
          raw.add((RouteStep(StepKind.levelReached, mapId: nb.mapId, position: nb.pos, floor: _floorOf(b)), meters));
        }
        onSteps = false;
        // every portal is a level change or a change of plan: the leg ends here
        // (never a straight line drawn across the plan to the other level)
        closeLeg(next: na.mapId != nb.mapId ? nb.mapId : null, portal: e.portal, exit: step);
        curMap = nb.mapId;
        legIds = <String>[b];
        legPts = <Offset>[nb.pos];
        legStart = meters;
        legMeters = <double>[0];
        room = _roomAt(curMap, nb.pos)?.id;
        continue;
      }

      // treads drawn on the plan: one instruction where they begin
      String? stepsInto;
      if (e.stairs && !onSteps) {
        final r = _roomAt(nb.mapId, nb.pos);
        stepsInto = r != null && r.id != room ? r.id : null;
        raw.add((
          RouteStep(StepKind.steps, mapId: na.mapId, position: na.pos, regionId: stepsInto,
              targetId: stepsInto == null ? null : r!.placeId),
          meters,
        ));
      }
      onSteps = e.stairs;

      final m = maps[nb.mapId]!;
      var prevPt = legPts.last;
      for (final p in [...e.via, nb.pos]) {
        legMeters.add(legMeters.last + _unitDist(m, prevPt, p) * m.metersPerPixel);
        legPts.add(p);
        prevPt = p;
      }
      legIds.add(b);
      meters += e.meters;
      seconds += e.meters / walkSpeed;

      if (i + 1 < ids.length) {
        final door = _doorById[b];
        if (door != null) {
          final next = _edge(b, ids[i + 1], stepFree);
          final after = next == null || next.portal != null ? null : (next.via.isNotEmpty ? next.via.first : _nodes[ids[i + 1]]!.pos);
          final before = legPts[legPts.length - 2];
          // only when the route really goes through (not along the wall past
          // it): across a doorway's line, or from one room into another
          // through a passage (a passage opens a corner, not one straight wall)
          final through = after != null &&
              (door.kind == DoorKind.passage
                  ? _roomAt(nb.mapId, before)?.id != _roomAt(nb.mapId, after)?.id
                  : _side(door, before) * _side(door, after) < 0);
          if (through) {
            raw.add((RouteStep(door.kind == DoorKind.passage ? StepKind.passage : StepKind.door, mapId: nb.mapId, position: nb.pos), meters));
            if (!door.verified) unverified = true;
          }
        }
        final r = _roomAt(nb.mapId, nb.pos);
        // (entering a room up the treads was already said with the steps)
        if (r != null && r.id != room && r.id != stepsInto) {
          raw.add((RouteStep(StepKind.enterRoom, mapId: nb.mapId, position: nb.pos, regionId: r.id, targetId: r.placeId), meters));
        }
        room = r?.id ?? room;
      }
    }
    closeLeg();

    final last = ids.last;
    raw.add((
      RouteStep(StepKind.arrive, mapId: _nodes[last]!.mapId, position: _nodes[last]!.pos, targetId: _places.containsKey(last) ? last : null),
      meters,
    ));

    // turns were added per leg: put every step in walking order (ties keep
    // their insertion order — List.sort is not stable on its own)
    final order = List<int>.generate(raw.length, (i) => i)
      ..sort((x, y) {
        final c = raw[x].$2.compareTo(raw[y].$2);
        return c != 0 ? c : x.compareTo(y);
      });
    raw.setAll(0, [for (final i in order) raw[i]]);
    final steps = <RouteStep>[
      for (var i = 0; i < raw.length; i++) raw[i].$1.withMeters(i + 1 < raw.length ? raw[i + 1].$2 - raw[i].$2 : 0),
    ];
    return RouteResult(
      legs: legs,
      steps: steps,
      meters: meters,
      seconds: seconds,
      usesStairs: usesStairs,
      stepFree: stepFree,
      usesTravelator: travelator,
      unverifiedDoors: unverified,
    );
  }

  /// Which side of a door's wall [p] is on (+1 / -1).
  double _side(MapDoor d, Offset p) {
    final m = maps[d.mapId]!;
    final ax = (d.b.dx - d.a.dx) * m.imageSize.width, ay = (d.b.dy - d.a.dy) * m.imageSize.height;
    final px = (p.dx - d.a.dx) * m.imageSize.width, py = (p.dy - d.a.dy) * m.imageSize.height;
    return (ax * py - ay * px).sign;
  }

  /// Turn instructions along one leg: at every bend sharper than [_turnAngle]
  /// whose two sides are long enough to be a real change of direction.
  void _turns(String mapId, List<Offset> pts, List<double> cum, double start, List<(RouteStep, double)> out) {
    final m = maps[mapId]!;
    var lastAt = -double.infinity;
    for (var i = 1; i + 1 < pts.length; i++) {
      final va = Offset((pts[i].dx - pts[i - 1].dx) * m.imageSize.width, (pts[i].dy - pts[i - 1].dy) * m.imageSize.height);
      final vb = Offset((pts[i + 1].dx - pts[i].dx) * m.imageSize.width, (pts[i + 1].dy - pts[i].dy) * m.imageSize.height);
      if (va.distance < _minTurnSegment || vb.distance < _minTurnSegment) continue;
      final cross = va.dx * vb.dy - va.dy * vb.dx; // y points down → positive = turning right
      final dot = va.dx * vb.dx + va.dy * vb.dy;
      final angle = math.atan2(cross, dot);
      final at = start + cum[i];
      if (angle.abs() < _turnAngle || at - lastAt < 8) continue;
      lastAt = at;
      out.add((
        RouteStep(angle > 0 ? StepKind.right : StepKind.left, mapId: mapId, position: pts[i], targetId: _nearPlace(mapId, pts[i], 80)),
        at,
      ));
    }
  }

  // ── tours ──────────────────────────────────────────────────────
  /// Orders [stops] (nearest-neighbour + 2-opt on real walking costs)
  /// and joins them into one route starting at [start].
  TourResult? tour(String start, List<String> stops, {bool avoidStairs = false, bool optimize = true}) {
    final ids = <String>[];
    for (final s in stops) {
      final id = redirects[s] ?? s;
      if (id != start && !ids.contains(id) && _nodes.containsKey(id)) ids.add(id);
    }
    if (ids.isEmpty || !_nodes.containsKey(start)) return null;

    final all = [start, ...ids];
    final d = <String, Map<String, double>>{for (final a in all) a: _dijkstra(a, stepFree: avoidStairs).dist};
    double dd(String a, String b) => d[a]![b] ?? double.infinity;
    final reachable = [for (final s in ids) if (dd(start, s).isFinite) s];
    final skipped = [for (final s in ids) if (!dd(start, s).isFinite) s];
    if (reachable.isEmpty) return null;

    double cost(List<String> o) {
      var c = dd(start, o.first);
      for (var i = 0; i + 1 < o.length; i++) {
        c += dd(o[i], o[i + 1]);
      }
      return c;
    }

    var order = List<String>.of(reachable);
    if (optimize && order.length > 1) {
      final left = List<String>.of(reachable);
      order = [];
      var at = start;
      while (left.isNotEmpty) {
        left.sort((a, b) => dd(at, a).compareTo(dd(at, b)));
        at = left.removeAt(0);
        order.add(at);
      }
      var improved = true;
      while (improved) {
        improved = false;
        for (var i = 0; i < order.length - 1; i++) {
          for (var j = i + 1; j < order.length; j++) {
            final cand = [...order.sublist(0, i), ...order.sublist(i, j + 1).reversed, ...order.sublist(j + 1)];
            if (cost(cand) + 1e-6 < cost(order)) {
              order = cand;
              improved = true;
            }
          }
        }
      }
      // 2-opt finds a local optimum: never return worse than the order given
      if (cost(reachable) < cost(order)) order = List<String>.of(reachable);
    }

    final legs = <RouteLeg>[];
    final steps = <RouteStep>[];
    var meters = 0.0, seconds = 0.0;
    var stairs = false, travelator = false, unverified = false;
    var from = start;
    for (var i = 0; i < order.length; i++) {
      final r = find(from, order[i], avoidStairs: avoidStairs);
      if (r == null) continue;
      legs.addAll(r.legs);
      for (final s in r.steps) {
        if (s.kind == StepKind.start && i > 0) continue;
        steps.add(s.kind == StepKind.arrive
            ? RouteStep(StepKind.stop, mapId: s.mapId, position: s.position, targetId: s.targetId, index: i + 1)
            : s);
      }
      meters += r.meters;
      seconds += r.seconds;
      stairs = stairs || r.usesStairs;
      travelator = travelator || r.usesTravelator;
      unverified = unverified || r.unverifiedDoors;
      from = order[i];
    }
    return TourResult(
      order: order,
      skipped: skipped,
      route: RouteResult(
        legs: legs,
        steps: steps,
        meters: meters,
        seconds: seconds,
        usesStairs: stairs,
        stepFree: avoidStairs,
        usesTravelator: travelator,
        unverifiedDoors: unverified,
      ),
    );
  }
}
