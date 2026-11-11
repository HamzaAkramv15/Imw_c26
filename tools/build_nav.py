"""Builds the routing graph of every plan from its walkable floor.

    python3 tools/build_nav.py          # writes lib/data/gem_nav.dart
    python3 tools/build_nav.py --check  # only validates, exits 1 on a problem

How the graph is made (per map):
 1. navgrid.build() rasterises the plan: FLOOR / STAIRS / BLOCKED (+ ROAD on the site).
 2. Doors from nav_spec are cut through their walls.
 3. Seeds: every place on the walkable floor, every door, and waypoints spread
    along the middle of the walkable floor (its skeleton).
 4. A geodesic Voronoi diagram of the seeds is grown over the grid; two seeds whose
    cells touch get an edge, laid along the shortest grid path between them and
    pulled straight wherever the straight line stays on walkable cells.
    This is done twice: once over every walkable cell (edges that use treads are
    flagged `stairs`) and once with the treads removed (step-free edges).
 5. Checks: every edge stays on walkable cells, no waypoint is a dead end, and
    every place can be reached from its map's entrance (and, step-free, wherever
    the plan allows it).

Because the graph comes from the floor itself it cannot cut through walls,
and a disconnected node can only exist if the plan itself is disconnected,
which the check reports."""
import heapq
import math
import os
import sys

import numpy as np
from scipy import ndimage
from skimage.morphology import skeletonize

import gemdata as g
import nav_spec as spec
from navgrid import BLOCKED, FLOOR, STAIRS, build, wall_cells

ROAD = 3
CLEARANCE = 8.0     # map units kept between a path and a wall where there is room
WALL_PENALTY = 1.0
WAYPOINT_SPACING = {'gem_complex': 55.0, 'main_building': 45.0, 'main_galleries': 45.0, 'tutankhamun': 45.0}
ENTRANCES = {'gem_complex': 'cx_ticket', 'main_building': 'mb_entrance',
             'main_galleries': 'mg_entrance', 'tutankhamun': 'tg_entrance'}
NB8 = [(-1, 0, 1.0), (1, 0, 1.0), (0, -1, 1.0), (0, 1, 1.0),
       (-1, -1, math.sqrt(2)), (-1, 1, math.sqrt(2)), (1, -1, math.sqrt(2)), (1, 1, math.sqrt(2))]


# ── grid ──────────────────────────────────────────────────────────────────────
def grid_for(mid):
    grid, cell = build(mid)
    if mid == 'gem_complex':
        # access roads inside the site can be crossed, at a cost
        from navgrid import _svg_rgba, _near, _downsample
        a = _svg_rgba(mid)
        road = _downsample(_near(a[..., :3], '#b4bdbb', 10) & (a[..., 3] > 200), cell)
        thin = road & ~ndimage.binary_opening(road, iterations=4)  # narrow roads only
        from navgrid import region_walls
        rooms = region_walls(mid, grid.shape, cell)  # drawn walls stay walls
        grid[(grid == BLOCKED) & thin & ~rooms] = ROAD
        # the site plan separates its areas with hairline gaps of bare paper:
        # those are kerbs, not barriers
        walk = grid != BLOCKED
        gaps = ndimage.binary_closing(walk, iterations=3) & ~walk
        bld = [r[4] for r in g.regions() if r[0] in ('cx_main_building', 'cx_boats', 'cx_conservation')]
        from navgrid import _poly_mask
        gaps &= ~_poly_mask(grid.shape, cell, bld) & ~rooms
        near_road = ndimage.binary_dilation(grid == ROAD, iterations=3)
        grid[gaps & ~near_road] = FLOOR
        grid[gaps & near_road] = ROAD  # a kerb beside a road: crossable, not a walkway
    return grid, cell


