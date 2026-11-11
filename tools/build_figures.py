"""Monuments of the 3D map.

Two styles, both drawn by museum_map_canvas.dart:
  * statues and stone monuments are upright SILHOUETTES (kSilhouettes): a front
    elevation outline stood on the plan, turned to face the viewer, with a little
    thickness.  The two Ramesses II colossi use the outlines the official plan
    itself draws for them (main_building.svg, paths 88-103 and 104-119); the
    Ptolemaic pair, the Merenptah column and the Hanging Obelisk use the front
    view of the models below, so each keeps its own shape and stone colour;
  * palms and the pyramids stay triangle meshes (kMeshes).

The models:

    python3 tools/build_figures.py            # writes lib/data/gem_figures.dart
    python3 tools/build_figures.py --preview  # also writes figures_*.png (4 views each)

Each monument is sculpted from lofted sections, tubes and ellipsoids (meshkit.py)
in its own frame, in units of its height: u across (the figure's LEFT is +u),
w forward, v up.  The canvas places the mesh, turns it to face its real direction,
culls faces turned away from the camera, shades the rest from one light and
draws them back to front with Canvas.drawVertices.

What the shapes follow (the official plan only marks each statue with an icon):

Grand Hall colossus (mb_1, GEM 1): red granite, 11.35 m high and 1.80 m wide
  [GEM collection record "Colossal statue of Ramesses II"]: striding, LEFT leg
  forward; the Double Crown (the flat-topped Red Crown with its back spike, the
  tall White Crown rising from it) over the striped nemes, with the uraeus at the
  brow; false beard; broad collar; arms straight down, fists clenched on
  cylinders; pleated royal kilt with apron, belt and dagger; back pillar.
  Prince Khaemwaset and Princess Bintanath are carved behind the king's legs
  [GEM collection record; "Ramesses loved by Ptah", reviewed on the-past.com].
  Which child stands behind which leg is not given in the sources used here: they
  are placed one behind each leg.  [Also egypt-museum.com; Wikipedia "Statue of
  Ramesses II"; Egyptian Gazette.]
Food-court colossus (mb_5): rosy quartzite from Tanis (San el-Hagar), "over eight
  metres": striding, left foot forward; the tall White Crown worn on the head (no
  nemes), its tip left unrestored, so it ends flat; ears showing; Merytamun stands
  between his legs and Bintanath behind them.  [Egyptian Gazette, "The pharaoh
  hidden in plain sight at GEM"; the-past.com, "A first look at the GEM"]
Hanging Obelisk (cx_obelisk): a Ramesses II obelisk from Tanis raised on a base so
  its underside, with the king's cartouche, can be seen.  [GEM visitor guide]
  The shaft's inscribed central column is shown as a recessed band on each face.
Ptolemaic king and queen (mb_3): he wears the Double Crown and a simple kilt; she
  the crown of Hathor-Isis (cow horns, sun disc, two feathers) and a sheath dress.
  [the-past.com]
Victory Column of Merenpetah (mb_2): granite column on a limestone base
  [the-past.com].  Its capital is not described in the sources used, so the shaft
  ends in a plain abacus.
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from meshkit import Mesh, resample, ring, shade, render  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))

STONE = {
    'granite': 0xffa65f4e,     # Aswan red granite
    'quartzite': 0xffc58f69,   # rosy quartzite
    'limestone': 0xffd8ccb2,
    'trunk': 0xff8d6c4a,
    'frond': 0xff5e7d3a,
    'sand': 0xffd2b07a,
    'steel': 0xff6d7378,
}


def tone(base, k):
    return shade(base, k)


def stripes(base, step, dark=0.88, axis=2):
    """Alternating bands (nemes, collar beads, kilt pleats) along an axis."""
    def f(m, k):
        return tone(base, dark if int(math.floor(m[axis] / step)) % 2 else 1.0)
    return f


def pleats(base):
    """Kilt pleats: alternate sectors of the loft."""
    return lambda j: tone(base, 0.9 if j % 2 else 1.0)


# ── the striding king ─────────────────────────────────────────────────────────
def striding_king(M, s, w_span=1.0, front_leg=1):
    """Feet to neck of a striding royal figure (front_leg = +1: LEFT leg forward).
    Widths follow the GEM record of the Grand Hall colossus (1.80 m of 11.35 m)."""
    L = front_leg
    # feet: the advanced foot long and flat, toes tapering
    M.box(0.016 * L, 0.048 * L, 0.025, 0.14, 0.03, 0.052, tone(s, 0.98), top=(0.019 * L, 0.045 * L, 0.03, 0.125))
    M.box(-0.016 * L, -0.048 * L, -0.07, 0.055, 0.03, 0.052, tone(s, 0.98), top=(-0.019 * L, -0.045 * L, -0.065, 0.042))
    # legs: ankle, calf, knee, thigh; the front one slants forward from the hip
    M.tube([(0.032 * L, 0.075, 0.05, 0.013, 0.016), (0.033 * L, 0.066, 0.09, 0.015, 0.018),
            (0.034 * L, 0.05, 0.16, 0.019, 0.022), (0.034 * L, 0.036, 0.235, 0.016, 0.019),
            (0.035 * L, 0.024, 0.29, 0.021, 0.023), (0.036 * L, 0.012, 0.345, 0.026, 0.027)], s, n=10)
    M.tube([(-0.032 * L, -0.012, 0.05, 0.013, 0.016), (-0.033 * L, -0.012, 0.09, 0.015, 0.018),
            (-0.034 * L, -0.014, 0.16, 0.019, 0.022), (-0.034 * L, -0.01, 0.235, 0.016, 0.019),
            (-0.035 * L, -0.006, 0.29, 0.021, 0.023), (-0.036 * L, -0.002, 0.345, 0.026, 0.027)], s, n=10)
    # knee caps
    for u, w in ((0.034 * L, 0.052), (-0.034 * L, 0.007)):
        M.ellipsoid(u, w, 0.236, 0.013, 0.008, 0.015, tone(s, 1.03), n=8, m=4)
    # the stone left between the legs (a web joining the back pillar)
    M.box(-0.014, 0.014, -0.075, 0.03, 0.03, 0.32, tone(s, 0.82))
    # kilt (shendyt): pleated, flaring slightly at the hem
    M.loft([ring(0, 0.006, 0.325, 0.064, 0.051, 20, 2.6), ring(0, 0.004, 0.4, 0.059, 0.047, 20, 2.6),
            ring(0, 0.002, 0.468, 0.05, 0.041, 20, 2.6)], None, sector=pleats(s))
    # apron: the central tab of the kilt, set forward
    M.box(-0.021, 0.021, 0.05, 0.059, 0.33, 0.468, tone(s, 1.1), top=(-0.012, 0.012, 0.042, 0.05))
    # belt with the buckle (his cartouche) and the dagger handle
    M.loft([ring(0, 0.002, 0.464, 0.053, 0.043, 20, 2.6), ring(0, 0.002, 0.49, 0.051, 0.042, 20, 2.6)], tone(s, 0.84))
    M.box(-0.011, 0.011, 0.042, 0.05, 0.465, 0.492, tone(s, 1.12))
    M.box(0.014 * L, 0.025 * L, 0.04, 0.052, 0.47, 0.515, tone(s, 1.05))
    # torso: narrow waist, full chest, square shoulders
    M.loft([ring(0, 0.0, 0.488, 0.046, 0.036, 18, 2.4), ring(0, 0.002, 0.55, 0.052, 0.039, 18, 2.4),
            ring(0, 0.004, 0.6, 0.058, 0.041, 18, 2.4), ring(0, 0.002, 0.643, 0.061, 0.04, 18, 2.6),
            ring(0, 0.0, 0.668, 0.047, 0.034, 18, 2.4)], s)
    for side in (1, -1):
        M.ellipsoid(0.025 * side, 0.03, 0.604, 0.024, 0.012, 0.019, tone(s, 1.02), n=8, m=4)   # pectorals
    # broad collar: bands of beads over the chest
    bead = lambda i: tone(s, 0.92 if i % 2 else 1.07)
    M.loft([ring(*r, n=18, exp=2.6) for r in resample([(0, 0.004, 0.618, 0.0605, 0.0425), (0, 0.003, 0.645, 0.0625, 0.0415),
                                                       (0, 0.001, 0.66, 0.05, 0.036)], 0.007)], None, caps=(False, False), band=bead)
    # arms straight down, close to the body, fists clenched on cylinders
    for side in (1, -1):
        M.ellipsoid(0.062 * side, 0.0, 0.645, 0.017, 0.02, 0.018, s, n=8, m=5)   # shoulder
        M.tube([(0.066 * side, -0.001, 0.646, 0.016, 0.019), (0.069 * side, -0.003, 0.6, 0.015, 0.018),
                (0.07 * side, -0.004, 0.538, 0.013, 0.016), (0.069 * side, 0.0, 0.48, 0.012, 0.014),
                (0.068 * side, 0.004, 0.445, 0.011, 0.013)], s, n=8)
        M.ellipsoid(0.068 * side, 0.008, 0.42, 0.014, 0.017, 0.022, tone(s, 0.98), n=8, m=5)  # fist
        M.box(0.061 * side, 0.075 * side, 0.016, 0.034, 0.407, 0.427, tone(s, 0.93))           # cylinder
    # neck
    M.tube([(0, 0.003, 0.662, 0.021, 0.021), (0, 0.006, 0.7, 0.019, 0.019)], s, n=10)


def face(M, s, cv=0.738, ears=False):
    """Head and the features of an Egyptian royal face: brow, almond eyes, a
    straight nose, full lips and the false beard."""
    M.ellipsoid(0, 0.008, cv, 0.029, 0.033, 0.041, s, n=12, m=7)
    M.ellipsoid(0, 0.022, cv - 0.022, 0.018, 0.016, 0.016, s, n=10, m=5)                  # chin and jaw
    M.box(-0.026, 0.026, 0.034, 0.041, cv + 0.012, cv + 0.019, tone(s, 1.04))             # brow
    for side in (1, -1):
        M.box(0.006 * side, 0.02 * side, 0.036, 0.0412, cv + 0.002, cv + 0.01, tone(s, 0.74), top=(0.008 * side, 0.019 * side, 0.036, 0.041))   # almond eye
        M.box(0.02 * side, 0.028 * side, 0.034, 0.039, cv + 0.004, cv + 0.008, tone(s, 0.8))    # cosmetic line
        M.ellipsoid(0.019 * side, 0.03, cv - 0.006, 0.01, 0.006, 0.01, tone(s, 1.03), n=6, m=3)  # cheek
    M.box(-0.006, 0.006, 0.038, 0.05, cv - 0.013, cv + 0.009, tone(s, 1.06), top=(-0.004, 0.004, 0.036, 0.042))  # nose
    M.box(-0.011, 0.011, 0.035, 0.042, cv - 0.026, cv - 0.019, tone(s, 0.9))              # lips
    M.tube([(0, 0.032, cv - 0.034, 0.008, 0.007), (0, 0.037, cv - 0.06, 0.009, 0.008),
            (0, 0.041, cv - 0.075, 0.008, 0.007)], tone(s, 0.92), n=8)                    # false beard
    if ears:
        for side in (1, -1):
            M.ellipsoid(0.031 * side, 0.002, cv + 0.002, 0.006, 0.01, 0.014, tone(s, 0.97), n=6, m=4)


def uraeus(M, s, w, v0):
    M.tube([(0, w, v0, 0.005, 0.005), (0, w + 0.004, v0 + 0.022, 0.006, 0.004)], tone(s, 1.08), n=6)
    M.ellipsoid(0, w + 0.004, v0 + 0.02, 0.009, 0.0045, 0.01, tone(s, 1.1), n=8, m=4)     # the cobra's hood


def nemes(M, s):
    """The striped royal headcloth: around and behind the head (the face stays
    open), wings over the shoulders, lappets on the chest, tail down the back."""
    light, dark = tone(s, 1.04), tone(s, 0.84)
    band = lambda i: dark if i % 2 else light
    spec = [(0, -0.02, 0.684, 0.058, 0.03), (0, -0.018, 0.7, 0.055, 0.032), (0, -0.016, 0.722, 0.044, 0.034),
            (0, -0.014, 0.75, 0.039, 0.036), (0, -0.012, 0.774, 0.033, 0.033)]
    M.loft([ring(*r, n=16, exp=2.2) for r in resample(spec, 0.0075)], None, band=band)
    for side in (1, -1):   # lappets: two striped bands falling on the chest
        spec = [(0.036 * side, 0.026, 0.618, 0.012, 0.005), (0.035 * side, 0.024, 0.7, 0.009, 0.005)]
        M.loft([ring(*r, n=8, exp=4.0) for r in resample(spec, 0.0075)], None, band=band)
    M.box(-0.016, 0.016, -0.052, -0.036, 0.655, 0.735, light)


def double_crown(M, s):
    # Red Crown: flat-topped, flaring a little, its tall back spike, the curl
    M.loft([ring(0, -0.004, 0.77, 0.034, 0.037, 16, 2.2), ring(0, -0.004, 0.83, 0.038, 0.041, 16, 2.4)], tone(s, 0.97))
    M.box(-0.024, 0.024, -0.045, -0.029, 0.83, 0.888, tone(s, 0.95), top=(-0.017, 0.017, -0.043, -0.034))
    M.tube([(0.012, 0.03, 0.828, 0.0028, 0.0028), (0.014, 0.046, 0.846, 0.003, 0.003),
            (0.012, 0.052, 0.864, 0.0035, 0.0035)], tone(s, 1.05), n=5)
    # White Crown rising from it, ending in a knob
    M.loft([ring(0, -0.004, 0.828, 0.025, 0.028, 16), ring(0, -0.004, 0.87, 0.03, 0.033, 16),
            ring(0, -0.004, 0.92, 0.029, 0.031, 16), ring(0, -0.004, 0.955, 0.023, 0.025, 16),
            ring(0, -0.004, 0.978, 0.014, 0.015, 16)], tone(s, 1.08))
    M.ellipsoid(0, -0.002, 0.987, 0.0125, 0.0135, 0.0125, tone(s, 1.1), n=10, m=5)


def white_crown(M, s, broken=True):
    """The White Crown worn on the head, with a brow band; at Tanis its tip is lost."""
    M.loft([ring(0, 0.0, 0.752, 0.034, 0.037, 16), ring(0, 0.0, 0.765, 0.035, 0.038, 16)], tone(s, 0.9))
    rings = [ring(0, 0.0, 0.765, 0.035, 0.038, 16), ring(0, -0.002, 0.82, 0.037, 0.04, 16),
             ring(0, -0.003, 0.9, 0.031, 0.033, 16), ring(0, -0.003, 0.965, 0.023, 0.025, 16),
             ring(0, -0.003, 1.0, 0.019, 0.02, 16)]
    if broken:
        M.loft(rings, tone(s, 1.06), caps=(True, False))
        M.loft([rings[-1], ring(0, -0.003, 1.0, 0.0, 0.0, 16)], tone(s, 0.78), caps=(False, False))  # broken top
    else:
        M.loft(rings, tone(s, 1.06))


def small_figure(M, s, cu, cw, h, female=True, crown='modius'):
    """A royal child carved at the king's legs: standing, arms down, about knee high."""
    v0 = 0.03
    k = h
    M.tube([(cu, cw, v0, 0.011, 0.009), (cu, cw, v0 + 0.55 * k, 0.012, 0.01),
            (cu, cw, v0 + 0.78 * k, 0.014, 0.01)], tone(s, 1.06), n=8)                      # body
    M.ellipsoid(cu, cw, v0 + 0.86 * k, 0.009, 0.009, 0.011, tone(s, 1.08), n=8, m=4)       # head / wig
    if female and crown == 'modius':
        M.tube([(cu, cw, v0 + 0.93 * k, 0.007, 0.007), (cu, cw, v0 + k, 0.008, 0.008)], tone(s, 1.1), n=6)
    elif not female:
        M.ellipsoid(cu + 0.006, cw, v0 + 0.84 * k, 0.004, 0.004, 0.01, tone(s, 1.08), n=5, m=3)  # side-lock


