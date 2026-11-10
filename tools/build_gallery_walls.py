"""Real walls of the Main Galleries plan, taken straight from the SVG.

assets/maps/light/main_galleries.svg draws the walls as open polylines with stroke
#9aa6a4.  Long ones (>= MIN_LEN px) are walls; the many short parallel strokes are
stair hatches (they are already MapStep treads).  Nothing is closed, bridged or
guessed: a gap in the drawing stays a gap (a door / an open side).  Each wall is cut
into short thin strips so the canvas can paint them back-to-front.
Output: Dart MapBlock('rwall', ...) lines for gem_blocks.dart -> walls_main_galleries.txt
"""
import sys, os, math
sys.path.insert(0, os.path.dirname(__file__))
from svgutil import load_paths, subpaths
from shapely.geometry import LineString
W, H = 1400.0, 1080.0
SVG = os.path.join(os.path.dirname(__file__), '..', 'assets/maps/light/main_galleries.svg')
MIN_LEN, THICK, PIECE, H_WALL = 60.0, 3.0, 70.0, 0.022
out, n_lines, n_pieces = [], 0, 0
for i, a, M in load_paths(SVG):
    if a.get('stroke') != '#9aa6a4':
        continue
    for sp in subpaths(a['d'], M, 6):
        ls = LineString(sp)
        if ls.length < MIN_LEN:
            continue
        n_lines += 1
        pts = list(ls.simplify(0.6).coords)
        for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
            L = math.hypot(x1 - x0, y1 - y0)
            if L < 0.5:
                continue
            k = max(1, math.ceil(L / PIECE))
            for j in range(k):
                ax, ay = x0 + (x1 - x0) * j / k, y0 + (y1 - y0) * j / k
                bx, by = x0 + (x1 - x0) * (j + 1) / k, y0 + (y1 - y0) * (j + 1) / k
                dx, dy = (bx - ax), (by - ay)
                d = math.hypot(dx, dy); ux, uy = dx / d, dy / d
                ext = 0.6  # overlap with the neighbour so no seam shows
                ax -= ux * ext; ay -= uy * ext; bx += ux * ext; by += uy * ext
                nx, ny = -uy * THICK / 2, ux * THICK / 2
                q = [(ax + nx, ay + ny), (bx + nx, by + ny), (bx - nx, by - ny), (ax - nx, ay - ny)]
                out.append("    MapBlock('rwall', %s, [%s])," % (H_WALL, ','.join('%.4f,%.4f' % (x / W, y / H) for x, y in q)))
                n_pieces += 1
open(os.path.join(os.path.dirname(__file__), 'walls_main_galleries.txt'), 'w').write('\n'.join(out) + '\n')
print('walls', n_lines, 'pieces', n_pieces, file=sys.stderr)