def cut_openings(mid, grid, cell, openings):
    """Cut each opening through the walls within its half-width (walls only:
    cases and other obstacles stay)."""
    walls = wall_cells(mid, grid.shape, cell)
    h, w = grid.shape
    cut = {}
    for oid, m, x, y, r, kind, verified, source in openings:
        cut[oid] = set()
        r0, c0, rad = int(y / cell), int(x / cell), int(r / cell) + 1
        for rr in range(max(0, r0 - rad), min(h, r0 + rad + 1)):
            for cc in range(max(0, c0 - rad), min(w, c0 + rad + 1)):
                # the whole cell inside the gap the canvas leaves in the wall
                if math.hypot((rr + 0.5) * cell - y, (cc + 0.5) * cell - x) <= r - 0.75 * cell and walls[rr, cc] and grid[rr, cc] == BLOCKED:
                    grid[rr, cc] = FLOOR
                    cut[oid].add((rr, cc))
    return cut


def cost_of(cls, step_free):
    if cls == FLOOR:
        return 1.0
    if cls == STAIRS:
        return None if step_free else spec.STAIR_COST
    if cls == ROAD:
        return spec.ROAD_COST
    return None


def _seg_dist(p, a, b):
    dx, dy = b[0] - a[0], b[1] - a[1]
    l2 = dx * dx + dy * dy
    t = 0.0 if l2 == 0 else max(0.0, min(1.0, ((p[0] - a[0]) * dx + (p[1] - a[1]) * dy) / l2))
    return math.hypot(p[0] - a[0] - t * dx, p[1] - a[1] - t * dy)


def cut_aisle_doors(mid, grid, cell):
    """Open the walls listed in nav_spec.AISLE_DOORS where the plan's aisles meet them."""
    doors = []
    walls = [b for b in g.blocks()[mid] if b[0] == 'wall']
    for m, at, count, source in spec.AISLE_DOORS:
        if m != mid:
            continue
        pts = min((b[2] for b in walls), key=lambda q: min(_seg_dist(at, q[i], q[(i + 1) % len(q)]) for i in range(len(q))))
        # the wall's long axis
        (x0, y0), (x1, y1) = max(((p, q) for p in pts for q in pts), key=lambda pq: math.dist(*pq))
        length = math.dist((x0, y0), (x1, y1))
        ux, uy = (x1 - x0) / length, (y1 - y0) / length
        nx, ny = -uy, ux
        clear = []
        for k in range(int(length)):
            px, py = x0 + ux * k, y0 + uy * k
            ok = True
            for side in (-1, 1):
                for off in (6, 10, 14):
                    c, r = int((px + nx * off * side) / cell), int((py + ny * off * side) / cell)
                    if not (0 <= r < grid.shape[0] and 0 <= c < grid.shape[1]) or grid[r, c] != FLOOR:
                        ok = False
            clear.append(ok)
        runs, start = [], None
        for k, ok in enumerate(clear + [False]):
            if ok and start is None:
                start = k
            elif not ok and start is not None:
                runs.append((k - start, start))
                start = None
        for n, (run, start) in enumerate(sorted(runs, reverse=True)[:count]):
            width = min(run, 24)  # the aisle's clear width, up to ~6.7 m
            mid_k = start + run / 2
            cx, cy = x0 + ux * mid_k, y0 + uy * mid_k
            did = '%s_aisle%d' % (mid[:2], n + 1)
            # cut like every other opening: the walls inside its circle
            cut = cut_openings(mid, grid, cell, [(did, mid, cx, cy, width / 2, 'door', False, source)])[did]
            doors.append(dict(id=did, map=mid, x=cx, y=cy,
                              ax=ux, ay=uy, width=width, kind='door', verified=False, source=source, cells=cut))
    return doors


def wall_dir(grid, cell, x, y):
    """Direction of the boundary near (x, y): principal axis of nearby blocked cells."""
    r0, c0 = int(y / cell), int(x / cell)
    pts = []
    rad = int(14 / cell) + 1
    for r in range(r0 - rad, r0 + rad + 1):
        for c in range(c0 - rad, c0 + rad + 1):
            if 0 <= r < grid.shape[0] and 0 <= c < grid.shape[1] and grid[r, c] == BLOCKED:
                pts.append((c, r))
    if len(pts) < 3:
        return 1.0, 0.0
    a = np.array(pts, dtype=float)
    a -= a.mean(axis=0)
    _, _, vt = np.linalg.svd(a, full_matrices=False)
    return float(vt[0][0]), float(vt[0][1])


