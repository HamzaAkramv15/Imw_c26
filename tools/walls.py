"""Where the canvas raises walls around rooms, in one place for the routing grid,
the generated wall gaps (kWallGaps, drawn by museum_map_canvas.dart) and the tests.

  * every edge of a walled room (hall, zone, building, attraction) is a wall,
  * except where a zone meets other floor (another zone, or the circulation
    floor between them): the Tutankhamun plan colours its thematic areas inside
    one hall and draws a line only on the hall's outer edge,
  * and except within an opening (a circle around each door's centre).
"""
import math

import gemdata as g

WALLED_KINDS = {'building', 'attraction', 'hall', 'zone'}
SOLID_KINDS = {'building', 'attraction'}  # drawn as closed blocks
NO_WALLS = {'cx_events', 'cx_obelisk'}    # open-air areas drawn flat
SHARE_TOL = 6.0  # map units: traced zone outlines meet within this


def walled_regions(mid):
    return [r for r in g.regions() if r[1] == mid and r[3] in WALLED_KINDS and r[0] not in NO_WALLS]


def _dist_seg(p, a, b):
    dx, dy = b[0] - a[0], b[1] - a[1]
    l2 = dx * dx + dy * dy
    t = 0.0 if l2 == 0 else max(0.0, min(1.0, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / l2))
    return math.hypot(p[0] - a[0] - t * dx, p[1] - a[1] - t * dy)


def _merge(gaps):
    out = []
    for g0, g1 in sorted(gaps):
        if out and g0 <= out[-1][1] + 1e-6:
            out[-1] = (out[-1][0], max(out[-1][1], g1))
        else:
            out.append((g0, g1))
    return out


def shared_gaps(mid):
    """{region id: [gaps per edge]}: the stretches of a zone's edges that run along
    other floor (no wall on the plan there)."""
    regs = walled_regions(mid)
    out = {}
    for r in regs:
        pts = r[4]
        per_edge = []
        others = [] if r[3] != 'zone' else (
            [o[4] for o in regs if o[0] != r[0] and o[3] == 'zone'] +
            [p for k, p in g.floors().get(mid, []) if k in ('hall', 'landing')])
        for i in range(len(pts)):
            a, b = pts[i], pts[(i + 1) % len(pts)]
            n = max(2, int(math.dist(a, b)))
            gaps, start = [], None
            for k in range(n + 1):
                t = k / n
                p = (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
                shared = any(_dist_seg(p, o[j], o[(j + 1) % len(o)]) <= SHARE_TOL
                             for o in others for j in range(len(o)))
                if shared and start is None:
                    start = t
                elif not shared and start is not None:
                    gaps.append((start, t))
                    start = None
            if start is not None:
                gaps.append((start, 1.0))
            per_edge.append(gaps)
        out[r[0]] = per_edge
    return out


def circle_gaps(a, b, circles):
    """Stretches of a→b inside an opening circle (x, y, radius)."""
    dx, dy = b[0] - a[0], b[1] - a[1]
    l2 = dx * dx + dy * dy
    if l2 < 1e-9:
        return []
    gaps = []
    for cx, cy, r in circles:
        fx, fy = a[0] - cx, a[1] - cy
        bq, cq = 2 * (fx * dx + fy * dy), fx * fx + fy * fy - r * r
        disc = bq * bq - 4 * l2 * cq
        if disc <= 0:
            continue
        s = math.sqrt(disc)
        t0, t1 = max(0.0, (-bq - s) / (2 * l2)), min(1.0, (-bq + s) / (2 * l2))
        if t1 > t0:
            gaps.append((t0, t1))
    return gaps


def wall_gaps(mid, circles):
    """{region id: [merged gaps per edge]} for rooms drawn with open walls
    (solid blocks are drawn closed)."""
    shared = shared_gaps(mid)
    out = {}
    for r in walled_regions(mid):
        if r[3] in SOLID_KINDS:
            continue
        pts = r[4]
        out[r[0]] = [_merge(shared[r[0]][i] + circle_gaps(pts[i], pts[(i + 1) % len(pts)], circles))
                     for i in range(len(pts))]
    return out


def solid_runs(gaps):
    out, t = [], 0.0
    for g0, g1 in _merge(gaps):
        if g0 > t:
            out.append((t, g0))
        t = max(t, g1)
    if t < 1:
        out.append((t, 1.0))
    return out


def wall_segments(mid, circles=(), include_solid=True):
    """The wall lines as segments ((x0, y0), (x1, y1))."""
    shared = shared_gaps(mid)
    segs = []
    for r in walled_regions(mid):
        solid = r[3] in SOLID_KINDS
        if solid and not include_solid:
            continue
        pts = r[4]
        for i in range(len(pts)):
            a, b = pts[i], pts[(i + 1) % len(pts)]
            gaps = [] if solid else shared[r[0]][i] + circle_gaps(a, b, circles)
            for t0, t1 in solid_runs(gaps):
                segs.append(((a[0] + (b[0] - a[0]) * t0, a[1] + (b[1] - a[1]) * t0),
                             (a[0] + (b[0] - a[0]) * t1, a[1] + (b[1] - a[1]) * t1)))
    return segs
