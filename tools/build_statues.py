"""Stepped Ramesses II figures from the plan's silhouette paths (#2c3438, paths 88-119
of assets/maps/light/main_building.svg).  Output: Dart MapBlock lines (normalised 0..1)."""
import sys; sys.path.insert(0,'.')
from svgutil import *
from shapely.geometry import Polygon, box
from shapely.ops import unary_union
SVG='/home/claude/Imw_c26/assets/maps/light/main_building.svg'
W,H=1625.0,885.0
P={i:(a,M) for i,a,M in load_paths(SVG)}
# y cuts (SVG px): head | torso | legs | base      heights are fractions of short side
STATUES={
 'A':dict(ids=range(88,104),placeId='mb_1',cuts=(262,316,375),h=(0.048,0.036,0.022,0.010)),
 'B':dict(ids=range(104,120),placeId='mb_5',cuts=(232,274,292),h=(0.040,0.030,0.018,0.008)),
}
def silhouette(ids):
    polys=[]
    for i in ids:
        a,M=P[i]
        for sp in subpaths(a['d'],M,6):
            if len(sp)>=4:
                pg=Polygon(sp).buffer(0)
                if pg.area>0.5: polys.append(pg)
    return unary_union(polys).buffer(0.25).buffer(-0.25)
def parts(g):
    return list(g.geoms) if g.geom_type=='MultiPolygon' else [g]
out=[]
for name,c in STATUES.items():
    sil=silhouette(c['ids']); x0,y0,x1,y1=sil.bounds
    cuts=c['cuts']; bands=[(y0-1,cuts[0]),(cuts[0],cuts[1]),(cuts[1],cuts[2]),(cuts[2],y1+1)]
    for (ya,yb),h,label in zip(bands,c['h'],('head','torso','legs','base')):
        for pg in parts(sil.intersection(box(x0-1,ya,x1+1,yb))):
            if pg.area<1.0: continue
            pg=pg.buffer(-0.35).buffer(0.35)          # drop hairline slivers
            if pg.is_empty or pg.geom_type!='Polygon': 
                cand=[q for q in parts(pg) if q.area>=1.0]
                if not cand: continue
                pg=max(cand,key=lambda q:q.area)
            pg=pg.simplify(0.35)
            xy=list(pg.exterior.coords)[:-1]
            flat=','.join(f'{x/W:.4f},{y/H:.4f}' for x,y in xy)
            pid=f", '{c['placeId']}'" if label=='base' else ''
            out.append(f"    MapBlock('statue', {h}, [{flat.replace(',',', ',1) if False else flat}]{pid}), // {name} {label}")
    print(name,sil.bounds,len(out),file=sys.stderr)
open('statues.dart.txt','w').write('\n'.join(out)+'\n')