# ── search ────────────────────────────────────────────────────────────────────
def dijkstra(grid, sources, step_free, allowed=None, target=None, penalty=None):
    """Multi-source Dijkstra.  sources: {cell: label}.  Returns (dist, owner, prev).
    `penalty` (per cell, >= 1) makes cells close to walls more expensive."""
    h, w = grid.shape
    dist = np.full((h, w), np.inf)
    owner = np.full((h, w), -1, dtype=np.int32)
    prev = {}
    pq = []
    for (r, c), lab in sources.items():
        dist[r, c] = 0
        owner[r, c] = lab
        heapq.heappush(pq, (0.0, r, c))
    while pq:
        d, r, c = heapq.heappop(pq)
        if d > dist[r, c]:
            continue
        if target is not None and (r, c) == target:
            break
        for dr, dc, k in NB8:
            rr, cc = r + dr, c + dc
            if not (0 <= rr < h and 0 <= cc < w):
                continue
            cost = cost_of(grid[rr, cc], step_free)
            if cost is None:
                continue
            if dr and dc:  # no corner cutting through blocked cells
                if cost_of(grid[r + dr, c], step_free) is None or cost_of(grid[r, c + dc], step_free) is None:
                    continue
            if allowed is not None and not allowed(rr, cc):
                continue
            nd = d + k * cost * (penalty[rr, cc] if penalty is not None else 1.0)
            if nd < dist[rr, cc]:
                dist[rr, cc] = nd
                owner[rr, cc] = owner[r, c]
                prev[(rr, cc)] = (r, c)
                heapq.heappush(pq, (nd, rr, cc))
    return dist, owner, prev


def path_between(grid, a, b, step_free, allowed=None, penalty=None):
    _, _, prev = dijkstra(grid, {a: 0}, step_free, allowed, target=b, penalty=penalty)
    if b != a and b not in prev:
        return None
    out = [b]
    while out[-1] != a:
        out.append(prev[out[-1]])
    return out[::-1]


def line_cells(a, b):
    (r0, c0), (r1, c1) = a, b
    n = int(max(abs(r1 - r0), abs(c1 - c0)) * 2) + 1
    seen = []
    for i in range(n + 1):
        t = i / n
        cell = (int(round(r0 + (r1 - r0) * t)), int(round(c0 + (c1 - c0) * t)))
        if not seen or seen[-1] != cell:
            seen.append(cell)
    return seen


def _clear_beside(grid, a, b):
    """The straight line keeps one cell of floor on both sides (no grazing corners)."""
    (r0, c0), (r1, c1) = a, b
    length = math.hypot(r1 - r0, c1 - c0) or 1.0
    nr, nc = -(c1 - c0) / length, (r1 - r0) / length
    for side in (-1, 1):
        oa = (int(round(r0 + nr * side)), int(round(c0 + nc * side)))
        ob = (int(round(r1 + nr * side)), int(round(c1 + nc * side)))
        for r, c in line_cells(oa, ob):
            if not (0 <= r < grid.shape[0] and 0 <= c < grid.shape[1]) or grid[r, c] == BLOCKED:
                return False
    return True


def pull(grid, cells, classes, clear=None):
    """String-pull a cell path: keep a corner only where the straight line would
    leave the walkable cells (of the given classes), or come closer to a wall
    than the path itself did there."""
    def visible(i, j):
        floor = min(clear[r, c] for r, c in cells[i:j + 1]) - 0.5 if clear is not None else 0
        for r, c in line_cells(cells[i], cells[j]):
            if grid[r, c] not in classes:
                return False
            if clear is not None and clear[r, c] < floor:
                return False
        return True
    out = [cells[0]]
    i = 0
    while i < len(cells) - 1:
        j = len(cells) - 1
        while j > i + 1 and not visible(i, j):
            j -= 1
        out.append(cells[j])
        i = j
    return out


