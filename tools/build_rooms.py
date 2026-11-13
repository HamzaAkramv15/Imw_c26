"""Gallery outlines of the Main Galleries, rebuilt from the plan's walls.

    python3 tools/build_rooms.py      # rewrites the main_galleries regions in gem_regions.dart

The official plan numbers each gallery but draws the galleries as one open floor
whose walls leave wide openings.  Each floor cell goes to the gallery whose
number (pin) it reaches first walking around the walls, and walking through a
narrow place costs extra; so the outlines follow the walls wherever the plan has
them and cross the floor at the openings between galleries, never through a wall.
Areas nearer the entrance landing or the Tutankhamun doorway than to any gallery
stay circulation (no outline).

What the walk cannot reach is then given to the nearest room: the floor under
the walls (so two neighbouring outlines meet on the wall's centre line, with no
unlit strip beside it) and pockets the walls close off from every pin (the
wedge between galleries 09 and 09b, the bay at the foot of 07).  Then run
tools/build_nav.py."""
import os
import sys

import cv2
import numpy as np
import skimage.graph as sg
from PIL import Image, ImageDraw
from scipy import ndimage

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gemdata as g  # noqa: E402

MID = 'main_galleries'
S = 0.5                       # raster cells per map unit
ERA = {'01': 'era1', '02': 'era1', '03': 'era1', '04': 'era2', '05': 'era2', '06': 'era2',
       '07': 'era3', '08': 'era3', '09': 'era3', '09b': 'era3', '10': 'era4', '11': 'era4', '12': 'era4'}


def _mask(polys, w, h, width=0):
    im = Image.new('L', (int(w * S), int(h * S)), 0)
    d = ImageDraw.Draw(im)
    for p in polys:
        q = [(x * S, y * S) for x, y in p]
        d.polygon(q, fill=1)
        if width:
            d.line(q + [q[0]], fill=1, width=width)
    return np.array(im, dtype=bool)


def rooms():
    W, H = g.SIZES[MID]
    floor = _mask([p for k, p in g.floors()[MID] if k == 'floor'], W, H)
    walls = _mask([b[2] for b in g.blocks()[MID] if b[0] == 'rwall'], W, H, width=2)
    free = floor & ~walls
    clear = ndimage.distance_transform_edt(free) / S
    cost = np.where(free, 1.0 + 8.0 * np.exp(-clear / 7.0), -1)
    seeds = [(pid, x, y) for pid, name, (x, y), cat in g.places()[MID]]
    ys, xs = np.nonzero(free)
    pts = []
    for pid, x, y in seeds:
        i = ((ys - y * S) ** 2 + (xs - x * S) ** 2).argmin()
        pts.append((ys[i], xs[i]))
    dist = np.stack([sg.MCP_Geometric(cost).find_costs([p])[0] for p in pts])
    best = dist.argmin(axis=0)
    lab = np.where(free & np.isfinite(dist.min(axis=0)), best, -1)
    # walls and closed-off pockets of the floor: to the nearest labelled cell
    _, (iy, ix) = ndimage.distance_transform_edt(lab < 0, return_indices=True)
    lab = np.where(floor, lab[iy, ix], -1)
    out = []
    for i, (pid, x, y) in enumerate(seeds):
        if not pid.startswith('mg_') or pid in ('mg_entrance', 'mg_tut'):
            continue
        m = (lab == i).astype(np.uint8)
        # close the 1-cell wall slits inside a gallery, keep the biggest piece
        m = cv2.morphologyEx(m, cv2.MORPH_CLOSE, np.ones((3, 3), np.uint8))
        contours, _ = cv2.findContours(m, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
        c = max(contours, key=cv2.contourArea)
        c = cv2.approxPolyDP(c, 1.2, True)[:, 0, :]
        poly = [((px + 0.5) / S / W, (py + 0.5) / S / H) for px, py in c]
        # label where the room is deepest
        dt = ndimage.distance_transform_edt(lab == i)
        ly, lx = np.unravel_index(dt.argmax(), dt.shape)
        out.append((pid, poly, ((lx + 0.5) / S / W, (ly + 0.5) / S / H)))
    return out


def write(rs):
    path = os.path.join(g.DATA, 'gem_regions.dart')
    src = open(path, encoding='utf-8').read()
    lines = [l for l in src.split('\n') if "mapId: 'main_galleries'" not in l]
    new = []
    for pid, poly, (lx, ly) in rs:
        num = pid[3:]
        name = 'Gallery %s' % num if num != '09b' else 'Gallery 09 (second hall)'
        pts = ','.join('%.4f,%.4f' % p for p in poly)
        new.append("  MapRegion(id: 'mg_zone_%s', mapId: 'main_galleries', name: '%s', kind: RegionKind.gallery, "
                   "labelAt: Offset(%.4f, %.4f), placeId: '%s', group: '%s', showLabel: false, points: _p(const [%s]))," % (
                       num, name, lx, ly, pid, ERA[num], pts))
    # insert where the main-building regions end
    at = max(i for i, l in enumerate(lines) if "mapId: 'main_building'" in l) + 1
    lines[at:at] = new
    open(path, 'w', encoding='utf-8').write('\n'.join(lines))


if __name__ == '__main__':
    rs = rooms()
    write(rs)
    print('%d gallery outlines written' % len(rs))