def memphis():
    s = STONE['granite']
    M = Mesh()
    M.box(-0.075, 0.075, -0.115, 0.16, 0.0, 0.03, tone(s, 0.92))                          # plinth
    M.box(-0.032, 0.032, -0.088, -0.05, 0.03, 0.745, tone(s, 0.86))                       # back pillar
    striding_king(M, s)
    face(M, s)
    nemes(M, s)
    uraeus(M, s, 0.036, 0.762)
    double_crown(M, s)
    # Khaemwaset and Bintanath, behind the legs
    small_figure(M, s, -0.03, -0.042, 0.19, female=False)
    small_figure(M, s, 0.03, -0.034, 0.18, female=True)
    return M


def tanis():
    s = STONE['quartzite']
    M = Mesh()
    M.box(-0.08, 0.08, -0.12, 0.165, 0.0, 0.03, tone(s, 0.92))                            # plinth
    M.box(-0.033, 0.033, -0.09, -0.05, 0.03, 0.73, tone(s, 0.86))                         # back pillar
    striding_king(M, s)
    face(M, s, cv=0.728, ears=True)
    white_crown(M, s, broken=True)
    uraeus(M, s, 0.036, 0.752)
    # Merytamun between his legs, Bintanath behind them (both knee high)
    small_figure(M, s, 0.0, 0.045, 0.2, female=True)
    small_figure(M, s, 0.0, -0.1, 0.19, female=True)
    return M


