import 'dart:ui';

import '../data/gem_extras.dart';
import '../data/gem_map_data.dart';
import '../data/gem_nav.dart';
import '../data/gem_rostau.dart';
import '../models/map_models.dart';
import '../models/rostau.dart';
import '../state/store.dart';
import 'route_finder.dart';

/// A trip turned into one walk.
class RostauPlan {
  const RostauPlan(this.trip, this.tour, this.onTheWay);
  final RostauTrip trip;

  /// Stops in walking order, the route, and the stops that cannot be reached
  /// with the current options.
  final TourResult tour;

  /// Highlights the walk passes close by that are not on the trip, in the
  /// order the walk reaches them: worth a glance on the way.
  final List<String> onTheWay;
}

/// Plans Rostau trips on the museum graph.
///
/// The order is the shortest walk through the stops ([MuseumGraph.tour]:
/// nearest neighbour, then 2-opt on real walking costs). What makes a trip more
/// than a list is what the walk passes: [onTheWay] names the highlights within
/// a few metres of it, so nothing worth seeing is walked past unnoticed.
class RostauPlanner {
  RostauPlanner(this.graph);
  final MuseumGraph graph;

  /// How close (metres) a highlight must be to the walk to be "on the way".
  static const double nearMeters = 12;

  RostauPlan? plan(RostauTrip trip, String from, {bool avoidStairs = false}) {
    final t = graph.tour(from, trip.stops, avoidStairs: avoidStairs);
    if (t == null) return null;
    return RostauPlan(trip, t, onTheWay(t.route, exclude: {from, ...trip.stops}));
  }

  /// Attractions within [nearMeters] of the route that are not in [exclude].
  List<String> onTheWay(RouteResult route, {Set<String> exclude = const {}}) {
    final found = <String, double>{}; // id -> metres along the route where it is passed
    var along = 0.0;
    for (final leg in route.legs) {
      final m = allMaps[leg.mapId];
      if (m == null || leg.points.length < 2) continue;
      final w = m.imageSize.width, h = m.imageSize.height, mpp = m.metersPerPixel;
      final pts = [for (final p in leg.points) Offset(p.dx * w, p.dy * h)];
      for (final place in m.places) {
        // upper-floor rooms drawn on the ground plan are not passed on foot
        if (place.category != PlaceCategory.attraction || exclude.contains(place.id) || kPlaceFloor.containsKey(place.id)) continue;
        final q = Offset(place.position.dx * w, place.position.dy * h);
        var run = along;
        for (var i = 0; i + 1 < pts.length; i++) {
          final seg = (pts[i + 1] - pts[i]).distance * mpp;
          if (_segDist(q, pts[i], pts[i + 1]) * mpp <= nearMeters) {
            found.putIfAbsent(place.id, () => run);
            break;
          }
          run += seg;
        }
      }
      for (var i = 0; i + 1 < pts.length; i++) {
        along += (pts[i + 1] - pts[i]).distance * mpp;
      }
    }
    return found.keys.toList()..sort((a, b) => found[a]!.compareTo(found[b]!));
  }

  static double _segDist(Offset p, Offset a, Offset b) {
    final d = b - a;
    final l2 = d.dx * d.dx + d.dy * d.dy;
    final t = l2 == 0 ? 0.0 : (((p.dx - a.dx) * d.dx + (p.dy - a.dy) * d.dy) / l2).clamp(0.0, 1.0);
    return (p - (a + d * t)).distance;
  }
}

/// The curated trips and the visitor's own, saved with the app state.
class RostauLibrary {
  RostauLibrary._();

  static const _key = 'rostau';

  /// Longest name and longest trip a visitor can save (the planner's 2-opt is
  /// cubic in the number of stops; 30 plans instantly).
  static const maxName = 60, maxStops = 30;

  static List<RostauTrip> get all => [...kRostauTrips, ...custom];

  static List<RostauTrip> get custom {
    final raw = Store.get(_key);
    if (raw is! List) return const [];
    final out = <RostauTrip>[];
    for (final e in raw) {
      final t = RostauTrip.fromJson(e);
      final stops = t == null ? const <String>[] : _clean(t.stops);
      if (stops.isNotEmpty) out.add(t!.copyWith(stops: stops));
    }
    return out;
  }

  static RostauTrip? byId(String id) {
    for (final t in all) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// Saves a new trip, or replaces the one with [id]. Unknown and repeated
  /// places are dropped; returns null when no place is left or the name is
  /// blank.
  static RostauTrip? save({String? id, required String name, required List<String> stops}) {
    final clean = _clean(stops);
    var n = name.trim();
    if (clean.isEmpty || n.isEmpty) return null;
    if (n.length > maxName) n = n.substring(0, maxName);
    final trip = RostauTrip.custom(id ?? 'c${DateTime.now().microsecondsSinceEpoch}', n, clean);
    final list = [for (final t in custom) if (t.id != trip.id) t, trip];
    Store.put({_key: [for (final t in list) t.toJson()]});
    return trip;
  }

  static void delete(String id) {
    Store.put({_key: [for (final t in custom) if (t.id != id) t.toJson()]});
  }

  static List<String> _clean(List<String> stops) {
    final out = <String>[];
    for (final s in stops) {
      if (out.length == maxStops) break;
      if (placeById(s) != null && !out.contains(s)) out.add(s);
    }
    return out;
  }
}
