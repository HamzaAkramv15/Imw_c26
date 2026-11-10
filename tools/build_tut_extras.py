"""Tutankhamun hall: missing floor + missing cases, straight from the SVG.
 * 'tg_connecting_hall' floor = the SVG's own grey fill (path 5, #b4bdbb)
 * every closed light outline (stroke #f7f1e7, or small #c9c8bb fill) not already in
   kBlocks['tutankhamun'] becomes a 'fixture' block.
Dashed display-zone outlines are NOT turned into geometry (several are open lines)."""
import sys, os, re
sys.path.insert(0, os.path.dirname(__file__))
from svgutil import load_paths, subpaths
from shapely.geometry import Polygon
W, H = 1389.0, 962.0
P = load_paths(os.path.join(os.path.dirname(__file__), '..', 'assets/maps/light/tutankhamun.svg'))
src = open(os.path.join(os.path.dirname(__file__), '..', 'lib/data/gem_blocks.dart')).read()
b = src.find("  'tutankhamun': [", src.find('const Map<String, List<MapBlock>> kBlocks')); e = src.find('  ],', b)
have = []
for m in re.finditer(r"MapBlock\('\w+', [\d.]+, \[([^\]]*)\]", src[b:e]):
    v = [float(x) for x in m.group(1).split(',')]
    have.append(Polygon([(v[i] * W, v[i + 1] * H) for i in range(0, len(v), 2)]).buffer(0))
cand = []
for i, a, M in P:
    closed_light = a.get('fill') == 'none' and a.get('stroke') == '#f7f1e7'
    small_fill = a.get('fill') == '#c9c8bb' and a.get('stroke') is None
    if not (closed_light or small_fill): continue
    for sp in subpaths(a['d'], M, 6):
        if len(sp) < 4: continue
        pg = Polygon(sp).buffer(0)
        if pg.is_empty or pg.area < 8 or pg.area > 3000: continue   # skip hairlines and big floor patches
        r = pg.minimum_rotated_rectangle.exterior.coords
        side = sorted([((r[k+1][0]-r[k][0])**2 + (r[k+1][1]-r[k][1])**2) ** 0.5 for k in range(2)])
        if side[0] < 5 or side[1] / max(side[0], 1e-6) > 8: continue  # long thin bars are not cases
        cand.append((i, pg.simplify(0.4)))
new, lines = [], []
for i, pg in cand:
    dup = any(pg.intersection(h).area > 0.5 * min(pg.area, h.area) for h in have)
    if dup: continue
    if pg.geom_type != 'Polygon': continue
    new.append(i)
    lines.append("    MapBlock('fixture', 0.007, [%s]), // svg path %d" % (', '.join('%.4f,%.4f' % (x / W, y / H) for x, y in list(pg.exterior.coords)[:-1]), i))
print('existing', len(have), 'candidates', len(cand), 'new', len(new), new, file=sys.stderr)
open(os.path.join(os.path.dirname(__file__), 'tut_cases.txt'), 'w').write('\n'.join(lines) + '\n')
# connecting hall polygon (path 5)
a, M = [(a, M) for i, a, M in P if i == 5][0]
pg = Polygon(subpaths(a['d'], M, 8)[0]).buffer(0).simplify(0.5)
open(os.path.join(os.path.dirname(__file__), 'tut_hall.txt'), 'w').write(','.join('%.4f,%.4f' % (x / W, y / H) for x, y in list(pg.exterior.coords)[:-1]))
print('hall verts', len(pg.exterior.coords) - 1, 'area', round(pg.area), file=sys.stderr)
