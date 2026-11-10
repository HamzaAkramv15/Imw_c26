import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_svg/flutter_svg.dart';

import '../data/gem_blocks.dart';
import '../data/gem_extras.dart';
import '../data/gem_map_data.dart';
import '../data/gem_paths.dart';
import '../i18n/strings.dart';
import '../models/map_models.dart';
import '../services/route_finder.dart';
import '../theme.dart';
import 'gem_ui.dart';
import 'iso_camera.dart';
import 'map_pin.dart';

// ═══════════════════════════════════════════════════════════════
//  The 2.5D museum map.
//
//  * The plan (SVG, recoloured to the sand palette) is captured once into a
//    bitmap and laid on a TILTED plane (perspective camera, see iso_camera).
//  * Rooms get real walls: every gallery / hall polygon is extruded. Buildings
//    on the site plan are solid blocks whose roofs show the plan.
//  * The selected room rises and lights up; the rest of the plan dims.
//  * The route is a glowing ribbon with light flowing along it.
//  * Pins and the "you are here" marker are upright billboards: they live in
//    screen space at a fixed size and never get squashed by the tilt.
//  * Pan / pinch / two-finger rotate work on the plane, so the point under
//    your finger stays under your finger even when tilted.
// ═══════════════════════════════════════════════════════════════

/// Crowded pins (shops, food, services) appear once zoomed in this far
/// (1 = the map fitted to the screen).
const double _denseZoom = 1.2;

/// Tap box of a pin (logical px). The pin's tip sits at the bottom centre.
const double _tapW = 46, _tapH = 58;

/// Pins closer than this on screen are thinned out (the important one stays).
const double _pinSeparation = 34;

/// Longest side (px) of the cached bitmap of the plan.
const double _rasterMaxSide = 4096;

/// Fraction of the visible area the plan fills when fitted.
const double _fitK = 0.9;

/// Light for the walls, in screen space (from the top left).
const double _lx = -0.5, _ly = -0.85;

const Color _floorColor = Color(0xffd3c8ae);

typedef _Placed = ({MapPlace place, Offset screen, int prio});

// ── the plan, recoloured to the new palette ────────────────────────
const Map<String, String> _fillSwap = {
  '#2b2f35': '#c9bea3',
  '#454b53': '#d6ccb2',
  '#3a3f46': '#d0c5aa',
  '#1b1d21': '#a89c80',
  '#d9d4c7': '#f3eddf',
  '#a88444': '#c9a45c',
  '#1d5a6b': '#6f9a92',
  '#b4475c': '#d96b7e',
};
const Map<String, String> _strokeSwap = {
  '#1b1d21': '#8a7f66',
  '#2b2f35': '#7b715a',
  '#c99a4b': '#b58a3e',
  '#9aa1a8': '#7a6f57',
  '#7f868d': '#8d8268',
  '#b9bdc1': '#8a7f66',
};

String _recolor(String svg) {
  var s = svg.replaceAll(RegExp(r'<metadata>.*?</metadata>', dotAll: true), '');
  s = s.replaceAllMapped(
    RegExp(r'fill="(#[0-9a-fA-F]{6})"'),
    (m) => 'fill="${_fillSwap[m[1]!.toLowerCase()] ?? m[1]}"',
  );
  s = s.replaceAllMapped(
    RegExp(r'stroke="(#[0-9a-fA-F]{6})"'),
    (m) => 'stroke="${_strokeSwap[m[1]!.toLowerCase()] ?? m[1]}"',
  );
  return s;
}

// ── room geometry ──────────────────────────────────────────────────
/// A region turned into a solid: footprint in map px, height in map px.
class _Prism {
  _Prism({
    required this.region,
    required this.pts,
    required this.height,
    required this.solid,
    required this.sign,
    required this.path,
    required this.centroid,
  });
  final MapRegion region;
  final List<Offset> pts;
  final double height;

  /// A block seen from outside (roof shows the plan) instead of a room seen
  /// from above (walls only).
  final bool solid;

  /// +1 when the outline runs clockwise on screen, -1 otherwise.
  final int sign;
  final Path path;
  final Offset centroid;
}

/// A shop unit, fixture, exhibit case, statue, thin wall or stair tread:
/// a low solid standing on the floor (data: gem_blocks.dart).
class _Slab {
  _Slab({
    required this.kind,
    required this.norm,
    required this.pts,
    required this.height,
    required this.centroid,
    required this.sign,
  });
  final String kind;
  final List<Offset> norm; // 0..1, for hit-tests
  final List<Offset> pts; // map px
  final double height; // map px
  final Offset centroid;
  final int sign;

  /// Centroid in normalised (0..1) space, to find the room a slab stands in.
  Offset get normCentroid {
    var x = 0.0, y = 0.0;
    for (final o in norm) {
      x += o.dx;
      y += o.dy;
    }
    return Offset(x / norm.length, y / norm.length);
  }

  bool contains(Offset p) {
    var inside = false;
    for (var i = 0, j = norm.length - 1; i < norm.length; j = i++) {
      final a = norm[i], b = norm[j];
      if ((a.dy > p.dy) != (b.dy > p.dy) &&
          p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx) {
        inside = !inside;
      }
    }
    return inside;
  }
}

/// A statue that stands upright on its plinth (data: kFigures in gem_blocks.dart).
/// Its outline is a front elevation, so it is turned to face the viewer.
class _Figure {
  _Figure({
    required this.id,
    required this.norm,
    required this.anchor,
    required this.height,
    required this.uv,
  });
  final String id;
  final Offset norm; // anchor, 0..1 (to find the room it stands in)
  final Offset anchor; // map px
  final double height; // map px
  final List<Offset> uv; // u across, v up, in units of [height]
}

/// Which walls of a room prism to paint: [back] the far (inner) faces,
/// [front] the near (outer) faces, [all] both.
enum _Pass { all, back, front }

/// Wall height of a region kind, as a fraction of the plan's short side.
double _heightFactor(RegionKind k) => switch (k) {
  RegionKind.building => 0.06,
  RegionKind.attraction => 0.03,
  RegionKind.hall || RegionKind.zone => 0.024,
  // Gallery outlines come from an old tracing and are not real walls: no prism.
  // The Main Galleries' real walls are the 'rwall' strips in gem_blocks.dart.
  RegionKind.gallery => 0,
  RegionKind.garden || RegionKind.parking => 0,
};

/// Stair treads in gem_blocks.dart climb to 0.0474u, taller than any hall wall.
/// They are drawn at this fraction of that, so the tallest tread (0.0213u) stays
/// below the 0.024u hall walls and the 0.034u Grand Stairs walls.
const double _stepScale = 0.45;

/// Open-air areas that are drawn as "attractions" but should stay (almost) flat.
const Map<String, double> _heightOverride = {
  // The staircase well is walled higher than a normal hall so no tread
  // (<= 0.0213u after _stepScale) can ever rise above its walls.
  'mb_zone_stairs': 0.034,
  'cx_events': 0,
  'cx_pyramids_steps': 0.012,
  'cx_obelisk': 0.02,
};

bool _pointInPoly(Offset p, List<Offset> poly) {
  var inside = false;
  for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    final a = poly[i], b = poly[j];
    if ((a.dy > p.dy) != (b.dy > p.dy) &&
        p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx)
      inside = !inside;
  }
  return inside;
}

Color _shade(Color c, double k) => Color.from(
  alpha: 1,
  red: (c.r * k).clamp(0.0, 1.0),
  green: (c.g * k).clamp(0.0, 1.0),
  blue: (c.b * k).clamp(0.0, 1.0),
);

// ═══════════════════════════════════════════════════════════════
//  Widget
// ═══════════════════════════════════════════════════════════════

class MuseumMapCanvas extends StatefulWidget {
  const MuseumMapCanvas({
    super.key,
    required this.map,
    required this.places,
    required this.regions,
    required this.highlighted,
    required this.selected,
    required this.selectedRegionId,
    required this.pinned,
    required this.legs,
    required this.routeProgress,
    required this.routeTargetId,
    required this.originMapId,
    required this.originPos,
    required this.pickMode,
    required this.showAllPins,
    required this.transform,
    required this.resetTick,
    required this.quarterTurns,
    required this.focusPoint,
    required this.focusTick,
    required this.zoomTick,
    required this.zoomFactor,
    required this.onPlaceTap,
    required this.onRegionTap,
    required this.onEmptyTap,
    required this.onPickTap,
    required this.onLongPress,
    required this.onPortalTap,
    this.tilted = true,
    this.onFocusDone,
    this.padding = EdgeInsets.zero,
  });

