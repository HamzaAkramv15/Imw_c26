import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_svg/flutter_svg.dart';
import 'package:imo/models/rostau.dart';

import '../data/gem_blocks.dart';
import '../data/gem_extras.dart';
import '../data/gem_figures.dart';
import '../data/gem_nav.dart';
import '../data/gem_floors.dart';
import '../data/gem_map_data.dart';
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

/// Per-plan exceptions to [_fillSwap]. On the site plan the grey is the roads,
/// drawn as asphalt so they read as streets, not as more paving; and the tan
/// is landscaping, drawn green as on the official GEM map's legend (the
/// pyramid symbol, tagged #a88445 in the asset, keeps its gold).
const Map<String, Map<String, String>> _fillSwapByMap = {
  'gem_complex': {'#454b53': '#9d988e', '#a88444': '#7c9a70', '#a88445': '#c9a45c'},
};

String _recolor(String svg, String mapId) {
  final own = _fillSwapByMap[mapId] ?? const <String, String>{};
  var s = svg.replaceAll(RegExp(r'<metadata>.*?</metadata>', dotAll: true), '');
  s = s.replaceAllMapped(
    RegExp(r'fill="(#[0-9a-fA-F]{6})"'),
    (m) {
      final c = m[1]!.toLowerCase();
      return 'fill="${own[c] ?? _fillSwap[c] ?? m[1]}"';
    },
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
    this.gaps = const [],
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

  /// Per edge, the stretches (t0, t1 along the edge) left open (kWallGaps).
  final List<List<(double, double)>> gaps;
}

/// kWallGaps for one region as gaps per edge (see gem_nav.dart).
List<List<(double, double)>> _gapsOf(String id, int edges) {
  final out = List.generate(edges, (_) => <(double, double)>[]);
  final v = kWallGaps[id] ?? const <double>[];
  for (var i = 0; i + 2 < v.length; i += 3) {
    final e = v[i].toInt();
    if (e < edges) out[e].add((v[i + 1], v[i + 2]));
  }
  return out;
}

/// The solid stretches of an edge between its gaps.
List<(double, double)> _solidRuns(List<(double, double)> gaps) {
  if (gaps.isEmpty) return const [(0.0, 1.0)];
  final out = <(double, double)>[];
  var t = 0.0;
  for (final (g0, g1) in gaps) {
    if (g0 > t) out.add((t, g0));
    if (g1 > t) t = g1;
  }
  if (t < 1) out.add((t, 1.0));
  return out;
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
    required this.outer,
    this.convex = true,
    this.figure,
    this.prism,
  });

  /// A block kind from gem_blocks.dart, 'step', or one of the things that join
  /// the blocks in one depth order (see [_orderedSlabs]):
  ///   'figure' - a statue, palm or other monument, by its footprint;
  ///   'pwall'  - a stretch of a room's wall between its openings: pts[0] to
  ///              pts[1] is the wall, the quad gives it a hair of thickness;
  ///   'psolid' - a convex piece of a roofed block (a building on the site plan).
  final String kind;
  final bool convex;
  final _Figure? figure;
  final _Prism? prism;

  /// Per edge i (pts[i] -> pts[i+1]): true if it is a real side of the solid,
  /// false if it is only a seam where two pieces of one concave solid meet (or
  /// where a lower solid was cut away under a taller one). Only real sides get
  /// a wall face.
  final List<bool> outer;
  final List<Offset> norm; // 0..1, for hit-tests
  final List<Offset> pts; // map px
  final double height; // map px
  final Offset centroid;
  final int sign;

  /// Convex hull, bounds and winding of the footprint (map px): what the
  /// painter's-order test in [_slabFront] works with. Built once, on first use.
  late final List<Offset> hull = _hullOf(pts);
  late final Rect bounds = _boundsOf(pts);
  late final int hullSign = _signOf(hull);

  /// Centroid in normalised (0..1) space, to find the room a slab stands in.
  Offset get normCentroid {
    var x = 0.0, y = 0.0;
    for (final o in norm) {
      x += o.dx;
      y += o.dy;
    }
    return Offset(x / norm.length, y / norm.length);
  }

  bool contains(Offset p) => pointInPolygon(p, norm);
}

List<Offset> _hullOf(List<Offset> pts) {
  final p = [
    ...pts,
  ]..sort((a, b) => a.dx != b.dx ? a.dx.compareTo(b.dx) : a.dy.compareTo(b.dy));
  if (p.length < 3) return p;
  double cross(Offset o, Offset a, Offset b) =>
      (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);
  final lo = <Offset>[];
  for (final q in p) {
    while (lo.length >= 2 && cross(lo[lo.length - 2], lo.last, q) <= 0) {
      lo.removeLast();
    }
    lo.add(q);
  }
  final up = <Offset>[];
  for (final q in p.reversed) {
    while (up.length >= 2 && cross(up[up.length - 2], up.last, q) <= 0) {
      up.removeLast();
    }
    up.add(q);
  }
  lo.removeLast();
  up.removeLast();
  return [...lo, ...up];
}

Rect _boundsOf(List<Offset> pts) {
  var l = double.infinity, t = double.infinity;
  var r = -double.infinity, b = -double.infinity;
  for (final o in pts) {
    l = math.min(l, o.dx);
    t = math.min(t, o.dy);
    r = math.max(r, o.dx);
    b = math.max(b, o.dy);
  }
  return Rect.fromLTRB(l, t, r, b);
}

int _signOf(List<Offset> poly) {
  var s = 0.0;
  for (var k = 0; k < poly.length; k++) {
    final a = poly[k], b = poly[(k + 1) % poly.length];
    s += a.dx * b.dy - b.dx * a.dy;
  }
  return s >= 0 ? 1 : -1;
}

/// Do two convex polygons overlap (more than just touching)?
bool _hullsOverlap(List<Offset> p, List<Offset> q) {
  for (final poly in [p, q]) {
    final n = poly.length;
    if (n < 3) return false;
    for (var i = 0; i < n; i++) {
      final a = poly[i], b = poly[(i + 1) % n];
      final ex = b.dx - a.dx, ey = b.dy - a.dy;
      final len = math.sqrt(ex * ex + ey * ey);
      if (len < 1e-9) continue;
      final nx = ey / len, ny = -ex / len;
      var pMin = double.infinity, pMax = -double.infinity;
      var qMin = double.infinity, qMax = -double.infinity;
      for (final o in p) {
        final d = o.dx * nx + o.dy * ny;
        pMin = math.min(pMin, d);
        pMax = math.max(pMax, d);
      }
      for (final o in q) {
        final d = o.dx * nx + o.dy * ny;
        qMin = math.min(qMin, d);
        qMax = math.max(qMax, d);
      }
      if (pMax <= qMin + 0.05 || qMax <= pMin + 0.05) return false;
    }
  }
  return true;
}

// ── convex pieces ──────────────────────────────────────────────
// The draw order of the solids (see _slabFront) is only exact for convex
// footprints. A concave one (a U-shaped wall round a staircase) is cut into
// convex pieces first, and a low solid that runs under a taller one (a tread
// that crosses a wall strip) loses the part that is hidden under it.

double _cross(Offset o, Offset a, Offset b) =>
    (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);

double _area2(List<Offset> p) {
  var s = 0.0;
  for (var i = 0; i < p.length; i++) {
    final a = p[i], b = p[(i + 1) % p.length];
    s += a.dx * b.dy - b.dx * a.dy;
  }
  return s;
}

bool _isConvex(List<Offset> p) {
  final n = p.length;
  for (var i = 0; i < n; i++) {
    if (_cross(p[i], p[(i + 1) % n], p[(i + 2) % n]) < -1e-6) return false;
  }
  return true;
}

bool _samePt(Offset a, Offset b) =>
    (a.dx - b.dx).abs() < 1e-6 && (a.dy - b.dy).abs() < 1e-6;

/// Ear-clipping triangulation of a counter-clockwise polygon (null on failure).
List<List<int>>? _earClip(List<Offset> pts) {
  final n = pts.length;
  final idx = List<int>.generate(n, (i) => i);
  final tris = <List<int>>[];
  var guard = 0;
  bool inTri(Offset p, Offset a, Offset b, Offset c) =>
      _cross(a, b, p) >= -1e-9 &&
      _cross(b, c, p) >= -1e-9 &&
      _cross(c, a, p) >= -1e-9;
  while (idx.length > 3 && guard++ < 10 * n * n) {
    var found = false;
    for (var k = 0; k < idx.length && !found; k++) {
      final i0 = idx[(k + idx.length - 1) % idx.length];
      final i1 = idx[k];
      final i2 = idx[(k + 1) % idx.length];
      final a = pts[i0], b = pts[i1], c = pts[i2];
      if (_cross(a, b, c) <= 1e-9) continue;
      var blocked = false;
      for (final j in idx) {
        if (j == i0 || j == i1 || j == i2) continue;
        final q = pts[j];
        if (_samePt(q, a) || _samePt(q, b) || _samePt(q, c)) continue;
        if (inTri(q, a, b, c)) {
          blocked = true;
          break;
        }
      }
      if (blocked) continue;
      tris.add([i0, i1, i2]);
      idx.removeAt(k);
      found = true;
    }
    if (found) continue;
    // no ear: drop a collinear vertex, else give up
    var dropped = false;
    for (var k = 0; k < idx.length; k++) {
      final i0 = idx[(k + idx.length - 1) % idx.length];
      final i1 = idx[k];
      final i2 = idx[(k + 1) % idx.length];
      if (_cross(pts[i0], pts[i1], pts[i2]).abs() <= 1e-9) {
        idx.removeAt(k);
        dropped = true;
        break;
      }
    }
    if (!dropped) return null;
  }
  if (idx.length == 3 && _cross(pts[idx[0]], pts[idx[1]], pts[idx[2]]) > 1e-9) {
    tris.add([idx[0], idx[1], idx[2]]);
  }
  return tris;
}

class _SlabPiece {
  _SlabPiece(this.kind, this.height, this.pts, this.outer, this.convex);
  final String kind;
  final double height;
  final List<Offset> pts;
  final List<bool> outer;
  final bool convex;
}

/// [poly] as convex, counter-clockwise pieces. Falls back to the polygon itself
/// (flagged non-convex) when it cannot be cut.
List<({List<Offset> pts, List<bool> outer, bool convex})> _convexPieces(
  List<Offset> poly,
) {
  final p = <Offset>[];
  for (final o in poly) {
    if (p.isEmpty || !_samePt(o, p.last)) p.add(o);
  }
  if (p.length > 1 && _samePt(p.first, p.last)) p.removeLast();
  if (p.length < 3) return const [];
  if (_area2(p) < 0) {
    final r = p.reversed.toList();
    p
      ..clear()
      ..addAll(r);
  }
  List<bool> all(int n) => List<bool>.filled(n, true);
  if (_isConvex(p)) return [(pts: p, outer: all(p.length), convex: true)];
  final tris = _earClip(p);
  if (tris == null || tris.isEmpty) {
    return [(pts: p, outer: all(p.length), convex: false)];
  }
  var ta = 0.0;
  for (final t in tris) {
    ta += _cross(p[t[0]], p[t[1]], p[t[2]]);
  }
  final pa = _area2(p);
  if ((ta - pa).abs() > 1e-3 * pa.abs() + 1e-6) {
    return [
      (pts: p, outer: all(p.length), convex: false),
    ]; // not a simple outline
  }
  final pieces = [for (final t in tris) List<int>.of(t)];
  var merged = true;
  while (merged) {
    merged = false;
    outer:
    for (var i = 0; i < pieces.length; i++) {
      for (var j = i + 1; j < pieces.length; j++) {
        final a = pieces[i], b = pieces[j];
        for (var ai = 0; ai < a.length; ai++) {
          final u = a[ai], v = a[(ai + 1) % a.length];
          for (var bi = 0; bi < b.length; bi++) {
            if (b[bi] == v && b[(bi + 1) % b.length] == u) {
              final a2 = [...a.sublist(ai), ...a.sublist(0, ai)]; // u, v, ...
              final b2 = [...b.sublist(bi), ...b.sublist(0, bi)]; // v, u, ...
              final cand = [...a2.sublist(1), a2[0], ...b2.sublist(2)];
              if (_isConvex([for (final k in cand) p[k]])) {
                pieces[i] = cand;
                pieces.removeAt(j);
                merged = true;
                break outer;
              }
            }
          }
        }
      }
    }
  }
  final n0 = p.length;
  return [
    for (final pc in pieces)
      (
        pts: [for (final k in pc) p[k]],
        outer: [
          for (var t = 0; t < pc.length; t++)
            (pc[(t + 1) % pc.length] - pc[t]) % n0 == 1,
        ],
        convex: true,
      ),
  ];
}