# ── seeds ─────────────────────────────────────────────────────────────────────
def snap(grid, x, y, cell, classes=(FLOOR,)):
    r, c = int(y / cell), int(x / cell)
    r = min(max(r, 0), grid.shape[0] - 1)
    c = min(max(c, 0), grid.shape[1] - 1)
    if grid[r, c] in classes:
        return (r, c), 0.0
    ys, xs = np.nonzero(np.isin(grid, classes))
    d = (ys - r) ** 2 + (xs - c) ** 2
    i = int(d.argmin())
    return (int(ys[i]), int(xs[i])), math.sqrt(d[i]) * cell


def waypoints(grid, cell, spacing, taken):
    walk = grid == FLOOR
    sk = skeletonize(walk)
    # branch points first (corridor crossings), then evenly along the skeleton
    nb = ndimage.convolve(sk.astype(int), np.ones((3, 3)), mode='constant') - 1
    branch = sk & (nb >= 3)
    cand = list(zip(*np.nonzero(branch))) + list(zip(*np.nonzero(sk & ~branch)))
    chosen = []
    min_d = spacing / cell
    occupied = [p for p in taken]
    for r, c in cand:
        if all((r - a) ** 2 + (c - b) ** 2 >= min_d ** 2 for a, b in occupied):
            chosen.append((int(r), int(c)))
            occupied.append((r, c))
    return chosen


def add_detour_edges(grid, cell, nodes, edges, penalty, crosses_door, radius):
    adj = {}
    for e in edges.values():
        adj.setdefault(e['a'], []).append((e['b'], e['length'], e['stairs']))
        adj.setdefault(e['b'], []).append((e['a'], e['length'], e['stairs']))
    rad_c = radius / cell
    h, w = grid.shape
    by_cell = {}
    for n, rc in nodes.items():
        by_cell.setdefault(rc, []).append(n)
    added = []
    for na, ra in list(nodes.items()):
        if grid[ra] != FLOOR:
            continue
        # graph distances from na (level edges only), bounded
        gd, pq = {na: 0.0}, [(0.0, na)]
        while pq:
            d, u = heapq.heappop(pq)
            if d > gd[u] or d > radius * 2:
                continue
            for v, c, st in adj.get(u, ()):
                if not st and d + c < gd.get(v, math.inf):
                    gd[v] = d + c
                    heapq.heappush(pq, (d + c, v))
        near = [nb for nb, rb in nodes.items() if nb > na and 0 < math.dist(ra, rb) <= rad_c and grid[rb] == FLOOR]
        if not near:
            continue
        box = (ra[0] - rad_c - 2, ra[0] + rad_c + 2, ra[1] - rad_c - 2, ra[1] + rad_c + 2)
        dist, _, prev = dijkstra(grid, {ra: 0}, True, penalty=penalty,
                                 allowed=lambda r, c: box[0] <= r <= box[1] and box[2] <= c <= box[3] and grid[r, c] == FLOOR)
        for nb in near:
            rb = nodes[nb]
            if not math.isfinite(dist[rb]):
                continue
            cells, n = [rb], rb
            while n != ra:
                n = prev[n]
                cells.append(n)
            cells.reverse()
            walk = sum(math.dist(p, q) for p, q in zip(cells, cells[1:])) * cell
            if gd.get(nb, math.inf) <= 1.25 * walk + 2 * cell or crosses_door(na, nb, cells):
                continue
            # the walk must not pass through another node's cell (it would go via it)
            if any(c in by_cell and c not in (ra, rb) for c in cells):
                continue
            pulled = pull(grid, cells, {FLOOR}, None)
            length = sum(math.dist(pulled[k], pulled[k + 1]) for k in range(len(pulled) - 1)) * cell
            key = (na, nb, False) if na < nb else (nb, na, False)
            if key not in edges:
                added.append(key)
                edges[key] = dict(a=key[0], b=key[1], stairs=False,
                                  pts=[(c * cell + cell / 2, r * cell + cell / 2) for r, c in pulled[1:-1]],
                                  length=length)
                adj.setdefault(na, []).append((nb, length, False))
                adj.setdefault(nb, []).append((na, length, False))
    return added