  final GemMap map;
  final List<MapPlace> places;
  final List<MapRegion> regions;
  final Set<String> highlighted;
  final MapPlace? selected;
  final String? selectedRegionId;
  final Set<String> pinned;

  /// Route pieces that lie on this map.
  final List<RouteLeg> legs;

  /// 0..1 draw-in of the route.
  final Animation<double> routeProgress;
  final String? routeTargetId;

  /// Where the visitor is (drawn when it is on this map).
  final String? originMapId;
  final Offset? originPos;

  /// While true, a tap on the map means "I am here".
  final bool pickMode;

  /// True while a category filter is on: crowded pins are then always shown.
  final bool showAllPins;

  /// This map's own controller (flat pan / zoom / rotate): each map keeps its
  /// view when you switch away and come back.
  final TransformationController transform;

  /// Bump to re-fit the map to the screen.
  final int resetTick;

  /// 0 = as drawn, 1 = turned 90°.
  final int quarterTurns;

  /// Bump [focusTick] to zoom to [focusPoint] (normalised).
  final Offset? focusPoint;
  final int focusTick;

  /// Bump [zoomTick] to zoom about the centre by [zoomFactor].
  final int zoomTick;
  final double zoomFactor;

  /// true = the plan leans back (2.5D); false = straight down. Animated.
  final bool tilted;

  final void Function(MapPlace) onPlaceTap;
  final void Function(MapRegion) onRegionTap;
  final VoidCallback onEmptyTap;
  final void Function(Offset normalised) onPickTap;
  final void Function(Offset normalised) onLongPress;
  final void Function(String mapId) onPortalTap;

  /// Called once a requested focus has been applied (so it is not replayed).
  final VoidCallback? onFocusDone;

  /// Space covered by overlays (bars, chips, tabs): the map is fitted inside
  /// the rest.
  final EdgeInsets padding;

  @override
  State<MuseumMapCanvas> createState() => _MuseumMapCanvasState();
}