double _side(Offset p, Offset a, Offset b) =>
    (b.dx - a.dx) * (p.dy - a.dy) - (b.dy - a.dy) * (p.dx - a.dx);

/// Sutherland-Hodgman against one half-plane of the line a->b, carrying the
/// "real side" flag of every edge (the new edge on the cut line is not real).
(List<Offset>, List<bool>) _clipHalf(
  List<Offset> poly,
  List<bool> flags,
  Offset a,
  Offset b,
  bool keepLeft,
) {
  final sg = keepLeft ? 1.0 : -1.0;
  final out = <Offset>[];
  final of = <bool>[];
  final n = poly.length;
  for (var i = 0; i < n; i++) {
    final pp = poly[i], q = poly[(i + 1) % n];
    final f = flags[i];
    final sp = sg * _side(pp, a, b), sq = sg * _side(q, a, b);
    final pin = sp >= 0, qin = sq >= 0;
    if (pin && qin) {
      out.add(pp);
      of.add(f);
    } else if (pin && !qin) {
      final t = sp / (sp - sq);
      out
        ..add(pp)
        ..add(Offset(pp.dx + (q.dx - pp.dx) * t, pp.dy + (q.dy - pp.dy) * t));
      of
        ..add(f)
        ..add(false);
    } else if (!pin && qin) {
      final t = sp / (sp - sq);
      out.add(Offset(pp.dx + (q.dx - pp.dx) * t, pp.dy + (q.dy - pp.dy) * t));
      of.add(f);
    }
  }
  return (out, of);
}

/// Convex [l] minus convex counter-clockwise [t], as convex pieces.
List<({List<Offset> pts, List<bool> outer})> _subtractConvex(
  List<Offset> l,
  List<bool> lf,
  List<Offset> t,
) {
  final res = <({List<Offset> pts, List<bool> outer})>[];
  var rem = l, rf = lf;
  for (var i = 0; i < t.length; i++) {
    final a = t[i], b = t[(i + 1) % t.length];
    final o = _clipHalf(rem, rf, a, b, false);
    if (o.$1.length >= 3 && _area2(o.$1).abs() > 1.0) {
      res.add((pts: o.$1, outer: o.$2));
    }
    final r = _clipHalf(rem, rf, a, b, true);
    rem = r.$1;
    rf = r.$2;
    if (rem.length < 3) break;
  }
  return res;
}

/// Every low solid loses the part that lies under a taller one: that part can
/// never be seen (the taller roof covers it) and, left in, it makes the two
/// impossible to put in a correct back-to-front order.
List<_SlabPiece> _cutUnderTaller(List<_SlabPiece> all) {
  final out = <_SlabPiece>[];
  final bounds = [for (final s in all) _boundsOf(s.pts)];
  for (var oi = 0; oi < all.length; oi++) {
    final o = all[oi];
    var pcs = [(pts: o.pts, outer: o.outer)];
    if (o.convex) {
      for (var ti = 0; ti < all.length; ti++) {
        final t = all[ti];
        if (!t.convex || t.height <= o.height + 0.5) continue;
        if (!bounds[oi].overlaps(bounds[ti])) continue;
        final tp = _area2(t.pts) >= 0 ? t.pts : t.pts.reversed.toList();
        final next = <({List<Offset> pts, List<bool> outer})>[];
        for (final pc in pcs) {
          if (_hullsOverlap(pc.pts, tp)) {
            next.addAll(_subtractConvex(pc.pts, pc.outer, tp));
          } else {
            next.add(pc);
          }
        }
        pcs = next;
      }
    }
    for (final pc in pcs) {
      out.add(_SlabPiece(o.kind, o.height, pc.pts, pc.outer, o.convex));
    }
  }
  return out;
}

/// Which of two slabs is nearer the viewer. `(vx, vy)` points from the scene
/// towards the viewer, in map space. Returns 1 if [b] must be painted after
/// [a] (b is in front), -1 if before, 0 if the footprints don't separate.
///
/// Two disjoint convex footprints are split by a line along one of their edges;
/// the slab on the viewer's side of that line is the nearer one. A centroid sort
/// gets this wrong for long thin shapes (wall strips beside cases).
///
/// Two things made stairs flicker "at certain angles", and both are handled:
///  * Several edges can separate two footprints. An edge that runs exactly
///    along the viewing direction says nothing about who is in front (n.v = 0),
///    so the first separating edge must not win: the most decisive one does.
///  * A tread is modelled starting a hair INSIDE the wall it climbs beside, so
///    the footprints overlap by a pixel or two and no edge separates them. The
///    order then fell back to centroid depth and the tread was painted over the
///    wall. The test is therefore repeated allowing a growing overlap.
int _slabFront(_Slab a, _Slab b, double vx, double vy) {
  // Signed "nearness" of q relative to p: > 0 when q is nearer the viewer.
  // Of all edges of p that split q off, the one most square-on to the view.
  double? sep(_Slab p, _Slab q, double tol) {
    final h = p.hull, n = h.length;
    if (n < 3) return null;
    final sg = p.hullSign;
    double? best;
    for (var i = 0; i < n; i++) {
      final a0 = h[i], a1 = h[(i + 1) % n];
      final ex = a1.dx - a0.dx, ey = a1.dy - a0.dy;
      final len = math.sqrt(ex * ex + ey * ey);
      if (len < 1e-9) continue;
      final nx = sg * ey / len, ny = -sg * ex / len;
      var outside = true;
      for (final o in q.hull) {
        if ((o.dx - a0.dx) * nx + (o.dy - a0.dy) * ny < -tol) {
          outside = false;
          break;
        }
      }
      if (!outside) continue;
      final d = nx * vx + ny * vy;
      if (best == null || d.abs() > best.abs()) best = d;
    }
    return best;
  }

  for (final tol in const [0.05, 1.5, 3.0, 6.0]) {
    final d = sep(a, b, tol); // b lies along n from a: b is nearer iff n.v > 0
    var e = sep(b, a, tol); // a lies along n from b: a is nearer iff n.v > 0
    if (e != null) e = -e;
    double? x;
    for (final c in [d, e]) {
      if (c != null && (x == null || c.abs() > x.abs())) x = c;
    }
    if (x != null && x.abs() > 1e-4) return x > 0 ? 1 : -1;
  }
  // Footprints genuinely overlap (a tread inside a wall frame): the taller solid
  // is painted last so it hides the lower one where they meet.
  if ((a.height - b.height).abs() > 0.5) return b.height > a.height ? 1 : -1;
  return 0;
}

/// A thin wall quad with the openings in it cut out: the wall is split along its
/// long axis wherever an opening's circle crosses that axis (the routes go
/// through there; tools/test_nav.py checks the same geometry).
List<List<Offset>> _cutDoorways(
  List<Offset> quad,
  List<(Offset, Offset)> doors,
) {
  if (quad.length != 4) return [quad];
  // long axis: from the middle of one short side to the middle of the other
  final e0 = (quad[1] - quad[0]).distance, e1 = (quad[2] - quad[1]).distance;
  final s0 = e0 < e1 ? 0 : 1; // first short side starts at quad[s0]
  final a = (quad[s0] + quad[s0 + 1]) / 2,
      b = (quad[(s0 + 2) % 4] + quad[(s0 + 3) % 4]) / 2;
  final len = (b - a).distance;
  if (len < 1e-6) return [quad];
  final dir = (b - a) / len;
  final half = (e0 < e1 ? e0 : e1) / 2;
  final normal = Offset(-dir.dy, dir.dx);
  final cuts = <(double, double)>[];
  for (final (p, q) in doors) {
    final c = (p + q) / 2;
    final t = (c - a).dx * dir.dx + (c - a).dy * dir.dy;
    final off = ((c - a).dx * normal.dx + (c - a).dy * normal.dy).abs();
    // the opening is the circle around the door's centre (radius half its
    // width): it opens the stretch of the wall's axis inside that circle, as
    // the routing grid does
    final r = (q - p).distance / 2;
    if (off >= r) continue;
    final w = math.sqrt(r * r - off * off);
    if (t > -w && t < len + w) cuts.add((t - w, t + w));
  }
  if (cuts.isEmpty) return [quad];
  cuts.sort((x, y) => x.$1.compareTo(y.$1));
  final out = <List<Offset>>[];
  var from = 0.0;
  List<Offset> piece(double t0, double t1) => [
    a + dir * t0 + normal * half,
    a + dir * t1 + normal * half,
    a + dir * t1 - normal * half,
    a + dir * t0 - normal * half,
  ];
  for (final (c0, c1) in cuts) {
    if (c0 - from > 0.5) out.add(piece(from, math.min(c0, len)));
    from = c1 > from ? c1 : from;
  }
  if (len - from > 0.5) out.add(piece(from, len));
  return out;
}

/// Stall lines of a car park: across its longest side, every [gap] map units,
/// clipped to the outline and kept off its edges.
List<(Offset, Offset)> _stallLines(
  List<Offset> poly, {
  double gap = 7,
  double inset = 3,
}) {
  if (poly.length < 3) return const [];
  var a = poly[0], b = poly[1];
  for (var i = 0; i < poly.length; i++) {
    final p = poly[i], q = poly[(i + 1) % poly.length];
    if ((q - p).distance > (b - a).distance) {
      a = p;
      b = q;
    }
  }
  final len = (b - a).distance;
  if (len < 1) return const [];
  final dir = (b - a) / len, nrm = Offset(-dir.dy, dir.dx);
  double along(Offset p) => (p - a).dx * dir.dx + (p - a).dy * dir.dy;
  var lo = double.infinity, hi = -double.infinity;
  for (final p in poly) {
    lo = math.min(lo, along(p));
    hi = math.max(hi, along(p));
  }
  final out = <(Offset, Offset)>[];
  for (var t = lo + inset + gap / 2; t < hi - inset; t += gap) {
    // crossings of the line {along = t} with the outline
    final hits = <double>[];
    for (var i = 0; i < poly.length; i++) {
      final p = poly[i], q = poly[(i + 1) % poly.length];
      final tp = along(p), tq = along(q);
      if ((tp - t) * (tq - t) < 0) {
        final k = (t - tp) / (tq - tp);
        final c = p + (q - p) * k;
        hits.add((c - a).dx * nrm.dx + (c - a).dy * nrm.dy);
      }
    }
    hits.sort();
    for (var i = 0; i + 1 < hits.length; i += 2) {
      if (hits[i + 1] - hits[i] < inset * 3) continue;
      final base = a + dir * t;
      out.add((
        base + nrm * (hits[i] + inset),
        base + nrm * (hits[i + 1] - inset),
      ));
    }
  }
  return out;
}

