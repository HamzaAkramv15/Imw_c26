"""Real floors, halls, display zones, missing cases and stair flights for the two
plans that were broken: the Main Galleries and the Tutankhamun Galleries.

Everything is read from the original plan SVGs in assets/maps/light/ (which are
the PDF's own vector geometry).  Nothing is invented except where marked
"CHOICE" below.  Output: lib/data/gem_floors.dart

Main Galleries (viewBox 1400x1080)
  * floor  = the building footprint.  The plan draws walls as open polylines
             (stroke #9aa6a4) whose door gaps never close, so the footprint is
             found by closing gaps up to 2*CLOSE px (CHOICE: CLOSE = 16) and
             filling the outline.  Notches wider than 2*CLOSE stay open.
  * steps  = the plan's stair hatches (short parallel strokes).  The plan does
             not say which end of a flight is the top, so every tread is drawn at
             the same height (CHOICE) - no direction is implied.

Tutankhamun Galleries (viewBox 1389x962)
  * hall    = the SVG's grey connecting band (path 5, fill #b4bdbb) minus the five
              corridor fills.  (tools/tut_hall.txt had the right polygon but it
              was never wired into the app.)
  * landing = the beige patches inside that hall (paths 7-11).
  * zone    = the dashed display-zone outlines (stroke-dasharray), grouped and
              closed (CHOICE: dashes less than 4 px apart belong to one outline).
  * cases   = every closed light outline / small light fill / light bar that is not
              already in kBlocks['tutankhamun'].
  * steps   = the black stair hatches at the corridor ends.
"""
import sys, os, math, re
sys.path.insert(0, os.path.dirname(__file__))
from svgutil import load_paths, subpaths
from shapely.geometry import LineString, Polygon
from shapely.ops import unary_union
from shapely.geometry.polygon import orient

HERE = os.path.dirname(__file__)
ROOT = os.path.join(HERE, '..')
CLOSE = 16.0


def polys(g):
    if g.is_empty:
        return []
    return [g] if g.geom_type == 'Polygon' else [p for p in g.geoms if p.geom_type == 'Polygon']


def fmt(pg, W, H, nd=4):
    pg = orient(pg, 1.0)
    pts = list(pg.exterior.coords)[:-1]
    return ','.join('%.*f,%.*f' % (nd, x / W, nd, y / H) for x, y in pts)


# ───────────────────────── regions (read back from the app) ─────────────────
def read_regions(map_id, W, H):
    src = open(os.path.join(ROOT, 'lib/data/gem_regions.dart')).read()
    out = {}
    for m in re.finditer(r"MapRegion\(id: '(\w+)', mapId: '(\w+)'.*?points: _p\(const \[([^\]]*)\]", src, re.S):
        if m.group(2) != map_id:
            continue
        v = [float(x) for x in m.group(3).replace('\n', ' ').split(',') if x.strip()]
        out[m.group(1)] = Polygon([(v[i] * W, v[i + 1] * H) for i in range(0, len(v), 2)]).buffer(0)
    return out


# ───────────────────────── stair flights ────────────────────────────────────
def flight_treads(strokes, fill=0.62):
    """strokes: list of ((x0,y0),(x1,y1)) parallel hatch lines of one flight.
    Returns tread quads: each stroke widened toward the next one by `fill` of the pitch."""
    if len(strokes) < 2:
        return []
    ux = sum(s[1][0] - s[0][0] for s in strokes)
    uy = sum(s[1][1] - s[0][1] for s in strokes)
    n = math.hypot(ux, uy)
    ux, uy = ux / n, uy / n
    # orient every stroke the same way
    st = []
    for a, b in strokes:
        if (b[0] - a[0]) * ux + (b[1] - a[1]) * uy < 0:
            a, b = b, a
        st.append((a, b))
    nx, ny = -uy, ux  # run direction = across the strokes
    st.sort(key=lambda s: ((s[0][0] + s[1][0]) / 2) * nx + ((s[0][1] + s[1][1]) / 2) * ny)
    pos = [((s[0][0] + s[1][0]) / 2) * nx + ((s[0][1] + s[1][1]) / 2) * ny for s in st]
    pitch = (pos[-1] - pos[0]) / (len(st) - 1)
    out = []
    for k, (a, b) in enumerate(st):
        d = pitch * fill
        a2 = (a[0] + nx * d, a[1] + ny * d)
        b2 = (b[0] + nx * d, b[1] + ny * d)
        out.append([a, b, b2, a2])
    return out