class _MuseumMapCanvasState extends State<MuseumMapCanvas>
    with TickerProviderStateMixin {
  Size _vp = Size.zero;
  double _minScale = 0.1, _maxScale = 10, _fit0 = 0.3;
  bool _needsFit = false, _needsFocus = false, _disposed = false;

  Matrix4 _startM = Matrix4.identity();
  Offset _startFlat = Offset.zero;

  // artwork
  final GlobalKey _captureKey = GlobalKey();
  ui.Image? _image;
  String? _svg;
  String? _loadedId;
  bool _capturing = false;

  // animation
  late final AnimationController _tilt = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
    value: widget.tilted ? 1 : 0,
  );
  late final CurvedAnimation _tiltCurve = CurvedAnimation(
    parent: _tilt,
    curve: Curves.easeInOutCubic,
  );
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );
  late final AnimationController _liftCtl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 460),
    value: 1,
  );
  late final CurvedAnimation _liftCurve = CurvedAnimation(
    parent: _liftCtl,
    curve: Curves.easeOutBack,
  );
  String? _liftFrom, _liftTo;

  // scene (rebuilt when the regions change, never per frame)
  List<_Prism> _prisms = const [];
  List<_Prism> _solids = const [];
  List<_Slab> _slabs = const [];
  List<_Figure> _figures = const [];

  /// Garden and parking regions: flat ground that has no walls and is not in
  /// _floorPath, so it gets its own fill (GemPalette.garden / .parking).
  List<(Path, RegionKind)> _ground = const [];
  final Map<String, Path> _paths = {};
  final Map<String, _Prism> _prismById = {};
  Path _floorPath = Path();
  double _maxHeight = 0;
  List<Float64List> _routeGeo = const [];

  List<({MapPlace place, int prio})> _sorted = const [];
  List<_LabelItem> _labelItems = const [];
  final Map<String, ({TextPainter fill, TextPainter halo})> _texts = {};
  bool? _darkSeen;

  Size get _px => widget.map.imageSize;

  Rect get _bounds {
    final b = kContentBounds[widget.map.id] ?? const Rect.fromLTRB(0, 0, 1, 1);
    return Rect.fromLTRB(
      b.left * _px.width,
      b.top * _px.height,
      b.right * _px.width,
      b.bottom * _px.height,
    );
  }

  // NB: Matrix4.getMaxScaleOnAxis() also looks at z (which is 1), so it reports 1 for
  // every zoom below 100%: read the x/y columns instead.
  static double _scaleOf(Matrix4 m) =>
      math.sqrt(m.storage[0] * m.storage[0] + m.storage[1] * m.storage[1]);
  static double _angleOf(Matrix4 m) => math.atan2(m.storage[1], m.storage[0]);

  @override
  void initState() {
    super.initState();
    _needsFit = widget.transform.value.isIdentity();
    _needsFocus = widget.focusPoint != null;
    _liftTo = widget.selectedRegionId;
    _buildScene();
    _buildRoute();
    _sortPins();
    _syncLoop();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dark = context.pal.dark;
    if (_darkSeen != dark) {
      _darkSeen = dark;
      _texts.clear();
    }
    _loadSvg();
    _rebuildLabels();
  }

  @override
  void didUpdateWidget(MuseumMapCanvas old) {
    super.didUpdateWidget(old);
    if (old.resetTick != widget.resetTick ||
        old.quarterTurns != widget.quarterTurns)
      _needsFit = true;
    if (old.focusTick != widget.focusTick) _needsFocus = true;
    if (old.zoomTick != widget.zoomTick) _zoomAtCenter(widget.zoomFactor);
    if (old.tilted != widget.tilted)
      widget.tilted ? _tilt.forward() : _tilt.reverse();
    if (!identical(old.regions, widget.regions)) _buildScene();
    if (old.selectedRegionId != widget.selectedRegionId) {
      _liftFrom = _liftTo;
      _liftTo = widget.selectedRegionId;
      _liftCtl.forward(from: 0);
    }
    if (!_sameLegs(old.legs, widget.legs)) _buildRoute();
    _sortPins();
    _rebuildLabels();
    _syncLoop();
  }

  @override
  void dispose() {
    _disposed = true;
    _tiltCurve.dispose();
    _liftCurve.dispose();
    _tilt.dispose();
    _loop.dispose();
    _liftCtl.dispose();
    _image?.dispose();
    super.dispose();
  }

  bool _sameLegs(List<RouteLeg> a, List<RouteLeg> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }

  /// The route flow / beacon pulse only run while something is showing them.
  void _syncLoop() {
    final need =
        widget.legs.isNotEmpty ||
        (widget.originPos != null && widget.originMapId == widget.map.id);
    if (need && !_loop.isAnimating) {
      _loop.repeat();
    } else if (!need && _loop.isAnimating) {
      _loop.stop();
    }
  }

  // ── scene ──────────────────────────────────────────────────────
  void _buildScene() {
    final px = _px;
    final u = math.min(px.width, px.height);
    final prisms = <_Prism>[];
    final floor = Path();
    final ground = <(Path, RegionKind)>[];
    _paths.clear();
    _prismById.clear();
    for (final r in widget.regions) {
      final pts = [
        for (final o in r.points) Offset(o.dx * px.width, o.dy * px.height),
      ];
      if (pts.length < 3) continue;
      final path = r.toPath(px);
      _paths[r.id] = path;
      if (r.kind == RegionKind.garden || r.kind == RegionKind.parking) {
        ground.add((path, r.kind));
      }
      if (r.kind == RegionKind.gallery ||
          r.kind == RegionKind.hall ||
          r.kind == RegionKind.zone)
        floor.addPolygon(pts, true);
      final f = _heightOverride[r.id] ?? _heightFactor(r.kind);
      if (f <= 0) continue;
      var s = 0.0, cx = 0.0, cy = 0.0;
      for (var k = 0; k < pts.length; k++) {
        final a = pts[k], b = pts[(k + 1) % pts.length];
        s += a.dx * b.dy - b.dx * a.dy;
        cx += a.dx;
        cy += a.dy;
      }
      final pr = _Prism(
        region: r,
        pts: pts,
        height: f * u,
        solid: r.kind == RegionKind.building || r.kind == RegionKind.attraction,
        sign: s >= 0 ? 1 : -1,
        path: path,
        centroid: Offset(cx / pts.length, cy / pts.length),
      );
      prisms.add(pr);
      _prismById[r.id] = pr;
    }
    _prisms = prisms;
    _ground = ground;
    final slabs = <_Slab>[];
    void addSlab(String kind, double h, List<double> v) {
      if (v.length < 6) return;
      final norm = <Offset>[
        for (var i = 0; i + 1 < v.length; i += 2) Offset(v[i], v[i + 1]),
      ];
      final pts = [for (final o in norm) Offset(o.dx * px.width, o.dy * px.height)];
      var s = 0.0, cx = 0.0, cy = 0.0;
      for (var k = 0; k < pts.length; k++) {
        final a = pts[k], b = pts[(k + 1) % pts.length];
        s += a.dx * b.dy - b.dx * a.dy;
        cx += a.dx;
        cy += a.dy;
      }
      slabs.add(_Slab(
        kind: kind,
        norm: norm,
        pts: pts,
        height: h * u,
        centroid: Offset(cx / pts.length, cy / pts.length),
        sign: s >= 0 ? 1 : -1,
      ));
    }
    for (final b in kBlocks[widget.map.id] ?? const <MapBlock>[]) {
      addSlab(b.kind, b.h, b.pts);
    }
    for (final st in kSteps[widget.map.id] ?? const <MapStep>[]) {
      addSlab('step', st.h * _stepScale, st.pts);
    }
    _slabs = slabs;
    _figures = [
      for (final f in kFigures[widget.map.id] ?? const <MapFigure>[])
        _Figure(
          id: f.id,
          norm: Offset(f.x, f.y),
          anchor: Offset(f.x * px.width, f.y * px.height),
          height: f.height * u,
          uv: [
            for (var i = 0; i + 1 < f.uv.length; i += 2)
              Offset(f.uv[i], f.uv[i + 1]),
          ],
        ),
    ];
    _solids = [
      for (final p in prisms)
        if (p.solid) p,
    ];
    _floorPath = floor;
    _maxHeight = math.max(
      prisms.fold(0.0, (m, p) => math.max(m, p.height)),
      math.max(
        slabs.fold(0.0, (m, s) => math.max(m, s.height)),
        _figures.fold(0.0, (m, f) => math.max(m, f.height)),
      ),
    ) * 1.8;
  }

  /// How far region [id] is risen: 1 = selected, 0 = resting.
  double _liftOf(String id) {
    final t = _liftCurve.value;
    if (id == _liftTo && id == _liftFrom) return 1;
    if (id == _liftTo) return t;
    if (id == _liftFrom) return 1 - t.clamp(0.0, 1.0);
    return widget.highlighted.contains(id) ? 0.6 : 0;
  }

  Set<String> get _focusIds => {
    ...widget.highlighted,
    if (widget.selectedRegionId != null) widget.selectedRegionId!,
  };

  /// Height of the ground at a normalised point (only solid blocks have a roof).
  double _groundZ(Offset n, {bool lifted = true}) {
    var z = 0.0;
    for (final p in _solids) {
      if (p.region.contains(n))
        z = math.max(
          z,
          p.height * (lifted ? 1 + 0.7 * _liftOf(p.region.id) : 1),
        );
    }
    // shop units, fixtures and stair treads: pins and the route stand on top
    for (final s in _slabs) {
      if (s.kind == 'wall' ||
          s.kind == 'rwall' ||
          s.kind == 'monument' ||
          s.kind == 'statue') {
        continue;
      }
      if (s.height > z && s.contains(n)) z = s.height;
    }
    return z;
  }

  /// Route legs, densified, with the ground height under each step, so the
  /// ribbon climbs onto roofs instead of hiding under them.
  void _buildRoute() {
    final px = _px;
    final out = <Float64List>[];
    for (final leg in widget.legs) {
      final v = <double>[];
      for (var i = 0; i < leg.points.length; i++) {
        final b = leg.points[i];
        if (i == 0) {
          v.addAll([
            b.dx * px.width,
            b.dy * px.height,
            _groundZ(b, lifted: false),
          ]);
          continue;
        }
        final a = leg.points[i - 1];
        final len =
            (Offset(b.dx * px.width, b.dy * px.height) -
                    Offset(a.dx * px.width, a.dy * px.height))
                .distance;
        final steps = math.max(1, (len / 12).ceil());
        for (var k = 1; k <= steps; k++) {
          final n = Offset.lerp(a, b, k / steps)!;
          v.addAll([
            n.dx * px.width,
            n.dy * px.height,
            _groundZ(n, lifted: false),
          ]);
        }
      }
      out.add(Float64List.fromList(v));
    }
    _routeGeo = out;
  }

  // ── artwork: recoloured SVG -> bitmap ──────────────────────────
  Future<void> _loadSvg() async {
    final id = widget.map.id;
    if (_loadedId == id) return;
    _loadedId = id;
    _image?.dispose();
    _image = null;
    _svg = null;
    _capturing = false;
    // Pre-rendered artwork (assets/maps/png/<id>.png) is exact and instant; the
    // off-screen SVG capture below stays as a fallback when it is missing.
    try {
      final data = await rootBundle.load('assets/maps/png/$id.png');
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      if (_disposed || !mounted || _loadedId != id) {
        frame.image.dispose();
        return;
      }
      setState(() {
        _image?.dispose();
        _image = frame.image;
      });
      return;
    } catch (_) {}
    String raw;
    try {
      raw = await rootBundle.loadString(
        widget.map.asset.replaceFirst('assets/maps/', 'assets/maps/dark/'),
      );
    } catch (_) {
      raw = await rootBundle.loadString(widget.map.asset);
    }
    if (_disposed || !mounted || _loadedId != id) return;
    setState(() => _svg = _recolor(raw));
  }

  double _captureRatio() {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final side = math.max(_px.width, _px.height);
    return math.min(_rasterMaxSide / side, dpr * 3);
  }

  /// Called when the SVG has finished loading (its placeholder went away).
  void _onSvgReady() {
    if (_disposed || _image != null || _capturing) return;
    _capturing = true;
    final id = _loadedId;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      for (var i = 0; i < 8; i++) {
        await WidgetsBinding.instance.endOfFrame;
        if (_disposed || !mounted || _loadedId != id) {
          _capturing = false;
          return;
        }
        final ro = _captureKey.currentContext?.findRenderObject();
        if (ro is! RenderRepaintBoundary) continue;
        try {
          final img = await ro.toImage(pixelRatio: _captureRatio());
          if (_disposed || !mounted || _loadedId != id) {
            img.dispose();
            _capturing = false;
            return;
          }
          if (await _isBlank(img)) {
            img.dispose();
            await Future<void>.delayed(const Duration(milliseconds: 120));
            continue;
          }
          setState(() {
            _image?.dispose();
            _image = img;
          });
          _capturing = false;
          return;
        } catch (_) {
          await Future<void>.delayed(const Duration(milliseconds: 60));
        }
      }
      _capturing = false;
    });
  }

  /// True when a captured bitmap has no visible pixel at all (the capture ran
  /// before the artwork was painted).
  Future<bool> _isBlank(ui.Image img) async {
    final rec = ui.PictureRecorder();
    Canvas(rec).drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      const Rect.fromLTWH(0, 0, 48, 48),
      Paint()..filterQuality = FilterQuality.medium,
    );
    final small = await rec.endRecording().toImage(48, 48);
    final bytes = await small.toByteData(format: ui.ImageByteFormat.rawRgba);
    small.dispose();
    if (bytes == null) return false;
    for (var i = 3; i < bytes.lengthInBytes; i += 4) {
      if (bytes.getUint8(i) > 0) return false;
    }
    return true;
  }

  // ── pin priority (computed when inputs change, not every frame) ─
  static int _priority(
    MapPlace p, {
    required bool selected,
    required bool target,
    required bool pinned,
  }) {
    if (selected) return 0;
    if (target) return 1;
    if (pinned) return 2;
    return switch (p.category) {
      PlaceCategory.attraction ||
      PlaceCategory.gallery ||
      PlaceCategory.entrance ||
      PlaceCategory.building => 3,
      PlaceCategory.garden || PlaceCategory.parking => 4,
      _ => 5,
    };
  }

  void _sortPins() {
    final sel = widget.selected;
    _sorted =
        [
          for (final p in widget.places)
            (
              place: p,
              prio: _priority(
                p,
                selected: p.id == sel?.id,
                target: p.id == widget.routeTargetId,
                pinned: widget.pinned.contains(p.id),
              ),
            ),
        ]..sort(
          (a, b) => a.prio != b.prio
              ? a.prio.compareTo(b.prio)
              : a.place.id.compareTo(b.place.id),
        );
  }

  // ── names ──────────────────────────────────────────────────────
  void _rebuildLabels() {
    final items = <_LabelItem>[];
    for (final r in widget.regions) {
      final forced =
          widget.highlighted.contains(r.id) || r.id == widget.selectedRegionId;
      if (!(r.showLabel || forced)) continue;
      final onDark =
          r.kind == RegionKind.building || r.kind == RegionKind.garden;
      items.add(
        _LabelItem(
          n: r.labelAt,
          text: S.region(r),
          kind: onDark ? _LabelKind.onFill : _LabelKind.region,
          size: 12.5,
          weight: FontWeight.w700,
          force: forced,
          prio: forced ? 0 : 2,
        ),
      );
    }
    for (final l in kLabels[widget.map.id] ?? const <MapLabel>[]) {
      final kind = switch (l.style) {
        LabelStyle.road => _LabelKind.road,
        LabelStyle.theme => _LabelKind.theme,
        LabelStyle.note => _LabelKind.note,
      };
      items.add(
        _LabelItem(
          n: l.position,
          text: S.label(l),
          kind: kind,
          size: switch (l.style) {
            LabelStyle.road => 11.0,
            LabelStyle.theme => 15.0,
            LabelStyle.note => 11.5,
          },
          weight: l.style == LabelStyle.theme
              ? FontWeight.w700
              : FontWeight.w600,
          rotation: l.rotation,
          minZoom: l.minZoom,
          prio: switch (l.style) {
            LabelStyle.theme => 1,
            LabelStyle.note => 3,
            LabelStyle.road => 4,
          },
        ),
      );
    }
    items.sort((a, b) => a.prio.compareTo(b.prio));
    _labelItems = items;
  }

  ({TextPainter fill, TextPainter halo}) _text(_LabelItem it, GemPalette p) {
    final key = '${it.kind.index}|${it.text}|${it.size}|${p.dark}';
    return _texts.putIfAbsent(key, () {
      final onFloor = it.kind == _LabelKind.region;
      final ink = onFloor ? Stone.midnight : Stone.sand;
      final halo = onFloor
          ? Stone.sand.withValues(alpha: 0.85)
          : Stone.midnight.withValues(alpha: 0.9);
      final base = TextStyle(
        fontFamily: it.kind == _LabelKind.theme || it.kind == _LabelKind.region
            ? 'Georgia'
            : 'Arial',
        fontSize: it.size,
        fontWeight: it.weight,
        letterSpacing: it.kind == _LabelKind.theme ? (S.ar ? 0 : 1.6) : 0.2,
        height: 1,
      );
      TextPainter mk(TextStyle st) => TextPainter(
        text: TextSpan(
          text: it.kind == _LabelKind.theme && !S.ar
              ? it.text.toUpperCase()
              : it.text,
          style: st,
        ),
        textDirection: S.ar ? TextDirection.rtl : TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout(maxWidth: 220);
      return (
        fill: mk(base.copyWith(color: ink)),
        halo: mk(
          base.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3.4
              ..strokeJoin = StrokeJoin.round
              ..color = halo,
          ),
        ),
      );
    });
  }

  // ── camera / fitting / limits ──────────────────────────────────
  Offset get _viewCenter {
    final pad = widget.padding;
    return Offset(
      pad.left + (_vp.width - pad.horizontal) / 2,
      pad.top + (_vp.height - pad.vertical) / 2,
    );
  }

  IsoCamera _cam() => IsoCamera(
    center: _viewCenter,
    tilt: _tiltCurve.value * kMaxTilt,
    viewport: _vp,
  );
  Matrix4 _full() => _cam().compose(widget.transform.value);

  double _fitScale(Size vp, int quarter) {
    final pad = widget.padding;
    final aw = math.max(1.0, vp.width - pad.horizontal),
        ah = math.max(1.0, vp.height - pad.vertical);
    final b = _bounds;
    final bw = quarter.isOdd ? b.height : b.width,
        bh = quarter.isOdd ? b.width : b.height;
    return math.min(aw / bw, ah / bh) * _fitK;
  }

  Matrix4 _fitMatrix(Size vp, int quarter) {
    final s = _fitScale(vp, quarter);
    final c = _viewCenter;
    final b = _bounds.center;
    return Matrix4.translationValues(c.dx, c.dy, 0)
      ..rotateZ(quarter * math.pi / 2)
      ..scale(s, s, s)
      ..translate(-b.dx, -b.dy);
  }

  void _focusOn(Size vp) {
    final p = widget.focusPoint;
    if (p == null) return;
    final c = _viewCenter;
    final cur = widget.transform.value;
    final z = math
        .max(_fit0 * 3.2, _scaleOf(cur))
        .clamp(_minScale, _maxScale)
        .toDouble();
    widget.transform.value = _clampPan(
      Matrix4.translationValues(c.dx, c.dy, 0)
        ..rotateZ(_angleOf(cur))
        ..scale(z, z, z)
        ..translate(-p.dx * _px.width, -p.dy * _px.height),
    );
  }

  void _zoomAtCenter(double factor) {
    if (_vp == Size.zero) return;
    final cur = widget.transform.value;
    final target = (_scaleOf(cur) * factor)
        .clamp(_minScale, _maxScale)
        .toDouble();
    final s = target / _scaleOf(cur);
    final c = _viewCenter;
    final m = Matrix4.translationValues(c.dx, c.dy, 0)
      ..scale(s, s, s)
      ..translate(-c.dx, -c.dy);
    widget.transform.value = _clampPan(m * cur);
  }

  /// Keeps you on the map (all in flat space, before the tilt).
  Matrix4 _clampPan(Matrix4 m) {
    if (_vp == Size.zero) return m;
    final pad = widget.padding;
    final aw = math.max(1.0, _vp.width - pad.horizontal),
        ah = math.max(1.0, _vp.height - pad.vertical);
    final c = Offset(pad.left + aw / 2, pad.top + ah / 2);
    final s = _scaleOf(m), th = _angleOf(m);
    final inv = Matrix4.copy(m)..invert();
    final p = MatrixUtils.transformPoint(inv, c);
    final ct = math.cos(th).abs(), st = math.sin(th).abs();
    final ex = (ct * aw / 2 + st * ah / 2) / s;
    final ey = (st * aw / 2 + ct * ah / 2) / s;
    final b = _bounds.inflate(math.min(_bounds.width, _bounds.height) * 0.03);
    double axis(double v, double lo, double hi, double mid) =>
        lo > hi ? mid : v.clamp(lo, hi).toDouble();
    const k = 0.92;
    final tx = axis(p.dx, b.left + ex * k, b.right - ex * k, b.center.dx);
    final ty = axis(p.dy, b.top + ey * k, b.bottom - ey * k, b.center.dy);
    final dx = tx - p.dx, dy = ty - p.dy;
    if (dx.abs() < 1e-6 && dy.abs() < 1e-6) return m;
    final sx = s * (math.cos(th) * dx - math.sin(th) * dy);
    final sy = s * (math.sin(th) * dx + math.cos(th) * dy);
    return Matrix4.translationValues(-sx, -sy, 0) * m;
  }

  // ── gestures: pan, pinch-zoom, two-finger rotate (on the tilted plane) ──
  void _onScaleStart(ScaleStartDetails d) {
    _startM = widget.transform.value.clone();
    _startFlat = _cam().toFlat(d.localFocalPoint);
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final f = _cam().toFlat(d.localFocalPoint);
    final start = _scaleOf(_startM);
    final target = (start * d.scale).clamp(_minScale, _maxScale).toDouble();
    final s = target / start;
    final m = Matrix4.translationValues(f.dx, f.dy, 0)
      ..rotateZ(d.rotation)
      ..scale(s, s, s)
      ..translate(-_startFlat.dx, -_startFlat.dy);
    widget.transform.value = _clampPan(m * _startM);
  }

  void _onSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    final cur = widget.transform.value;
    final target = (_scaleOf(cur) * math.exp(-e.scrollDelta.dy / 400))
        .clamp(_minScale, _maxScale)
        .toDouble();
    final s = target / _scaleOf(cur);
    final f = _cam().toFlat(e.localPosition);
    final m = Matrix4.translationValues(f.dx, f.dy, 0)
      ..scale(s, s, s)
      ..translate(-f.dx, -f.dy);
    widget.transform.value = _clampPan(m * cur);
  }

  /// Screen point -> normalised map point (on the floor).
  Offset _toMapNorm(Offset screen) {
    final flat = _cam().toFlat(screen);
    final inv = Matrix4.copy(widget.transform.value)..invert();
    final p = MatrixUtils.transformPoint(inv, flat);
    return Offset(p.dx / _px.width, p.dy / _px.height);
  }

  void _tap(Offset screen) {
    if (widget.pickMode) {
      widget.onPickTap(_toMapNorm(screen));
      return;
    }
    // 1 — roofs of solid blocks (they hide what is behind them), nearest first
    final full = _full();
    final solids = [..._solids]
      ..sort(
        (a, b) => project(
          full,
          b.centroid.dx,
          b.centroid.dy,
        ).dy.compareTo(project(full, a.centroid.dx, a.centroid.dy).dy),
      );
    for (final p in solids) {
      final h = p.height * (1 + 0.7 * _liftOf(p.region.id));
      final roof = [for (final o in p.pts) project(full, o.dx, o.dy, h)];
      if (_pointInPoly(screen, roof)) {
        widget.onRegionTap(p.region);
        return;
      }
    }
    // 2 — rooms and open areas on the floor: the smallest one under the finger
    final n = _toMapNorm(screen);
    MapRegion? best;
    for (final r in widget.regions) {
      if (r.contains(n) && (best == null || r.area < best.area)) best = r;
    }
    best == null ? widget.onEmptyTap() : widget.onRegionTap(best);
  }

  // ── build ──────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return LayoutBuilder(
      builder: (context, c) {
        _vp = c.biggest;
        _fit0 = _fitScale(_vp, 0);
        final f1 = _fitScale(_vp, 1);
        _minScale = math.min(_fit0, f1) * 0.9;
        _maxScale = math.max(_fit0, f1) * 14;
        final usable =
            _vp.width - widget.padding.horizontal > 40 &&
            _vp.height - widget.padding.vertical > 40;
        if (usable && (_needsFit || _needsFocus)) {
          final fit = _needsFit, focus = _needsFocus;
          _needsFit = false;
          _needsFocus = false;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (fit)
              widget.transform.value = _fitMatrix(_vp, widget.quarterTurns);
            if (focus) {
              _focusOn(_vp);
              widget.onFocusDone?.call();
            }
            setState(() {});
          });
        }
        return Listener(
          onPointerSignal: _onSignal,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: _onScaleStart,
            onScaleUpdate: _onScaleUpdate,
            onTapUp: (d) => _tap(d.localPosition),
            onLongPressStart: (d) =>
                widget.onLongPress(_toMapNorm(d.localPosition)),
            child: ClipRect(
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  // 1 — the ground the model stands on (static, painted once)
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: CustomPaint(painter: _GroundPainter(p)),
                    ),
                  ),
                  // 2 — floor, walls, route, names: one painter, repainted by the animations
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _IsoPainter(
                        s: this,
                        pal: p,
                        repaint: Listenable.merge([
                          widget.transform,
                          _tilt,
                          _loop,
                          _liftCtl,
                          widget.routeProgress,
                        ]),
                      ),
                    ),
                  ),
                  // 2b — off-screen host the artwork is captured from (removed once it has been)
                  if (_image == null && _svg != null) _captureHost(),
                  // 3 — pins, you-are-here, portal chips: upright, in screen space
                  Positioned.fill(
                    child: ListenableBuilder(
                      listenable: Listenable.merge([
                        widget.transform,
                        _tilt,
                        _liftCtl,
                      ]),
                      builder: (context, _) => _screenLayer(p),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _captureHost() => Positioned(
    left: -(_px.width + 80),
    top: 0,
    width: _px.width,
    height: _px.height,
    child: IgnorePointer(
      child: RepaintBoundary(
        key: _captureKey,
        child: SvgPicture.string(
          _svg!,
          key: ValueKey('cap_$_loadedId'),
          width: _px.width,
          height: _px.height,
          fit: BoxFit.fill,
          // the placeholder disappearing is our "the SVG is ready" signal
          placeholderBuilder: (_) => _Probe(onGone: _onSvgReady),
        ),
      ),
    ),
  );

  bool _onScreen(Offset s, [double margin = 60]) =>
      s.dx > -margin &&
      s.dy > -margin &&
      s.dx < _vp.width + margin &&
      s.dy < _vp.height + margin;

  Widget _screenLayer(GemPalette p) {
    final full = _full();
    final zoom = math.max(1e-6, _scaleOf(widget.transform.value));
    final pins = _layoutPins(full, zoom);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ..._markers(full, p),
        ..._pinWidgets(pins),
        ..._chips(full, p),
      ],
    );
  }

  Offset _screenOf(Matrix4 full, Offset n, {double z = 0}) =>
      project(full, n.dx * _px.width, n.dy * _px.height, z);

  // ── which pins to show (thinned so they never pile up) ─────────
  List<_Placed> _layoutPins(Matrix4 full, double zoom) {
    final rel = zoom / math.max(1e-6, _fit0);
    final denseVisible = widget.showAllPins || rel >= _denseZoom;
    final out = <_Placed>[];
    for (final c in _sorted) {
      final pl = c.place;
      if (pl.category.isDense && !(denseVisible || c.prio <= 2)) continue;
      final s = _screenOf(full, pl.position, z: _groundZ(pl.position));
      if (!_onScreen(s)) continue;
      if (c.prio > 2) {
        final sep = pl.category.isDense ? _pinSeparation * (rel >= 2.0 ? 0.8 : 0.62) : _pinSeparation;
        var clash = false;
        for (final o in out) {
          if ((o.screen - s).distance < sep) {
            clash = true;
            break;
          }
        }
        if (clash) continue;
      }
      out.add((place: pl, screen: s, prio: c.prio));
    }
    return out;
  }

  List<Widget> _pinWidgets(List<_Placed> pins) {
    final sel = widget.selected;
    // far pins first, so near ones overlap them; the selected one always on top
    final order = [...pins]
      ..sort((a, b) {
        final as = a.place.id == sel?.id, bs = b.place.id == sel?.id;
        if (as != bs) return as ? 1 : -1;
        return a.screen.dy.compareTo(b.screen.dy);
      });
    return [
      for (final c in order)
        Positioned(
          key: ValueKey('pin_${c.place.id}'),
          left: c.screen.dx - _tapW / 2,
          top: c.screen.dy - _tapH + 3,
          width: _tapW,
          height: _tapH,
          child: _PinHost(
            place: c.place,
            selected: sel?.id == c.place.id,
            pinned: widget.pinned.contains(c.place.id),
            target: widget.routeTargetId == c.place.id,
            onTap: () => widget.onPlaceTap(c.place),
          ),
        ),
    ];
  }

  List<Widget> _markers(Matrix4 full, GemPalette p) {
    if (widget.originMapId != widget.map.id || widget.originPos == null)
      return const [];
    final s = _screenOf(
      full,
      widget.originPos!,
      z: _groundZ(widget.originPos!),
    );
    if (!_onScreen(s)) return const [];
    return [
      Positioned(
        key: const ValueKey('you'),
        left: s.dx - 30,
        top: s.dy - 30,
        width: 60,
        height: 60,
        child: IgnorePointer(
          child: _YouAreHere(pal: p, anim: _loop),
        ),
      ),
    ];
  }

  List<Widget> _chips(Matrix4 full, GemPalette p) {
    final res = <Widget>[];
    for (var i = 0; i < widget.legs.length; i++) {
      final leg = widget.legs[i];
      if (leg.nextMapId == null || leg.points.isEmpty) continue;
      final s = _screenOf(full, leg.points.last, z: _groundZ(leg.points.last));
      if (!_onScreen(s, 100)) continue;
      res.add(
        Positioned(
          key: ValueKey('chip_$i'),
          left: s.dx - 110,
          top: s.dy - 48 - 22,
          width: 220,
          height: 44,
          child: Center(
            child: _ExitChip(
              pal: p,
              icon: switch (leg.portal?.kind) {
                PortalKind.stairs => Icons.stairs,
                PortalKind.lift => Icons.elevator,
                _ => Icons.login,
              },
              label: S.t(
                'continue_on',
                x: S.mapShort(allMaps[leg.nextMapId!]!),
              ),
              onTap: () => widget.onPortalTap(leg.nextMapId!),
            ),
          ),
        ),
      );
    }
    return res;
  }
}