def ptolemaic_pair():
    s = STONE['granite']
    M = Mesh()
    M.box(-0.3, 0.3, -0.12, 0.17, 0.0, 0.03, tone(s, 0.92))
    king, queen = Mesh(), Mesh()
    striding_king(king, s)
    face(king, s)
    king.box(-0.03, 0.03, -0.035, 0.03, 0.74, 0.775, tone(s, 0.95))                       # headcloth under the crown
    double_crown(king, s)
    king.box(-0.03, 0.03, -0.088, -0.05, 0.03, 0.74, tone(s, 0.86))
    # the queen: sheath dress, wig, the crown of Hathor-Isis
    queen.box(-0.03, 0.03, -0.088, -0.05, 0.03, 0.72, tone(s, 0.86))
    queen.box(-0.016, 0.016, 0.0, 0.05, 0.03, 0.05, tone(s, 0.98))
    queen.loft([ring(0, 0.0, 0.05, 0.034, 0.03, 16), ring(0, 0.0, 0.25, 0.04, 0.034, 16),
                ring(0, 0.0, 0.45, 0.05, 0.038, 16), ring(0, 0.002, 0.6, 0.055, 0.04, 16),
                ring(0, 0.0, 0.66, 0.045, 0.033, 16)], s)
    for side in (1, -1):
        queen.tube([(0.056 * side, 0.0, 0.64, 0.013, 0.015), (0.058 * side, 0.002, 0.45, 0.01, 0.012)], s, n=8)
    face(queen, s, cv=0.72)
    queen.loft([ring(0, -0.008, 0.66, 0.042, 0.03, 14), ring(0, -0.004, 0.73, 0.038, 0.036, 14),
                ring(0, -0.002, 0.765, 0.03, 0.032, 14)], stripes(s, 0.008, 0.9))            # tripartite wig
    queen.tube([(0, 0.0, 0.765, 0.026, 0.026), (0, 0.0, 0.79, 0.027, 0.027)], tone(s, 0.95), n=12)  # modius
    for side in (1, -1):
        queen.tube([(0.03 * side, 0.0, 0.79, 0.004, 0.004), (0.04 * side, 0.0, 0.83, 0.004, 0.004),
                    (0.022 * side, 0.0, 0.87, 0.004, 0.004)], tone(s, 0.95), n=5)           # cow horns
    queen.ellipsoid(0, 0.0, 0.84, 0.022, 0.006, 0.022, tone(s, 1.1), n=10, m=5)             # sun disc
    for side in (1, -1):
        queen.box(0.002 * side, 0.012 * side, -0.004, 0.004, 0.84, 0.97, tone(s, 1.06), top=(0.002 * side, 0.008 * side, -0.003, 0.003))
    M.extend(king.transformed(lambda p: (p[0] * 0.95 + 0.14, p[1], p[2])))
    M.extend(queen.transformed(lambda p: (p[0] * 0.9 - 0.14, p[1], p[2] * 0.94)))
    return M