# ── graph per map ─────────────────────────────────────────────────────────────
def build_map(mid, log):
    grid, cell = grid_for(mid)
    w, h = g.SIZES[mid]
    openings = [o for o in spec.OPENINGS if o[1] == mid]
    opening_cells = cut_openings(mid, grid, cell, openings)
    doors = cut_aisle_doors(mid, grid, cell)
    # Only the floor connected to the map's entrance is reachable: pockets the
    # plan encloses on every side (wing rooms, kiosks) are not walked into.
    lab, _ = ndimage.label(grid != BLOCKED)  # 4-connected, like the search (no corner cutting)
    ex, ey = next(p[2] for p in g.places()[mid] if p[0] == ENTRANCES[mid])
    # the nearest floor that is a real space, not a sliver of a cut wall
    sizes = np.bincount(lab.ravel())
    big = (lab > 0) & (sizes[lab] >= 400)
    ys, xs = np.nonzero(big)
    i = int(((ys - ey / cell) ** 2 + (xs - ex / cell) ** 2).argmin())
    er, ec = int(ys[i]), int(xs[i])
    grid[(lab != lab[er, ec]) & (grid != BLOCKED)] = BLOCKED
    # Distance to the nearest wall or case, in cells. Paths are pushed towards
    # the middle of corridors and doorways: a cell closer than CLEARANCE map units
    # to an obstacle costs up to (1 + WALL_PENALTY) times more to cross.
    clear = ndimage.distance_transform_edt(grid != BLOCKED)
    reach_c = CLEARANCE / cell
    penalty = 1.0 + WALL_PENALTY * np.clip((reach_c - clear) / reach_c, 0, 1)
    nodes = {}  # id -> (r, c)
    snaps = {}
    for pid, name, (x, y), cat in g.places()[mid]:
        if pid in spec.PLACE_FLOOR and mid == 'main_building':
            continue  # upper level: portals only
        rc, dd = snap(grid, x, y, cell)
        nodes[pid] = rc
        snaps[pid] = dd
    for did, m, x, y, r, kind, verified, source in openings:
        rc, dd = snap(grid, x, y, cell)
        nodes[did] = rc
        ax, ay = wall_dir(grid, cell, x, y)
        doors.append(dict(id=did, map=mid, x=x, y=y, ax=ax, ay=ay, width=2 * r, kind=kind,
                          verified=verified, source=source, cells=opening_cells[did]))
    for d in doors:
        if d['id'] not in nodes:
            nodes[d['id']] = snap(grid, d['x'], d['y'], cell)[0]
    # waypoints on the main walkable component(s) that hold a node
    wps = waypoints(grid, cell, WAYPOINT_SPACING[mid], list(nodes.values()))
    for i, rc in enumerate(wps):
        nodes['w_%s_%d' % (mid[:2] if mid != 'main_galleries' else 'mg', i)] = rc
    ids = list(nodes)
    edges = {}
    # cells of the openings cut through walls: only the door's own node may lead
    # through them, so every route that crosses the wall passes the door
    door_cells = {rc: d['id'] for d in doors for rc in d.get('cells', ())}

    def crosses_door(a, b, cells):
        return any(door_cells.get(rc) not in (None, a, b) for rc in cells)

    for step_free in (False, True):
        classes = {FLOOR, ROAD} if step_free else {FLOOR, ROAD, STAIRS}
        src = {}
        for i, nid in enumerate(ids):
            if nodes[nid] in src:  # two nodes on one cell: join them directly
                other = ids[src[nodes[nid]]]
                key = (nid, other) if nid < other else (other, nid)
                edges.setdefault(key + (False,), dict(a=key[0], b=key[1], stairs=False, pts=[], length=0.0))
                continue
            if cost_of(grid[nodes[nid]], step_free) is None:
                continue
            src[nodes[nid]] = i
        dist, owner, _ = dijkstra(grid, src, step_free, penalty=penalty)
        pairs = set()
        a, b = owner[:, :-1], owner[:, 1:]
        for x, y in zip(a[(a != b) & (a >= 0) & (b >= 0)], b[(a != b) & (a >= 0) & (b >= 0)]):
            pairs.add((min(x, y), max(x, y)))
        a, b = owner[:-1, :], owner[1:, :]
        for x, y in zip(a[(a != b) & (a >= 0) & (b >= 0)], b[(a != b) & (a >= 0) & (b >= 0)]):
            pairs.add((min(x, y), max(x, y)))
        for i, j in pairs:
            na, nb_ = ids[i], ids[j]
            key = (na, nb_) if na < nb_ else (nb_, na)
            ra, rb = nodes[key[0]], nodes[key[1]]
            lab = {i, j}
            cells = path_between(grid, ra, rb, step_free, allowed=lambda r, c: owner[r, c] in lab, penalty=penalty)
            if cells is None:
                cells = path_between(grid, ra, rb, step_free, penalty=penalty)
            if cells is None or crosses_door(na, nb_, cells):
                continue
            uses_stairs = any(grid[r, c] == STAIRS for r, c in cells)
            k2 = key + (uses_stairs,)
            if k2 in edges:
                continue
            used = {int(grid[r, c]) for r, c in cells}
            pulled = pull(grid, cells, used, clear)
            length = sum(math.dist(pulled[k], pulled[k + 1]) for k in range(len(pulled) - 1)) * cell
            edges[k2] = dict(a=key[0], b=key[1], stairs=uses_stairs,
                             pts=[(c * cell + cell / 2, r * cell + cell / 2) for r, c in pulled[1:-1]],
                             length=length)
    # straight shortcuts: two nodes that see each other across level floor are
    # joined directly, so routes do not zig-zag through intermediate waypoints
    reach = WAYPOINT_SPACING[mid] * 2.6 / cell
    ids = list(nodes)
    for i, na in enumerate(ids):
        for nb_ in ids[i + 1:]:
            ra, rb = nodes[na], nodes[nb_]
            if math.dist(ra, rb) > reach or ra == rb:
                continue
            key = (na, nb_, False) if na < nb_ else (nb_, na, False)
            if key in edges:
                continue
            line = line_cells(ra, rb)
            # keep clear of walls, but a lane between two cases is still a lane
            need = max(1.5, 0.6 * min(reach_c, clear[ra], clear[rb]))
            if (all(grid[r, c] == FLOOR and clear[r, c] >= need for r, c in line)
                    and _clear_beside(grid, ra, rb) and not crosses_door(na, nb_, line)):
                edges[key] = dict(a=key[0], b=key[1], stairs=False, pts=[], length=math.dist(ra, rb) * cell)
    # detours: where the graph between two nearby nodes is much longer than the
    # walk between them on the floor (a lane between two cases that no waypoint
    # sits in), the walk itself becomes an edge
    add_detour_edges(grid, cell, nodes, edges, penalty, crosses_door, WAYPOINT_SPACING[mid] * 2.6)
    # drop waypoints that ended up dead ends (degree 1) or isolated: they add nothing
    while True:
        deg = {n: 0 for n in nodes}
        for e in edges.values():
            deg[e['a']] += 1
            deg[e['b']] += 1
        dead = [n for n, d in deg.items() if n.startswith('w_') and d <= 1]
        if not dead:
            break
        for n in dead:
            del nodes[n]
        edges = {k: e for k, e in edges.items() if e['a'] in nodes and e['b'] in nodes}
    pos = {n: (c * cell + cell / 2, r * cell + cell / 2) for n, (r, c) in nodes.items()}
    far = {p: round(d) for p, d in snaps.items() if d > 40}
    if far:
        log.append('  %s: places more than 40 units from walkable floor: %s' % (mid, far))
    return dict(grid=grid, cell=cell, nodes=pos, edges=list(edges.values()), doors=doors)