// ═══════════════════════════════════════════════════════════════
//  Painters
// ═══════════════════════════════════════════════════════════════

/// The ground around the model: deep stone with a soft pool of light under it.
class _GroundPainter extends CustomPainter {
  const _GroundPainter(this.pal);
  final GemPalette pal;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = pal.mapBg);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(size.width / 2, size.height * 0.52),
          size.longestSide * 0.62,
          [
            pal.sage.withValues(alpha: pal.dark ? 0.16 : 0.22),
            pal.sage.withValues(alpha: 0),
          ],
        ),
    );
    // distance haze at the top, so the plane melts into the night
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height * 0.34),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, size.height * 0.34),
          [pal.mapBg, pal.mapBg.withValues(alpha: 0)],
        ),
    );
  }

  @override
  bool shouldRepaint(_GroundPainter old) => old.pal.dark != pal.dark;
}

class _IsoPainter extends CustomPainter {
  _IsoPainter({required this.s, required this.pal, required Listenable repaint})
    : super(repaint: repaint);

  final _MuseumMapCanvasState s;
  final GemPalette pal;

  @override
  bool shouldRepaint(covariant _IsoPainter old) => true;

  @override
  void paint(Canvas canvas, Size size) {
    if (s._vp == Size.zero) return;
    final flat = s.widget.transform.value;
    final full = s._cam().compose(flat);
    final zoom = _MuseumMapCanvasState._scaleOf(flat);
    final yaw = _MuseumMapCanvasState._angleOf(flat);
    final view = (Offset.zero & size).inflate(80);
    final focus = s._focusIds;
    final px = s._px;

    // ── 1. floor: room floors, then the plan itself ──
    canvas.save();
    canvas.transform(full.storage);
    canvas.drawPath(s._floorPath, Paint()..color = _floorColor);
    _groundFills(canvas);
    _art(canvas, px);
    canvas.restore();

    // ── 2. rooms and the things standing in them, back to front ──
    // Per room: far walls -> what stands on the floor -> near walls. So a tread
    // or a case is hidden by the wall in front of it and hides the wall behind
    // it, whatever the yaw/tilt, instead of every wall landing on top of it.
    final prisms = [...s._prisms]
      ..sort(
        (a, b) => project(
          full,
          a.centroid.dx,
          a.centroid.dy,
        ).dy.compareTo(project(full, b.centroid.dx, b.centroid.dy).dy),
      );
    final rest = focus.isEmpty
        ? prisms
        : [for (final pr in prisms) if (!focus.contains(pr.region.id)) pr];
    for (final pr in rest) {
      _prism(canvas, full, yaw, pr, view, false, _Pass.back);
    }
    _slabsPaint(canvas, full, yaw, view);
    for (final pr in rest) {
      _prism(canvas, full, yaw, pr, view, false, _Pass.front);
    }
    // The statues are taller than every wall, so they are drawn after the near
    // walls: a wall must never be painted across a standing figure.
    _figuresPaint(canvas, full, yaw, view);
    if (focus.isNotEmpty) {
      final lit = [for (final pr in prisms) if (focus.contains(pr.region.id)) pr];
      _veil(canvas, full);
      _spotlight(canvas, full, focus, zoom, px);
      for (final pr in lit) {
        _prism(canvas, full, yaw, pr, view, true, _Pass.back);
      }
      // what stands inside a lifted room is shown again, bright
      _slabsPaint(canvas, full, yaw, view, inside: lit);
      for (final pr in lit) {
        _prism(canvas, full, yaw, pr, view, true, _Pass.front);
      }
      _figuresPaint(canvas, full, yaw, view, inside: lit);
    }

    // ── 3. route ──
    _route(canvas, full);

    // ── 4. names ──
    _labels(canvas, full, flat, view, size);
  }