def cluster(items, radius, ang_tol=None):
    par = list(range(len(items)))

    def f(x):
        while par[x] != x:
            par[x] = par[par[x]]
            x = par[x]
        return x
    for a in range(len(items)):
        for b in range(a + 1, len(items)):
            if math.dist(items[a]['m'], items[b]['m']) < radius and (ang_tol is None or abs(items[a]['ang'] - items[b]['ang']) < ang_tol):
                par[f(a)] = f(b)
    cl = {}
    for k in range(len(items)):
        cl.setdefault(f(k), []).append(items[k])
    return list(cl.values())


def step_lines(treads, W, H, h):
    return ["    MapStep(%.4f, [%s])," % (h, ','.join('%.4f,%.4f' % (x / W, y / H) for x, y in q)) for q in treads]


# ═════════════════════════ MAIN GALLERIES ═══════════════════════════════════
def galleries():
    W, H = 1400.0, 1080.0
    P = load_paths(os.path.join(ROOT, 'assets/maps/light/main_galleries.svg'))
    walls = []
    hatch = []
    for i, a, M in P:
        if a.get('stroke') != '#9aa6a4':
            continue
        for sp in subpaths(a['d'], M, 6):
            if len(sp) < 2:
                continue
            ls = LineString(sp)
            walls.append(ls)
            if ls.length < 60:
                (x0, y0), (x1, y1) = sp[0], sp[-1]
                ang = math.degrees(math.atan2(y1 - y0, x1 - x0)) % 180
                if 100 <= ang <= 125:  # all stair hatches of this plan lie at ~105 deg
                    hatch.append(dict(p=(sp[0], sp[-1]), m=((x0 + x1) / 2, (y0 + y1) / 2), ang=ang))
    U = unary_union(walls)
    B = U.buffer(CLOSE)
    foot = unary_union([Polygon(p.exterior) for p in polys(B)]).buffer(-CLOSE)
    foot = max(polys(foot), key=lambda p: p.area)
    foot = Polygon(foot.exterior).simplify(0.7)

    regs = read_regions('main_galleries', W, H)
    ru = unary_union(list(regs.values())).buffer(1.6)
    halls = [p.buffer(-2.5).buffer(2.5) for p in polys(foot.difference(ru))]
    halls = [p.simplify(0.7) for q in halls for p in polys(q) if p.area >= 250]

    flights = [c for c in cluster(hatch, 16) if len(c) >= 3]
    steps = []
    for c in flights:
        steps += flight_treads([h['p'] for h in c])
    print('galleries: footprint verts', len(foot.exterior.coords) - 1, 'area', round(foot.area),
          '| halls', len(halls), round(sum(p.area for p in halls)), '| flights', len(flights), 'treads', len(steps))
    floors = ["    MapFloor('floor', [%s])," % fmt(foot, W, H)]
    # (the leftover gaps between the old gallery outlines are NOT tinted as halls: their edges are
    #  the old tracing's, so tinting them would only expose it. The uniform footprint floor hides them.)
    return floors, step_lines(steps, W, H, 0.016), [], foot, halls, steps, (W, H)


