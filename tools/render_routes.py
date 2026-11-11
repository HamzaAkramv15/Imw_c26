"""Visual regression check of routes against walls, from the generated Dart data
only (what the app loads): lib/data/gem_nav.dart (nodes, edges, doors,
kWallGaps), gem_regions.dart and gem_blocks.dart.

    python3 tools/render_routes.py [OUT_DIR]

Per map it writes OUT_DIR/routes_<map>.png: the plan, the walls as
museum_map_canvas.dart draws them (room outlines minus kWallGaps in red, wall
strips in grey, openings as green circles) and the shortest routes between
sample places of that map, standard (orange) and step-free (blue).  A route
segment that crosses a drawn wall is circled in magenta and counted.
"""
import heapq
import math
import os
import re
import subprocess
import sys

from PIL import Image, ImageDraw

import gemdata as g
import walls
from test_nav import in_poly, seg_cross, strip_cut_at

ROOT = os.path.join(os.path.dirname(__file__), '..')


def load_nav():
    src = open(os.path.join(ROOT, 'lib/data/gem_nav.dart')).read()
    nodes = {m[0]: (m[1], float(m[2]), float(m[3])) for m in
             re.findall(r"'([^']+)': NavNode\('([^']+)', Offset\(([-\d.]+), ([-\d.]+)\)\)", src)}
    edges = []
    for a, b, flags, via in re.findall(r"NavEdge\('([^']+)', '([^']+)', (stairs: true, )?_p\(const \[([^\]]*)\]\)\)", src):
        v = [float(x) for x in via.split(',') if x.strip()]
        edges.append((a, b, bool(flags), [(v[i], v[i + 1]) for i in range(0, len(v), 2)]))
    doors = []
    for mid, ax, ay, bx, by in re.findall(
            r"MapDoor\('[^']+', '([^']+)', Offset\(([-\d.]+), ([-\d.]+)\), Offset\(([-\d.]+), ([-\d.]+)\)", src):
        w, h = g.SIZES[mid]
        a, b = (float(ax) * w, float(ay) * h), (float(bx) * w, float(by) * h)
        doors.append((mid, ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, math.dist(a, b) / 2)))
    body = src[src.index('kWallGaps'):]
    body = body[:body.index('};')]
    gaps = {}
    for rid, v in re.findall(r"'([^']+)': \[([^\]]*)\]", body):
        f = [float(x) for x in v.split(',')]
        gaps[rid] = [(int(f[i]), f[i + 1], f[i + 2]) for i in range(0, len(f), 3)]
    return nodes, edges, doors, gaps


def drawn_walls(mid, gaps):
    """Room-outline wall segments as the canvas draws them: (solid block?, a, b)."""
    segs = []
    for r in walls.walled_regions(mid):
        pts = r[4]
        solid = r[3] in walls.SOLID_KINDS
        for i in range(len(pts)):
            a, b = pts[i], pts[(i + 1) % len(pts)]
            eg = [] if solid else [(t0, t1) for e, t0, t1 in gaps.get(r[0], []) if e == i]
            for t0, t1 in walls.solid_runs(eg):
                segs.append((solid, (a[0] + (b[0] - a[0]) * t0, a[1] + (b[1] - a[1]) * t0),
                             (a[0] + (b[0] - a[0]) * t1, a[1] + (b[1] - a[1]) * t1)))
    return segs


def shortest(adj, pos, a, b, step_free):
    """The route a → b as a polyline in map units, or None."""
    dist, prev, pq = {a: 0.0}, {}, [(0.0, a)]
    while pq:
        x, u = heapq.heappop(pq)
        if u == b:
            break
        if x > dist[u]:
            continue
        for v, c, st, line in adj.get(u, ()):
            if step_free and st:
                continue
            if x + c < dist.get(v, math.inf):
                dist[v], prev[v] = x + c, (u, line)
                heapq.heappush(pq, (x + c, v))
    if b not in dist:
        return None
    out, n = [], b
    while n != a:
        u, line = prev[n]  # the line runs u → n
        out = line[1:] + out
        n = u
    return [pos[a]] + out


def main(out):
    os.makedirs(out, exist_ok=True)
    nodes, edges, doors, gaps = load_nav()
    total = 0
    for mid in g.MAPS:
        w, h = g.SIZES[mid]
        S = 1600 / w
        png = os.path.join(out, '_plan_%s.png' % mid)
        subprocess.run(['rsvg-convert', '-w', str(int(w * S)),
                        os.path.join(ROOT, 'assets/maps/light/%s.svg' % mid), '-o', png], check=True)
        im = Image.open(png).convert('RGB')
        os.remove(png)
        im = Image.blend(im, Image.new('RGB', im.size, (255, 255, 255)), 0.45)
        d = ImageDraw.Draw(im)
        segs = drawn_walls(mid, gaps)
        circles = [c for m, c in doors if m == mid]
        strips = [b[2] for b in g.blocks()[mid] if b[0] in ('wall', 'rwall')]
        for q in strips:
            d.polygon([(x * S, y * S) for x, y in q], fill=(70, 70, 70))
        for cx, cy, r in circles:
            d.ellipse(((cx - r) * S, (cy - r) * S, (cx + r) * S, (cy + r) * S), outline=(0, 170, 0), width=2)
        for solid, a, b in segs:
            d.line([(a[0] * S, a[1] * S), (b[0] * S, b[1] * S)], fill=(120, 0, 0) if solid else (210, 30, 30), width=3)
        pos = {n: (x * w, y * h) for n, (m, x, y) in nodes.items() if m == mid}
        adj = {}
        for a, b, st, via in edges:
            if a not in pos:
                continue
            line = [pos[a]] + [(x * w, y * h) for x, y in via] + [pos[b]]
            length = sum(math.dist(p, q) for p, q in zip(line, line[1:]))
            adj.setdefault(a, []).append((b, length, st, line))
            adj.setdefault(b, []).append((a, length, st, line[::-1]))
        places = [p[0] for p in g.places()[mid] if p[0] in adj]
        pairs = [(places[i], places[j]) for i in range(len(places)) for j in range(i + 1, len(places))]
        pairs = pairs[::max(1, len(pairs) // 14)]
        crossings = 0
        for a, b in pairs:
            for sf, col, width in ((False, (255, 140, 0), 4), (True, (30, 90, 230), 2)):
                line = shortest(adj, pos, a, b, sf)
                if not line:
                    continue
                for p, q in zip(line, line[1:]):
                    hit = any(seg_cross(p, q, s0, s1) for solid, s0, s1 in segs)
                    n = max(2, int(math.dist(p, q)))
                    for k in range(n + 1):
                        if hit:
                            break
                        x, y = p[0] + (q[0] - p[0]) * k / n, p[1] + (q[1] - p[1]) * k / n
                        hit = any(in_poly(x, y, s) and not strip_cut_at(s, x, y, circles) for s in strips)
                    if hit:
                        crossings += 1
                        mx, my = (p[0] + q[0]) / 2 * S, (p[1] + q[1]) / 2 * S
                        d.ellipse((mx - 9, my - 9, mx + 9, my + 9), outline=(255, 0, 255), width=3)
                d.line([(x * S, y * S) for x, y in line], fill=col, width=width)
        im.save(os.path.join(out, 'routes_%s.png' % mid))
        print('%-15s %3d sample routes, %d wall crossings' % (mid, 2 * len(pairs), crossings))
        total += crossings
    return 1 if total else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else '/tmp/route_render'))