  Color _slabColor(String kind) => switch (kind) {
    'shop' => pal.dark ? const Color(0xff6f8a78) : const Color(0xff7d977f),
    'food' => const Color(0xffc4705d),
    'service' => Color.lerp(pal.pinService, pal.surfaceHi, 0.45)!,
    'plinth' => pal.dark ? const Color(0xffd8bf86) : const Color(0xffcfb06a),
    'monument' || 'statue' => const Color(0xff4a4f55),
    'wall' || 'rwall' => pal.solid,
    'step' => Color.lerp(pal.gold, _floorColor, 0.55)!,
    'ledge' => Color.lerp(pal.solid, _floorColor, 0.45)!,
    _ => Color.lerp(pal.solid, _floorColor, 0.55)!,
  };

  /// Solids that stand on the floor, back to front. Painted between a room's
  /// far walls and its near walls (see paint). With [inside], only the slabs
  /// whose centre lies in one of those rooms.
  void _slabsPaint(
    Canvas canvas,
    Matrix4 full,
    double yaw,
    Rect view, {
    List<_Prism>? inside,
  }) {
    if (s._slabs.isEmpty) return;
    final order = [
      for (final sl in s._slabs)
        if (inside == null ||
            inside.any((pr) => pr.region.contains(sl.normCentroid)))
          sl,
    ]
      ..sort(
        (a, b) => project(full, a.centroid.dx, a.centroid.dy, 0)
            .dy
            .compareTo(project(full, b.centroid.dx, b.centroid.dy, 0).dy),
      );
    final cs = math.cos(yaw), sn = math.sin(yaw);
    for (final sl in order) {
      final n = sl.pts.length;
      final h = sl.height;
      final base = [for (final p in sl.pts) project(full, p.dx, p.dy)];
      final top = [for (final p in sl.pts) project(full, p.dx, p.dy, h)];
      var l = double.infinity, t = double.infinity;
      var r = -double.infinity, b = -double.infinity;
      for (final o in [...base, ...top]) {
        l = math.min(l, o.dx);
        t = math.min(t, o.dy);
        r = math.max(r, o.dx);
        b = math.max(b, o.dy);
      }
      if (!view.overlaps(Rect.fromLTRB(l, t, r, b))) continue;
      final roofC = _slabColor(sl.kind);
      final dark = _shade(roofC, 0.72), lit = _shade(roofC, 1.05);
      final order2 = List<int>.generate(n, (i) => i)
        ..sort((a, c) => (base[a].dy + base[(a + 1) % n].dy)
            .compareTo(base[c].dy + base[(c + 1) % n].dy));
      for (final i in order2) {
        final j = (i + 1) % n;
        final dx = sl.pts[j].dx - sl.pts[i].dx, dy = sl.pts[j].dy - sl.pts[i].dy;
        final len = math.sqrt(dx * dx + dy * dy);
        if (len < 1e-6) continue;
        final nx = sl.sign > 0 ? dy / len : -dy / len;
        final ny = sl.sign > 0 ? -dx / len : dx / len;
        final sx = nx * cs - ny * sn, sy = nx * sn + ny * cs;
        if (sy < 0) continue; // face turned away from us
        final k = ((sx * _lx + sy * _ly) * 0.5 + 0.5).clamp(0.0, 1.0);
        canvas.drawPath(
          Path()
            ..moveTo(base[i].dx, base[i].dy)
            ..lineTo(base[j].dx, base[j].dy)
            ..lineTo(top[j].dx, top[j].dy)
            ..lineTo(top[i].dx, top[i].dy)
            ..close(),
          Paint()..color = Color.lerp(dark, lit, k)!,
        );
      }
      final roof = Path()..addPolygon(top, true);
      canvas.drawPath(roof, Paint()..color = roofC);
      if (sl.kind != 'step' && sl.kind != 'rwall') {
        canvas.drawPath(
          roof,
          Paint()
            ..color = pal.rim.withValues(alpha: 0.35)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.8,
        );
      }
    }
  }