# ═════════════════════════ TUTANKHAMUN ══════════════════════════════════════
def tutankhamun():
    W, H = 1389.0, 962.0
    PL = load_paths(os.path.join(ROOT, 'assets/maps/light/tutankhamun.svg'))
    P = {i: (a, M) for i, a, M in PL}

    def poly_of(i, n=8):
        return Polygon(subpaths(P[i][0]['d'], P[i][1], n)[0]).buffer(0)
    corridors = unary_union([poly_of(i) for i in (0, 1, 2, 3, 4, 6)])
    hall = poly_of(5).difference(corridors)
    hall = [p.simplify(0.4) for p in polys(hall)]
    landings = [poly_of(i).intersection(poly_of(5)).simplify(0.4) for i in (7, 8, 9, 10, 11)]
    landings = [p for q in landings for p in polys(q) if p.area > 500]

    # ── dashed display zones ──
    dashed = []
    for i, (a, M) in P.items():
        if a.get('stroke-dasharray'):
            for sp in subpaths(a['d'], M, 6):
                dashed.append(LineString(sp))
    zones = []
    for g in polys(unary_union(dashed).buffer(4.0)):
        frags = [l for l in dashed if l.distance(g.representative_point()) < 1e9 and g.buffer(0.5).contains(l)]
        if not frags:
            continue
        # chain the dash fragments end to end (nearest free end within 12 px), then close the ring
        frags = sorted(frags, key=lambda l: -l.length)
        chain = list(frags[0].coords)
        rest = frags[1:]
        while rest:
            best = None
            for k, l in enumerate(rest):
                c = list(l.coords)
                for rev in (False, True):
                    cc = c[::-1] if rev else c
                    for at_end in (True, False):
                        ref = chain[-1] if at_end else chain[0]
                        dist = math.dist(ref, cc[0] if at_end else cc[-1])
                        if best is None or dist < best[0]:
                            best = (dist, k, cc, at_end)
            dist, k, cc, at_end = best
            if dist > 12:
                break
            chain = chain + cc if at_end else cc + chain
            rest.pop(k)
        if len(chain) >= 4:
            pg = Polygon(chain).buffer(0)
            for p in polys(pg):
                if p.area > 300:
                    zones.append(p.simplify(0.5))
    # ── cases: not already in kBlocks['tutankhamun'] ──
    src = open(os.path.join(ROOT, 'lib/data/gem_blocks.dart')).read()
    b = src.find("  'tutankhamun': [", src.find('const Map<String, List<MapBlock>> kBlocks'))
    e = src.find('\n  ],', b)
    have = []
    for m in re.finditer(r"MapBlock\('\w+', [\d.]+, \[([^\]]*)\]", src[b:e]):
        v = [float(x) for x in m.group(1).split(',')]
        have.append(Polygon([(v[i] * W, v[i + 1] * H) for i in range(0, len(v), 2)]).buffer(0))
    print('tut: existing blocks', len(have))

    def covered(pg):
        return any(pg.intersection(h).area > 0.5 * min(pg.area, h.area) for h in have)

    cand = []  # (svg path index, polygon)
    for i, a, M in PL:
        light_outline = a.get('fill') == 'none' and a.get('stroke') == '#f7f1e7'
        small_fill = a.get('fill') == '#c9c8bb' and a.get('stroke') is None and i not in (7, 8, 9, 10, 11)
        if not (light_outline or small_fill):
            continue
        for sp in subpaths(a['d'], M, 6):
            if len(sp) < 4:
                continue
            pg = Polygon(sp).buffer(0)
            if pg.is_empty or pg.area < 8 or pg.area > 3000:
                continue
            for q in polys(pg.simplify(0.4)):
                cand.append((i, q))
    # open beige strokes (3 px wide): short ones are thin bars, the two long ones with
    # their small companions are rectangular display tables drawn on three sides
    open_lines = {}
    for i, a, M in PL:
        if a.get('fill') == 'none' and a.get('stroke') == '#c9c8bb':
            for sp in subpaths(a['d'], M, 6):
                open_lines[i] = LineString(sp)
    tables = [(200, 201), (208, 209)]
    used = set()
    for i, j in tables:
        cand.append((i, unary_union([open_lines[i], open_lines[j]]).convex_hull))
        used |= {i, j}
    for i, ls in open_lines.items():
        if i not in used:
            cand.append((i, ls.buffer(1.6, cap_style=2)))

    new, ledges = [], []
    for i, pg in cand:
        if pg.geom_type != 'Polygon' or covered(pg):
            continue
        r = pg.minimum_rotated_rectangle.exterior.coords
        side = sorted([math.dist(r[k], r[k + 1]) for k in range(2)])
        thin = side[0] < 6 or side[1] / max(side[0], 1e-6) > 8
        new.append((i, pg, thin))
    blocks = []
    for i, pg, thin in new:
        kind, h = ('ledge', 0.010) if thin else ('fixture', 0.007)
        blocks.append("    MapBlock('%s', %s, [%s]), // svg path %d" % (kind, h, fmt(pg, W, H), i))
    print('tut: candidates', len(cand), 'new', len(new), '(thin', sum(1 for n in new if n[2]), ')')

    # ── stair hatches at the corridor ends (black, vertical, 20-33 px) ──
    S = []
    for i, a, M in PL:
        if a.get('stroke') != '#182025' or a.get('stroke-dasharray'):
            continue
        for sp in subpaths(a['d'], M, 6):
            L = LineString(sp).length
            if 6 <= L < 45 and len(sp) <= 8:
                (x0, y0), (x1, y1) = sp[0], sp[-1]
                S.append(dict(p=(sp[0], sp[-1]), m=((x0 + x1) / 2, (y0 + y1) / 2), ang=math.degrees(math.atan2(y1 - y0, x1 - x0)) % 180))
    flights = [c for c in cluster(S, 10, 8) if len(c) >= 4]
    steps = []
    for c in flights:
        steps += flight_treads([s['p'] for s in c])
    print('tut: hall pieces', len(hall), [round(p.area) for p in hall], '| landings', len(landings), '| zones', len(zones),
          [round(p.area) for p in zones], '| flights', len(flights), 'treads', len(steps))
    floors = ["    MapFloor('hall', [%s])," % fmt(p, W, H) for p in hall]
    floors += ["    MapFloor('landing', [%s])," % fmt(p, W, H) for p in landings]
    floors += ["    MapFloor('zone', [%s])," % fmt(p, W, H) for p in zones]
    return floors, step_lines(steps, W, H, 0.016), blocks, hall, landings, zones, new, steps, (W, H)