def obelisk():
    s = STONE['granite']
    lime = STONE['limestone']
    M = Mesh()
    M.box(-0.17, 0.17, -0.17, 0.17, 0.0, 0.045, tone(lime, 0.95))                         # plinth
    M.box(-0.14, 0.14, -0.14, 0.14, 0.045, 0.065, tone(lime, 1.02))
    for su in (1, -1):                                                                     # the supports it hangs on
        for sw in (1, -1):
            M.box(min(0.06 * su, 0.1 * su), max(0.06 * su, 0.1 * su), min(0.06 * sw, 0.1 * sw), max(0.06 * sw, 0.1 * sw),
                  0.065, 0.15, tone(STONE['steel'], 1.0))
    M.box(-0.072, 0.072, -0.072, 0.072, 0.15, 0.93, s, top=(-0.048, 0.048, -0.048, 0.048))  # shaft (tapering)
    for (u0, u1, w0, w1) in ((-0.014, 0.014, 0.0705, 0.074), (-0.014, 0.014, -0.074, -0.0705),
                             (0.0705, 0.074, -0.014, 0.014), (-0.074, -0.0705, -0.014, 0.014)):
        # the inscribed central column of each face
        tu = (u0 * 0.68, u1 * 0.68) if abs(u0) > 0.05 else (u0, u1)
        tw = (w0 * 0.68, w1 * 0.68) if abs(w0) > 0.05 else (w0, w1)
        M.box(u0, u1, w0, w1, 0.2, 0.88, tone(s, 0.8), top=(tu[0] * 0.98 if abs(u0) > 0.05 else u0 * 0.9,
                                                            tu[1] * 0.98 if abs(u1) > 0.05 else u1 * 0.9,
                                                            tw[0] * 0.98 if abs(w0) > 0.05 else w0 * 0.9,
                                                            tw[1] * 0.98 if abs(w1) > 0.05 else w1 * 0.9))
    M.box(-0.048, 0.048, -0.048, 0.048, 0.93, 1.0, tone(s, 1.12), top=(0, 0, 0, 0))        # pyramidion
    return M