# ── checks ────────────────────────────────────────────────────────────────────
def check(result):
    problems = []
    adj = {}
    for mid, r in result.items():
        grid, cell = r['grid'], r['cell']
        for e in r['edges']:
            pts = [r['nodes'][e['a']]] + e['pts'] + [r['nodes'][e['b']]]
            ok = {FLOOR, ROAD} | ({STAIRS} if e['stairs'] else set())
            for p, q in zip(pts, pts[1:]):
                for rr, cc in line_cells((int(p[1] / cell), int(p[0] / cell)), (int(q[1] / cell), int(q[0] / cell))):
                    if grid[rr, cc] not in ok:
                        problems.append('%s: edge %s-%s leaves the walkable floor at (%d, %d)' % (mid, e['a'], e['b'], cc * cell, rr * cell))
                        break
            for sf in (False, True):
                if sf and e['stairs']:
                    continue
                adj.setdefault((e['a'], sf), set()).add(e['b'])
                adj.setdefault((e['b'], sf), set()).add(e['a'])
    for a, b, kind, metres, sfv, src in spec.PORTALS:
        for sf in (False, True):
            if sf and (kind == 'stairs' or (kind == 'travelator' and not sfv)):
                continue
            adj.setdefault((a, sf), set()).add(b)
            adj.setdefault((b, sf), set()).add(a)
    every = {n for r in result.values() for n in r['nodes']}
    places = {pid: mid for mid, pl in g.places().items() for pid, *_ in pl}
    for p in spec.PORTALS:
        for n in p[:2]:
            if n not in every and n not in places:
                problems.append('portal end %s is neither a node nor a place' % n)
    reach = {}
    for sf in (False, True):
        seen = {'cx_ticket'}
        todo = ['cx_ticket']
        while todo:
            n = todo.pop()
            for m in adj.get((n, sf), ()):
                if m not in seen:
                    seen.add(m)
                    todo.append(m)
        reach[sf] = seen
    for pid in places:
        target = spec.REDIRECTS.get(pid, pid)
        if target not in reach[False]:
            problems.append('unreachable from the ticket gate: %s' % pid)
    no_sf = sorted(p for p in places if spec.REDIRECTS.get(p, p) in reach[False] and spec.REDIRECTS.get(p, p) not in reach[True])
    return problems, no_sf