/// A monument standing on the plan (data: kFigures / kMeshes in gem_figures.dart):
/// a triangle mesh fixed in the world, facing its real direction. Light comes
/// from a fixed direction in the world, so each triangle's shade is computed
/// once; every frame only culls, sorts and projects.
class _Figure {
  _Figure({
    required this.id,
    required this.norm,
    required this.anchor,
    required this.height,
    required this.xyz,
    required this.tris,
    required this.normals,
    required this.lit,
    required this.litDark,
    required this.foot,
    this.layer,
    this.outline,
    this.color = 0,
    this.lo,
  });
  final String id;

  /// Footprint on the floor (map px): where it stands in the depth order.
  final List<Offset> foot;

  /// Draw layer per triangle (FigureMesh.layers), or null for one layer.
  final Int32List? layer;

  /// The same figure with fewer triangles, used while it is small on screen.
  final _Figure? lo;

  /// Triangles turned towards the viewer, far to near, for the yaw in
  /// [orderKey] (half-degree steps): only turning the map changes it.
  int orderKey = 1 << 30;
  List<int> order = const [];
  final Offset norm; // anchor, 0..1 (to find the room it stands in)
  final Offset anchor; // map px
  final double height; // map px
  final Float64List xyz; // vertices in map px (x, y, z up)
  final List<int> tris; // three vertex indices per triangle
  final Float64List normals; // outward normal per triangle (unit)
  final Int32List lit; // shaded colour per triangle, day palette
  final Int32List litDark; // night palette

  /// An upright outline instead of a mesh (kSilhouettes): u across, v up, in
  /// units of [height]; drawn turned to face the viewer, in [color].
  final List<Offset>? outline;
  final int color;
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
  'cx_obelisk':
      0, // an open plaza: no walls (also left open in the routing grid)
};

