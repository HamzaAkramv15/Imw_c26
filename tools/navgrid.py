"""Walkable grids of the four plans, built from what the app actually draws.

Each map becomes a raster of CELL x CELL map units with three classes:
  BLOCKED  walls, display cases, shop units, statues, roads, outside the plan
  FLOOR    level floor you can walk (and roll) on
  STAIRS   the treads the plans draw (kSteps / kExtraSteps)

Sources per map (nothing here is guessed geometry):
  gem_complex     the site plan's own colours (roads and the main building are not
                  walkable; the Boats Museum and Conservation Centre footprints are
                  buildings, entered at their edge)
  main_building   the plan's floor colour (#eee9dc), minus kBlocks; treads from kSteps
  main_galleries  the footprint from kFloors minus the real walls ('rwall') and cases
  tutankhamun     the display zones (gem_regions) + hall and landings (kFloors), minus cases

Needs: numpy, scipy, Pillow and the rsvg-convert binary (librsvg)."""
import os
import subprocess
import tempfile

import numpy as np
from PIL import Image, ImageDraw

import gemdata as g

BLOCKED, FLOOR, STAIRS = 0, 1, 2

from walls import wall_segments
CELL = {'gem_complex': 4.0, 'main_building': 2.0, 'main_galleries': 2.0, 'tutankhamun': 2.0}


def _svg_rgba(mid):
    w, h = g.SIZES[mid]
    with tempfile.TemporaryDirectory() as d:
        out = os.path.join(d, 'r.png')
        svg = os.path.join(g.ROOT, 'assets', 'maps', 'light', mid + '.svg')
        subprocess.run(['rsvg-convert', '-w', str(int(w)), '-h', str(int(h)), svg, '-o', out], check=True)
        return np.array(Image.open(out).convert('RGBA')).astype(int)


def _near(rgb, hexcol, tol=6):
    c = [int(hexcol[i:i + 2], 16) for i in (1, 3, 5)]
    return (np.abs(rgb - np.array(c)).max(axis=-1) <= tol)


def _poly_mask(shape, cell, polys, grow=0):
    im = Image.new('L', (shape[1], shape[0]), 0)
    d = ImageDraw.Draw(im)
    for pts in polys:
        q = [(x / cell, y / cell) for x, y in pts]
        if len(q) >= 3:
            d.polygon(q, fill=1, outline=1 if grow else None)
            if grow:
                d.line(q + [q[0]], fill=1, width=int(grow))
    return np.array(im, dtype=bool)


def _downsample(mask, cell):
    """Unit-resolution boolean mask -> cell grid, a cell is set if most of it is."""
    k = int(cell)
    h, w = mask.shape[0] // k, mask.shape[1] // k
    return mask[:h * k, :w * k].reshape(h, k, w, k).mean(axis=(1, 3)) >= 0.5


def build(mid):
    w, h = g.SIZES[mid]
    cell = CELL[mid]
    shape = (int(h // cell), int(w // cell))
    blocks = g.blocks()[mid]
    if mid == 'gem_complex':
        a = _svg_rgba(mid)
        rgb, al = a[..., :3], a[..., 3]
        floor = (al > 200) & ~_near(rgb, '#b4bdbb', 10) & ~_near(rgb, '#3d6b79', 12)
        floor = _downsample(floor, cell)
        bld = [r[4] for r in g.regions() if r[0] in ('cx_main_building', 'cx_boats', 'cx_conservation')]
        floor &= ~_poly_mask(shape, cell, bld)
    elif mid == 'main_building':
        a = _svg_rgba(mid)
        floor = _near(a[..., :3], '#eee9dc', 8) & (a[..., 3] > 200)
        floor = _downsample(floor, cell)
        floor &= ~_poly_mask(shape, cell, [b[2] for b in blocks], grow=1)
    elif mid == 'main_galleries':
        fl = [p for k, p in g.floors()[mid] if k == 'floor']
        floor = _poly_mask(shape, cell, fl)
        floor &= ~_poly_mask(shape, cell, [b[2] for b in blocks], grow=2)
    else:
        zones = [r[4] for r in g.regions() if r[1] == mid]
        fl = [p for k, p in g.floors()[mid] if k in ('hall', 'landing')]
        floor = _poly_mask(shape, cell, zones + fl)
        floor &= ~_poly_mask(shape, cell, [b[2] for b in blocks], grow=1)
    floor &= ~_poly_mask(shape, cell, g.figure_footprints()[mid])  # statues, obelisk
    grid = np.where(floor, FLOOR, BLOCKED).astype(np.uint8)
    st = _poly_mask(shape, cell, g.steps()[mid])
    # a tread is walkable where the plan has floor around it (stairs are never
    # inside a wall); it turns the cell into STAIRS
    grid[st & (grid != BLOCKED) | st & _touches_floor(floor, st)] = STAIRS
    # a wall stays a wall where tread hatching runs into it
    grid[_poly_mask(shape, cell, [b[2] for b in blocks if b[0] in ('wall', 'rwall')])] = BLOCKED
    grid[region_walls(mid, shape, cell)] = BLOCKED
    return grid, cell


def _touches_floor(floor, st):
    from scipy import ndimage
    return ndimage.binary_dilation(floor, iterations=2) & st


def region_walls(mid, shape, cell):
    """Cells under the walls the canvas raises around rooms (region outlines),
    one cell thick: these walls are solid wherever no opening is cut."""
    im = Image.new('L', (shape[1], shape[0]), 0)
    d = ImageDraw.Draw(im)
    for a, b in wall_segments(mid):  # openings are cut later (build_nav.cut_openings)
        d.line([(a[0] / cell, a[1] / cell), (b[0] / cell, b[1] / cell)], fill=1, width=1)
    w = np.array(im, dtype=bool)
    # 4-connected: a diagonal step in the line is closed with an extra cell, so
    # no path can slip between two corner-touching wall cells
    out = w.copy()
    out[:-1, :-1] |= w[:-1, 1:] & w[1:, :-1] & ~w[:-1, :-1] & ~w[1:, 1:]
    out[:-1, 1:] |= w[:-1, :-1] & w[1:, 1:] & ~w[:-1, 1:] & ~w[1:, :-1]
    return out


def wall_cells(mid, shape, cell):
    """Every wall cell: room outlines plus the plan's own wall strips."""
    walls = [b[2] for b in g.blocks()[mid] if b[0] in ('wall', 'rwall')]
    return region_walls(mid, shape, cell) | _poly_mask(shape, cell, walls, grow=1)
