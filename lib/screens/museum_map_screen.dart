import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../data/gem_extras.dart';
import '../data/gem_map_data.dart';
import '../data/gem_nav.dart';
import '../data/gem_regions.dart';
import '../data/gem_stories.dart';
import '../i18n/lang.dart';
import '../i18n/strings.dart';
import '../models/map_models.dart';
import '../models/rostau.dart';
import '../services/rostau.dart';
import '../services/route_finder.dart';
import '../services/search_engine.dart';
import '../state/app_state.dart';
import '../state/store.dart';
import '../theme.dart';
import 'directions_sheet.dart';
import 'lore_sheets.dart';
import '../widgets/era_bar.dart';
import '../widgets/gem_ui.dart';
import '../widgets/map_control.dart';
import '../widgets/museum_map_canvas.dart';
import '../widgets/story_block.dart';
import 'place_detail_sheet.dart';
import 'rostau_sheet.dart';
import 'search_page.dart';
import 'tour_sheet.dart';
import 'where_am_i_sheet.dart';

class MuseumMapScreen extends StatefulWidget {
  const MuseumMapScreen({super.key});

  @override
  State<MuseumMapScreen> createState() => _MuseumMapScreenState();
}

class _MuseumMapScreenState extends State<MuseumMapScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final AppState _app = AppState.instance;
  final ToastController _toast = ToastController();

  /// One graph for every map, joined by doors / stairs / lifts.
  late final MuseumGraph _graph = MuseumGraph(allMaps);

  /// Each map keeps its own zoom / position, so coming back to it finds it
  /// exactly as you left it.
  final Map<String, TransformationController> _views = {
    for (final id in allMaps.keys) id: TransformationController(),
  };

  GemMap _map = groundMap;
  late List<MapRegion> _regions = regionsFor(_map.id);

  MapPlace? _selected;
  String? _selectedRegionId;
  String? _highlightGroup;
  PlaceCategory? _filter;

  /// Ordered (insertion order) so the tour starts as the visitor pinned.
  final Set<String> _pinned = {};

  /// Where the visitor says they are: a routing node (place or junction).
  /// Null until they tell us; every route then asks (we never guess).
  String? _originNode;
  bool _picking = false;
  VoidCallback? _afterOrigin;

  RouteResult? _route;
  String? _routeTargetId;
  String _routeLabel = '';
  List<String>? _tourOrder;

  /// The Rostau trip being walked (null for the pinned tour or a single route).
  String? _tripId;

  /// How many of [_tourOrder]'s stops are behind the visitor, where they
  /// started the walk, and the route they have walked so far.
  int _tripDone = 0;
  String? _tripStart;
  RouteResult? _walked;

  /// On a walk, the way on from the stop the visitor is heading for (drawn
  /// light; [_route] is only the stretch to that stop).
  RouteResult? _later;

  /// The instruction of [_route] shown on the card and marked on the map
  /// (an index into [_steps]).
  int _stepIndex = 0;
  Rect? _focusRect;

  int _resetTick = 0;
  int _zoomTick = 0;
  double _zoomFactor = 1;
  Offset? _focusPoint;
  int _focusTick = 0;
  final Map<String, int> _quarter = {};

  /// Measured height of the bottom stack (route card, era timeline, tabs).
  double? _bottomH;

  /// Landscape when last built: turning the device fits the map again, into
  /// the room the new layout leaves it.
  bool? _wasWide;

  late final AnimationController _routeAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  late final Animation<double> _routeProgress = CurvedAnimation(
    parent: _routeAnim,
    curve: Curves.easeOut,
  );

  Offset? get _originPos =>
      _originNode == null ? null : _graph.positionOf(_originNode!);
  String? get _originMapId =>
      _originNode == null ? null : _graph.mapOf(_originNode!);
  int get _quarterTurns => _quarter[_map.id] ?? 0;
  TransformationController get _view => _views[_map.id]!;

  @override
  void initState() {
    super.initState();
    _app.addListener(_onAppChanged);
    WidgetsBinding.instance.addObserver(this);
    _restore();
    for (final v in _views.values) {
      v.addListener(_scheduleSave);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    _saveNow();
    _app.removeListener(_onAppChanged);
    _routeAnim.dispose();
    _toast.dispose();
    for (final v in _views.values) {
      v.removeListener(_scheduleSave);
      v.dispose();
    }
    super.dispose();
  }

  // ── saved state: everything you did is still there next time ───
  Timer? _saveTimer;

  /// Any setState may have changed something worth keeping.
  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _scheduleSave();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // leaving the app (home button, swipe away): write immediately
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _saveTimer?.cancel();
      _saveNow();
    }
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), _saveNow);
  }

  void _saveNow() {
    Store.put({
      'map': _map.id,
      'pinned': _pinned.toList(),
      'origin': _originNode,
      'quarter': _quarter,
      'routeTarget': _routeTargetId,
      'tour': _tourOrder,
      'trip': _tripId,
      'tripDone': _tripDone,
      'tripStart': _tripStart,
      'views': {
        for (final e in _views.entries)
          if (!e.value.value.isIdentity())
            e.key: e.value.value.storage.toList(),
      },
    });
  }

  void _restore() {
    final map = allMaps[Store.get('map')];
    if (map != null) {
      _map = map;
      _regions = regionsFor(map.id);
    }
    final pinned = Store.get('pinned');
    if (pinned is List) {
      _pinned.addAll([
        for (final id in pinned)
          if (id is String && placeById(id) != null) id,
      ]);
    }
    final origin = Store.get('origin');
    if (origin is String && _graph.positionOf(origin) != null) {
      _originNode = origin;
    }
    final q = Store.get('quarter');
    if (q is Map) {
      q.forEach((k, v) {
        if (k is String && v is int) _quarter[k] = v;
      });
    }
    final views = Store.get('views');
    if (views is Map) {
      views.forEach((k, v) {
        final ctl = _views[k];
        if (ctl != null && v is List && v.length == 16) {
          ctl.value = Matrix4.fromList([
            for (final x in v) (x as num).toDouble(),
          ]);
        }
      });
    }
    // bring the route (or tour) back once the first frame is up
    final target = Store.get('routeTarget');
    final tour = Store.get('tour');
    final trip = Store.get('trip');
    final done = Store.get('tripDone'), start = Store.get('tripStart');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _originNode == null) return;
      if (tour is List && tour.isNotEmpty) {
        if (start is String && _graph.positionOf(start) != null) {
          _tripStart = start;
        }
        _startTour(
          [
            for (final id in tour)
              if (id is String) id,
          ],
          quiet: true,
          tripId: trip is String && RostauLibrary.byId(trip) != null
              ? trip
              : null,
          resume: done is int ? done : 0,
        );
      } else if (target is String) {
        _routeTo(target, label: S.placeId(target), quiet: true);
      }
    });
  }

  /// Language or "avoid stairs" changed: redraw, and re-plan the active route.
  void _onAppChanged() {
    if (!mounted) return;
    setState(() {});
    _replan();
  }

  /// The category picked in the row, and always the stops of the walk.
  List<MapPlace> get _visiblePlaces => _filter == null
      ? _map.places
      : _map.places
            .where((p) => p.category == _filter || _stopNodes.containsKey(p.id))
            .toList();

  /// The galleries of the era picked in the timeline (lit on the plan).
  Set<String> get _highlightedIds => regionsInGroup(_regions, _highlightGroup);

  // ── maps ───────────────────────────────────────────────────────
  void _setMap(String mapId) {
    final next = allMaps[mapId];
    if (next == null || next.id == _map.id) return;
    _focusPoint = null;
    _focusRect = null;
    setState(() {
      _map = next;
      _regions = regionsFor(next.id);
      _selected = null;
      _selectedRegionId = null;
      _highlightGroup = null;
      _filter = null;
    });
  }

  void _openLinkedMap(String mapId) {
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    _setMap(mapId);
  }

  void _resetView() => setState(() => _resetTick++);

  void _zoom(double factor) => setState(() {
    _zoomFactor = factor;
    _zoomTick++;
  });

  void _rotateView() => setState(() {
    _quarter[_map.id] = (_quarterTurns + 1) % 2;
    _resetTick++;
  });

  /// "Where am I?": ask if we don't know, otherwise fly to the marker.
  void _locateMe() {
    if (_originNode == null) {
      _askOrigin();
      return;
    }
    final mapId = _originMapId;
    if (mapId != null) _setMap(mapId);
    setState(() {
      _focusPoint = _originPos;
      _focusRect = null;
      _focusTick++;
    });
  }

  // ── places & regions ───────────────────────────────────────────
  MapRegion? _regionOfPlace(String placeId) {
    for (final r in _regions) {
      if (r.placeId == placeId) return r;
    }
    return null;
  }

  Future<void> _selectPlace(MapPlace p) async {
    if (_picking) {
      _setOriginNode(p.id);
      return;
    }
    final owner = mapIdOfPlace(p.id);
    if (owner != null && owner != _map.id) _setMap(owner);
    setState(() {
      _selected = p;
      _selectedRegionId = _regionOfPlace(p.id)?.id;
    });
    await _showDetailSheet(p);
    if (mounted) setState(() => _selected = null);
  }

  Future<void> _showDetailSheet(MapPlace p) {
    // how far it is from where the visitor said they are (no GPS indoors)
    final from = _originNode;
    final there = from == null || from == p.id ? null : _graph.find(from, p.id, avoidStairs: _app.avoidStairs);
    final walk = there == null ? null : '${S.minutes(there.walkTime)} · ${S.distance(there.meters)}';
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black45,
      builder: (_) => PlaceDetailSheet(
        place: p,
        walk: walk,
        isPinned: _pinned.contains(p.id),
        isRouteTarget: _routeTargetId == p.id,
        isOrigin: _originNode == p.id,
        onPin: () => setState(() {
          if (!_pinned.remove(p.id)) _pinned.add(p.id);
        }),
        onRoute: () {
          Navigator.of(context).pop();
          _routeTo(p.id, label: S.place(p));
        },
        onSetOrigin: () {
          Navigator.of(context).pop();
          _setOriginNode(p.id);
        },
        onOpenLinkedMap: _openLinkedMap,
      ),
    );
  }

  void _onRegionTap(MapRegion r) {
    final place = r.placeId == null ? null : placeById(r.placeId!);
    if (place != null) {
      _selectPlace(place);
      return;
    }
    setState(() {
      _selected = null;
      _selectedRegionId = r.id;
    });
    final story = storyFor(r.id);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black38,
      isScrollControlled: story != null,
      builder: (context) => SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .86,
          ),
          child: GemSheetFrame(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            GemEyebrow(S.t('f_halls')),
                            const SizedBox(height: 4),
                            Text(
                              S.region(r),
                              style: TextStyle(
                                fontSize: 22,
                                color: context.pal.ink,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: () {
                          Navigator.of(context).pop();
                          final node = _graph.nearestNodeId(_map.id, r.labelAt);
                          if (node != null) _routeTo(node, label: S.region(r));
                        },
                        icon: const Icon(Icons.alt_route, size: 18),
                        label: Text(S.t('region_route')),
                        style: gemFilled(context),
                      ),
                    ],
                  ),
                  if (story != null) ...[
                    const SizedBox(height: 18),
                    StoryBlock(story),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── "where am I?" ──────────────────────────────────────────────
  /// Ask the visitor. [then] runs once a location is known.
  Future<void> _askOrigin({VoidCallback? then}) async {
    final r = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const WhereAmISheet(),
    );
    if (r == null || !mounted) return;
    if (r == WhereAmISheet.pickOnMap) {
      setState(() {
        _picking = true;
        _afterOrigin = then;
        _selected = null;
      });
      return;
    }
    _setOriginNode(r, then: then);
  }

  void _setOriginNode(String id, {VoidCallback? then}) {
    final todo = then ?? _afterOrigin;
    _afterOrigin = null;
    setState(() {
      _originNode = id;
      _picking = false;
      // standing at a stop still ahead: it, and every stop before it, is done
      final g = _progress;
      if (g != null) _tripDone = g.at(id).done;
    });
    final mapId = _graph.mapOf(id);
    if (mapId != null && mapId != _map.id) _setMap(mapId);
    _toast.show(
      S.t('location_set', x: S.nodeName(id)),
      icon: Icons.my_location,
    );
    if (todo != null) {
      todo();
    } else {
      _replan();
    }
  }

  void _cancelPick() => setState(() {
    _picking = false;
    _afterOrigin = null;
  });

  /// A tap on the map while picking: snap to the nearest routing node there.
  void _onPickTap(Offset n) {
    final id = _graph.nearestNodeId(_map.id, n);
    if (id != null) _setOriginNode(id);
  }

  /// Long-press: shortcut for "I'm here".
  void _onLongPress(Offset n) {
    final id = _graph.nearestNodeId(_map.id, n);
    if (id != null) _setOriginNode(id);
  }

  /// Re-plan whatever is on screen (new start, language, step-free…).
  void _replan() {
    if (_originNode == null) return;
    if (_tourOrder != null) {
      _planTrip(quiet: true);
    } else if (_routeTargetId != null) {
      _routeTo(_routeTargetId!, label: _routeLabel, quiet: true);
    }
  }

  // ── settings ───────────────────────────────────────────────────
  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .9,
          ),
          child: _SettingsSheet(
            onRotate: () {
              Navigator.of(context).pop();
              _rotateView();
            },
          ),
        ),
      ),
    );
  }

  // ── routes ─────────────────────────────────────────────────────
  void _routeTo(String destId, {required String label, bool quiet = false}) {
    final from = _originNode;
    if (from == null) {
      _askOrigin(then: () => _routeTo(destId, label: label));
      return;
    }
    if ((kRouteRedirects[destId] ?? destId) == from) {
      if (!quiet) {
        _toast.show(S.t('already_here'), icon: Icons.check_circle_outline);
      }
      return;
    }
    final r = _graph.find(from, destId, avoidStairs: _app.avoidStairs);
    if (r == null) {
      if (!quiet) {
        _toast.show(
          S.t(_app.avoidStairs ? 'no_step_free' : 'no_path'),
          icon: Icons.block,
        );
      }
      return;
    }
    setState(() {
      _route = r;
      _tourOrder = null;
      _routeTargetId = destId;
      _routeLabel = label;
      _tripId = null;
      _resetProgress();
    });
    _revealRoute();
    _showStep(0, quiet: quiet);
  }

  void _revealRoute() {
    if (MediaQuery.disableAnimationsOf(context)) {
      _routeAnim.value = 1;
    } else {
      _routeAnim.forward(from: 0);
    }
  }

  /// Walk [ids] as one route: the pinned tour, or the Rostau trip [tripId].
  /// A new walk is put in the shortest order from where the visitor stands;
  /// with [resume] (stops already done) [ids] keep the order given.
  void _startTour(
    List<String> ids, {
    bool quiet = false,
    String? tripId,
    int? resume,
  }) {
    final from = _originNode;
    if (from == null) {
      _askOrigin(then: () => _startTour(ids, tripId: tripId));
      return;
    }
    if (resume != null) {
      setState(() {
        _tourOrder = ids;
        _tripDone = resume;
        _routeTargetId = null;
        _tripId = tripId;
        _routeLabel = _tripTitle ?? S.t('my_tour');
      });
      _planTrip(quiet: quiet);
      return;
    }
    final t = _graph.tour(from, ids, avoidStairs: _app.avoidStairs);
    if (t == null) {
      if (!quiet) {
        _toast.show(
          S.t(_app.avoidStairs ? 'no_step_free' : 'no_path'),
          icon: Icons.block,
        );
      }
      return;
    }
    setState(() {
      _tourOrder = t.order;
      _routeTargetId = null;
      _tripId = tripId;
      _routeLabel = _tripTitle ?? S.t('my_tour');
      _resetProgress();
      _tripStart = from;
    });
    _planTrip(quiet: quiet);
    if (!quiet && t.skipped.isNotEmpty) {
      _toast.show(
        S.t('skipped', x: S.list(t.skipped.map(S.placeId))),
        icon: Icons.block,
      );
    }
  }

  TripProgress? get _progress =>
      _tourOrder == null ? null : TripProgress(_tourOrder!, _tripDone);

  void _resetProgress() {
    _tripDone = 0;
    _tripStart = null;
    _walked = null;
    _later = null;
    _stepIndex = 0;
  }

  /// The walk in its planned order, in three parts: the stretch from where
  /// the visitor is to the stop they are heading for (the route proper, with
  /// its directions), the way on through the stops after it (drawn light),
  /// and the part already walked (drawn faint).
  void _planTrip({bool quiet = false}) {
    final g = _progress, from = _originNode;
    if (g == null || from == null) return;
    final next = g.next;
    final ahead = next == null
        ? null
        : _graph.find(from, next, avoidStairs: _app.avoidStairs);
    final later = next == null || g.remaining.length < 2
        ? null
        : _graph.tour(
            next,
            g.remaining.sublist(1),
            avoidStairs: _app.avoidStairs,
            optimize: false,
          );
    final start = _tripStart ?? (g.walked.isEmpty ? null : g.walked.first);
    final behind = start == null || g.walked.isEmpty
        ? null
        : _graph.tour(
            start,
            g.walked,
            avoidStairs: _app.avoidStairs,
            optimize: false,
          );
    if (ahead == null && next != null && next != from && !quiet) {
      _toast.show(
        S.t(_app.avoidStairs ? 'no_step_free' : 'no_path'),
        icon: Icons.block,
      );
    }
    setState(() {
      _route = ahead;
      _later = later?.route;
      _walked = behind?.route;
      _stepIndex = 0;
    });
    if (ahead != null) {
      _revealRoute();
      _showStep(0, quiet: quiet);
    }
  }

  /// "Arrived" at the stop that was next: it is done, and the visitor is there.
  void _arrive() {
    final g = _progress;
    final here = g?.next;
    if (g == null || here == null) return;
    setState(() {
      _tripDone = g.arrive().done;
      _originNode = here;
    });
    _planTrip();
  }

  /// The place a stop of the walk stands for. [_tourOrder] holds routing nodes,
  /// and a few places are reached through another node (kRouteRedirects).
  String _stopPlace(String node) {
    if (placeById(node) != null) return node;
    final listed = _trip?.stops ?? _pinned;
    String? any;
    for (final e in kRouteRedirects.entries) {
      if (e.value != node) continue;
      if (listed.contains(e.key)) return e.key;
      any ??= e.key;
    }
    return any ?? node;
  }

  /// Place id -> its stop's node, for every stop of the walk.
  Map<String, String> get _stopNodes => {
    for (final n in _tourOrder ?? const <String>[]) _stopPlace(n): n,
  };

  /// The instructions of the route, without its "start here" line.
  List<RouteStep> get _steps => [
    for (final st in _route?.steps ?? const <RouteStep>[])
      if (st.kind != StepKind.start) st,
  ];

  /// Show instruction [i]: on the card, marked on the map, and the camera
  /// glides over the stretch that leads to it (opening its plan first).
  /// [quiet] (a route restored at launch) leaves the view as it was.
  void _showStep(int i, {bool quiet = false}) {
    final steps = _steps, r = _route;
    if (steps.isEmpty || r == null) return;
    i = i.clamp(0, steps.length - 1);
    setState(() => _stepIndex = i);
    if (quiet) return;
    final st = steps[i];
    final at = st.position;
    if (at == null) return;
    if (st.mapId != _map.id) _setMap(st.mapId);
    // from the instruction before it, when that is on the same plan
    final k = r.steps.indexOf(st);
    final prev = k > 0 ? r.steps[k - 1] : null;
    var rect = Rect.fromCenter(center: at, width: 0.02, height: 0.02);
    if (prev?.position != null && prev!.mapId == st.mapId) {
      rect = rect.expandToInclude(
        Rect.fromPoints(prev.position!, prev.position!),
      );
    }
    setState(() {
      _focusRect = rect.inflate(0.01);
      _focusPoint = rect.center;
      _focusTick++;
    });
  }

  /// How far the instruction being read is from the one before it.
  double _metersTo(RouteStep st) {
    final all = _route?.steps ?? const <RouteStep>[];
    final k = all.indexOf(st);
    return k > 0 ? all[k - 1].meters : 0;
  }

  RostauTrip? get _trip =>
      _tripId == null ? null : RostauLibrary.byId(_tripId!);
  String? get _tripTitle => _trip?.titleIn(S.lang);

  void _clearRoute() {
    setState(() {
      _route = null;
      _routeTargetId = null;
      _tourOrder = null;
      _tripId = null;
      _focusRect = null;
      _resetProgress();
    });
    _routeAnim.reset();
  }

  void _setStepFree(bool v) {
    _app.setAvoidStairs(v);
    _toast.show(
      S.t(v ? 'step_free_on' : 'step_free_off'),
      icon: v ? Icons.accessible_forward : Icons.directions_walk,
    );
  }

  void _openDirections() {
    final r = _route;
    if (r == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DirectionsSheet(
        title: _tourOrder != null
            ? (_tripTitle ?? _routeLabel)
            : S.t('route_to', x: _routeLabel),
        route: r,
        current: _steps.isEmpty
            ? null
            : _steps[_stepIndex.clamp(0, _steps.length - 1)],
        onStepTap: (s) {
          Navigator.of(context).pop();
          final i = _steps.indexOf(s);
          i < 0 ? _setMap(s.mapId) : _showStep(i);
        },
        onToggleStairs: (v) {
          Navigator.of(context).pop();
          _setStepFree(v);
        },
      ),
    );
  }

  void _openTour() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TourSheet(
        graph: _graph,
        stopIds: _pinned.toList(),
        originId: _originNode,
        originName: _originNode == null ? null : S.nodeName(_originNode!),
        onChangeOrigin: () {
          Navigator.of(context).pop();
          _askOrigin(then: _openTour);
        },
        onRemove: (id) => setState(() => _pinned.remove(id)),
        onStart: (order) {
          Navigator.of(context).pop();
          _startTour(order);
        },
        onSaveAsTrip: (ids) async {
          Navigator.of(context).pop();
          final trip = await Navigator.of(
            context,
          ).push(TripEditorPage.route(stops: ids));
          if (trip is RostauTrip && mounted) {
            _toast.show(S.t('trip_saved'), icon: Icons.check_circle_outline);
            _openTrips();
          }
        },
      ),
    );
  }

  // ── Rostau trips ───────────────────────────────────────────────
  /// The trips sheet; [tripId] opens it straight on one trip (after the
  /// visitor chose where they start).
  void _openTrips({String? tripId}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RostauSheet(
        graph: _graph,
        originId: _originNode,
        pinnedCount: _pinned.length,
        activeTripId: _tripId,
        openTripId: tripId,
        onOpenTour: () {
          Navigator.of(context).pop();
          _openTour();
        },
        onChooseStart: (reopen) {
          Navigator.of(context).pop();
          _askOrigin(then: () => _openTrips(tripId: reopen));
        },
        onStart: (trip, order) {
          Navigator.of(context).pop();
          _startTour(order, tripId: trip.id);
        },
        onPlaceTap: (id) {
          final place = placeById(id);
          if (place == null) return;
          Navigator.of(context).pop();
          _selectPlace(place);
        },
        onMessage: (m) => _toast.show(m, icon: Icons.check_circle_outline),
      ),
    );
  }

  // ── search ─────────────────────────────────────────────────────
  Future<void> _openSearch() async {
    // nearest first, by walking distance from where the visitor said they are
    // (no GPS indoors); recomputed each time, so it follows their position
    final from = _originNode;
    final e = await Navigator.of(context).push<SearchEntry>(SearchPage.route(
      near: from == null ? null : _graph.metersFrom(from, avoidStairs: _app.avoidStairs),
      onLocate: () => _askOrigin(then: _openSearch),
    ));
    if (e == null || !mounted) return;
    if (e.place != null) {
      _selectPlace(e.place!);
    } else if (e.region != null) {
      _setMap(e.region!.mapId);
      _onRegionTap(e.region!);
    }
  }

  // ── build ──────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final safe = MediaQuery.paddingOf(context);
    final galleries = _map.id == 'main_galleries';
    final parent = kSubMapParent[_map.id];
    final b = kContentBounds[_map.id];
    final tall =
        b != null &&
        ((b.width * _map.imageSize.width) /
                (b.height * _map.imageSize.height)) <
            1.4;
    // The control column sits at the *end* edge (the left one in Arabic), so the
    // room kept free for it is on that side too.
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final screen = MediaQuery.sizeOf(context);
    final screenW = screen.width;
    final gutter = tall || screenW > screen.height ? 60.0 : 12.0;
    // in landscape the notch side has an inset too
    final endInset = rtl ? safe.left : safe.right;
    // locate (46) + gap + zoom pill (89) + gap + my tour (46), at end: 12, top: safe.top + 124
    final controlsRect = Rect.fromLTWH(
      rtl ? 12 + endInset : screenW - 12 - 46 - endInset,
      safe.top + 124,
      46,
      46 + 10 + 89 + 10 + 46,
    ).inflate(6);
    // The bottom stack is never wider than a phone. In landscape it sits at the
    // start edge, so it never runs under the control column at the end edge,
    // and the map is fitted beside it instead of above it.
    final wide = screenW > screen.height;
    if (_wasWide != null && _wasWide != wide) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _resetView();
      });
    }
    _wasWide = wide;
    final panelW = math.min(
      wide ? 440.0 : 560.0,
      screenW - safe.horizontal - (wide ? 12 + 46 + 12 + 12 : 0),
    );
    final bottomH =
        _bottomH ?? (galleries ? 110 : 66) + (_route != null ? 76 : 0);
    // the map is fitted above the stack, but always keeps half the screen
    final stackTop = safe.bottom + 10 + bottomH + 8;
    final bottomPad = math.min(stackTop, screen.height * .5);
    final panelRect = Rect.fromLTWH(
      wide
          ? (rtl ? screenW - safe.right - panelW : safe.left)
          : (screenW - panelW) / 2,
      screen.height - safe.bottom - 10 - bottomH,
      panelW,
      bottomH,
    );
    final side =
        (wide ? panelW : 0) + 8; // the start edge, past the stack in landscape
    final mapPadding = EdgeInsets.fromLTRB(
      rtl ? gutter + endInset : safe.left + side,
      safe.top + 112,
      rtl ? safe.right + side : gutter + endInset,
      wide ? safe.bottom + 12 : bottomPad,
    );
    final legs = _route?.legsOn(_map.id) ?? const <RouteLeg>[];

    return Scaffold(
      backgroundColor: p.mapBg,
      body: Stack(
        children: [
          // ── the map (one canvas per map; cross-fades when you switch) ──
          Positioned.fill(
            // no cross-fade: a canvas that is fading in has zero opacity, and Flutter then
            // skips painting it, which is exactly when the map bitmap is captured
            child: Builder(
              builder: (context) => KeyedSubtree(
                key: ValueKey(_map.id),
                child: MuseumMapCanvas(
                  map: _map,
                  places: _visiblePlaces,
                  regions: _regions,
                  highlighted: _highlightedIds,
                  selected: _selected,
                  selectedRegionId: _selectedRegionId,
                  pinned: _pinned,
                  legs: legs,
                  walkedLegs: _walked?.legsOn(_map.id) ?? const <RouteLeg>[],
                  laterLegs: _later?.legsOn(_map.id) ?? const <RouteLeg>[],
                  trip: _progress,
                  stopNodes: _stopNodes,
                  stepFocus: _steps.isEmpty
                      ? null
                      : _steps[_stepIndex.clamp(0, _steps.length - 1)],
                  focusRect: _focusRect,
                  routeProgress: _routeProgress,
                  routeTargetId: _routeTargetId,
                  originMapId: _originMapId,
                  originPos: _originPos,
                  pickMode: _picking,
                  showAllPins: _filter != null,
                  transform: _view,
                  resetTick: _resetTick,
                  quarterTurns: _quarterTurns,
                  focusPoint: _focusPoint,
                  focusTick: _focusTick,
                  zoomTick: _zoomTick,
                  zoomFactor: _zoomFactor,
                  onFocusDone: () =>
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          setState(() {
                            _focusPoint = null;
                            _focusRect = null;
                          });
                        }
                      }),
                  padding: mapPadding,
                  // the stack only covers the map where it is taller than the padding
                  keepClear: [
                    controlsRect,
                    if (wide || bottomPad < stackTop) panelRect,
                  ],
                  onPlaceTap: _selectPlace,
                  onRegionTap: _onRegionTap,
                  onEmptyTap: () => setState(() {
                    _selected = null;
                    _selectedRegionId = null;
                  }),
                  onPickTap: _onPickTap,
                  onLongPress: _onLongPress,
                  onPortalTap: _setMap,
                ),
              ),
            ),
          ),

          // ── soft fades so the controls sit on the map instead of floating on top of it ──
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: safe.top + 124,
            child: IgnorePointer(child: _Scrim(color: p.mapBg, down: true)),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: safe.bottom + 150,
            child: IgnorePointer(child: _Scrim(color: p.mapBg, down: false)),
          ),

          // ── top: search, menu, tour, categories ──
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          Expanded(child: SearchPill(onTap: _openSearch)),
                          const SizedBox(width: 8),
                          RoundAction(
                            tooltip: S.t('settings'),
                            onTap: _openSettings,
                            child: Icon(
                              Icons.tune_rounded,
                              size: 22,
                              color: p.ink,
                            ),
                          ),
                          const SizedBox(width: 8),
                          RoundAction(
                            tooltip: S.t('trips'),
                            onTap: _openTrips,
                            active: _tripId != null,
                            child: GlyphIcon(
                              'wat',
                              size: 24,
                              color: _tripId != null ? p.onAccent : p.gold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: _picking
                          ? Padding(
                              key: const ValueKey('pick'),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: _pickBanner(p),
                            )
                          : Align(
                              key: ValueKey('cat_${_map.id}'),
                              alignment: AlignmentDirectional.centerStart,
                              child: CategoryRow(
                                categories: _map.categories,
                                selected: _filter,
                                onSelect: (c) => setState(() => _filter = c),
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── right: map controls (three, not five) ──
          PositionedDirectional(
            end: 12 + endInset,
            top: safe.top + 124,
            child: Column(
              children: [
                MapControl(
                  icon: _originNode == null
                      ? Icons.location_searching
                      : Icons.my_location,
                  tooltip: S.t('locate_me'),
                  onTap: _locateMe,
                  active: _originNode != null,
                ),
                const SizedBox(height: 10),
                ZoomPill(
                  onIn: () => _zoom(1.6),
                  onOut: () => _zoom(1 / 1.6),
                  inTip: S.t('zoom_in'),
                  outTip: S.t('zoom_out'),
                ),
                const SizedBox(height: 10),
                RoundAction(
                  tooltip: S.t('my_tour'),
                  onTap: _openTour,
                  badge: _pinned.length,
                  child: Icon(
                    _pinned.isEmpty
                        ? Icons.bookmarks_outlined
                        : Icons.bookmarks,
                    size: 22,
                    color: p.accent,
                  ),
                ),
              ],
            ),
          ),

          // ── bottom: route card, era timeline, tabs ──
          Positioned(
            left: safe.left,
            right: safe.right,
            bottom: safe.bottom + 10,
            child: Align(
              alignment: wide
                  ? AlignmentDirectional.bottomStart
                  : Alignment.bottomCenter,
              child: SizedBox(
                width: panelW,
                child: _SizeReporter(
                  onSize: (sz) {
                    if (mounted && (sz.height - (_bottomH ?? -1)).abs() > .5) {
                      setState(() => _bottomH = sz.height);
                    }
                  },
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedSize(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.bottomCenter,
                        child: _route == null && _tourOrder == null
                            ? const SizedBox(width: double.infinity)
                            : Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  0,
                                  12,
                                  8,
                                ),
                                child: _tourOrder != null
                                    ? _tripCard(p)
                                    : _routeCard(p),
                              ),
                      ),
                      if (galleries) ...[
                        EraBar(
                          selected: _highlightGroup,
                          onSelect: (e) => setState(() => _highlightGroup = e),
                        ),
                        const SizedBox(height: 8),
                      ],
                      if (parent != null)
                        _BackPill(
                          label: S.t(
                            'back_to',
                            x: S.mapShort(allMaps[parent]!),
                          ),
                          onTap: () => _setMap(parent),
                        )
                      else
                        _MapSwitcher(
                          currentMapId: _map.id,
                          onSwitch: (id) =>
                              id == _map.id ? _resetView() : _setMap(id),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── toast ──
          Positioned(
            top: safe.top + 116,
            left: 12 + 46 + 12,
            right: 12 + 46 + 12,
            child: IgnorePointer(
              child: Center(child: GemToastHost(toast: _toast.value)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pickBanner(GemPalette p) => Container(
    constraints: const BoxConstraints(minHeight: 44),
    padding: const EdgeInsetsDirectional.only(start: 14, end: 4),
    decoration: BoxDecoration(
      color: p.accent,
      borderRadius: BorderRadius.circular(22),
      boxShadow: gemShadow(p),
    ),
    child: Row(
      children: [
        Icon(Icons.touch_app, color: p.onAccent, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            S.t('pick_hint'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Arial',
              fontSize: 14,
              color: p.onAccent,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        TextButton(
          onPressed: _cancelPick,
          child: Text(
            S.t('cancel'),
            style: TextStyle(
              fontFamily: 'Arial',
              color: p.onAccent.withValues(alpha: .75),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );

  /// The walk being followed, readable at a glance: the stop to go to now and
  /// its number, where the walk ends, how many stops are done (in words and as
  /// a row of segments), and "Arrived" to tick the stop off. Tap it for the
  /// directions to the next stop.
  Widget _tripCard(GemPalette p) {
    final g = _progress!;
    final next = g.next, finish = g.finish;
    // a trip by its title alone ("The Great House"), so it fits the card
    final name = _trip == null
        ? S.t('my_tour')
        : splitTripTitle(_trip!, S.lang).$2;
    final title = next == null
        ? S.t('trip_complete')
        : S.t(
            'trip_next',
            x: '${S.t('stop_of', n: g.nextNumber, x: '${g.total}')} — ${S.placeId(_stopPlace(next))}',
          );
    final meta = [
      S.t('trip_done_of', n: g.done, x: '${g.total}'),
      if (next != null && finish != null)
        S.t('trip_finish', x: S.placeId(_stopPlace(finish)))
      else
        name,
    ].join(' · ');
    final text = TextStyle(fontFamily: 'Arial', fontSize: 12, color: p.muted);
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: p.line.withValues(alpha: .8)),
        boxShadow: gemShadow(p, lift: 1.3),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: _route == null ? null : _openDirections,
          borderRadius: BorderRadius.circular(26),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 6, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    // done / total, as a ring
                    SizedBox(
                      width: 42,
                      height: 42,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Positioned.fill(
                            child: CircularProgressIndicator(
                              value: g.total == 0 ? 0 : g.done / g.total,
                              strokeWidth: 4,
                              color: p.accent,
                              backgroundColor: p.accent.withValues(alpha: .14),
                            ),
                          ),
                          next == null
                              ? Icon(Icons.check, color: p.accent, size: 22)
                              : Text(
                                  '${g.done}/${g.total}',
                                  style: TextStyle(
                                    fontFamily: 'Arial',
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: p.ink,
                                  ),
                                ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Arial',
                              fontSize: 15,
                              height: 1.2,
                              color: p.ink,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            meta,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _clearRoute,
                      tooltip: S.t('clear_route'),
                      icon: Icon(Icons.close, color: p.muted, size: 20),
                    ),
                  ],
                ),
                if (_route != null) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 6),
                    child: _stepStrip(p),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    // one segment per stop: done, the one to go to now, still ahead
                    Expanded(
                      child: Row(
                        children: [
                          for (var i = 0; i < g.total; i++)
                            Expanded(
                              child: Container(
                                height: 6,
                                margin: const EdgeInsetsDirectional.only(
                                  end: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: i < g.done
                                      ? p.accent
                                      : i == g.done
                                      ? p.rose
                                      : p.line,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 9),
                    Tooltip(
                      message: next == null ? '' : S.t('arrived_hint'),
                      child: FilledButton.icon(
                        onPressed: next == null ? _clearRoute : _arrive,
                        icon: Icon(
                          next == null ? Icons.flag : Icons.check,
                          size: 18,
                        ),
                        label: Text(S.t(next == null ? 'end_trip' : 'arrived')),
                        style: gemFilled(context).copyWith(
                          padding: const WidgetStatePropertyAll(
                            EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// One calm card: where to, how far, and a clear "Start". Tap it for the directions.
  Widget _routeCard(GemPalette p) {
    final r = _route!;
    final title = S.t('to_x', x: _routeLabel);
    final meta = [S.distance(r.meters), S.minutes(r.walkTime)].join(' · ');
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: p.line.withValues(alpha: .8)),
        boxShadow: gemShadow(p, lift: 1.3),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: _openDirections,
          borderRadius: BorderRadius.circular(26),
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 6, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: p.accent.withValues(alpha: .14),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.alt_route, color: p.accent, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'Arial',
                              fontSize: 16,
                              color: p.ink,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  meta,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: 'Arial',
                                    fontSize: 12,
                                    color: p.muted,
                                  ),
                                ),
                              ),
                              if (_app.avoidStairs) ...[
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.accessible_forward,
                                  size: 14,
                                  color: p.accent,
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _clearRoute,
                      tooltip: S.t('clear_route'),
                      icon: Icon(Icons.close, color: p.muted, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  child: _stepStrip(p),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The one instruction to follow now, with the buttons to step through the
  /// others (the map marks where it happens and glides there). Tap it for
  /// the full list.
  Widget _stepStrip(GemPalette p) {
    final steps = _steps;
    if (steps.isEmpty) return const SizedBox.shrink();
    final i = _stepIndex.clamp(0, steps.length - 1);
    final st = steps[i];
    final ahead = _metersTo(st);
    final meta = [
      S.t('step_n_of', n: i + 1, x: '${steps.length}'),
      if (ahead > 4) S.t('step_in', x: S.distance(ahead)),
    ].join(' · ');
    final last = st.kind == StepKind.arrive || st.kind == StepKind.stop;
    return Container(
      decoration: BoxDecoration(
        color: p.accent.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: S.t('step_prev'),
            onPressed: i > 0 ? () => _showStep(i - 1) : null,
            icon: Icon(
              Icons.chevron_left, // mirrors itself in right-to-left text
              size: 26,
            ),
            color: p.ink,
          ),
          Expanded(
            child: InkWell(
              onTap: _openDirections,
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: Row(
                    key: ValueKey(i),
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: last ? p.rose : p.accent,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(st.icon, size: 19, color: p.onAccent),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Semantics(
                          liveRegion: true,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                S.step(st),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'Arial',
                                  fontSize: 15,
                                  height: 1.2,
                                  fontWeight: FontWeight.w800,
                                  color: p.ink,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                meta,
                                maxLines: 1,
                                style: TextStyle(
                                  fontFamily: 'Arial',
                                  fontSize: 12,
                                  color: p.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: S.t('step_next'),
            onPressed: i < steps.length - 1 ? () => _showStep(i + 1) : null,
            icon: Icon(
              Icons.chevron_right,
              size: 26,
            ),
            color: p.ink,
          ),
        ],
      ),
    );
  }
}

/// Reports its child's size after every layout that changes it (the bottom
/// stack, so the map is fitted above whatever it holds right now).
class _SizeReporter extends SingleChildRenderObjectWidget {
  const _SizeReporter({required this.onSize, super.child});
  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSizeReporter(onSize);

  @override
  void updateRenderObject(BuildContext context, _RenderSizeReporter r) =>
      r.onSize = onSize;
}

class _RenderSizeReporter extends RenderProxyBox {
  _RenderSizeReporter(this.onSize);
  ValueChanged<Size> onSize;
  Size? _last;

  @override
  void performLayout() {
    super.performLayout();
    if (size == _last) return;
    _last = size;
    final s = size;
    WidgetsBinding.instance.addPostFrameCallback((_) => onSize(s));
  }
}

/// Fades the map into the UI colour at the top / bottom edge.
class _Scrim extends StatelessWidget {
  const _Scrim({required this.color, required this.down});
  final Color color;
  final bool down;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: down ? Alignment.topCenter : Alignment.bottomCenter,
        end: down ? Alignment.bottomCenter : Alignment.topCenter,
        colors: [
          color.withValues(alpha: .88),
          color.withValues(alpha: .55),
          color.withValues(alpha: 0),
        ],
        stops: const [0, .55, 1],
      ),
    ),
  );
}

class _MapSwitcher extends StatelessWidget {
  const _MapSwitcher({required this.currentMapId, required this.onSwitch});
  final String currentMapId;
  final void Function(String) onSwitch;

  static IconData _icon(String id) => switch (id) {
    'gem_complex' => Icons.account_balance_outlined,
    'main_building' => Icons.place_outlined,
    'main_galleries' => Icons.photo_library_outlined,
    _ => Icons.map_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final maps = allMaps.values
        .where((m) => !kSubMapParent.containsKey(m.id))
        .toList();
    return Center(
      // in a narrow stack (landscape, long names, large text) it shrinks to fit
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: p.line.withValues(alpha: .8)),
            boxShadow: gemShadow(p, lift: 1.2),
          ),
          // the tabs' ink needs a Material above the pill's colour
          child: Material(
            type: MaterialType.transparency,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final m in maps)
                  Semantics(
                    button: true,
                    selected: m.id == currentMapId,
                    hint: m.id == currentMapId ? S.t('fit_hint') : null,
                    child: InkWell(
                      onTap: () => onSwitch(m.id),
                      borderRadius: BorderRadius.circular(24),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: m.id == currentMapId
                              ? p.accent
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _icon(m.id),
                              size: 19,
                              color: m.id == currentMapId
                                  ? p.onAccent
                                  : p.muted,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              S.mapShort(m),
                              style: TextStyle(
                                fontFamily: 'Arial',
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: m.id == currentMapId
                                    ? p.onAccent
                                    : p.ink,
                              ),
                            ),
                            Text(
                              S.levelTag(m),
                              style: TextStyle(
                                fontFamily: 'Arial',
                                fontSize: 12,
                                color: m.id == currentMapId
                                    ? p.onAccent.withValues(alpha: .75)
                                    : p.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shown instead of the tabs while inside a hall that belongs to another map
/// (Tutankhamun Galleries ⊂ Main Galleries).
class _BackPill extends StatelessWidget {
  const _BackPill({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Center(
      child: Container(
        decoration: BoxDecoration(
          color: p.accent,
          borderRadius: BorderRadius.circular(26),
          boxShadow: gemShadow(p),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(26),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.arrow_back, color: p.onAccent, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'Arial',
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: p.onAccent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Language, appearance, step-free routing and rotation: everything that used
/// to be a loose button on the map lives here.
class _SettingsSheet extends StatelessWidget {
  const _SettingsSheet({required this.onRotate});
  final VoidCallback onRotate;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final app = AppState.instance;
    Widget seg<T>({
      required T value,
      required List<(T, String)> items,
      required void Function(T) onChanged,
    }) => SizedBox(
      width: double.infinity,
      child: SegmentedButton<T>(
        showSelectedIcon: false,
        segments: [
          for (final i in items)
            ButtonSegment<T>(
              value: i.$1,
              label: Text(
                i.$2,
                style: const TextStyle(
                  fontFamily: 'Arial',
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
        selected: {value},
        onSelectionChanged: (s) => onChanged(s.first),
        style: SegmentedButton.styleFrom(
          backgroundColor: p.surface,
          foregroundColor: p.ink,
          selectedBackgroundColor: p.accent,
          selectedForegroundColor: p.onAccent,
          side: BorderSide(color: p.line),
        ),
      ),
    );

    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => GemSheetFrame(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 12, 22, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                S.t('settings'),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: p.ink,
                ),
              ),
              const SizedBox(height: 18),
              GemEyebrow(S.t('language')),
              const SizedBox(height: 8),
              // eight languages: a wrap of chips, each in its own script
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final l in AppLang.values)
                    ChoiceChip(
                      label: Text(
                        l.nativeName,
                        style: TextStyle(
                          locale: l.locale,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      selected: app.lang == l,
                      onSelected: (_) => app.setLang(l),
                      selectedColor: p.accent,
                      labelStyle: TextStyle(
                        color: app.lang == l ? p.onAccent : p.ink,
                      ),
                      backgroundColor: p.surface,
                      side: BorderSide(color: p.line),
                      showCheckmark: false,
                    ),
                ],
              ),
              const SizedBox(height: 18),
              GemEyebrow(S.t('appearance')),
              const SizedBox(height: 8),
              seg<ThemeMode>(
                value: app.themeMode,
                items: [
                  (ThemeMode.system, S.t('theme_system')),
                  (ThemeMode.light, S.t('theme_light')),
                  (ThemeMode.dark, S.t('theme_dark')),
                ],
                onChanged: app.setThemeMode,
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                activeThumbColor: p.accent,
                secondary: Icon(
                  app.avoidStairs ? Icons.accessible_forward : Icons.accessible,
                  color: p.accent,
                ),
                title: Text(
                  S.t('avoid_stairs'),
                  style: TextStyle(
                    fontFamily: 'Arial',
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: p.ink,
                  ),
                ),
                subtitle: Text(
                  S.t('step_free_hint'),
                  style: TextStyle(
                    fontFamily: 'Arial',
                    fontSize: 12,
                    color: p.muted,
                  ),
                ),
                value: app.avoidStairs,
                onChanged: app.setAvoidStairs,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                onTap: () => showAboutSheet(context),
                leading: Icon(Icons.auto_stories_outlined, color: p.gold),
                title: Text(
                  S.t('about_museum'),
                  style: TextStyle(
                    fontFamily: 'Arial',
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: p.ink,
                  ),
                ),
                subtitle: Text(
                  S.t('about_hint'),
                  style: TextStyle(
                    fontFamily: 'Arial',
                    fontSize: 12,
                    color: p.muted,
                  ),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                onTap: onRotate,
                leading: Icon(Icons.screen_rotation, color: p.accent),
                title: Text(
                  S.t('rotate_map'),
                  style: TextStyle(
                    fontFamily: 'Arial',
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: p.ink,
                  ),
                ),
                subtitle: Text(
                  S.t('rotate_hint'),
                  style: TextStyle(
                    fontFamily: 'Arial',
                    fontSize: 12,
                    color: p.muted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