  /// Gardens (sage green) and parking (slate) lie flat on the ground. They are
  /// drawn under the artwork, so the plan's own fills and outlines stay on top.
  void _groundFills(Canvas canvas) {
    for (final (path, kind) in s._ground) {
      final fill = kind == RegionKind.garden ? pal.garden : pal.parking;
      canvas.drawPath(path, Paint()..color = fill);
      canvas.drawPath(
        path,
        Paint()
          ..color = pal.rim.withValues(alpha: pal.dark ? 0.16 : 0.45)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  Color _figureColor(String id) => switch (id) {
    // Memphis colossus: red granite. Tanis colossus: quartzite.
    'ramesses_san_el_hagar' =>
      pal.dark ? const Color(0xffc9a074) : const Color(0xffb98b62),
    _ => pal.dark ? const Color(0xffc27a6c) : const Color(0xffad6c5e),
  };

  /// Statues that stand upright: the plan's elevation outline is raised on the
  /// ground plane, turned to face the viewer (a billboard), with a little depth
  /// so it still reads as a solid when the map is tilted.
  void _figuresPaint(
    Canvas canvas,
    Matrix4 full,
    double yaw,
    Rect view, {
    List<_Prism>? inside,
  }) {
    if (s._figures.isEmpty) return;
    final cs = math.cos(yaw), sn = math.sin(yaw);
    // ground-plane directions: screen-right, and towards the viewer
    final rx = cs, ry = -sn, tx = sn, ty = cs;
    final order = [
      for (final f in s._figures)
        if (inside == null ||
            inside.any((pr) => pr.region.contains(f.norm)))
          f,
    ]..sort(
        (a, b) => project(full, a.anchor.dx, a.anchor.dy, 0).dy
            .compareTo(project(full, b.anchor.dx, b.anchor.dy, 0).dy),
      );
    for (final f in order) {
      final h = f.height;
      final half = h * 0.07; // half the thickness, along the view direction
      Offset at(Offset p, double side) => project(
        full,
        f.anchor.dx + rx * p.dx * h + tx * side,
        f.anchor.dy + ry * p.dx * h + ty * side,
        p.dy * h,
      );
      final front = [for (final p in f.uv) at(p, half)];
      final back = [for (final p in f.uv) at(p, -half)];
      var l = double.infinity, t = double.infinity;
      var r = -double.infinity, b = -double.infinity;
      for (final o in [...front, ...back]) {
        l = math.min(l, o.dx);
        t = math.min(t, o.dy);
        r = math.max(r, o.dx);
        b = math.max(b, o.dy);
      }
      if (!view.overlaps(Rect.fromLTRB(l, t, r, b))) continue;
      final c = _figureColor(f.id);
      // contact shadow on the floor
      final foot = project(full, f.anchor.dx, f.anchor.dy, 0);
      final sh = project(full, f.anchor.dx + rx * h * 0.2, f.anchor.dy, 0);
      canvas.drawOval(
        Rect.fromCenter(
          center: foot,
          width: (sh.dx - foot.dx).abs() * 2.2,
          height: (sh.dx - foot.dx).abs() * 0.9,
        ),
        Paint()..color = pal.shadow.withValues(alpha: pal.dark ? 0.45 : 0.22),
      );
      canvas.drawPath(
        Path()..addPolygon(back, true),
        Paint()..color = _shade(c, 0.55),
      );
      final n = f.uv.length;
      for (var i = 0; i < n; i++) {
        final j = (i + 1) % n;
        canvas.drawPath(
          Path()..addPolygon([front[i], front[j], back[j], back[i]], true),
          Paint()
            ..color = _shade(c, 0.66)
            ..style = PaintingStyle.fill
            ..isAntiAlias = true,
        );
      }
      final face = Path()..addPolygon(front, true);
      canvas.drawPath(face, Paint()..color = c);
      canvas.drawPath(
        face,
        Paint()
          ..color = _shade(c, 0.6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.7
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  void _art(Canvas canvas, Size px) {
    final img = s._image;
    if (img == null) return;
    canvas.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Offset.zero & px,
      Paint()
        ..filterQuality = FilterQuality.medium
        ..isAntiAlias = true,
    );
  }

  /// Dim the whole model (it is drawn over everything but the focused rooms).
  void _veil(Canvas canvas, Matrix4 full) {
    final b = s._bounds.inflate(
      math.min(s._bounds.width, s._bounds.height) * 0.02,
    );
    final top = s._maxHeight;
    final path = Path()
      ..addPolygon([
        project(full, b.left, b.top, top),
        project(full, b.right, b.top, top),
        project(full, b.right, b.bottom),
        project(full, b.left, b.bottom),
      ], true);
    canvas.drawPath(path, Paint()..color = pal.mapBg.withValues(alpha: 0.56));
  }

  /// The focused rooms' floors, bright again above the veil, with a glow.
  void _spotlight(
    Canvas canvas,
    Matrix4 full,
    Set<String> focus,
    double zoom,
    Size px,
  ) {
    canvas.save();
    canvas.transform(full.storage);
    for (final id in focus) {
      final path = s._paths[id];
      if (path == null) continue;
      final pr = s._prismById[id];
      if (pr != null && pr.solid) continue; // its roof shows the plan
      canvas.save();
      canvas.clipPath(path);
      final kind = s.widget.regions.where((r) => r.id == id).firstOrNull?.kind;
      canvas.drawPath(
        path,
        Paint()
          ..color = switch (kind) {
            RegionKind.garden => pal.garden,
            RegionKind.parking => pal.parking,
            _ => _floorColor,
          },
      );
      _art(canvas, px);
      canvas.restore();
      canvas.drawPath(
        path,
        Paint()..color = pal.accent.withValues(alpha: 0.26),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = pal.route
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = 2.6 / zoom,
      );
    }
    canvas.restore();
  }

  /// One room or block: walls far-to-near, then (blocks only) the roof.
  void _prism(
    Canvas canvas,
    Matrix4 full,
    double yaw,
    _Prism pr,
    Rect view,
    bool focused, [
    _Pass pass = _Pass.all,
  ]) {
    // A solid block is one opaque body: it is drawn whole, in the front pass.
    if (pr.solid && pass == _Pass.back) return;
    final n = pr.pts.length;
    final h = pr.height * (1 + 0.7 * s._liftOf(pr.region.id));
    final base = List<Offset>.generate(
      n,
      (i) => project(full, pr.pts[i].dx, pr.pts[i].dy),
    );
    final top = List<Offset>.generate(
      n,
      (i) => project(full, pr.pts[i].dx, pr.pts[i].dy, h),
    );

    var l = double.infinity,
        t = double.infinity,
        r = -double.infinity,
        b = -double.infinity;
    for (final o in base) {
      l = math.min(l, o.dx);
      t = math.min(t, o.dy);
      r = math.max(r, o.dx);
      b = math.max(b, o.dy);
    }
    for (final o in top) {
      t = math.min(t, o.dy);
    }
    if (!view.overlaps(Rect.fromLTRB(l, t, r, b))) return;

    final cs = math.cos(yaw), sn = math.sin(yaw);
    final dark = _shade(pal.solid, 0.7), lit = _shade(pal.solid, 1.3);
    final inner = Color.lerp(pal.solid, pal.rim, 0.3)!;
    final order = List<int>.generate(n, (i) => i)
      ..sort(
        (a, c) => (base[a].dy + base[(a + 1) % n].dy).compareTo(
          base[c].dy + base[(c + 1) % n].dy,
        ),
      );
    final rim = Paint()
      ..color = pal.rim.withValues(alpha: focused ? 0.9 : 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = focused ? 1.8 : 1.2
      ..strokeCap = StrokeCap.round;

    for (final i in order) {
      final j = (i + 1) % n;
      final dx = pr.pts[j].dx - pr.pts[i].dx, dy = pr.pts[j].dy - pr.pts[i].dy;
      final len = math.sqrt(dx * dx + dy * dy);
      if (len < 1e-6) continue;
      // outward normal, turned into screen orientation
      final nx = pr.sign > 0 ? dy / len : -dy / len,
          ny = pr.sign > 0 ? -dx / len : dx / len;
      final sx = nx * cs - ny * sn, sy = nx * sn + ny * cs;
      final facing =
          sy >= 0; // outer face towards us; otherwise we see the inner face
      // back pass = the far walls we look at from inside (behind everything
      // that stands in the room); front pass = the near walls (in front of it).
      if (!pr.solid) {
        if (pass == _Pass.back && facing) continue;
        if (pass == _Pass.front && !facing) continue;
      }
      final k =
          ((facing ? (sx * _lx + sy * _ly) : -(sx * _lx + sy * _ly)) * 0.5 +
                  0.5)
              .clamp(0.0, 1.0);
      final color = facing
          ? Color.lerp(dark, lit, k)!
          : Color.lerp(_shade(inner, 0.8), _shade(inner, 1.12), k)!;
      final quad = Path()
        ..moveTo(base[i].dx, base[i].dy)
        ..lineTo(base[j].dx, base[j].dy)
        ..lineTo(top[j].dx, top[j].dy)
        ..lineTo(top[i].dx, top[i].dy)
        ..close();
      canvas.drawPath(quad, Paint()..color = color);
      canvas.drawLine(top[i], top[j], rim);
    }

    if (pr.solid && pass != _Pass.back) {
      final roof = Path()..addPolygon(top, true);
      canvas.save();
      canvas.clipPath(roof, doAntiAlias: true);
      canvas.drawPath(roof, Paint()..color = _floorColor);
      if (s._image != null) {
        canvas.transform((full.clone()..translate(0.0, 0.0, h)).storage);
        _art(canvas, s._px);
      }
      canvas.restore();
      if (focused)
        canvas.drawPath(
          roof,
          Paint()..color = pal.accent.withValues(alpha: 0.22),
        );
      canvas.drawPath(roof, rim);
    }
  }

  void _route(Canvas canvas, Matrix4 full) {
    final legs = s.widget.legs;
    if (legs.isEmpty) return;
    final prog = s.widget.routeProgress.value.clamp(0.0, 1.0);
    final phase = s._loop.value * 30;

    Paint stroke(Color c, double w) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (var li = 0; li < legs.length && li < s._routeGeo.length; li++) {
      final g = s._routeGeo[li];
      final count = g.length ~/ 3;
      if (count < 2) continue;
      final pts = [
        for (var i = 0; i < count; i++)
          project(full, g[i * 3], g[i * 3 + 1], g[i * 3 + 2] + 0.5),
      ];
      var total = 0.0;
      for (var i = 1; i < pts.length; i++) {
        total += (pts[i] - pts[i - 1]).distance;
      }
      final drawLen = total * prog;
      final path = Path()..moveTo(pts[0].dx, pts[0].dy);
      var drawn = 0.0;
      for (var i = 1; i < pts.length; i++) {
        final seg = (pts[i] - pts[i - 1]).distance;
        if (drawn + seg <= drawLen) {
          path.lineTo(pts[i].dx, pts[i].dy);
          drawn += seg;
        } else {
          final f = seg == 0 ? 0.0 : (drawLen - drawn) / seg;
          path.lineTo(
            pts[i - 1].dx + (pts[i].dx - pts[i - 1].dx) * f,
            pts[i - 1].dy + (pts[i].dy - pts[i - 1].dy) * f,
          );
          break;
        }
      }
      canvas.drawPath(
        path,
        stroke(pal.route.withValues(alpha: 0.20), 19),
      ); // halo
      canvas.drawPath(
        path,
        stroke(pal.routeCase.withValues(alpha: 0.9), 10),
      ); // contrast
      canvas.drawPath(path, stroke(pal.route, 6)); // line

      // light flowing along the line, in the direction of travel
      final dash = stroke(Colors.white.withValues(alpha: 0.9), 2.2);
      for (final m in path.computeMetrics()) {
        for (var d = phase - 30; d < m.length; d += 30) {
          final a = math.max(0.0, d), e = math.min(m.length, d + 11);
          if (e > a) canvas.drawPath(m.extractPath(a, e), dash);
        }
      }

      // destination ring (only where the route really ends)
      if (legs[li].nextMapId == null && prog >= 0.999) {
        final end = pts.last;
        final pulse = s._loop.value;
        canvas.drawCircle(
          end,
          9 + 14 * pulse,
          Paint()..color = pal.rose.withValues(alpha: 0.4 * (1 - pulse)),
        );
        canvas.drawCircle(end, 8, Paint()..color = Colors.white);
        canvas.drawCircle(end, 5.5, Paint()..color = pal.rose);
      }
    }
  }

  void _labels(
    Canvas canvas,
    Matrix4 full,
    Matrix4 flat,
    Rect view,
    Size size,
  ) {
    final screen = Offset.zero & size;
    final safe = screen.deflate(6);
    final placed = <Rect>[];
    final zoomRel =
        _MuseumMapCanvasState._scaleOf(flat) / math.max(1e-6, s._fit0);
    final px = s._px;
    for (final it in s._labelItems) {
      if (zoomRel < it.minZoom) continue;
      final pos = Offset(it.n.dx * px.width, it.n.dy * px.height);
      final sp = project(full, pos.dx, pos.dy, s._groundZ(it.n));
      if (!screen.inflate(40).contains(sp)) continue;
      final tx = s._text(it, pal);
      var rect = Rect.fromCenter(
        center: sp,
        width: tx.fill.width,
        height: tx.fill.height,
      ).inflate(4);
      // A label near the screen edge slides inwards so its whole word stays
      // readable (e.g. "KINGSHIP" used to be cut in half by the edge).
      var shift = Offset.zero;
      if (it.rotation == 0) {
        final dx = rect.width >= safe.width
            ? 0.0
            : rect.left < safe.left
            ? safe.left - rect.left
            : rect.right > safe.right
            ? safe.right - rect.right
            : 0.0;
        final dy = rect.height >= safe.height
            ? 0.0
            : rect.top < safe.top
            ? safe.top - rect.top
            : rect.bottom > safe.bottom
            ? safe.bottom - rect.bottom
            : 0.0;
        shift = Offset(dx, dy);
        rect = rect.shift(shift);
      }
      if (!it.force && placed.any((o) => o.overlaps(rect))) continue;
      placed.add(rect);
      canvas.save();
      canvas.translate(sp.dx + shift.dx, sp.dy + shift.dy);
      if (it.rotation != 0) {
        // the text direction as it appears on the tilted plane
        final a = it.rotation * math.pi / 180;
        final p1 = project(
          full,
          pos.dx + 60 * math.cos(a),
          pos.dy + 60 * math.sin(a),
        );
        var ang = math.atan2(p1.dy - sp.dy, p1.dx - sp.dx);
        if (ang > math.pi / 2) ang -= math.pi;
        if (ang < -math.pi / 2) ang += math.pi;
        canvas.rotate(ang);
      }
      final o = Offset(-tx.fill.width / 2, -tx.fill.height / 2);
      tx.halo.paint(canvas, o);
      tx.fill.paint(canvas, o);
      canvas.restore();
    }
  }
}

enum _LabelKind { region, onFill, theme, road, note }

class _LabelItem {
  const _LabelItem({
    required this.n,
    required this.text,
    required this.kind,
    required this.size,
    required this.weight,
    this.rotation = 0,
    this.minZoom = 0,
    this.force = false,
    this.prio = 3,
  });
  final Offset n;
  final String text;
  final _LabelKind kind;
  final double size;
  final FontWeight weight;
  final double rotation;
  final double minZoom;
  final bool force;
  final int prio;
}

// ═══════════════════════════════════════════════════════════════
//  Screen-space bits
// ═══════════════════════════════════════════════════════════════

class _Probe extends StatefulWidget {
  const _Probe({required this.onGone});
  final VoidCallback onGone;
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void dispose() {
    final cb = widget.onGone;
    scheduleMicrotask(cb);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// One pin: its own repaint layer, a 46 px tap target, and a small pop-in when
/// it first appears. The tip of the drop is the bottom centre of the box.
class _PinHost extends StatelessWidget {
  const _PinHost({
    required this.place,
    required this.selected,
    required this.pinned,
    required this.target,
    required this.onTap,
  });
  final MapPlace place;
  final bool selected;
  final bool pinned;
  final bool target;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutBack,
      builder: (context, t, child) => Transform.scale(
        scale: 0.55 + 0.45 * t,
        alignment: Alignment.bottomCenter,
        child: child,
      ),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: MapPin(
          place: place,
          isSelected: selected,
          isPinned: pinned,
          isTarget: target,
          onTap: onTap,
        ),
      ),
    ),
  );
}

/// You: a bright disc with a heading arrow and a slow pulse.
class _YouAreHere extends StatelessWidget {
  const _YouAreHere({required this.pal, required this.anim});
  final GemPalette pal;
  final Animation<double> anim;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: anim,
    builder: (context, _) {
      final t = anim.value;
      return Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 24 + 34 * t,
            height: 24 + 34 * t,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: pal.route.withValues(alpha: 0.32 * (1 - t)),
            ),
          ),
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: pal.route,
              border: Border.all(color: Colors.white, width: 2.4),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              Icons.navigation_rounded,
              size: 17,
              color: pal.routeCase,
            ),
          ),
        ],
      );
    },
  );
}

/// "Continue on …": where the route leaves this map.
class _ExitChip extends StatelessWidget {
  const _ExitChip({
    required this.pal,
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final GemPalette pal;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: pal.accent,
      borderRadius: BorderRadius.circular(22),
      boxShadow: gemShadow(pal),
    ),
    child: Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: pal.onAccent),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Arial',
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: pal.onAccent,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Directionality.of(context) == TextDirection.rtl
                    ? Icons.chevron_left
                    : Icons.chevron_right,
                size: 18,
                color: pal.onAccent,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