# ── output ────────────────────────────────────────────────────────────────────
def fmt(v):
    return ('%.4f' % v).rstrip('0').rstrip('.') if v else '0'


def write_dart(result, path):
    L = ['// GENERATED by tools/build_nav.py from the plans and tools/nav_spec.py. Do not edit by hand.',
         '// Re-run `python3 tools/build_nav.py` after changing a plan, a block, a place or the spec.',
         "import 'dart:ui';", '', "import '../models/map_models.dart';", '',
         'List<Offset> _p(List<double> v) => [for (var i = 0; i < v.length; i += 2) Offset(v[i], v[i + 1])];', '',
         '/// Routing nodes: every place on walkable floor, every door and the waypoints.',
         '/// Normalised positions (a place\'s node sits on the floor in front of its pin).',
         'const Map<String, NavNode> kNavNodes = {']
    for mid, r in result.items():
        w, h = g.SIZES[mid]
        for n, (x, y) in sorted(r['nodes'].items()):
            L.append("  '%s': NavNode('%s', Offset(%s, %s))," % (n, mid, fmt(x / w), fmt(y / h)))
    L += ['};', '', '/// Walkable connections. `stairs` edges climb treads drawn on the plan.',
          'final List<NavEdge> kNavEdges = [']
    for mid, r in result.items():
        w, h = g.SIZES[mid]
        for e in sorted(r['edges'], key=lambda e: (e['a'], e['b'], e['stairs'])):
            pts = ','.join('%s,%s' % (fmt(x / w), fmt(y / h)) for x, y in e['pts'])
            L.append("  NavEdge('%s', '%s', %s_p(const [%s]))," % (e['a'], e['b'], 'stairs: true, ' if e['stairs'] else '', pts))
    L += ['];', '', '/// Where the walls the canvas raises around rooms stay open, per region and',
          '/// edge: flat lists of (edge index, t0, t1) along the edge. Openings (doors,',
          '/// passages) and, between Tutankhamun zones, the stretches where the plan draws',
          '/// no line. The routing grid leaves the same stretches open.',
          'const Map<String, List<double>> kWallGaps = {']
    import walls
    for mid, r in result.items():
        circles = [(d['x'], d['y'], d['width'] / 2) for d in r['doors']]
        for rid, per_edge in walls.wall_gaps(mid, circles).items():
            flat = ['%d, %s, %s' % (i, fmt(t0), fmt(t1)) for i, gaps in enumerate(per_edge) for t0, t1 in gaps]
            if flat:
                L.append("  '%s': [%s]," % (rid, ', '.join(flat)))
    L += ['};', '', '/// Doorways the plans draw, and openings cut where the plan draws none',
          '/// (`verified: false`: position taken from the plan\'s aisles, not from a source).',
          'const List<MapDoor> kDoors = [']
    for mid, r in result.items():
        w, h = g.SIZES[mid]
        for d in r['doors']:
            half = d['width'] / 2
            L.append("  MapDoor('%s', '%s', Offset(%s, %s), Offset(%s, %s)%s%s)," % (
                d['id'], mid, fmt((d['x'] - d['ax'] * half) / w), fmt((d['y'] - d['ay'] * half) / h),
                fmt((d['x'] + d['ax'] * half) / w), fmt((d['y'] + d['ay'] * half) / h),
                '' if d.get('kind', 'door') == 'door' else ', kind: DoorKind.%s' % d['kind'],
                '' if d['verified'] else ', verified: false'))
    kind = {'door': 'PortalKind.door', 'stairs': 'PortalKind.stairs', 'lift': 'PortalKind.lift', 'travelator': 'PortalKind.travelator'}
    L += ['];', '', '/// Links between maps and levels (sources in tools/nav_spec.py).', 'const List<Portal> kPortals = [']
    for a, b, k, m, sfv, src in spec.PORTALS:
        extra = ', stepFreeVerified: false' if k == 'travelator' and not sfv else ''
        L.append("  Portal('%s', '%s', %s, meters: %d%s), // %s" % (a, b, kind[k], m, extra, src))
    L += ['];', '', '/// Places drawn on a plan whose real floor differs from the plan\'s level.',
          'const Map<String, int> kPlaceFloor = {']
    L += ["  '%s': %d," % kv for kv in spec.PLACE_FLOOR.items()]
    L += ['};', '', '/// "Route to X" really means "route to Y" (the pin points at another plan).',
          'const Map<String, String> kRouteRedirects = {']
    L += ["  '%s': '%s'," % kv for kv in spec.REDIRECTS.items()]
    L += ['};', '']
    with open(path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(L))


def main():
    log = []
    result = {mid: build_map(mid, log) for mid in g.MAPS}
    problems, no_sf = check(result)
    for mid, r in result.items():
        n_wp = sum(1 for n in r['nodes'] if n.startswith('w_'))
        print('%-15s nodes %4d (waypoints %3d)  edges %4d (stairs %3d)  doors %d' % (
            mid, len(r['nodes']), n_wp, len(r['edges']), sum(e['stairs'] for e in r['edges']), len(r['doors'])))
    for line in log:
        print(line)
    if no_sf:
        print('no step-free route (the plan only shows treads to reach them):', ', '.join(no_sf))
    for p in problems:
        print('PROBLEM', p)
    if '--check' not in sys.argv:
        write_dart(result, os.path.join(g.ROOT, 'lib', 'data', 'gem_nav.dart'))
    return result, problems


if __name__ == '__main__':
    _, probs = main()
    sys.exit(1 if probs else 0)
