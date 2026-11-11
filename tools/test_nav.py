"""Verifies the routing graph that build_nav.py generates.

    python3 tools/test_nav.py

  * every edge stays on walkable floor (no route through a wall or a case)
  * no dead-end waypoints, no node without an edge
  * every place is reachable from the ticket gate, standard and step-free
  * step-free routes never use treads, stairs portals or the moving walkway
  * routes are short: on every map, graph distance between random floor points is
    compared with the shortest walk over the floor grid (stretch factor; routes
    keep about 2 m from walls where there is room, so they are slightly longer)
  * a set of real visitor journeys gives the expected portals
Exit code 1 on any failure."""
import heapq
import math
import random
import numpy as np
import walls
import sys

import build_nav as bn
import gemdata as g
import nav_spec as spec

FAIL = []


def expect(cond, msg):
    print(('  ok   ' if cond else '  FAIL ') + msg)
    if not cond:
        FAIL.append(msg)


def graph(result, step_free):
    adj = {}
    for mid, r in result.items():
        for e in r['edges']:
            if step_free and e['stairs']:
                continue
            c = e['length'] * (bn.spec.STAIR_COST if e['stairs'] else 1)
            adj.setdefault(e['a'], []).append((e['b'], c, 'walk:' + mid))
            adj.setdefault(e['b'], []).append((e['a'], c, 'walk:' + mid))
    for a, b, kind, metres, sfv, _ in spec.PORTALS:
        if step_free and (kind == 'stairs' or (kind == 'travelator' and not sfv)):
            continue
        c = metres * 3  # metres → plan units, roughly; only the order matters here
        adj.setdefault(a, []).append((b, c, kind))
        adj.setdefault(b, []).append((a, c, kind))
    return adj


def route(adj, a, b):
    b = spec.REDIRECTS.get(b, b)
    dist, prev, pq = {a: 0.0}, {}, [(0.0, a)]
    while pq:
        d, u = heapq.heappop(pq)
        if u == b:
            break
        if d > dist[u]:
            continue
        for v, c, kind in adj.get(u, ()):
            if d + c < dist.get(v, math.inf):
                dist[v] = d + c
                prev[v] = (u, kind)
                heapq.heappush(pq, (d + c, v))
    if b not in dist:
        return None
    kinds, n = [], b
    while n != a:
        n, k = prev[n]
        kinds.append(k)
    return dist[b], kinds[::-1]


def strip_cut_at(quad, x, y, circles):
    """Whether the canvas leaves (x, y) open in this wall strip: _cutDoorways in
    museum_map_canvas.dart, which opens a quad along its long axis where an
    opening's circle crosses that axis."""
    if len(quad) != 4:
        return False
    e0, e1 = math.dist(quad[0], quad[1]), math.dist(quad[1], quad[2])
    s0 = 0 if e0 < e1 else 1
    a = ((quad[s0][0] + quad[s0 + 1][0]) / 2, (quad[s0][1] + quad[s0 + 1][1]) / 2)
    b = ((quad[(s0 + 2) % 4][0] + quad[(s0 + 3) % 4][0]) / 2, (quad[(s0 + 2) % 4][1] + quad[(s0 + 3) % 4][1]) / 2)
    length = math.dist(a, b)
    if length < 1e-6:
        return False
    dx, dy = (b[0] - a[0]) / length, (b[1] - a[1]) / length
    half = min(e0, e1) / 2
    tp = (x - a[0]) * dx + (y - a[1]) * dy
    for cx, cy, w in circles:
        tc = (cx - a[0]) * dx + (cy - a[1]) * dy
        off = abs(-(cx - a[0]) * dy + (cy - a[1]) * dx)
        if off >= w:
            continue
        chord = math.sqrt(w * w - off * off)
        if tc - chord <= tp <= tc + chord:
            return True
    return False


def seg_cross(p, q, a, b):
    """Proper crossing of segments pq and ab."""
    def o(u, v, w):
        return (v[0] - u[0]) * (w[1] - u[1]) - (v[1] - u[1]) * (w[0] - u[0])
    d1, d2, d3, d4 = o(a, b, p), o(a, b, q), o(p, q, a), o(p, q, b)
    return d1 * d2 < 0 and d3 * d4 < 0