def main():
    gf, gs, gb, gfoot, ghalls, gsteps, gwh = galleries()
    tf, ts, tb, thall, tland, tzones, tnew, tsteps, twh = tutankhamun()
    out = ["// GENERATED by tools/build_floors.py from the original plan SVGs. Do not edit by hand.",
           "//",
           "// What the plans draw but the canvas did not have (see the script's docstring):",
           "//   * MapFloor - flat floor areas that are not part of any region: the Main Galleries'",
           "//     real footprint and the circulation space between the numbered galleries, the",
           "//     Tutankhamun connecting hall, its landings and its dashed display zones.",
           "//   * kExtraBlocks - Tutankhamun cases that were never extracted.",
           "//   * kExtraSteps  - stair flights (the plans' hatch strokes), drawn as treads.",
           "//",
           "// Same normalised (0..1) space as MapPlace.position. The routing graph (gem_nav.dart)",
           "// is built from these floors and treads by tools/build_nav.py.",
           "import 'gem_blocks.dart';",
           "",
           "class MapFloor {",
           "  const MapFloor(this.kind, this.pts);",
           "",
           "  /// floor (building footprint) | hall (circulation) | landing | zone (display zone)",
           "  final String kind;",
           "",
           "  /// x0,y0,x1,y1,... normalised.",
           "  final List<double> pts;",
           "}",
           "",
           "const Map<String, List<MapFloor>> kFloors = {",
           "  'main_galleries': [", *gf, "  ],",
           "  'tutankhamun': [", *tf, "  ],",
           "};",
           "",
           "const Map<String, List<MapBlock>> kExtraBlocks = {",
           "  'tutankhamun': [", *tb, "  ],",
           "};",
           "",
           "const Map<String, List<MapStep>> kExtraSteps = {",
           "  'main_galleries': [", *gs, "  ],",
           "  'tutankhamun': [", *ts, "  ],",
           "};", ""]
    open(os.path.join(ROOT, 'lib/data/gem_floors.dart'), 'w').write('\n'.join(out))
    # preview data for the checker
    import pickle
    pickle.dump(dict(gfoot=gfoot, ghalls=ghalls, gsteps=gsteps, thall=thall, tland=tland, tzones=tzones,
                     tnew=[(i, p, t) for i, p, t in tnew], tsteps=tsteps), open('/home/claude/work/preview.pkl', 'wb'))


if __name__ == '__main__':
    main()
