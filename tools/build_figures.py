"""Standing Ramesses II figures for the 3D map.

The plan (assets/maps/light/main_building.svg, paths 88-103 and 104-119) draws each
colossus as a FRONT ELEVATION silhouette laid flat on the floor.  Extruding that
outline as a floor polygon makes the statue lie on its back, so instead we keep the
outline as an upright elevation (u across, v up) and let the canvas stand it on a
small plinth footprint.  Nothing here is invented: the outline is the plan's own
silhouette; only the display scale (K) and the plinth depth are choices.
Output: Dart text for gem_blocks.dart (kFigures + two footprint slabs).
"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from svgutil import load_paths, subpaths
from shapely.geometry import Polygon
from shapely.ops import unary_union

SVG = os.path.join(os.path.dirname(__file__), '..', 'assets/maps/light/main_building.svg')
W, H = 1625.0, 885.0
P = {i: (a, M) for i, a, M in load_paths(SVG)}
FIGS = {
    'ramesses_grand_hall': dict(ids=range(88, 104), placeId='mb_1'),
    'ramesses_san_el_hagar': dict(ids=range(104, 120), placeId='mb_5'),
}
K = 0.60  # display height of the tall figure = 0.10 of the short side (148px*0.60/885)

def silhouette(ids):
    polys = []
    for i in ids:
        a, M = P[i]
        for sp in subpaths(a['d'], M, 6):
            if len(sp) >= 4:
                pg = Polygon(sp).buffer(0)
                if pg.area > 0.5:
                    polys.append(pg)
    g = unary_union(polys).buffer(0.25).buffer(-0.25)
    return max(g.geoms, key=lambda q: q.area) if g.geom_type == 'MultiPolygon' else g

figs, foot = [], []
for name, c in FIGS.items():
    sil = silhouette(c['ids']).simplify(0.45)
    x0, y0, x1, y1 = sil.bounds
    hpx = y1 - y0
    cx = (x0 + x1) / 2
    # base plate = lowest 14 px band: its plan rectangle becomes the footprint
    plate_w = x1 - x0
    uv = []
    for x, y in list(sil.exterior.coords)[:-1]:
        uv += [round((x - cx) / hpx, 4), round((y1 - y) / hpx, 4)]
    height = round(hpx * K / min(W, H), 4)
    fw = plate_w * K / W            # footprint width (normalised x)
    fd = plate_w * K * 0.5 / H      # footprint depth (normalised y)
    ax, ay = cx / W, y1 / H         # anchor: centre of the base plate's front edge
    figs.append(f"    MapFigure('{name}', {ax:.4f}, {ay:.4f}, {height}, [{','.join(map(str, uv))}], '{c['placeId']}'),")
    xa, xb, ya, yb = ax - fw / 2, ax + fw / 2, ay - fd / 2, ay + fd / 2
    foot.append(f"    MapBlock('statue', 0.006, [{xa:.4f},{ya:.4f}, {xb:.4f},{ya:.4f}, {xb:.4f},{yb:.4f}, {xa:.4f},{yb:.4f}], '{c['placeId']}'), // {name} footprint")
    print(name, 'bbox px', [round(v, 1) for v in sil.bounds], 'height u', height, 'verts', len(uv) // 2, file=sys.stderr)
open('figures.dart.txt', 'w').write('\n'.join(figs) + '\n')
open('footprints.dart.txt', 'w').write('\n'.join(foot) + '\n')
