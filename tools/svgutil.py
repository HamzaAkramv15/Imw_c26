import re, numpy as np
import xml.etree.ElementTree as ET
from svgpathtools import parse_path
def parse_tf(t):
    M=np.eye(3)
    if not t: return M
    for name,args in re.findall(r'(\w+)\(([^)]*)\)',t):
        a=[float(x) for x in re.split(r'[ ,]+',args.strip()) if x]
        if name=='matrix': T=np.array([[a[0],a[2],a[4]],[a[1],a[3],a[5]],[0,0,1]])
        elif name=='translate': T=np.array([[1,0,a[0]],[0,1,a[1] if len(a)>1 else 0],[0,0,1]])
        elif name=='scale': T=np.diag([a[0],a[-1],1.0])
        else: raise ValueError(name)
        M=M@T
    return M
def load_paths(fn):
    """returns list of (index, attrs, cumulative transform) for every <path>, document order"""
    root=ET.parse(fn).getroot(); out=[]; idx=[0]
    def walk(e,M):
        tag=e.tag.split('}')[-1]
        if tag=='metadata': return
        M2=M@parse_tf(e.get('transform'))
        if tag=='path':
            out.append((idx[0],dict(e.attrib),M2)); idx[0]+=1
        for c in e: walk(c,M2)
    walk(root,np.eye(3)); return out
def subpaths(d,tf,n=8):
    p=parse_path(d); res=[]
    for sp in p.continuous_subpaths():
        pts=[]
        for seg in sp:
            for t in np.linspace(0,1,n,endpoint=False):
                z=seg.point(t); v=tf@np.array([z.real,z.imag,1]); pts.append((v[0],v[1]))
        z=sp[-1].point(1); v=tf@np.array([z.real,z.imag,1]); pts.append((v[0],v[1]))
        res.append(pts)
    return res