extension on Color {
  /// The colour darkened (k < 1) or lightened (k > 1), clamped.
  Color withShade(double k) => _shade(this, k);
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

/// Regions lifted out of the veil and outlined: every region [highlighted]
/// (the galleries of the era picked on the timeline), and the [selected] one
/// unless it is a gallery, whose traced outline is only approximate, so its
/// pin alone marks it.
Set<String> focusRegions(
  List<MapRegion> regions,
  Set<String> highlighted,
  String? selected,
) => {
  ...highlighted,
  if (selected != null &&
      regions.where((r) => r.id == selected).firstOrNull?.kind !=
          RegionKind.gallery)
    selected,
};

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
    this.keepClear = const <Rect>[],
    this.walkedLegs = const <RouteLeg>[],
    this.laterLegs = const <RouteLeg>[],
    this.trip,
    this.stopNodes = const <String, String>{},
    this.stepFocus,
    this.focusRect,
  });

  final GemMap map;
  final List<MapPlace> places;
  final List<MapRegion> regions;
  final Set<String> highlighted;
  final MapPlace? selected;
  final String? selectedRegionId;
  final Set<String> pinned;

  /// Route pieces that lie on this map: the stretch to walk now (drawn bold,
  /// with arrows showing the way).
  final List<RouteLeg> legs;

  /// The part of a walk already behind the visitor (drawn faint) and the part
  /// after the stop they are heading for (drawn as a light dotted line).
  final List<RouteLeg> walkedLegs;
  final List<RouteLeg> laterLegs;

  /// The walk being followed, and each stop's routing node by place id: the
  /// stops' pins carry their number and state.
  final TripProgress? trip;
  final Map<String, String> stopNodes;

  /// The instruction the visitor is reading: marked on the map where it
  /// happens.
  final RouteStep? stepFocus;

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

  /// Bump [focusTick] to glide to [focusPoint] (normalised), or to fit
  /// [focusRect] (normalised) when that is set.
  final Offset? focusPoint;
  final Rect? focusRect;
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

  /// Screen-space rectangles (this widget's own coordinates) that overlay
  /// controls sit on. Names slide out from under them and pins that are mostly
  /// hidden behind them are left out until the map is panned clear again.
  final List<Rect> keepClear;

  /// Plan artwork handed in ready-made, by map id (tests only: the SVG cannot
  /// be rasterised under the test binding's fake clock).
  @visibleForTesting
  static final Map<String, ui.Image> debugArt = {};

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
  List<_Slab> _slabOrder = const [];

  /// Pairs of slabs (i, j, flattened) close enough that one may hide the other
  /// from some direction. It does not depend on the yaw, so it is found once per
  /// scene; turning the map only re-decides these pairs.
  Int32List _slabPairs = Int32List(0);
  List<_Slab>? _slabPairsOf;
  List<_Slab>? _slabOrderOf;
  int _slabOrderKey = 1 << 30;
  List<_Figure> _figures = const [];

  /// Garden and parking regions: flat ground that has no walls and is not in
  /// _floorPath, so it gets its own fill (GemPalette.garden / .parking).
  List<(Path, RegionKind)> _ground = const [];

  /// Parking bays: the stall lines painted across each car park (map px).
  List<(Offset, Offset)> _bays = const [];
  final Map<String, Path> _paths = {};
  final Map<String, _Prism> _prismById = {};
  Path _floorPath = Path();

  /// Flat floors from gem_floors.dart, painted in list order under the plan.
  List<(String, Path)> _extraFloors = const [];
  double _maxHeight = 0;
  List<Float64List> _routeGeo = const [];
  List<Float64List> _walkedGeo = const [];
  List<Float64List> _laterGeo = const [];

  /// Camera glides (focus on a place, a step of the route): flat point and
  /// zoom at the start and end, eased by [_glide].
  late final AnimationController _glide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 560),
  )..addListener(_onGlide);
  Offset _glideFrom = Offset.zero, _glideTo = Offset.zero;
  double _glideZ0 = 1, _glideZ1 = 1;

  List<({MapPlace place, int prio})> _sorted = const [];

  /// Where the pins were drawn at the last build of the screen layer, so the
  /// names (painted underneath) can keep out from under them.
  List<Rect> _pinRects = const [];
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
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _syncLoop();
  }

  /// The visitor asked for less motion: the route and the beacon stand still.
  bool _reduceMotion = false;

  @override
  void didUpdateWidget(MuseumMapCanvas old) {
    super.didUpdateWidget(old);
    if (old.resetTick != widget.resetTick ||
        old.quarterTurns != widget.quarterTurns) {
      _needsFit = true;
    }
    if (old.focusTick != widget.focusTick) _needsFocus = true;
    if (old.zoomTick != widget.zoomTick) _zoomAtCenter(widget.zoomFactor);
    if (old.tilted != widget.tilted) {
      widget.tilted ? _tilt.forward() : _tilt.reverse();
    }
    if (!identical(old.regions, widget.regions)) _buildScene();
    if (old.selectedRegionId != widget.selectedRegionId) {
      _liftFrom = _liftTo;
      _liftTo = widget.selectedRegionId;
      _liftCtl.forward(from: 0);
    }
    if (!_sameLegs(old.legs, widget.legs) ||
        !_sameLegs(old.walkedLegs, widget.walkedLegs) ||
        !_sameLegs(old.laterLegs, widget.laterLegs)) {
      _buildRoute();
    }
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
    _glide.dispose();
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

  /// The beacon's slow pulse runs only while the visitor's position is on this
  /// map (the route itself stands still: its arrows show the way).
  void _syncLoop() {
    final need =
        !_reduceMotion &&
        widget.originPos != null &&
        widget.originMapId == widget.map.id;
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
    final doors = [
      for (final d in kDoors)
        if (d.mapId == widget.map.id)
          (
            Offset(d.a.dx * px.width, d.a.dy * px.height),
            Offset(d.b.dx * px.width, d.b.dy * px.height),
          ),
    ];
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
          r.kind == RegionKind.zone) {
        floor.addPolygon(pts, true);
      }
      final f = _heightOverride[r.id] ?? _heightFactor(r.kind);
      // A flat open-air attraction (the Events Area) has no walls to draw, but
      // it still needs a floor, or the garden underneath shows through it.
      if (f <= 0 && r.kind == RegionKind.attraction) ground.add((path, r.kind));
      if (f <= 0) continue;
      var s = 0.0, cx = 0.0, cy = 0.0;
      for (var k = 0; k < pts.length; k++) {
        final a = pts[k], b = pts[(k + 1) % pts.length];
        s += a.dx * b.dy - b.dx * a.dy;
        cx += a.dx;
        cy += a.dy;
      }
      final solid =
          r.kind == RegionKind.building || r.kind == RegionKind.attraction;
      final pr = _Prism(
        region: r,
        pts: pts,
        height: f * u,
        solid: solid,
        // openings, and where Tutankhamun zones meet other floor: the routing
        // grid leaves exactly these open. A solid block is drawn closed.
        gaps: solid ? const [] : _gapsOf(r.id, pts.length),
        sign: s >= 0 ? 1 : -1,
        path: path,
        centroid: Offset(cx / pts.length, cy / pts.length),
      );
      prisms.add(pr);
      _prismById[r.id] = pr;
    }
    _prisms = prisms;
    _ground = ground;
    _bays = [
      for (final r in widget.regions)
        if (r.kind == RegionKind.parking)
          ..._stallLines([
            for (final o in r.points) Offset(o.dx * px.width, o.dy * px.height),
          ]),
    ];
    final raw = <_SlabPiece>[];
    void addSlab(String kind, double h, List<double> v) {
      if (v.length < 6) return;
      final poly = <Offset>[
        for (var i = 0; i + 1 < v.length; i += 2)
          Offset(v[i] * px.width, v[i + 1] * px.height),
      ];
      final parts = (kind == 'wall' || kind == 'rwall') && doors.isNotEmpty
          ? _cutDoorways(poly, doors)
          : [poly];
      for (final part in parts) {
        for (final pc in _convexPieces(part)) {
          raw.add(_SlabPiece(kind, h * u, pc.pts, pc.outer, pc.convex));
        }
      }
    }

    for (final b in kBlocks[widget.map.id] ?? const <MapBlock>[]) {
      addSlab(b.kind, b.h, b.pts);
    }
    for (final b in kExtraBlocks[widget.map.id] ?? const <MapBlock>[]) {
      addSlab(b.kind, b.h, b.pts);
    }
    for (final st in kSteps[widget.map.id] ?? const <MapStep>[]) {
      addSlab('step', st.h * _stepScale, st.pts);
    }
    for (final st in kExtraSteps[widget.map.id] ?? const <MapStep>[]) {
      addSlab('step', st.h * _stepScale, st.pts);
    }
    final slabs = <_Slab>[];
    for (final pc in _cutUnderTaller(raw)) {
      final pts = pc.pts;
      var cx = 0.0, cy = 0.0;
      for (final o in pts) {
        cx += o.dx;
        cy += o.dy;
      }
      slabs.add(
        _Slab(
          kind: pc.kind,
          norm: [
            for (final o in pts) Offset(o.dx / px.width, o.dy / px.height),
          ],
          pts: pts,
          height: pc.height,
          centroid: Offset(cx / pts.length, cy / pts.length),
          sign: _signOf(pts),
          outer: pc.outer,
        ),
      );
    }
    // flat floors that no region covers (footprint, halls, landings, display zones)
    final extra = <(String, Path)>[];
    for (final f in kFloors[widget.map.id] ?? const <MapFloor>[]) {
      if (f.pts.length < 6) continue;
      final fp = <Offset>[
        for (var i = 0; i + 1 < f.pts.length; i += 2)
          Offset(f.pts[i] * px.width, f.pts[i + 1] * px.height),
      ];
      extra.add((f.kind, Path()..addPolygon(fp, true)));
    }
    _extraFloors = extra;
    _figures = [
      for (final f in kFigures[widget.map.id] ?? const <MapFigure>[])
        _placeFigure(f, px, u),
    ];
    // Everything that stands up shares ONE depth order (_orderedSlabs): the
    // blocks, every stretch of a room's walls, the pieces of roofed blocks and
    // the figures. Painted in separate passes, a statue would show through a
    // wall in front of it, or a wall behind it would cut across it, depending
    // on which way the map is turned.
    _Slab joined(String kind, List<Offset> pts, double h, {List<bool>? outer, bool convex = true, _Figure? figure, _Prism? prism}) {
      var cx = 0.0, cy = 0.0;
      for (final o in pts) {
        cx += o.dx;
        cy += o.dy;
      }
      return _Slab(
        kind: kind,
        norm: [for (final o in pts) Offset(o.dx / px.width, o.dy / px.height)],
        pts: pts,
        height: h,
        centroid: Offset(cx / pts.length, cy / pts.length),
        sign: _signOf(pts),
        outer: outer ?? List<bool>.filled(pts.length, true),
        convex: convex,
        figure: figure,
        prism: prism,
      );
    }

    for (final pr in prisms) {
      if (pr.height <= 0) continue;
      if (pr.solid) {
        for (final pc in _convexPieces(pr.pts)) {
          slabs.add(joined('psolid', pc.pts, pr.height, outer: pc.outer, convex: pc.convex, prism: pr));
        }
        continue;
      }
      final n = pr.pts.length;
      for (var i = 0; i < n; i++) {
        final a = pr.pts[i], b = pr.pts[(i + 1) % n];
        final len = (b - a).distance;
        if (len < 1e-6) continue;
        final d = (b - a) / len;
        final out = pr.sign > 0 ? Offset(d.dy, -d.dx) : Offset(-d.dy, d.dx);
        for (final (t0, t1) in _solidRuns(pr.gaps.isEmpty ? const [] : pr.gaps[i])) {
          final b0 = Offset.lerp(a, b, t0)!, b1 = Offset.lerp(a, b, t1)!;
          if ((b1 - b0).distance < 0.5) continue;
          slabs.add(joined('pwall', [b0, b1, b1 + out * 0.8, b0 + out * 0.8], pr.height,
              outer: const [true, false, true, false], prism: pr));
        }
      }
    }
    for (final f in _figures) {
      slabs.add(joined('figure', f.foot, f.height, figure: f));
    }
    _slabs = slabs;
    _solids = [
      for (final p in prisms)
        if (p.solid) p,
    ];
    _floorPath = floor;
    _maxHeight =
        math.max(
          prisms.fold(0.0, (m, p) => math.max(m, p.height)),
          math.max(
            slabs.fold(0.0, (m, s) => math.max(m, s.height)),
            _figures.fold(0.0, (m, f) => math.max(m, f.height)),
          ),
        ) *
        1.8;
  }

  /// A monument's mesh in map space: its frame (u across, w forward, v up, in
  /// units of its height) turned to face `facing` at its anchor, with every
  /// triangle's normal and shaded colour worked out once.
  _Figure _placeFigure(MapFigure f, Size px, double u, {String? meshKey}) {
    final h = f.height * u;
    final ax = f.x * px.width, ay = f.y * px.height;
    // the base on the floor; a palm (no footprint) takes a small square
    final fp = f.footprint.length == 4 ? f.footprint : const [-0.06, 0.06, -0.06, 0.06];
    final fx0 = math.cos(f.facing), fy0 = math.sin(f.facing);
    final foot = [
      for (final (pu, pw) in [(fp[0], fp[2]), (fp[1], fp[2]), (fp[1], fp[3]), (fp[0], fp[3])])
        Offset(ax + (fy0 * pu + fx0 * pw) * h, ay + (-fx0 * pu + fy0 * pw) * h),
    ];
    final sil = kSilhouettes[f.mesh];
    if (sil != null) {
      return _Figure(
        id: f.id,
        norm: Offset(f.x, f.y),
        anchor: Offset(ax, ay),
        height: h,
        xyz: Float64List(0),
        tris: const [],
        normals: Float64List(0),
        lit: Int32List(0),
        litDark: Int32List(0),
        foot: foot,
        outline: [
          for (var i = 0; i + 1 < sil.uv.length; i += 2)
            Offset(sil.uv[i], sil.uv[i + 1]),
        ],
        color: sil.color,
      );
    }
    final mesh = kMeshes[meshKey ?? f.mesh]!;
    final fx = math.cos(f.facing),
        fy = math.sin(f.facing); // forward, plan coordinates
    final lx = fy, ly = -fx; // the statue's left
    final n = mesh.verts.length ~/ 3;
    final xyz = Float64List(n * 3);
    for (var i = 0; i < n; i++) {
      final pu = mesh.verts[i * 3],
          pw = mesh.verts[i * 3 + 1],
          pv = mesh.verts[i * 3 + 2];
      xyz[i * 3] = ax + (lx * pu + fx * pw) * h;
      xyz[i * 3 + 1] = ay + (ly * pu + fy * pw) * h;
      xyz[i * 3 + 2] = pv * h;
    }
    final t = mesh.tris.length ~/ 3;
    final normals = Float64List(t * 3);
    final lit = Int32List(t), litDark = Int32List(t);
    const lx0 = -0.45, ly0 = -0.55, lz0 = 0.7;
    final ll = math.sqrt(lx0 * lx0 + ly0 * ly0 + lz0 * lz0);
    for (var k = 0; k < t; k++) {
      final a = mesh.tris[k * 3] * 3,
          b = mesh.tris[k * 3 + 1] * 3,
          c = mesh.tris[k * 3 + 2] * 3;
      final ux = xyz[b] - xyz[a],
          uy = xyz[b + 1] - xyz[a + 1],
          uz = xyz[b + 2] - xyz[a + 2];
      final vx = xyz[c] - xyz[a],
          vy = xyz[c + 1] - xyz[a + 1],
          vz = xyz[c + 2] - xyz[a + 2];
      var nx = uy * vz - uz * vy,
          ny = uz * vx - ux * vz,
          nz = ux * vy - uy * vx;
      final nl = math.sqrt(nx * nx + ny * ny + nz * nz);
      if (nl > 0) {
        nx /= nl;
        ny /= nl;
        nz /= nl;
      }
      normals[k * 3] = nx;
      normals[k * 3 + 1] = ny;
      normals[k * 3 + 2] = nz;
      final lam = math.max(0.0, (nx * lx0 + ny * ly0 + nz * lz0) / ll);
      // sky light from above keeps shadowed stone readable
      final sky = 0.12 * math.max(0.0, nz);
      final base = Color(mesh.colors[k]).withValues(alpha: 1);
      lit[k] = base.withShade(0.56 + 0.5 * lam + sky).toARGB32();
      litDark[k] = base.withShade(0.46 + 0.46 * lam + sky).toARGB32();
    }
    Int32List? layer;
    if (mesh.layers.isNotEmpty) {
      layer = Int32List(t);
      var l = 0;
      for (var k = 0; k < t; k++) {
        while (l < mesh.layers.length && k >= mesh.layers[l]) {
          l++;
        }
        layer[k] = l;
      }
    }
    final loKey = '${f.mesh}_lo';
    return _Figure(
      id: f.id,
      norm: Offset(f.x, f.y),
      anchor: Offset(ax, ay),
      height: h,
      xyz: xyz,
      tris: mesh.tris,
      normals: normals,
      lit: lit,
      litDark: litDark,
      foot: foot,
      layer: layer,
      lo: meshKey == null && kMeshes.containsKey(loKey) ? _placeFigure(f, px, u, meshKey: loKey) : null,
    );
  }

  /// The slabs far-to-near for the current yaw (cached: pan and zoom never
  /// change the order, only turning the map does). Built from a topological
  /// sort of the pairwise "who is in front" relation, see [_slabFront].
  List<_Slab> _orderedSlabs(double yaw) {
    final key = (yaw * 360 / math.pi).round(); // half-degree steps
    if (key == _slabOrderKey && identical(_slabOrderOf, _slabs)) {
      return _slabOrder;
    }
    _slabOrderKey = key;
    _slabOrderOf = _slabs;
    final vx = math.sin(yaw), vy = math.cos(yaw);
    final n = _slabs.length;
    final depth = [
      for (final sl in _slabs) sl.centroid.dx * vx + sl.centroid.dy * vy,
    ];
    // Each slab as it appears on screen: its footprint plus the footprint
    // lifted by its height (tan of the max tilt ~ 1.35). Only pairs whose
    // pictures overlap constrain each other; ordering the rest only invents
    // contradictions (cycles).
    final cs = math.cos(yaw), sn = math.sin(yaw);
    final swept = <List<Offset>>[
      for (final sl in _slabs)
        _hullOf([
          for (final p in sl.hull)
            Offset(p.dx * cs - p.dy * sn, p.dx * sn + p.dy * cs),
          for (final p in sl.hull)
            Offset(
              p.dx * cs - p.dy * sn,
              p.dx * sn + p.dy * cs - sl.height * 1.35,
            ),
        ]),
    ];
    if (!identical(_slabPairsOf, _slabs)) {
      // each slab's picture reaches at most ~1.35x its own height beyond its
      // footprint, whichever way the map is turned (tilt <= 53 deg)
      final reachOf = [for (final sl in _slabs) sl.bounds.inflate(sl.height * 1.4 + 1)];
      final pairs = <int>[];
      for (var i = 0; i < n; i++) {
        final bi = reachOf[i];
        for (var j = i + 1; j < n; j++) {
          if (bi.overlaps(reachOf[j])) {
            pairs
              ..add(i)
              ..add(j);
          }
        }
      }
      _slabPairs = Int32List.fromList(pairs);
      _slabPairsOf = _slabs;
    }
    final after = List<List<int>>.generate(n, (_) => <int>[]);
    final waiting = List<int>.filled(n, 0);
    for (var p = 0; p < _slabPairs.length; p += 2) {
      final i = _slabPairs[p], j = _slabPairs[p + 1];
      if (!_hullsOverlap(swept[i], swept[j])) continue;
      final r = _slabFront(_slabs[i], _slabs[j], vx, vy);
      if (r > 0) {
        after[i].add(j);
        waiting[j]++;
      } else if (r < 0) {
        after[j].add(i);
        waiting[i]++;
      }
    }
    final done = List<bool>.filled(n, false);
    final order = <_Slab>[];
    for (var k = 0; k < n; k++) {
      var best = -1;
      for (var i = 0; i < n; i++) {
        if (done[i] || waiting[i] > 0) continue;
        if (best < 0 || depth[i] < depth[best]) best = i;
      }
      if (best < 0) {
        // a cycle (interlocking shapes): take the farthest one left
        for (var i = 0; i < n; i++) {
          if (done[i]) continue;
          if (best < 0 || depth[i] < depth[best]) best = i;
        }
      }
      done[best] = true;
      order.add(_slabs[best]);
      for (final t in after[best]) {
        waiting[t]--;
      }
    }
    return _slabOrder = order;
  }

  /// How far region [id] is risen: 1 = selected, 0 = resting.
  double _liftOf(String id) {
    final t = _liftCurve.value;
    if (id == _liftTo && id == _liftFrom) return 1;
    if (id == _liftTo) return t;
    if (id == _liftFrom) return 1 - t.clamp(0.0, 1.0);
    return widget.highlighted.contains(id) ? 0.6 : 0;
  }

  Set<String> get _focusIds =>
      focusRegions(widget.regions, widget.highlighted, widget.selectedRegionId);

  /// Height of the ground at a normalised point (only solid blocks have a roof).
  double _groundZ(Offset n, {bool lifted = true}) {
    var z = 0.0;
    for (final p in _solids) {
      if (p.region.contains(n)) {
        z = math.max(
          z,
          p.height * (lifted ? 1 + 0.7 * _liftOf(p.region.id) : 1),
        );
      }
    }
    // shop units, fixtures and stair treads: pins and the route stand on top
    for (final s in _slabs) {
      if (s.kind == 'wall' ||
          s.kind == 'rwall' ||
          s.kind == 'monument' ||
          s.kind == 'statue' ||
          s.kind == 'figure' ||
          s.kind == 'pwall' ||
          s.kind == 'psolid') {
        continue;
      }
      if (s.height > z && s.contains(n)) z = s.height;
    }
    return z;
  }

  /// Route legs, densified, with the ground height under each step, so the
  /// ribbon climbs onto roofs instead of hiding under them.
  void _buildRoute() {
    _routeGeo = _geoOf(widget.legs);
    _walkedGeo = _geoOf(widget.walkedLegs);
    _laterGeo = _geoOf(widget.laterLegs);
  }

  /// Each leg as x, y, z triples (map px) laid on the floor, one point at
  /// least every 12 px so the line follows steps and slabs.
  List<Float64List> _geoOf(List<RouteLeg> legs) {
    final px = _px;
    final out = <Float64List>[];
    for (final leg in legs) {
      final v = <double>[];
      for (var i = 0; i < leg.points.length; i++) {
        final b = leg.points[i];
        if (i == 0) {
          v.addAll([b.dx * px.width, b.dy * px.height, _groundZ(b, lifted: false)]);
          continue;
        }
        final a = leg.points[i - 1];
        final len = (Offset(b.dx * px.width, b.dy * px.height) -
                Offset(a.dx * px.width, a.dy * px.height))
            .distance;
        final steps = math.max(1, (len / 12).ceil());
        for (var k = 1; k <= steps; k++) {
          final n = Offset.lerp(a, b, k / steps)!;
          v.addAll([n.dx * px.width, n.dy * px.height, _groundZ(n, lifted: false)]);
        }
      }
      out.add(Float64List.fromList(v));
    }
    return out;
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
    final ready = MuseumMapCanvas.debugArt[id];
    if (ready != null) {
      setState(() => _image = ready.clone());
      return;
    }
    final String raw;
    try {
      raw = await rootBundle.loadString(widget.map.asset);
    } catch (e) {
      debugPrint('map artwork missing: ${widget.map.asset} ($e)');
      return; // the map still draws its rooms, walls and pins without it
    }
    if (_disposed || !mounted || _loadedId != id) return;
    setState(() => _svg = _recolor(raw, id));
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
    bool stop = false,
  }) {
    if (selected) return 0;
    if (target || stop) return 1;
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
                stop: widget.stopNodes.containsKey(p.id),
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
    final key =
        '${it.kind.index}|${it.text}|${it.size}|${p.dark}|${S.lang.code}';
    return _texts.putIfAbsent(key, () {
      // capitals and tracking only suit alphabets with letter case
      final spaced = !S.rtl && !S.lang.cjk;
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
        letterSpacing: it.kind == _LabelKind.theme
            ? (spaced ? 1.6 : 0)
            : (S.lang.cjk ? 0 : 0.2),
        height: 1,
        locale: S.lang.locale,
      );
      TextPainter mk(TextStyle st) => TextPainter(
        text: TextSpan(
          text: it.kind == _LabelKind.theme && spaced
              ? it.text.toUpperCase()
              : it.text,
          style: st,
        ),
        textDirection: S.rtl ? TextDirection.rtl : TextDirection.ltr,
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

  IsoCamera _cam() {
    final tilt = _tiltCurve.value * kMaxTilt;
    final c = _viewCenter;
    final m = widget.transform.value.storage;
    final px = _px;
    // How far the plan (and its tallest wall) reaches from the tilt axis, in
    // screen px. Zoomed in, that outgrows the camera distance and the far part
    // of the plan ends up BEHIND the camera: the geometry flips and glitches.
    // IsoCamera pushes the camera back just far enough to prevent that.
    var far = 0.0;
    for (final o in [
      Offset.zero,
      Offset(px.width, 0),
      Offset(0, px.height),
      Offset(px.width, px.height),
    ]) {
      final y = m[1] * o.dx + m[5] * o.dy + m[13];
      far = math.max(far, (y - c.dy).abs());
    }
    final zoom = _scaleOf(widget.transform.value);
    return IsoCamera(
      center: c,
      tilt: tilt,
      viewport: _vp,
      reach: far * math.sin(tilt) + _maxHeight * zoom * math.cos(tilt),
    );
  }

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
      ..scaleByDouble(s, s, s, 1)
      ..translateByDouble(-b.dx, -b.dy, 0, 1);
  }

  void _focusOn(Size vp) {
    final rect = widget.focusRect;
    final p = rect?.center ?? widget.focusPoint;
    if (p == null) return;
    final cur = widget.transform.value;
    final double z;
    if (rect != null) {
      // fit the stretch, turned as the map is, into the free part of the
      // screen; the tilt squeezes its depth to about 60 %
      final pad = widget.padding;
      final aw = math.max(1.0, vp.width - pad.horizontal) * 0.72,
          ah = math.max(1.0, vp.height - pad.vertical) * 0.72;
      final th = _angleOf(cur), ct = math.cos(th).abs(), st = math.sin(th).abs();
      final w = rect.width * _px.width, h = rect.height * _px.height;
      final ew = math.max(1.0, ct * w + st * h),
          eh = math.max(1.0, st * w + ct * h) * (widget.tilted ? 0.6 : 1);
      z = math.min(aw / ew, ah / eh).clamp(_fit0 * 1.1, _fit0 * 4.2).toDouble();
    } else {
      z = math.max(_fit0 * 3.2, _scaleOf(cur)).toDouble();
    }
    _glideTo = Offset(p.dx * _px.width, p.dy * _px.height);
    _glideZ1 = z.clamp(_minScale, _maxScale).toDouble();
    final inv = Matrix4.copy(cur)..invert();
    _glideFrom = MatrixUtils.transformPoint(inv, _viewCenter);
    _glideZ0 = _scaleOf(cur);
    if (_reduceMotion) {
      _glide.value = 1;
      _onGlide();
    } else {
      _glide.forward(from: 0);
    }
  }

  /// One frame of a camera glide: the point at the centre and the zoom are
  /// eased together (zoom on a log scale, so it feels even).
  void _onGlide() {
    final t = Curves.easeInOutCubic.transform(_glide.value);
    final p = Offset.lerp(_glideFrom, _glideTo, t)!;
    final z = math.exp(ui.lerpDouble(math.log(_glideZ0), math.log(_glideZ1), t)!);
    final c = _viewCenter;
    widget.transform.value = _clampPan(
      Matrix4.translationValues(c.dx, c.dy, 0)
        ..rotateZ(_angleOf(widget.transform.value))
        ..scaleByDouble(z, z, z, 1)
        ..translateByDouble(-p.dx, -p.dy, 0, 1),
    );
  }

  void _zoomAtCenter(double factor) {
    if (_vp == Size.zero) return;
    _glide.stop();
    final cur = widget.transform.value;
    final target = (_scaleOf(cur) * factor)
        .clamp(_minScale, _maxScale)
        .toDouble();
    final s = target / _scaleOf(cur);
    final c = _viewCenter;
    final m = Matrix4.translationValues(c.dx, c.dy, 0)
      ..scaleByDouble(s, s, s, 1)
      ..translateByDouble(-c.dx, -c.dy, 0, 1);
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
    _glide.stop();
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
      ..scaleByDouble(s, s, s, 1)
      ..translateByDouble(-_startFlat.dx, -_startFlat.dy, 0, 1);
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
      ..scaleByDouble(s, s, s, 1)
      ..translateByDouble(-f.dx, -f.dy, 0, 1);
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
      if (pointInPolygon(screen, roof)) {
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
            if (fit) {
              widget.transform.value = _fitMatrix(_vp, widget.quarterTurns);
            }
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
                  // 2 — the model (floor, walls, blocks, monuments), the route, the
                  // names: three layers, so the route's draw-in repaints the
                  // route alone, not the scene
                  for (final (layer, anims) in [
                    (
                      _Layer.scene,
                      <Listenable>[widget.transform, _tilt, _liftCtl],
                    ),
                    (
                      _Layer.route,
                      <Listenable>[
                        widget.transform,
                        _tilt,
                        _liftCtl,
                        widget.routeProgress,
                      ],
                    ),
                    (
                      _Layer.labels,
                      <Listenable>[widget.transform, _tilt, _liftCtl],
                    ),
                  ])
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: _IsoPainter(
                            s: this,
                            pal: p,
                            layer: layer,
                            repaint: Listenable.merge(anims),
                          ),
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
    final sel = widget.selected;
    _pinRects = [
      for (final c in pins)
        _pinBox(c.place, c.screen, selected: c.place.id == sel?.id),
    ];
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

  /// The visible body of a pin whose tip is at [tip] (what MapPin draws).
  static Rect _pinBox(MapPlace pl, Offset tip, {bool selected = false}) {
    final d = MapPin.sizeFor(pl) * (selected ? 1.3 : 1.0);
    return Rect.fromLTWH(tip.dx - d / 2, tip.dy - d * 1.32, d, d * 1.32);
  }

  /// Share (0..1) of [r] that lies under any of [covers].
  static double _coveredShare(Rect r, List<Rect> covers) {
    final area = r.width * r.height;
    if (area <= 0) return 0;
    var hidden = 0.0;
    for (final c in covers) {
      final i = r.intersect(c);
      if (i.width > 0 && i.height > 0) hidden += i.width * i.height;
    }
    return hidden / area;
  }

  // ── which pins to show (thinned so they never pile up) ─────────
  List<_Placed> _layoutPins(Matrix4 full, double zoom) {
    final rel = zoom / math.max(1e-6, _fit0);
    final denseVisible = widget.showAllPins || rel >= _denseZoom;
    final out = <_Placed>[];
    final placedBoxes = <Rect>[];
    // the "you are here" marker is drawn under the pins but must stay readable
    Rect? youBox;
    if (widget.originMapId == widget.map.id && widget.originPos != null) {
      final y = _screenOf(
        full,
        widget.originPos!,
        z: _groundZ(widget.originPos!),
      );
      youBox = Rect.fromCenter(center: y, width: 40, height: 40);
    }
    final step = _stepScreen(full);
    final stepBox = step == null
        ? null
        : Rect.fromCenter(center: step, width: 40, height: 40);
    for (final c in _sorted) {
      final pl = c.place;
      if (pl.category.isDense && !(denseVisible || c.prio <= 2)) continue;
      final s = _screenOf(full, pl.position, z: _groundZ(pl.position));
      if (!_onScreen(s)) continue;
      // A pin that is mostly behind a map button cannot be read or tapped: wait
      // until the map is panned clear of it. Selected, route-target and saved
      // pins (prio <= 2) are never dropped.
      if (c.prio > 2 &&
          widget.keepClear.isNotEmpty &&
          _coveredShare(_pinBox(pl, s), widget.keepClear) > 0.3) {
        continue;
      }
      if (c.prio > 2) {
        // Compare the pins' real on-screen bodies (not just their tips): the
        // body rises ~1.3x its width above the tip, so two pins whose tips are
        // far enough apart can still sit on top of each other, depending on the
        // rotation and tilt. A small gap keeps neighbours readable.
        final gap = pl.category.isDense ? (rel >= 2.0 ? 1.0 : 3.0) : 4.0;
        final box = _pinBox(pl, s).inflate(gap / 2);
        var clash = (youBox != null && box.overlaps(youBox)) ||
            (stepBox != null && box.overlaps(stepBox));
        if (!clash) {
          for (final o in placedBoxes) {
            if (box.overlaps(o)) {
              clash = true;
              break;
            }
          }
        }
        if (clash) continue;
      }
      placedBoxes.add(
        _pinBox(
          pl,
          s,
          selected: pl.id == widget.selected?.id,
        ).inflate((pl.category.isDense ? 0.5 : 2.0)),
      );
      out.add((place: pl, screen: s, prio: c.prio));
    }
    return out;
  }

  /// The pin's place in the walk being followed, if it is a stop.
  PinStop? _stopOf(MapPlace pl) {
    final g = widget.trip, node = widget.stopNodes[pl.id];
    if (g == null || node == null) return null;
    final n = g.numberOf(node), st = g.stateOf(node);
    if (n == null || st == null) return null;
    return (number: n, total: g.total, state: st, last: n == g.total);
  }

  bool get _routeShown =>
      widget.legs.isNotEmpty || widget.laterLegs.isNotEmpty || widget.trip != null;

  List<Widget> _pinWidgets(List<_Placed> pins) {
    final sel = widget.selected;
    final routing = _routeShown;
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
            stop: _stopOf(c.place),
            // while a route is shown, pins off it step back so the way reads first
            quiet: routing && c.prio > 2,
            onTap: () => widget.onPlaceTap(c.place),
          ),
        ),
    ];
  }

  /// Where the instruction being read happens, on screen (null when it is on
  /// another map or off screen).
  Offset? _stepScreen(Matrix4 full) {
    final st = widget.stepFocus;
    final at = st?.position;
    if (st == null || at == null || st.mapId != widget.map.id) return null;
    // the arrival is already marked by the destination's pin and ring
    if (st.kind == StepKind.arrive) return null;
    final s = _screenOf(full, at, z: _groundZ(at));
    return _onScreen(s) ? s : null;
  }

  List<Widget> _markers(Matrix4 full, GemPalette p) {
    final out = <Widget>[];
    final step = _stepScreen(full);
    if (step != null) {
      out.add(
        Positioned(
          key: const ValueKey('step'),
          left: step.dx - 19,
          top: step.dy - 19,
          width: 38,
          height: 38,
          child: IgnorePointer(child: _StepMarker(pal: p, icon: widget.stepFocus!.icon)),
        ),
      );
    }
    if (widget.originMapId != widget.map.id || widget.originPos == null) {
      return out;
    }
    final s = _screenOf(
      full,
      widget.originPos!,
      z: _groundZ(widget.originPos!),
    );
    if (!_onScreen(s)) return out;
    return [
      ...out,
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

  /// Where a leg ends at stairs, a lift, the moving walkway or a door, a callout
  /// says what to do there; when the route goes on in another plan, tapping
  /// it opens that plan.
  List<Widget> _chips(Matrix4 full, GemPalette p) {
    final res = <Widget>[];
    for (var i = 0; i < widget.legs.length; i++) {
      final leg = widget.legs[i];
      if (leg.portal == null || leg.points.isEmpty) continue;
      final s = _screenOf(full, leg.points.last, z: _groundZ(leg.points.last));
      if (!_onScreen(s, 120)) continue;
      final next = leg.nextMapId == null ? null : allMaps[leg.nextMapId!];
      // wide enough for the longer languages to say it in two lines
      final w = math.min(340.0, _vp.width - 24);
      res.add(
        Positioned(
          key: ValueKey('chip_$i'),
          left: (s.dx - w / 2).clamp(12.0, math.max(12.0, _vp.width - 12 - w)),
          top: s.dy - 76 - 26,
          width: w,
          height: 76,
          child: Center(
            child: _ExitChip(
              pal: p,
              icon: switch (leg.portal!.kind) {
                PortalKind.stairs => Icons.stairs,
                PortalKind.lift => Icons.elevator,
                PortalKind.travelator => Icons.moving,
                PortalKind.door => Icons.login,
              },
              label: leg.exitStep == null ? '' : S.step(leg.exitStep!),
              detail: next == null
                  ? null
                  : S.t('tap_to_open', x: S.mapShort(next)),
              onTap: next == null ? null : () => widget.onPortalTap(next.id),
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

/// The three painted layers of the model, bottom to top.
enum _Layer { scene, route, labels }

class _IsoPainter extends CustomPainter {
  _IsoPainter({
    required this.s,
    required this.pal,
    required this.layer,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final _MuseumMapCanvasState s;
  final GemPalette pal;
  final _Layer layer;

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
    switch (layer) {
      case _Layer.scene:
        _scene(canvas, full, zoom, yaw, view);
      case _Layer.route:
        _route(canvas, full);
      case _Layer.labels:
        _labels(canvas, full, flat, view, size);
    }
  }

  void _scene(Canvas canvas, Matrix4 full, double zoom, double yaw, Rect view) {
    final focus = s._focusIds;
    final px = s._px;

    // ── 1. floor: room floors, then the plan itself ──
    canvas.save();
    canvas.transform(full.storage);
    canvas.drawPath(s._floorPath, Paint()..color = _floorColor);
    for (final (kind, path) in s._extraFloors) {
      final c = switch (kind) {
        // Mode-independent brand tints, like _floorColor itself, so a hall or zone
        // is the same lightness in day and night (pal.gold is dark in day mode).
        'hall' => Color.lerp(_floorColor, GemColors.teal, 0.16)!,
        'landing' => Color.lerp(_floorColor, GemColors.gold, 0.28)!,
        'zone' => Color.lerp(_floorColor, GemColors.gold, 0.38)!,
        _ => _floorColor,
      };
      canvas.drawPath(path, Paint()..color = c);
    }
    _art(canvas, px);
    // gardens, car parks and plazas over the plan's own fills: gardens in the
    // green of the official GEM map legend (the PDF plan fills them tan)
    _groundFills(canvas);
    _bayLines(canvas);
    canvas.restore();

    // ── 2. rooms and the things standing in them, back to front ──
    // Per room: far walls -> what stands on the floor -> near walls. So a tread
    // or a case is hidden by the wall in front of it and hides the wall behind
    // it, whatever the yaw/tilt, instead of every wall landing on top of it.
    final prisms = focus.isEmpty
        ? const <_Prism>[]
        : ([...s._prisms]
            ..sort(
              (a, b) => project(full, a.centroid.dx, a.centroid.dy).dy.compareTo(project(full, b.centroid.dx, b.centroid.dy).dy),
            ));
    // walls, blocks, roofed buildings and figures in one depth order (the
    // walls of focused rooms are drawn again, lifted, above the veil)
    _slabsPaint(canvas, full, yaw, view, skip: focus);
    if (focus.isNotEmpty) {
      final lit = [
        for (final pr in prisms)
          if (focus.contains(pr.region.id)) pr,
      ];
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
      _figuresPaint(canvas, full, yaw, view, focus: focus);
    }
  }

  Color _slabColor(String kind) => switch (kind) {
    'shop' => pal.dark ? const Color(0xff6f8a78) : const Color(0xff7d977f),
    'food' => const Color(0xffc4705d),
    'service' => Color.lerp(pal.pinService, pal.surfaceHi, 0.45)!,
    'plinth' => pal.dark ? const Color(0xffd8bf86) : const Color(0xffcfb06a),
    'monument' => const Color(0xff4a4f55),
    // the colossi's plinths: stone, not a dark hole under their feet
    'statue' => pal.dark ? const Color(0xff8c8478) : const Color(0xffb3aa9a),
    'wall' || 'rwall' => pal.solid,
    'step' => Color.lerp(pal.gold, _floorColor, 0.55)!,
    'ledge' => Color.lerp(pal.solid, _floorColor, 0.45)!,
    _ => Color.lerp(pal.solid, _floorColor, 0.55)!,
  };

  /// Everything that stands up, back to front, in one depth order (see
  /// [_MuseumMapCanvasState._orderedSlabs]). Faces and roofs of consecutive
  /// solids go into one batch of triangles (one draw call instead of a path
  /// each); a figure or a roofed block (whose roof shows the plan) flushes it.
  /// [skip]: rooms drawn later, lifted above the veil. With [inside], only the
  /// blocks standing in those rooms (the rooms' walls and figures are drawn
  /// by their own passes).
  void _slabsPaint(
    Canvas canvas,
    Matrix4 full,
    double yaw,
    Rect view, {
    List<_Prism>? inside,
    Set<String> skip = const {},
  }) {
    if (s._slabs.isEmpty) return;
    final cs = math.cos(yaw), sn = math.sin(yaw);
    final pos = <double>[];
    final cols = <int>[];
    void tri(Offset a, Offset b, Offset c, int col) {
      pos
        ..add(a.dx)
        ..add(a.dy)
        ..add(b.dx)
        ..add(b.dy)
        ..add(c.dx)
        ..add(c.dy);
      cols
        ..add(col)
        ..add(col)
        ..add(col);
    }

    void quad(Offset a, Offset b, Offset c, Offset d, int col) {
      tri(a, b, c, col);
      tri(a, c, d, col);
    }

    // a top edge, as a thin band (no strokes inside a batch)
    void edge(Offset a, Offset b, double w, int col) {
      final d = b - a, l = d.distance;
      if (l < 1e-3) return;
      final n = Offset(-d.dy, d.dx) * (w / 2 / l);
      quad(a - n, b - n, b + n, a + n, col);
    }

    void flush() {
      if (pos.isEmpty) return;
      canvas.drawVertices(
        ui.Vertices.raw(ui.VertexMode.triangles, Float32List.fromList(pos), colors: Int32List.fromList(cols)),
        BlendMode.dst,
        Paint(),
      );
      pos.clear();
      cols.clear();
    }

    final rimMix = pal.rim;
    final wallDark = _shade(pal.solid, 0.7), wallLit = _shade(pal.solid, 1.3);
    final inner = Color.lerp(pal.solid, pal.rim, 0.3)!;
    final innerDark = _shade(inner, 0.8), innerLit = _shade(inner, 1.12);
    final wallRim = Color.lerp(pal.solid, pal.rim, 0.55)!.toARGB32();
    for (final sl in s._orderedSlabs(yaw)) {
      final joined = sl.kind == 'figure' || sl.kind == 'pwall' || sl.kind == 'psolid';
      if (inside != null) {
        if (joined || !inside.any((pr) => pr.region.contains(sl.normCentroid))) continue;
      } else if (sl.prism != null && skip.contains(sl.prism!.region.id)) {
        continue;
      }
      if (sl.kind == 'figure') {
        flush();
        _paintFigure(canvas, full, yaw, view, sl.figure!);
        continue;
      }
      if (sl.kind == 'psolid') {
        flush();
        _solidPiece(canvas, full, yaw, view, sl, skip.contains(sl.prism!.region.id));
        continue;
      }
      if (sl.kind == 'pwall') {
        final pr = sl.prism!;
        final h = pr.height * (1 + 0.7 * s._liftOf(pr.region.id));
        final b0 = project(full, sl.pts[0].dx, sl.pts[0].dy), b1 = project(full, sl.pts[1].dx, sl.pts[1].dy);
        final u0 = project(full, sl.pts[0].dx, sl.pts[0].dy, h), u1 = project(full, sl.pts[1].dx, sl.pts[1].dy, h);
        final r = Rect.fromPoints(b0, b1).expandToInclude(Rect.fromPoints(u0, u1));
        if (!view.overlaps(r)) continue;
        final d = sl.pts[1] - sl.pts[0], len = d.distance;
        final nx = pr.sign > 0 ? d.dy / len : -d.dy / len, ny = pr.sign > 0 ? -d.dx / len : d.dx / len;
        final sx = nx * cs - ny * sn, sy = nx * sn + ny * cs;
        final facing = sy >= 0; // its outer face towards us, or the inside of the room
        final k = ((facing ? (sx * _lx + sy * _ly) : -(sx * _lx + sy * _ly)) * 0.5 + 0.5).clamp(0.0, 1.0);
        final c = facing ? Color.lerp(wallDark, wallLit, k)! : Color.lerp(innerDark, innerLit, k)!;
        quad(b0, b1, u1, u0, c.toARGB32());
        edge(u0, u1, 1.2, wallRim);
        continue;
      }
      final n = sl.pts.length;
      final h = sl.height;
      final base = [for (final p in sl.pts) project(full, p.dx, p.dy)];
      final top = [for (final p in sl.pts) project(full, p.dx, p.dy, h)];
      var l = double.infinity, t = double.infinity;
      var r = -double.infinity, b = -double.infinity;
      for (final o in base) {
        l = math.min(l, o.dx);
        t = math.min(t, o.dy);
        r = math.max(r, o.dx);
        b = math.max(b, o.dy);
      }
      for (final o in top) {
        l = math.min(l, o.dx);
        t = math.min(t, o.dy);
        r = math.max(r, o.dx);
        b = math.max(b, o.dy);
      }
      if (!view.overlaps(Rect.fromLTRB(l, t, r, b))) continue;
      final roofC = _slabColor(sl.kind);
      final dark = _shade(roofC, 0.72), lit = _shade(roofC, 1.05);
      final order2 = List<int>.generate(n, (i) => i)
        ..sort((a, c) => (base[a].dy + base[(a + 1) % n].dy).compareTo(base[c].dy + base[(c + 1) % n].dy));
      for (final i in order2) {
        if (!sl.outer[i]) continue; // a seam inside one solid, not a wall
        final j = (i + 1) % n;
        final dx = sl.pts[j].dx - sl.pts[i].dx, dy = sl.pts[j].dy - sl.pts[i].dy;
        final len = math.sqrt(dx * dx + dy * dy);
        if (len < 1e-6) continue;
        final nx = sl.sign > 0 ? dy / len : -dy / len;
        final ny = sl.sign > 0 ? -dx / len : dx / len;
        final sx = nx * cs - ny * sn, sy = nx * sn + ny * cs;
        if (sy < 0) continue; // face turned away from us
        final k = ((sx * _lx + sy * _ly) * 0.5 + 0.5).clamp(0.0, 1.0);
        quad(base[i], base[j], top[j], top[i], Color.lerp(dark, lit, k)!.toARGB32());
      }
      if (sl.convex) {
        for (var i = 1; i + 1 < n; i++) {
          tri(top[0], top[i], top[i + 1], roofC.toARGB32());
        }
      } else {
        flush();
        canvas.drawPath(Path()..addPolygon(top, true), Paint()..color = roofC);
      }
      if (sl.kind != 'step' && sl.kind != 'rwall') {
        final rc = Color.lerp(roofC, rimMix, 0.35)!.toARGB32();
        for (var i = 0; i < n; i++) {
          if (sl.outer[i]) edge(top[i], top[(i + 1) % n], 0.8, rc);
        }
      }
    }
    flush();
  }

  /// A convex piece of a roofed block (a building on the site plan): its outer
  /// walls facing us, and its roof showing the plan.
  void _solidPiece(Canvas canvas, Matrix4 full, double yaw, Rect view, _Slab sl, bool focused) {
    final pr = sl.prism!;
    final h = pr.height * (1 + 0.7 * s._liftOf(pr.region.id));
    final n = sl.pts.length;
    final base = [for (final p in sl.pts) project(full, p.dx, p.dy)];
    final top = [for (final p in sl.pts) project(full, p.dx, p.dy, h)];
    var r = Rect.fromPoints(base[0], top[0]);
    for (var i = 1; i < n; i++) {
      r = r.expandToInclude(Rect.fromPoints(base[i], top[i]));
    }
    if (!view.overlaps(r)) return;
    final cs = math.cos(yaw), sn = math.sin(yaw);
    // the site's buildings are faced in pale stone (the main building's
    // translucent alabaster façade), not the slate of indoor walls
    final stone = pal.dark ? const Color(0xffa39a87) : const Color(0xffd6ccb7);
    final dark = _shade(stone, 0.72), lit = _shade(stone, 1.08);
    for (var i = 0; i < n; i++) {
      if (!sl.outer[i]) continue;
      final j = (i + 1) % n;
      final d = sl.pts[j] - sl.pts[i], len = d.distance;
      if (len < 1e-6) continue;
      final nx = sl.sign > 0 ? d.dy / len : -d.dy / len, ny = sl.sign > 0 ? -d.dx / len : d.dx / len;
      final sx = nx * cs - ny * sn, sy = nx * sn + ny * cs;
      if (sy < 0) continue;
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
    // pieces of one roof meet edge to edge: without anti-aliasing they join
    // seamlessly (no hairline between them); the outer edges get the rim
    final roof = Path()..addPolygon(top, true);
    canvas.save();
    canvas.clipPath(roof, doAntiAlias: false);
    canvas.drawPath(roof, Paint()
      ..color = _floorColor
      ..isAntiAlias = false);
    if (s._image != null) {
      canvas.transform((full.clone()..translateByDouble(0.0, 0.0, h, 1)).storage);
      _art(canvas, s._px);
    }
    canvas.restore();
    if (focused) canvas.drawPath(roof, Paint()..color = pal.accent.withValues(alpha: 0.22));
    final rim = Paint()
      ..color = pal.rim.withValues(alpha: focused ? 0.9 : 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = focused ? 1.8 : 1.2;
    for (var i = 0; i < n; i++) {
      if (sl.outer[i]) canvas.drawLine(top[i], top[(i + 1) % n], rim);
    }
  }

  /// Gardens (sage green), parking (slate) and open plazas lie flat on the
  /// ground, drawn over the plan's artwork with their own outline.
  void _groundFills(Canvas canvas) {
    // gardens and parking first, then flat plazas (Events Area) on top of them
    for (final plazas in const [false, true]) {
      for (final (path, kind) in s._ground) {
        final plaza = kind == RegionKind.attraction;
        if (plaza != plazas) continue;
        final fill = plaza
            ? Color.lerp(_floorColor, GemColors.gold, 0.22)!
            : (kind == RegionKind.garden ? pal.garden : pal.parking);
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
  }

  /// The painted stall lines of the car parks, on the plan's artwork.
  void _bayLines(Canvas canvas) {
    if (s._bays.isEmpty) return;
    final paint = Paint()
      ..color = (pal.dark ? Colors.white : Colors.black).withValues(
        alpha: pal.dark ? 0.16 : 0.12,
      )
      ..strokeWidth = 0.9;
    for (final (a, b) in s._bays) {
      canvas.drawLine(a, b, paint);
    }
  }

  /// Monuments: every block's visible faces, lit from the upper left, drawn far
  /// to near. Faces are wound outwards consistently, so a face is visible when
  /// its projection turns the same way as the block's base seen from above.
  /// The figures standing in the focused regions, drawn again above the veil.
  void _figuresPaint(
    Canvas canvas,
    Matrix4 full,
    double yaw,
    Rect view, {
    required Set<String> focus,
  }) {
    if (s._figures.isEmpty) return;
    final rooms = [
      for (final r in s.widget.regions)
        if (focus.contains(r.id)) r,
    ];
    final tx = math.sin(yaw), ty = math.cos(yaw);
    final figs = [
      for (final f in s._figures)
        if (rooms.any((r) => r.contains(f.norm))) f,
    ]..sort((a, b) => (a.anchor.dx * tx + a.anchor.dy * ty).compareTo(b.anchor.dx * tx + b.anchor.dy * ty));
    for (final f in figs) {
      _paintFigure(canvas, full, yaw, view, f);
    }
  }

  void _paintFigure(Canvas canvas, Matrix4 full, double yaw, Rect view, _Figure fig) {
    final foot = project(full, fig.anchor.dx, fig.anchor.dy, 0);
    final top = project(full, fig.anchor.dx, fig.anchor.dy, fig.height);
    if (!view.inflate(fig.height * 2).contains(foot) && !view.contains(top)) return;
    if (fig.outline != null) {
      _outlineFigure(canvas, full, yaw, fig, foot);
      return;
    }
    // small on screen: the lighter model reads the same and costs a tenth
    final f = (top - foot).distance < 22 && fig.lo != null ? fig.lo! : fig;
    // direction towards the viewer: on the ground (sin yaw, cos yaw), and up
    final tx = math.sin(yaw), ty = math.cos(yaw);
    const tz = 0.7;
    // contact shadow
    final rim = project(full, f.anchor.dx + f.height * 0.22, f.anchor.dy, 0);
    final rx = (rim - foot).distance;
    canvas.drawOval(
      Rect.fromCenter(center: foot, width: rx * 2.4, height: rx * 1.1),
      Paint()..color = pal.shadow.withValues(alpha: pal.dark ? 0.4 : 0.2),
    );
    // faces turned towards the viewer, layer by layer (a dome after its roof),
    // far to near within a layer; depends on the yaw alone, so it is kept
    final key = (yaw * 360 / math.pi).round();
    if (key != f.orderKey) {
      final t = f.tris.length ~/ 3;
      final keep = <int>[];
      final depth = Float64List(t);
      for (var k = 0; k < t; k++) {
        if (f.normals[k * 3] * tx + f.normals[k * 3 + 1] * ty + f.normals[k * 3 + 2] * tz <= 0) continue;
        final a = f.tris[k * 3] * 3, b = f.tris[k * 3 + 1] * 3, c = f.tris[k * 3 + 2] * 3;
        depth[k] = (f.xyz[a] + f.xyz[b] + f.xyz[c]) * tx +
            (f.xyz[a + 1] + f.xyz[b + 1] + f.xyz[c + 1]) * ty +
            (f.xyz[a + 2] + f.xyz[b + 2] + f.xyz[c + 2]) * tz;
        keep.add(k);
      }
      final layer = f.layer;
      keep.sort((a, b) {
        if (layer != null && layer[a] != layer[b]) return layer[a].compareTo(layer[b]);
        return depth[a].compareTo(depth[b]);
      });
      f.order = keep;
      f.orderKey = key;
    }
    final keep = f.order;
    final n = f.xyz.length ~/ 3;
    final sx = Float32List(n), sy = Float32List(n);
    for (var i = 0; i < n; i++) {
      final o = project(full, f.xyz[i * 3], f.xyz[i * 3 + 1], f.xyz[i * 3 + 2]);
      sx[i] = o.dx;
      sy[i] = o.dy;
    }
    final pos = Float32List(keep.length * 6);
    final cols = Int32List(keep.length * 3);
    final shades = pal.dark ? f.litDark : f.lit;
    for (var i = 0; i < keep.length; i++) {
      final k = keep[i];
      for (var j = 0; j < 3; j++) {
        final v = f.tris[k * 3 + j];
        pos[i * 6 + j * 2] = sx[v];
        pos[i * 6 + j * 2 + 1] = sy[v];
        cols[i * 3 + j] = shades[k];
      }
    }
    // vertex colours only (BlendMode.dst keeps them, ignoring the paint)
    canvas.drawVertices(ui.Vertices.raw(ui.VertexMode.triangles, pos, colors: cols), BlendMode.dst, Paint());
  }

  /// A statue drawn as its front elevation: the outline stood upright on the
  /// floor, turned to face the viewer, with a little depth so it still reads as
  /// a solid when the map is tilted.
  void _outlineFigure(
    Canvas canvas,
    Matrix4 full,
    double yaw,
    _Figure f,
    Offset foot,
  ) {
    final cs = math.cos(yaw), sn = math.sin(yaw);
    // ground-plane directions: screen-right, and towards the viewer
    final rx = cs, ry = -sn, tx = sn, ty = cs;
    final h = f.height;
    final half = h * 0.07;
    Offset at(Offset p, double side) => project(
      full,
      f.anchor.dx + rx * p.dx * h + tx * side,
      f.anchor.dy + ry * p.dx * h + ty * side,
      p.dy * h,
    );
    final pts = f.outline!;
    final front = [for (final p in pts) at(p, half)];
    final back = [for (final p in pts) at(p, -half)];
    final base = Color(f.color).withValues(alpha: 1);
    final c = pal.dark ? _shade(base, 1.12) : base;
    // contact shadow on the floor
    final sh = project(
      full,
      f.anchor.dx + rx * h * 0.2,
      f.anchor.dy + ry * h * 0.2,
      0,
    );
    final r = (sh - foot).distance;
    canvas.drawOval(
      Rect.fromCenter(center: foot, width: r * 2.2, height: r * 0.9),
      Paint()..color = pal.shadow.withValues(alpha: pal.dark ? 0.45 : 0.22),
    );
    canvas.drawPath(
      Path()..addPolygon(back, true),
      Paint()..color = _shade(c, 0.55),
    );
    final side = Paint()
      ..color = _shade(c, 0.66)
      ..isAntiAlias = true;
    for (var i = 0; i < pts.length; i++) {
      final j = (i + 1) % pts.length;
      canvas.drawPath(
        Path()..addPolygon([front[i], front[j], back[j], back[i]], true),
        side,
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
      final fill = Paint()..color = color;
      for (final (t0, t1) in _solidRuns(
        pr.gaps.isEmpty ? const [] : pr.gaps[i],
      )) {
        final b0 = Offset.lerp(base[i], base[j], t0)!,
            b1 = Offset.lerp(base[i], base[j], t1)!;
        final u0 = Offset.lerp(top[i], top[j], t0)!,
            u1 = Offset.lerp(top[i], top[j], t1)!;
        final quad = Path()
          ..moveTo(b0.dx, b0.dy)
          ..lineTo(b1.dx, b1.dy)
          ..lineTo(u1.dx, u1.dy)
          ..lineTo(u0.dx, u0.dy)
          ..close();
        canvas.drawPath(quad, fill);
        canvas.drawLine(u0, u1, rim);
      }
    }

    if (pr.solid && pass != _Pass.back) {
      final roof = Path()..addPolygon(top, true);
      canvas.save();
      canvas.clipPath(roof, doAntiAlias: true);
      canvas.drawPath(roof, Paint()..color = _floorColor);
      if (s._image != null) {
        canvas.transform((full.clone()..translateByDouble(0.0, 0.0, h, 1)).storage);
        _art(canvas, s._px);
      }
      canvas.restore();
      if (focused) {
        canvas.drawPath(
          roof,
          Paint()..color = pal.accent.withValues(alpha: 0.22),
        );
      }
      canvas.drawPath(roof, rim);
    }
  }

  /// The route in three weights, so the next stretch is never in doubt:
  ///   * behind the visitor: a faint line;
  ///   * after the stop they are heading for: a light dotted line;
  ///   * the stretch to walk now: bold, with arrows along it pointing the way.
  /// Nothing moves once it is drawn in (one 0.9 s draw-in), so it can be read
  /// while walking.
  void _route(Canvas canvas, Matrix4 full) {
    Paint stroke(Color c, double w) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    List<Offset> screen(Float64List g) => [
      for (var i = 0; i + 2 < g.length; i += 3)
        project(full, g[i], g[i + 1], g[i + 2] + 0.5),
    ];

    Path line(List<Offset> pts, [double upTo = double.infinity]) {
      final path = Path()..moveTo(pts[0].dx, pts[0].dy);
      var drawn = 0.0;
      for (var i = 1; i < pts.length; i++) {
        final seg = (pts[i] - pts[i - 1]).distance;
        if (drawn + seg <= upTo) {
          path.lineTo(pts[i].dx, pts[i].dy);
          drawn += seg;
        } else {
          final f = seg == 0 ? 0.0 : (upTo - drawn) / seg;
          final e = Offset.lerp(pts[i - 1], pts[i], f)!;
          path.lineTo(e.dx, e.dy);
          break;
        }
      }
      return path;
    }

    for (final g in s._walkedGeo) {
      final pts = screen(g);
      if (pts.length < 2) continue;
      canvas.drawPath(line(pts), stroke(pal.route.withValues(alpha: 0.28), 4));
    }

    final dot = stroke(pal.route.withValues(alpha: 0.75), 3.4);
    for (final g in s._laterGeo) {
      final pts = screen(g);
      if (pts.length < 2) continue;
      for (final m in line(pts).computeMetrics()) {
        for (var d = 0.0; d < m.length; d += 11) {
          final t = m.getTangentForOffset(d);
          if (t != null) canvas.drawPoints(ui.PointMode.points, [t.position], dot);
        }
      }
    }

    final legs = s.widget.legs;
    final prog = s.widget.routeProgress.value.clamp(0.0, 1.0);
    final arrow = stroke(Colors.white.withValues(alpha: 0.95), 2.2);
    for (var li = 0; li < legs.length && li < s._routeGeo.length; li++) {
      final pts = screen(s._routeGeo[li]);
      if (pts.length < 2) continue;
      var total = 0.0;
      for (var i = 1; i < pts.length; i++) {
        total += (pts[i] - pts[i - 1]).distance;
      }
      final path = line(pts, total * prog);
      canvas.drawPath(path, stroke(pal.routeCase.withValues(alpha: 0.9), 9.5));
      canvas.drawPath(path, stroke(pal.route, 5.5));

      // chevrons along the line, pointing the way (spaced on screen, so they
      // stay evenly apart at any zoom; none on very short pieces)
      for (final m in path.computeMetrics()) {
        if (m.length < 40) continue;
        for (var d = 28.0; d < m.length - 14; d += 56) {
          final t = m.getTangentForOffset(d);
          if (t == null) continue;
          final dir = t.vector, nrm = Offset(-dir.dy, dir.dx);
          final tip = t.position + dir * 3;
          canvas.drawPath(
            Path()
              ..moveTo(tip.dx - dir.dx * 5 + nrm.dx * 3.6, tip.dy - dir.dy * 5 + nrm.dy * 3.6)
              ..lineTo(tip.dx, tip.dy)
              ..lineTo(tip.dx - dir.dx * 5 - nrm.dx * 3.6, tip.dy - dir.dy * 5 - nrm.dy * 3.6),
            arrow,
          );
        }
      }

      // the destination (only where this stretch really ends, not at a portal)
      if (legs[li].nextMapId == null && legs[li].portal == null && prog >= 0.999) {
        final end = pts.last;
        canvas.drawCircle(end, 11, Paint()..color = pal.rose.withValues(alpha: 0.25));
        canvas.drawCircle(end, 7.5, Paint()..color = Colors.white);
        canvas.drawCircle(end, 5, Paint()..color = pal.rose);
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
    final keepClear = s.widget.keepClear;
    final blockers = <Rect>[...s._pinRects, ...keepClear];
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
      // Keep the name out from under pins and map buttons (they are drawn above
      // it): slide it to the nearest free spot, else leave it out. A name the
      // person asked for (selected / highlighted room) stays put as a last resort.
      if (blockers.any((b) => b.overlaps(rect))) {
        bool free(Rect r) =>
            !blockers.any((b) => b.overlaps(r)) &&
            (it.force || !placed.any((o) => o.overlaps(r))) &&
            (rect.width >= safe.width ||
                (r.left >= safe.left && r.right <= safe.right)) &&
            (rect.height >= safe.height ||
                (r.top >= safe.top && r.bottom <= safe.bottom));
        final tries = <Offset>[];
        for (final d in const [10.0, 20.0, 32.0, 48.0, 68.0]) {
          for (final v in const [
            Offset(0, -1),
            Offset(0, 1),
            Offset(1, 0),
            Offset(-1, 0),
            Offset(0.7, -0.7),
            Offset(-0.7, -0.7),
            Offset(0.7, 0.7),
            Offset(-0.7, 0.7),
          ]) {
            tries.add(v * d);
          }
        }
        for (final k in keepClear) {
          if (!k.overlaps(rect)) continue;
          tries
            ..add(Offset(k.left - rect.right - 2, 0))
            ..add(Offset(k.right - rect.left + 2, 0));
        }
        tries.sort((a, b) => a.distance.compareTo(b.distance));
        Offset? nudge;
        for (final o in tries) {
          if (free(rect.shift(o))) {
            nudge = o;
            break;
          }
        }
        if (nudge != null) {
          shift += nudge;
          rect = rect.shift(nudge);
        } else if (!it.force) {
          continue;
        }
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
    this.stop,
    this.quiet = false,
  });
  final MapPlace place;
  final bool selected;
  final bool pinned;
  final bool target;
  final PinStop? stop;
  final bool quiet;
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
        child: AnimatedOpacity(
          opacity: quiet ? 0.5 : 1,
          duration: const Duration(milliseconds: 220),
          child: MapPin(
            place: place,
            isSelected: selected,
            isPinned: pinned,
            isTarget: target,
            stop: stop,
            onTap: onTap,
          ),
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

/// The spot where the instruction being read happens: a white disc with the
/// instruction's icon, ringed in the route colour. Still, so it reads at a glance.
class _StepMarker extends StatelessWidget {
  const _StepMarker({required this.pal, required this.icon});
  final GemPalette pal;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      shape: BoxShape.circle,
      border: Border.all(color: pal.routeCase, width: 3),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.35),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Icon(icon, size: 20, color: pal.routeCase),
  );
}

/// "Continue on …": where the route leaves this map.
class _ExitChip extends StatelessWidget {
  const _ExitChip({
    required this.pal,
    required this.icon,
    required this.label,
    this.detail,
    this.onTap,
  });
  final GemPalette pal;
  final IconData icon;

  /// The instruction ("Take the stairs up to the 3rd floor").
  final String label;

  /// Second line when the route goes on in another plan ("Tap to open …").
  final String? detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: pal.accent,
      borderRadius: BorderRadius.circular(18),
      boxShadow: gemShadow(pal),
    ),
    child: Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: pal.onAccent.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 18, color: pal.onAccent),
              ),
              const SizedBox(width: 9),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Arial',
                        fontSize: 13,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                        color: pal.onAccent,
                      ),
                    ),
                    if (detail != null)
                      Text(
                        detail!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Arial',
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: pal.onAccent.withValues(alpha: 0.85),
                        ),
                      ),
                  ],
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right, // mirrors itself in right-to-left text
                  size: 20,
                  color: pal.onAccent,
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