def column():
    s = STONE['granite']
    M = Mesh()
    M.box(-0.2, 0.2, -0.2, 0.2, 0.0, 0.1, tone(STONE['limestone'], 0.95))
    M.tube([(0, 0, 0.1, 0.12, 0.12), (0, 0, 0.88, 0.105, 0.105)], s, n=16)
    M.box(-0.13, 0.13, -0.13, 0.13, 0.88, 0.94, tone(s, 1.04))
    return M


def palm(seed):
    """Date palm: a ringed, slightly curving trunk and a crown of arching fronds."""
    rnd = random.Random(seed)
    M = Mesh()
    lean_u, lean_w = rnd.uniform(-0.05, 0.05), rnd.uniform(-0.05, 0.05)
    trunk = []
    for i in range(9):   # banded like leaf-scar rings (finer bands vanish at map scale)
        t = i / 8
        trunk.append((lean_u * t * t, lean_w * t * t, t * 0.8, 0.032 - 0.01 * t, 0.032 - 0.01 * t))
    M.tube(trunk, None, n=6, band=lambda i: tone(STONE['trunk'], 0.84 if i % 2 else 1.0))
    top = (lean_u, lean_w, 0.8)
    green = STONE['frond']
    nfr = 11
    for k in range(nfr):
        a = 2 * math.pi * k / nfr + rnd.uniform(-0.2, 0.2)
        rise = rnd.uniform(0.05, 0.16)
        length = rnd.uniform(0.32, 0.4)
        col = tone(green, rnd.uniform(0.85, 1.12))
        pts = []
        for i in range(5):
            t = i / 4
            r = length * t
            v = top[2] + rise * math.sin(t * math.pi * 0.9) - 0.22 * t * t
            pts.append((top[0] + math.cos(a) * r, top[1] + math.sin(a) * r, v, 0.055 * math.sin(math.pi * min(1, t * 1.1)) + 0.004))
        # a frond is a strip of leaflets: a folded ribbon (V section) along its rib
        verts, tris = [], []
        for i, (u, w, v, half) in enumerate(pts):
            nu, nw = -math.sin(a), math.cos(a)
            verts += [(u + nu * half, w + nw * half, v - half * 0.35), (u, w, v + 0.004), (u - nu * half, w - nw * half, v - half * 0.35)]
        for i in range(len(pts) - 1):
            b0, b1 = i * 3, (i + 1) * 3
            tris += [(b0, b0 + 1, b1 + 1), (b0, b1 + 1, b1), (b0 + 1, b0 + 2, b1 + 2), (b0 + 1, b1 + 2, b1 + 1)]
        # two-sided: add the same faces reversed so they show from below too
        tris += [(a_, c_, b_) for a_, b_, c_ in tris]
        base = len(M.v)
        M.v += verts
        M.t += [(base + x, base + y, base + z, col) for x, y, z in tris]
    M.ellipsoid(top[0], top[1], top[2] + 0.01, 0.045, 0.045, 0.04, tone(green, 0.8), n=6, m=3)
    return M


