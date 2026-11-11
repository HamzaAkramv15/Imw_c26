"""Reads the map data straight out of the Dart sources (lib/data/*.dart) so the
Python tools always work on exactly what the app ships.  Pure standard library.

Every coordinate is returned in the map's own SVG units (not normalised)."""
import os
import re

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
DATA = os.path.join(ROOT, 'lib', 'data')

SIZES = {
    'gem_complex': (1790.0, 1080.0),
    'main_building': (1625.0, 885.0),
    'main_galleries': (1400.0, 1080.0),
    'tutankhamun': (1389.0, 962.0),
}
MAPS = list(SIZES)


def _read(name):
    with open(os.path.join(DATA, name), encoding='utf-8') as f:
        return f.read()


def _section(src, start_marker):
    """Text of a `const Map<...> name = { ... };` literal, split per map id."""
    i = src.index(start_marker)
    j = src.index('\n};', i)
    body = src[i:j]
    out, cur = {}, None
    for line in body.split('\n'):
        m = re.match(r"\s*'(\w+)': \[", line)
        if m and m.group(1) in SIZES:
            cur = m.group(1)
            out[cur] = []
            continue
        if cur:
            out[cur].append(line)
    return {k: '\n'.join(v) for k, v in out.items()}


def _nums(s):
    return [float(x) for x in s.replace(' ', '').split(',') if x]


def _denorm(mid, v):
    w, h = SIZES[mid]
    return [(v[i] * w, v[i + 1] * h) for i in range(0, len(v) - 1, 2)]


def blocks():
    """{map: [(kind, height, [(x, y)...], placeId)]} from kBlocks + kExtraBlocks."""
    out = {m: [] for m in MAPS}
    rx = re.compile(r"MapBlock\('(\w+)', ([\d.]+), \[([^\]]*)\](?:, '(\w+)')?\)")
    for fname, marker in (('gem_blocks.dart', 'const Map<String, List<MapBlock>> kBlocks'),
                          ('gem_floors.dart', 'const Map<String, List<MapBlock>> kExtraBlocks')):
        for mid, body in _section(_read(fname), marker).items():
            for m in rx.finditer(body):
                out[mid].append((m.group(1), float(m.group(2)), _denorm(mid, _nums(m.group(3))), m.group(4)))
    return out


def steps():
    """{map: [[(x, y)...]]} stair treads from kSteps + kExtraSteps."""
    out = {m: [] for m in MAPS}
    rx = re.compile(r"MapStep\(([\d.]+), \[([^\]]*)\]\)")
    for fname, marker in (('gem_blocks.dart', 'const Map<String, List<MapStep>> kSteps'),
                          ('gem_floors.dart', 'const Map<String, List<MapStep>> kExtraSteps')):
        for mid, body in _section(_read(fname), marker).items():
            for m in rx.finditer(body):
                out[mid].append(_denorm(mid, _nums(m.group(2))))
    return out


def floors():
    out = {m: [] for m in MAPS}
    rx = re.compile(r"MapFloor\('(\w+)', \[([^\]]*)\]\)")
    for mid, body in _section(_read('gem_floors.dart'), 'const Map<String, List<MapFloor>> kFloors').items():
        for m in rx.finditer(body):
            out[mid].append((m.group(1), _denorm(mid, _nums(m.group(2)))))
    return out


def regions():
    """[(id, map, name, kind, [(x, y)...], placeId)]"""
    src = _read('gem_regions.dart')
    out = []
    rx = re.compile(r"MapRegion\(id: '(\w+)', mapId: '(\w+)', name: '((?:[^'\\]|\\.)*)', kind: RegionKind\.(\w+),"
                    r".*?(?:placeId: '(\w+)',)?.*?points: _p\(const \[([^\]]*)\]\)\)")
    for m in rx.finditer(src):
        mid = m.group(2)
        out.append((m.group(1), mid, m.group(3).replace("\\'", "'"), m.group(4),
                    _denorm(mid, _nums(m.group(6))), m.group(5)))
    return out


def places():
    """{map: [(id, name, (x, y), category)]} from gem_map_data.dart + the Tutankhamun map."""
    out = {m: [] for m in MAPS}
    src = _read('gem_map_data.dart')
    helper = {'_cx': 'gem_complex', '_mb': 'main_building', '_mg': 'main_galleries'}
    for m in re.finditer(r"MapPlace\(\s*id: '(\w+)',\s*name: '((?:[^'\\]|\\.)*)',\s*position: (_\w+)\(([\d.]+), ([\d.]+)\),"
                         r"\s*category: PlaceCategory\.(\w+)", src):
        out[helper[m.group(3)]].append((m.group(1), m.group(2).replace("\\'", "'"),
                                        (float(m.group(4)), float(m.group(5))), m.group(6)))
    tut = _read('gem_tutankhamun_data.dart')
    for m in re.finditer(r"MapPlace\(id: '(\w+)', name: '((?:[^'\\]|\\.)*)', position: _tg\(([\d.]+), ([\d.]+)\), "
                         r"category: PlaceCategory\.(\w+)", tut):
        out['tutankhamun'].append((m.group(1), m.group(2), (float(m.group(3)), float(m.group(4))), m.group(5)))
    return out


def figure_footprints():
    """{map: [[(x, y)...]]}: the bases of the monuments in gem_figures.dart
    (statue plinths, the obelisk, the column), so routes walk around them.
    Palms have no footprint: you walk between them."""
    import math
    src = _read('gem_figures.dart')
    src = src[src.index('const Map<String, List<MapFigure>> kFigures'):]
    out = {m: [] for m in MAPS}
    cur = None
    rx = re.compile(r"MapFigure\('(\w+)', ([-\d.]+), ([-\d.]+), ([-\d.]+), ([-\d.]+), '\w+', \[([^\]]*)\]")
    for line in src.split('\n'):
        m = re.match(r"  '(\w+)': \[", line)
        if m:
            cur = m.group(1)
            continue
        m = rx.search(line)
        if not m or not cur or not m.group(6).strip():
            continue
        x, y, h, facing = map(float, m.groups()[1:5])
        u0, u1, w0, w1 = _nums(m.group(6))
        w_, h_ = SIZES[cur]
        k = min(w_, h_) * h
        fx, fy = math.cos(facing), math.sin(facing)
        lx, ly = fy, -fx
        out[cur].append([(x * w_ + (lx * pu + fx * pw) * k, y * h_ + (ly * pu + fy * pw) * k)
                         for pu, pw in ((u0, w0), (u1, w0), (u1, w1), (u0, w1))])
    return out