def in_poly(x, y, poly):
    inside, j = False, len(poly) - 1
    for i in range(len(poly)):
        (xi, yi), (xj, yj) = poly[i], poly[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            inside = not inside
        j = i
    return inside


def main():
    log = []
    result = {mid: bn.build_map(mid, log) for mid in g.MAPS}
    print('structure')
    problems, no_sf = bn.check(result)
    expect(not problems, 'no edge leaves the floor, every place reachable (%d problems)' % len(problems))
    for p in problems[:10]:
        print('       ', p)
    # The walls exactly as museum_map_canvas.dart draws them: every edge of a
    # walled region outside the openings (_edgeGaps), and the plan's wall strips
    # outside the openings.  No route segment may cross one.
    crossings = []
    for mid, r in result.items():
        circles = [(d['x'], d['y'], d['width'] / 2) for d in r['doors']]
        segs = walls.wall_segments(mid, circles)
        strips = [blk[2] for blk in g.blocks()[mid] if blk[0] in ('wall', 'rwall')]
        for e in r['edges']:
            pts = [r['nodes'][e['a']]] + e['pts'] + [r['nodes'][e['b']]]
            hit = None
            for p, q in zip(pts, pts[1:]):
                if any(seg_cross(p, q, s0, s1) for s0, s1 in segs):
                    hit = 'room wall'
                    break
                n = max(2, int(math.dist(p, q)))
                for k in range(n + 1):
                    x, y = p[0] + (q[0] - p[0]) * k / n, p[1] + (q[1] - p[1]) * k / n
                    if any(in_poly(x, y, s) and not strip_cut_at(s, x, y, circles) for s in strips):
                        hit = 'wall strip at (%d, %d)' % (x, y)
                        break
                if hit:
                    break
            if hit:
                crossings.append('%s: %s-%s crosses a %s' % (mid, e['a'], e['b'], hit))
    expect(not crossings, 'no route segment crosses a drawn wall (%d)' % len(crossings))
    for c in crossings[:10]:
        print('       ', c)
    for mid, r in result.items():
        deg = {n: 0 for n in r['nodes']}
        for e in r['edges']:
            deg[e['a']] += 1
            deg[e['b']] += 1
        portal_ends = {x for p in spec.PORTALS for x in p[:2]}
        lonely = [n for n, d in deg.items() if d == 0 and n not in portal_ends]
        dead = [n for n, d in deg.items() if d == 1 and n.startswith('w_')]
        expect(not lonely, '%s: no node without an edge %s' % (mid, lonely[:5]))
        expect(not dead, '%s: no dead-end waypoint %s' % (mid, dead[:5]))
    expect(not no_sf, 'every place has a step-free route (%s)' % ', '.join(no_sf))

    print('journeys')
    std, sf = graph(result, False), graph(result, True)
    cases = [
        ('cx_ticket', 'mb_1', False, {'door'}, {'stairs', 'lift'}),
        ('cx_ticket', 'mg_07', False, {'door'}, {'lift'}),
        ('cx_ticket', 'mg_07', True, {'door', 'lift'}, {'stairs', 'travelator'}),
        ('cx_ticket', 'tg_mask', True, {'lift'}, {'stairs', 'travelator'}),
        ('mb_entrance', 'mb_9', True, {'lift'}, {'stairs'}),
        ('mb_entrance', 'mb_r1', False, set(), {'stairs', 'lift', 'door'}),
        ('tg_mask', 'cx_parking_main', False, {'door'}, set()),
        ('mg_12', 'mg_01', True, set(), {'stairs', 'lift', 'travelator'}),
    ]
    for a, b, step_free, must, never in cases:
        r = route(sf if step_free else std, a, b)
        if r is None:
            expect(False, '%s → %s%s has a route' % (a, b, ' (step-free)' if step_free else ''))
            continue
        kinds = set(k for k in r[1] if not k.startswith('walk'))
        expect(must <= kinds and not (never & kinds),
               '%s → %s%s uses %s' % (a, b, ' (step-free)' if step_free else '', sorted(kinds) or 'only walking'))

    print('route quality (graph vs true shortest walk on the floor grid)')
    rnd = random.Random(7)
    for mid, r in result.items():
        grid, cell = r['grid'], r['cell']
        nodes = r['nodes']
        floor = [(rr, cc) for rr in range(grid.shape[0]) for cc in range(grid.shape[1]) if grid[rr, cc] == bn.FLOOR]
        adj = {}
        for e in r['edges']:
            if e['stairs']:
                continue
            adj.setdefault(e['a'], []).append((e['b'], e['length']))
            adj.setdefault(e['b'], []).append((e['a'], e['length']))
        ids = [n for n in nodes if n in adj]
        worst, ratios = 0, []
        clear = bn.ndimage.distance_transform_edt(grid != bn.BLOCKED)
        reach_c = bn.CLEARANCE / cell
        penalty = 1.0 + bn.WALL_PENALTY * np.clip((reach_c - clear) / reach_c, 0, 1)
        for _ in range(120):
            a, b = rnd.sample(ids, 2)
            ra = (int(nodes[a][1] / cell), int(nodes[a][0] / cell))
            rb = (int(nodes[b][1] / cell), int(nodes[b][0] / cell))
            # the reference: the best walk under the same keep-off-the-walls rule
            # the generator applies, measured by its real length
            dist, _, prev = bn.dijkstra(grid, {ra: 0}, True, target=rb, penalty=penalty)
            if not math.isfinite(dist[rb]):
                continue
            true, n = 0.0, rb
            while n != ra:
                p = prev[n]
                true += math.dist(p, n) * cell
                n = p
            if not math.isfinite(true) or true < 80:  # short hops: ratios are noise
                continue
            d, pq, best = {a: 0.0}, [(0.0, a)], math.inf
            while pq:
                x, u = heapq.heappop(pq)
                if u == b:
                    best = x
                    break
                if x > d[u]:
                    continue
                for v, c in adj.get(u, ()):
                    if x + c < d.get(v, math.inf):
                        d[v] = x + c
                        heapq.heappush(pq, (x + c, v))
            ratios.append(best / true)
            if best / true > 1.45: print("       long:", a, b, round(best), round(true))
        if ratios:
            ratios.sort()
            mean = sum(ratios) / len(ratios)
            p95, worst = ratios[int(0.95 * (len(ratios) - 1))], ratios[-1]
            # routes keep clear of walls on purpose, so they are a little longer
            # than the wall-hugging shortest line
            expect(mean < 1.10 and p95 < 1.30 and worst < 1.50,
                   '%s: stretch mean %.3f, 95th percentile %.3f, worst %.3f over %d step-free pairs'
                   % (mid, mean, p95, worst, len(ratios)))
    print('\n%d failure(s)' % len(FAIL))
    return 1 if FAIL else 0


if __name__ == '__main__':
    sys.exit(main())