def pyramid():
    M = Mesh()
    M.box(-0.8, 0.8, -0.8, 0.8, 0.0, 1.0, STONE['sand'], top=(0, 0, 0, 0))
    return M


# ── placement ─────────────────────────────────────────────────────────────────
def palms():
    """Palms spread over the site's gardens (deterministic, never on a path)."""
    import gemdata as g
    regions = [r for r in g.regions() if r[1] == 'gem_complex' and r[3] == 'garden']
    W, H = g.SIZES['gem_complex']
    rnd = random.Random(26)
    out = []
    for rid, mid, name, kind, pts, pid in regions:
        xs, ys = [p[0] for p in pts], [p[1] for p in pts]
        area = 0.5 * abs(sum(xs[i] * ys[i - 1] - xs[i - 1] * ys[i] for i in range(len(pts))))
        want = max(3, min(14, int(area / 2600)))
        tries, placed = 0, []
        while len(placed) < want and tries < 2000:
            tries += 1
            x, y = rnd.uniform(min(xs), max(xs)), rnd.uniform(min(ys), max(ys))
            if not _inside((x, y), pts) or any(math.dist((x, y), q) < 22 for q in placed):
                continue
            if any(math.dist((x, y), q) < 14 for q in _edge_points(pts)):
                continue  # keep the edges of gardens, where paths run, clear
            placed.append((x, y))
        for i, (x, y) in enumerate(placed):
            out.append(('palm_%s_%d' % (rid[3:], i), x / W, y / H, round(rnd.uniform(0.018, 0.024), 4),
                        rnd.uniform(0, 6.28), 'palm%d' % (i % 4), None))
    return out


