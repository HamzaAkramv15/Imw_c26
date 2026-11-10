import 'dart:async';

import 'package:flutter/material.dart';

import '../data/gem_extras.dart';
import '../data/gem_map_data.dart';
import '../data/gem_paths.dart';
import '../data/gem_regions.dart';
import '../data/gem_stories.dart';
import '../i18n/strings.dart';
import '../models/map_models.dart';
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
  late final MuseumGraph _graph = MuseumGraph(
    allMaps,
    portals: kPortals,
    stairEdges: kStairEdges,
    redirects: kRouteRedirects,
    placeFloors: kPlaceFloor,
  );

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

  int _resetTick = 0;
  int _zoomTick = 0;
  double _zoomFactor = 1;
  Offset? _focusPoint;
  int _focusTick = 0;
  final Map<String, int> _quarter = {};

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
      'views': {
        for (final e in _views.entries)
          if (!e.value.value.isIdentity())
            e.key: e.value.value.storage.toList(),
      },
    });
  }

  void _restore() {
    final map = allMaps[Store['map']];
    if (map != null) {
      _map = map;
      _regions = regionsFor(map.id);
    }
    final pinned = Store['pinned'];
    if (pinned is List) {
      _pinned.addAll([
        for (final id in pinned)
          if (id is String && placeById(id) != null) id,
      ]);
    }
    final origin = Store['origin'];
    if (origin is String && _graph.positionOf(origin) != null) {
      _originNode = origin;
    }
    final q = Store['quarter'];
    if (q is Map) {
      q.forEach((k, v) {
        if (k is String && v is int) _quarter[k] = v;
      });
    }
    final views = Store['views'];
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
    final target = Store['routeTarget'];
    final tour = Store['tour'];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _originNode == null) return;
      if (tour is List && tour.isNotEmpty) {
        _startTour([
          for (final id in tour)
            if (id is String) id,
        ], quiet: true);
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

  List<MapPlace> get _visiblePlaces => _filter == null
      ? _map.places
      : _map.places.where((p) => p.category == _filter).toList();

  /// The era chips only show the era's name and dates now: nothing on the plan is highlighted.
  Set<String> get _highlightedIds => const <String>{};

  // ── maps ───────────────────────────────────────────────────────
  void _setMap(String mapId) {
    final next = allMaps[mapId];
    if (next == null || next.id == _map.id) return;
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
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black45,
      builder: (_) => PlaceDetailSheet(
        place: p,
        isPinned: _pinned.contains(p.id),
        isRouteTarget: _routeTargetId == p.id,
        isOrigin: _originNode == p.id,
        onPin: () {
          setState(() {
            if (!_pinned.remove(p.id)) _pinned.add(p.id);
          });
          Navigator.of(context).pop();
          _showDetailSheet(p); // reopen so the button state refreshes
        },
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
                                fontSize: 24,
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
      _startTour(_tourOrder!, quiet: true);
    } else if (_routeTargetId != null) {
      _routeTo(_routeTargetId!, label: _routeLabel, quiet: true);
    }
  }

  // ── settings ───────────────────────────────────────────────────
  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => SafeArea(
        top: false,
        child: _SettingsSheet(
          onRotate: () {
            Navigator.of(context).pop();
            _rotateView();
          },
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
    });
    _routeAnim.forward(from: 0);
    _focusRoute(r, quiet);
  }

  void _startTour(List<String> ids, {bool quiet = false}) {
    final from = _originNode;
    if (from == null) {
      _askOrigin(then: () => _startTour(ids));
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
      _route = t.route;
      _tourOrder = t.order;
      _routeTargetId = null;
      _routeLabel = S.t('my_tour');
    });
    _routeAnim.forward(from: 0);
    _focusRoute(t.route, quiet);
    if (!quiet && t.skipped.isNotEmpty) {
      _toast.show(
        S.t('skipped', x: t.skipped.map(S.placeId).join('، ')),
        icon: Icons.block,
      );
    }
  }

  /// Make sure the part of the route you are about to follow is on screen.
  void _focusRoute(RouteResult r, bool quiet) {
    if (quiet || r.legs.isEmpty) return;
    if (!r.legs.any((l) => l.mapId == _map.id)) _setMap(r.legs.first.mapId);
  }

  void _clearRoute() {
    setState(() {
      _route = null;
      _routeTargetId = null;
      _tourOrder = null;
    });
    _routeAnim.reset();
  }

  void _toggleStepFree() {
    _app.setAvoidStairs(!_app.avoidStairs);
    _toast.show(
      S.t(_app.avoidStairs ? 'step_free_on' : 'step_free_off'),
      icon: _app.avoidStairs ? Icons.accessible_forward : Icons.directions_walk,
    );
  }

  void _openDirections() {
    final r = _route;
    if (r == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DirectionsSheet(
        title: _tourOrder != null
            ? _routeLabel
            : S.t('route_to', x: _routeLabel),
        route: r,
        onStepTap: (s) {
          Navigator.of(context).pop();
          _setMap(s.mapId);
        },
        onToggleStairs: (v) {
          Navigator.of(context).pop();
          _app.setAvoidStairs(v);
          _toast.show(
            S.t(v ? 'step_free_on' : 'step_free_off'),
            icon: v ? Icons.accessible_forward : Icons.directions_walk,
          );
        },
      ),
    );
  }

  void _openTour() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
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
      ),
    );
  }

  // ── search ─────────────────────────────────────────────────────
  Future<void> _openSearch() async {
    final e = await Navigator.of(context).push<SearchEntry>(SearchPage.route());
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
    final mapPadding = EdgeInsets.fromLTRB(
      8,
      safe.top + 112,
      tall ? 60 : 12,
      safe.bottom + (galleries ? 128 : 84) + (_route != null ? 76 : 0),
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
                        if (mounted) setState(() => _focusPoint = null);
                      }),
                  padding: mapPadding,
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
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
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
                          tooltip: S.t('my_tour'),
                          onTap: _openTour,
                          badge: _pinned.length,
                          child: Icon(
                            Icons.bookmarks_outlined,
                            size: 22,
                            color: p.ink,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: _picking
                          ? _pickBanner(p)
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
            end: 12,
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
                MapControl(
                  icon: Icons.fit_screen,
                  tooltip: S.t('fit_map'),
                  onTap: _resetView,
                ),
              ],
            ),
          ),

          // ── bottom: route card, era timeline, tabs ──
          Positioned(
            left: 0,
            right: 0,
            bottom: safe.bottom + 10,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSize(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.bottomCenter,
                  child: _route == null
                      ? const SizedBox(width: double.infinity)
                      : Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                          child: _routeCard(p),
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
                    label: S.t('back_to', x: S.mapShort(allMaps[parent]!)),
                    onTap: () => _setMap(parent),
                  )
                else
                  _MapSwitcher(currentMapId: _map.id, onSwitch: _setMap),
              ],
            ),
          ),

          // ── toast ──
          Positioned(
            top: safe.top + 116,
            left: 28,
            right: 28,
            child: IgnorePointer(
              child: Center(child: GemToastHost(toast: _toast.value)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pickBanner(GemPalette p) => Container(
    key: const ValueKey('pick'),
    height: 44,
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

  /// One calm card: where to, how far, and a clear "Start". Tap it for the directions.
  Widget _routeCard(GemPalette p) {
    final r = _route!;
    final title = _tourOrder != null
        ? '${S.t('tour')} · ${S.t('stops', n: _tourOrder!.length)}'
        : S.t('to_x', x: _routeLabel);
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
            child: Row(
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
                          fontSize: 15,
                          color: p.ink,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              '${S.distance(r.meters)} · ${S.minutes(r.walkTime)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'Arial',
                                fontSize: 12.5,
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
                FilledButton(
                  onPressed: _openDirections,
                  style: gemFilled(context).copyWith(
                    padding: const WidgetStatePropertyAll(
                      EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    ),
                  ),
                  child: Text(S.t('start')),
                ),
                IconButton(
                  onPressed: _clearRoute,
                  tooltip: S.t('clear_route'),
                  icon: Icon(Icons.close, color: p.muted, size: 20),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

extension on Type {
  Object? operator [](String other) {
    return null;
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
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: p.line.withValues(alpha: .8)),
          boxShadow: gemShadow(p, lift: 1.2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final m in maps)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSwitch(m.id),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: m.id == currentMapId ? p.accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _icon(m.id),
                        size: 19,
                        color: m.id == currentMapId ? p.onAccent : p.muted,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        S.mapShort(m),
                        style: TextStyle(
                          fontFamily: 'Arial',
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: m.id == currentMapId ? p.onAccent : p.ink,
                        ),
                      ),
                      Text(
                        S.levelTag(m),
                        style: TextStyle(
                          fontFamily: 'Arial',
                          fontSize: 9.5,
                          color: m.id == currentMapId
                              ? p.onAccent.withValues(alpha: .75)
                              : p.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
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
              seg<bool>(
                value: app.isArabic,
                items: const [(false, 'English'), (true, 'العربية')],
                onChanged: app.setArabic,
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
                    fontSize: 15,
                    color: p.ink,
                  ),
                ),
                subtitle: Text(
                  S.t('step_free_hint'),
                  style: TextStyle(
                    fontFamily: 'Arial',
                    fontSize: 12.5,
                    color: p.muted,
                  ),
                ),
                value: app.avoidStairs,
                onChanged: app.setAvoidStairs,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                onTap: () => showCarvingsSheet(context),
                leading: Icon(Icons.auto_awesome, color: p.gold),
                title: Text(
                  S.t('carvings'),
                  style: TextStyle(
                    fontFamily: 'Arial',
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: p.ink,
                  ),
                ),
                subtitle: Text(
                  S.t('carvings_hint'),
                  style: TextStyle(
                    fontFamily: 'Arial',
                    fontSize: 12.5,
                    color: p.muted,
                  ),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                onTap: () => showAboutSheet(context),
                leading: Icon(Icons.account_balance_outlined, color: p.gold),
                title: Text(
                  S.t('about_museum'),
                  style: TextStyle(
                    fontFamily: 'Arial',
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: p.ink,
                  ),
                ),
                subtitle: Text(
                  S.t('about_hint'),
                  style: TextStyle(
                    fontFamily: 'Arial',
                    fontSize: 12.5,
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
                    fontSize: 15,
                    color: p.ink,
                  ),
                ),
                subtitle: Text(
                  S.t('rotate_hint'),
                  style: TextStyle(
                    fontFamily: 'Arial',
                    fontSize: 12.5,
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
