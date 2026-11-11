"""A tiny modelling kit for the map's monuments: lofted sections, tubes, boxes.

Coordinates are a monument's own frame, in units of its height:
  u across (the figure's LEFT is +u), w forward (the way it faces), v up.
Every part is closed and wound so that the cross product (b - a) x (c - a) of a
triangle points OUT of the part; the app culls faces turned away from the camera
and shades the rest from one light, so the winding has to be right.  `Mesh.add`
checks it against the part's centre and flips triangles that point inwards."""
import math


class Mesh:
    def __init__(self):
        self.v = []      # (u, w, v)
        self.t = []      # (a, b, c, argb)

    # ── low level ─────────────────────────────────────────────────────────────
    def add(self, verts, tris, color, centre=None):
        """verts: points; tris: index triples into verts; color: ARGB int or a
        function (triangle centre, triangle index) -> ARGB."""
        base = len(self.v)
        self.v += verts
        if centre is None:
            centre = tuple(sum(p[i] for p in verts) / len(verts) for i in range(3))
        for k, (a, b, c) in enumerate(tris):
            pa, pb, pc = verts[a], verts[b], verts[c]
            n = _cross(_sub(pb, pa), _sub(pc, pa))
            m = tuple((pa[i] + pb[i] + pc[i]) / 3 for i in range(3))
            if _dot(n, _sub(m, centre)) < 0:
                b, c = c, b
            col = color(m, k) if callable(color) else color
            self.t.append((base + a, base + b, base + c, col))

    def extend(self, other):
        base = len(self.v)
        self.v += other.v
        self.t += [(a + base, b + base, c + base, col) for a, b, c, col in other.t]

    def transformed(self, f):
        m = Mesh()
        m.v = [f(p) for p in self.v]
        m.t = list(self.t)
        return m

    # ── parts ─────────────────────────────────────────────────────────────────
    def loft(self, rings, color, caps=(True, True), centre=None, band=None, sector=None):
        """rings: list of equal-length point loops, bottom to top.  `band`, if
        given, colours each band between two rings: band(index) -> ARGB."""
        if band is not None:
            n_ = len(rings[0])
            color = lambda m, k, n_=n_, last=len(rings) - 2: band(min(k // (2 * n_), last))
        elif sector is not None:
            n_ = len(rings[0])
            side_ = (len(rings) - 1) * n_ * 2
            color = lambda m, k, n_=n_, side_=side_: sector((k % (2 * n_)) // 2 if k < side_ else 0)
        n = len(rings[0])
        verts = [p for r in rings for p in r]
        tris = []
        for i in range(len(rings) - 1):
            for j in range(n):
                a, b = i * n + j, i * n + (j + 1) % n
                c, d = (i + 1) * n + (j + 1) % n, (i + 1) * n + j
                tris += [(a, b, c), (a, c, d)]
        if caps[0]:
            verts.append(_centroid(rings[0]))
            ci = len(verts) - 1
            tris += [(ci, (j + 1) % n, j) for j in range(n)]
        if caps[1]:
            verts.append(_centroid(rings[-1]))
            ci = len(verts) - 1
            off = (len(rings) - 1) * n
            tris += [(ci, off + j, off + (j + 1) % n) for j in range(n)]
        if centre is None:
            # the axis point at mid height is a safe "inside" for tall parts
            mid = rings[len(rings) // 2]
            centre = _centroid(mid)
        self._add_per_ring(verts, tris, color, rings, centre)

    def _add_per_ring(self, verts, tris, color, rings, centre):
        """Orient every side quad against the axis point of its own band (so long
        bent parts, arms and legs, are wound right all along) and every cap
        against the ring next to it."""
        n = len(rings[0])
        bands = [_centroid(r) for r in rings]
        base = len(self.v)
        self.v += verts
        side = (len(rings) - 1) * n * 2
        for k, (a, b, c) in enumerate(tris):
            pa, pb, pc = verts[a], verts[b], verts[c]
            m = tuple((pa[i] + pb[i] + pc[i]) / 3 for i in range(3))
            if k < side:
                band = k // (2 * n)
                ref = _mid(bands[band], bands[band + 1])
            elif _dist(m, bands[0]) <= _dist(m, bands[-1]):
                ref = bands[1]          # bottom cap: outward is away from the ring above
            else:
                ref = bands[-2]         # top cap
            nrm = _cross(_sub(pb, pa), _sub(pc, pa))
            if _dot(nrm, _sub(m, ref)) < 0:
                b, c = c, b
            col = color(m, k) if callable(color) else color
            self.t.append((base + a, base + b, base + c, col))

    def box(self, u0, u1, w0, w1, v0, v1, color, top=None):
        """A box, or with `top` = (u0, u1, w0, w1) a frustum."""
        tu0, tu1, tw0, tw1 = top if top else (u0, u1, w0, w1)
        bottom = [(u0, w0, v0), (u1, w0, v0), (u1, w1, v0), (u0, w1, v0)]
        upper = [(tu0, tw0, v1), (tu1, tw0, v1), (tu1, tw1, v1), (tu0, tw1, v1)]
        self.loft([bottom, upper], color)

    def tube(self, path, color, n=8, exp=2.0, caps=(True, True), band=None):
        """path: (u, w, v, ru, rw) points; rings lie horizontal (for upright limbs)."""
        rings = [ring(u, w, v, ru, rw, n, exp) for u, w, v, ru, rw in path]
        self.loft(rings, color, caps, band=band)

    def ellipsoid(self, cu, cw, cv, ru, rw, rv, color, n=10, m=6):
        rings = []
        for i in range(1, m):
            a = math.pi * i / m - math.pi / 2
            rings.append(ring(cu, cw, cv + rv * math.sin(a), ru * math.cos(a), rw * math.cos(a), n))
        verts = [p for r in rings for p in r] + [(cu, cw, cv - rv), (cu, cw, cv + rv)]
        tris = []
        for i in range(len(rings) - 1):
            for j in range(n):
                a, b = i * n + j, i * n + (j + 1) % n
                c, d = (i + 1) * n + (j + 1) % n, (i + 1) * n + j
                tris += [(a, b, c), (a, c, d)]
        lo, hi = len(verts) - 2, len(verts) - 1
        off = (len(rings) - 1) * n
        tris += [(lo, (j + 1) % n, j) for j in range(n)]
        tris += [(hi, off + j, off + (j + 1) % n) for j in range(n)]
        self.add(verts, tris, color, centre=(cu, cw, cv))

    def triangles(self):
        return len(self.t)


def ring(cu, cw, v, ru, rw, n=12, exp=2.0, phase=0.0):
    """A superellipse loop at height v (exp 2 = ellipse, larger = boxier)."""
    out = []
    for i in range(n):
        a = phase + 2 * math.pi * i / n
        c, s = math.cos(a), math.sin(a)
        out.append((cu + ru * _sgn(c) * abs(c) ** (2 / exp), cw + rw * _sgn(s) * abs(s) ** (2 / exp), v))
    return out


def shade(argb, k):
    a = (argb >> 24) & 255
    r, g, b = [min(255, max(0, int(((argb >> s) & 255) * k))) for s in (16, 8, 0)]
    return (a << 24) | (r << 16) | (g << 8) | b


def _sgn(x):
    return 1.0 if x >= 0 else -1.0


def _sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def _add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def _mid(a, b):
    return ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, (a[2] + b[2]) / 2)


def _dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def _cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def _dist(a, b):
    return math.sqrt(sum((a[i] - b[i]) ** 2 for i in range(3)))


def _centroid(pts):
    return tuple(sum(p[i] for p in pts) / len(pts) for i in range(3))


# ── a software preview with the app's shading rules ───────────────────────────
LIGHT = (-0.45, -0.55, 0.7)


def render(mesh, size=(420, 620), yaw_deg=35.0, scale=560, path=None, bg=(238, 233, 220)):
    """Orthographic view from the side `yaw_deg` (0 = the front), slightly from
    above, culling and shading the way museum_map_canvas.dart does."""
    from PIL import Image, ImageDraw
    W, H = size
    im = Image.new('RGB', size, bg)
    d = ImageDraw.Draw(im)
    yaw = math.radians(yaw_deg)
    # camera looks at the figure from direction (sin yaw, cos yaw) in (u, w), from above
    view = (math.sin(yaw), math.cos(yaw), 0.7)
    ll = math.sqrt(sum(c * c for c in LIGHT))
    faces = []
    for a, b, c, col in mesh.t:
        pa, pb, pc = mesh.v[a], mesh.v[b], mesh.v[c]
        n = _cross(_sub(pb, pa), _sub(pc, pa))
        nl = math.sqrt(_dot(n, n)) or 1
        if _dot(n, view) <= 0:
            continue
        lam = max(0.0, _dot(n, LIGHT) / (nl * ll))
        k = 0.58 + 0.5 * lam
        rgb = tuple(min(255, int(((col >> s) & 255) * k)) for s in (16, 8, 0))

        def p2(p):
            x = p[0] * math.cos(yaw) - p[1] * math.sin(yaw)
            dz = p[0] * math.sin(yaw) + p[1] * math.cos(yaw)
            return (W / 2 + x * scale, H - 20 - p[2] * scale * 0.94 + dz * scale * 0.2)
        m = _centroid([pa, pb, pc])
        faces.append((_dot(m, view), [p2(pa), p2(pb), p2(pc)], rgb))
    for _, pts, rgb in sorted(faces, key=lambda f: f[0]):
        d.polygon(pts, fill=rgb)
    if path:
        im.save(path)
    return im


def resample(rings_spec, step):
    """Interpolate a list of (cu, cw, v, ru, rw) sections every `step` of height,
    so a striped part gets one band per stripe."""
    out = []
    for (a, b) in zip(rings_spec, rings_spec[1:]):
        n = max(1, int(round((b[2] - a[2]) / step)))
        for i in range(n):
            t = i / n
            out.append(tuple(a[k] + (b[k] - a[k]) * t for k in range(5)))
    out.append(rings_spec[-1])
    return out