def _inside(p, poly):
    x, y = p
    inside = False
    j = len(poly) - 1
    for i in range(len(poly)):
        (xi, yi), (xj, yj) = poly[i], poly[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
            inside = not inside
        j = i
    return inside


def _edge_points(poly, step=6.0):
    out = []
    for i in range(len(poly)):
        a, b = poly[i], poly[(i + 1) % len(poly)]
        n = max(1, int(math.dist(a, b) / step))
        out += [(a[0] + (b[0] - a[0]) * k / n, a[1] + (b[1] - a[1]) * k / n) for k in range(n)]
    return out


def facing_towards(frm, to):
    return math.atan2(to[1] - frm[1], to[0] - frm[0])


def meshes():
    out = {'memphis': memphis(), 'tanis': tanis(), 'ptolemaic_pair': ptolemaic_pair(),
           'obelisk': obelisk(), 'column': column(), 'pyramid': pyramid()}
    for i in range(4):
        out['palm%d' % i] = palm(100 + i)
    return out


# The plan's own elevation outlines of the two colossi (u across, v up, in units
# of the outline's height), extracted from main_building.svg paths 88-103 (Grand
# Hall, red granite) and 104-119 (Tanis, quartzite).
PLAN_OUTLINES = {
    'memphis': (0xffad6c5e, [-0.1651,0.0381,-0.165,0.0,0.1651,0.0,0.165,0.0381,0.0699,0.0394,0.0671,0.3703,0.1069,0.3708,0.1063,0.6357,0.0938,0.6676,0.0643,0.6815,0.082,0.7043,0.0468,0.8015,0.0389,0.8028,0.044,0.8746,0.0584,0.8758,0.0347,0.9873,0.0074,0.9874,-0.0029,1.0,-0.0111,0.9982,-0.0174,0.9874,-0.0457,0.9873,-0.0662,0.8758,-0.0535,0.8746,-0.0482,0.8028,-0.056,0.8015,-0.0908,0.7043,-0.073,0.6816,-0.1027,0.6676,-0.1151,0.6357,-0.1144,0.3708,-0.0749,0.3681,-0.08,0.0394]),
    'tanis': (0xffb98b62, [-0.1812,0.0417,-0.181,0.0,0.1812,0.0015,0.181,0.0433,0.0723,0.0457,0.0876,0.3384,0.1424,0.3408,0.1552,0.6881,0.1274,0.7305,0.0448,0.7551,0.0426,0.7886,0.0569,0.8486,0.0493,0.9434,0.0205,0.9924,-0.0066,1.0,-0.0311,0.9922,-0.0591,0.9429,-0.0682,0.848,-0.0529,0.7882,-0.0546,0.7547,-0.1342,0.7308,-0.1619,0.6839,-0.1467,0.3396,-0.0918,0.3376,-0.0727,0.0445]),
}
SILHOUETTES = ('memphis', 'tanis', 'ptolemaic_pair', 'obelisk', 'column')


def front_outline(m, px=900):
    """A mesh's outline seen from the front (u across, v up), traced from a raster
    of its triangles, and its main stone colour (area-weighted)."""
    import cv2
    import numpy as np
    us = [p[0] for p in m.v]
    u0, u1 = min(us), max(us)
    k, pad = px, 4  # pixels per unit of height
    w, h = int((u1 - u0) * k) + 2 * pad, int(max(p[2] for p in m.v) * k) + 2 * pad
    img = np.zeros((h, w), np.uint8)
    area = {}
    for a, b, c, col in m.t:
        tri = np.array([[(m.v[i][0] - u0) * k + pad, h - pad - m.v[i][2] * k] for i in (a, b, c)], np.int32)
        cv2.fillPoly(img, [tri], 255)
        (xa, _, za), (xb, _, zb), (xc, _, zc) = m.v[a], m.v[b], m.v[c]
        area[col] = area.get(col, 0) + abs((xb - xa) * (zc - za) - (xc - xa) * (zb - za))
    img = cv2.morphologyEx(img, cv2.MORPH_CLOSE, np.ones((5, 5), np.uint8))
    img = cv2.dilate(img, np.ones((5, 5), np.uint8))  # thin parts (horns) stay solid
    cs, _ = cv2.findContours(img, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_NONE)
    c = cv2.approxPolyDP(max(cs, key=cv2.contourArea), 1.2, True)[:, 0, :]
    uv = []
    for x, y in c:
        uv += [round((x - pad) / k + u0, 4), round((h - pad - y) / k, 4)]
    return max(area, key=area.get), uv


def silhouettes(ms):
    return {key: PLAN_OUTLINES[key] if key in PLAN_OUTLINES else front_outline(ms[key]) for key in SILHOUETTES}


# Footprints on the floor (u0, u1, w0, w1), so routes walk around the bases.
FOOTPRINTS = {
    'memphis': (-0.075, 0.075, -0.115, 0.16),
    'tanis': (-0.08, 0.08, -0.12, 0.165),
    'ptolemaic_pair': (-0.3, 0.3, -0.12, 0.17),
    'obelisk': (-0.17, 0.17, -0.17, 0.17),
    'column': (-0.2, 0.2, -0.2, 0.2),
}


def figures():
    """(id, x, y, height, facing, mesh, placeId) per map."""
    W_mb, H_mb = 1625.0, 885.0
    W_cx, H_cx = 1790.0, 1080.0
    return {
        'main_building': [
            # each colossus stands on its plinth (the 'statue' slabs in gem_blocks.dart)
            ('ramesses_grand_hall', 0.63295, 0.42985, 0.1002, facing_towards((1029, 380), (940, 644)), 'memphis', 'mb_1'),
            ('ramesses_san_el_hagar', 0.8726, 0.33355, 0.0569, facing_towards((1418, 295), (1100, 400)), 'tanis', 'mb_5'),
            ('merenptah_column', 1059 / W_mb, 205 / H_mb, 0.05, 0.0, 'column', 'mb_2'),
            ('ptolemaic_pair', 1054 / W_mb, 145 / H_mb, 0.055, facing_towards((1054, 145), (940, 644)), 'ptolemaic_pair', 'mb_3'),
        ],
        'gem_complex': [
            ('hanging_obelisk', 787 / W_cx, 880 / H_cx, 0.075, 0.0, 'obelisk', 'cx_obelisk'),
            # the three pyramids of Giza beyond the site (the plan's direction marker)
            # laid out as at Giza: apart, on a line running south-west from Khufu
            # (up the plan, by its compass rose), bases square to the compass
            # (north points to the plan's lower right); Menkaure about half the size
            ('pyramid_khufu', 255 / W_cx, 610 / H_cx, 0.05, math.pi / 4, 'pyramid', None),
            ('pyramid_khafre', 245 / W_cx, 500 / H_cx, 0.047, math.pi / 4, 'pyramid', None),
            ('pyramid_menkaure', 237 / W_cx, 410 / H_cx, 0.024, math.pi / 4, 'pyramid', None),
        ] + palms(),
    }


def fmt(v):
    s = ('%.4f' % v).rstrip('0').rstrip('.')
    return '0' if s in ('-0', '') else s


def write():
    ms = meshes()
    L = ['// GENERATED by tools/build_figures.py (shapes and sources are documented there).',
         '// Do not edit by hand.', '',
         '/// A triangle mesh in a monument\'s own frame: u across (its left is +u),',
         '/// w forward, v up, in units of the monument\'s height.',
         'class FigureMesh {',
         '  const FigureMesh(this.verts, this.tris, this.colors);', '',
         '  /// u, w, v of every vertex.',
         '  final List<double> verts;', '',
         '  /// Vertex indices, three per triangle, wound so (b - a) x (c - a) points out.',
         '  final List<int> tris;', '',
         '  /// ARGB colour of every triangle (stone, with carved detail baked in).',
         '  final List<int> colors;', '}', '',
         '/// A monument placed on a plan.',
         'class MapFigure {',
         '  const MapFigure(this.id, this.x, this.y, this.height, this.facing, this.mesh, this.footprint, [this.placeId]);',
         '  final String id;', '',
         '  /// Ground anchor (normalised): the centre of the base.',
         '  final double x, y;', '',
         "  /// Height, as a fraction of the plan's short side.",
         '  final double height;', '',
         '  /// Direction the front faces, radians in plan coordinates (0 = +x, y down).',
         '  final double facing;', '',
         '  /// Key into [kMeshes].',
         '  final String mesh;', '',
         '  /// The base on the floor, (u0, u1, w0, w1) in the mesh frame; empty when',
         '  /// visitors walk around it freely (palms).',
         '  final List<double> footprint;',
         '  final String? placeId;', '}', '',
         '/// An upright outline: a front elevation stood on the plan and turned to',
         '/// face the viewer.',
         'class FigureSilhouette {',
         '  const FigureSilhouette(this.color, this.uv);', '',
         '  /// Stone colour (ARGB).',
         '  final int color;', '',
         "  /// u across, v up, in units of the figure's height.",
         '  final List<double> uv;', '}', '',
         '/// Figures drawn as outlines, by [MapFigure.mesh] key.',
         'const Map<String, FigureSilhouette> kSilhouettes = {']
    for key, (col, uv) in silhouettes(ms).items():
        L.append("  '%s': FigureSilhouette(0x%08x, [%s])," % (key, col, ','.join(fmt(c) for c in uv)))
    L += ['};', '', 'const Map<String, FigureMesh> kMeshes = {']
    for key, m in ms.items():
        if key in SILHOUETTES:
            continue
        L.append("  '%s': FigureMesh(" % key)
        L.append('    [%s],' % ','.join(fmt(c) for p in m.v for c in p))
        L.append('    [%s],' % ','.join(str(i) for a, b, c, _ in m.t for i in (a, b, c)))
        L.append('    [%s],' % ','.join('0x%08x' % col for *_, col in m.t))
        L.append('  ),')
    L += ['};', '', 'const Map<String, List<MapFigure>> kFigures = {']
    for mid, figs in figures().items():
        L.append("  '%s': [" % mid)
        for fid, x, y, h, facing, mesh, pid in figs:
            fp = FOOTPRINTS.get(mesh)
            L.append("    MapFigure('%s', %s, %s, %s, %s, '%s', [%s]%s)," % (
                fid, fmt(x), fmt(y), fmt(h), fmt(facing), mesh, ', '.join(fmt(c) for c in fp) if fp else '',
                ", '%s'" % pid if pid else ''))
        L.append('  ],')
    L += ['};', '']
    with open(os.path.join(ROOT, 'lib', 'data', 'gem_figures.dart'), 'w', encoding='utf-8') as f:
        f.write('\n'.join(L))
    return ms


def preview(ms, folder):
    from PIL import Image
    for key in ('memphis', 'tanis', 'ptolemaic_pair', 'obelisk', 'palm0'):
        views = [render(ms[key], yaw_deg=a, scale=560 if key in ('memphis', 'tanis') else 420) for a in (0, 35, 90, 180)]
        sheet = Image.new('RGB', (420 * 4, 620), (238, 233, 220))
        for i, im in enumerate(views):
            sheet.paste(im, (i * 420, 0))
        sheet.save(os.path.join(folder, 'figures_%s.png' % key))


if __name__ == '__main__':
    ms = write()
    for k, m in ms.items():
        print('%-15s %5d triangles' % (k, m.triangles()))
    if '--preview' in sys.argv:
        preview(ms, os.getcwd())
