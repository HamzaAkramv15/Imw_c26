"""Checks the painter's-order rule used by _orderedSlabs in museum_map_canvas.dart against the real
galleries data: counts occluding pairs drawn in the wrong order by the old centroid sort vs the new rule."""
import re,math
W,H=1400.0,1080.0; u=min(W,H)
import os
t=open(os.path.join(os.path.dirname(os.path.abspath(__file__)),'..','lib','data','gem_blocks.dart')).read()
sec=t[t.index("'main_galleries'"):]; sec=sec[:sec.index("'tutankhamun'")] if "'tutankhamun'" in sec else sec
S=[]
for m in re.finditer(r"MapBlock\('(\w+)', ([\d.]+), \[([^\]]*)\]",sec):
    v=[float(x) for x in m.group(3).split(',')]
    S.append(dict(kind=m.group(1),h=float(m.group(2))*u,pts=[(v[i]*W,v[i+1]*H) for i in range(0,len(v),2)]))
def hull(p):
    p=sorted(set(p))
    if len(p)<3: return p
    cr=lambda o,a,b:(a[0]-o[0])*(b[1]-o[1])-(a[1]-o[1])*(b[0]-o[0])
    lo=[]
    for q in p:
        while len(lo)>=2 and cr(lo[-2],lo[-1],q)<=0: lo.pop()
        lo.append(q)
    up=[]
    for q in reversed(p):
        while len(up)>=2 and cr(up[-2],up[-1],q)<=0: up.pop()
        up.append(q)
    return lo[:-1]+up[:-1]
def sign(poly):
    s=sum(poly[k][0]*poly[(k+1)%len(poly)][1]-poly[(k+1)%len(poly)][0]*poly[k][1] for k in range(len(poly)))
    return 1 if s>=0 else -1
for s in S:
    s['hull']=hull(s['pts']); s['sg']=sign(s['hull'])
    xs=[p[0] for p in s['pts']]; ys=[p[1] for p in s['pts']]
    s['bb']=(min(xs),min(ys),max(xs),max(ys)); s['c']=(sum(xs)/len(xs),sum(ys)/len(ys))
def sep(p,q,vx,vy):
    h=p['hull'];n=len(h)
    if n<3: return None
    for i in range(n):
        a0=h[i];a1=h[(i+1)%n];ex=a1[0]-a0[0];ey=a1[1]-a0[1];L=math.hypot(ex,ey)
        if L<1e-9: continue
        nx=p['sg']*ey/L; ny=-p['sg']*ex/L
        if all((o[0]-a0[0])*nx+(o[1]-a0[1])*ny>=-0.05 for o in q['hull']): return nx*vx+ny*vy
    return None
def front(a,b,vx,vy):
    d=sep(a,b,vx,vy)
    if d is not None and abs(d)>1e-4: return 1 if d>0 else -1
    e=sep(b,a,vx,vy)
    if e is not None and abs(e)>1e-4: return -1 if e>0 else 1
    return 0
KT=1.35
def sat_overlap(P,Q,eps=0.05):
    for poly in (P,Q):
        n=len(poly)
        for i in range(n):
            a=poly[i];b=poly[(i+1)%n];ex=b[0]-a[0];ey=b[1]-a[1];L=math.hypot(ex,ey)
            if L<1e-9: continue
            nx,ny=ey/L,-ex/L
            p0=[x*nx+y*ny for x,y in P]; q0=[x*nx+y*ny for x,y in Q]
            if max(p0)<=min(q0)+eps or max(q0)<=min(p0)+eps: return False
    return True
def order(yaw):
    vx,vy=math.sin(yaw),math.cos(yaw); n=len(S)
    cs,sn=math.cos(yaw),math.sin(yaw)
    sw=[]
    for s in S:
        pts=[(x*cs-y*sn,x*sn+y*cs) for x,y in s['hull']]
        sw.append(hull(pts+[(x,y-s['h']*KT) for x,y in pts]))
    depth=[s['c'][0]*vx+s['c'][1]*vy for s in S]
    reach=max(s['h'] for s in S)*2.5+1
    after=[[] for _ in range(n)];wait=[0]*n;rel={}
    for i in range(n):
        b=S[i]['bb']
        for j in range(i+1,n):
            c=S[j]['bb']
            if b[0]-reach>c[2] or c[0]>b[2]+reach or b[1]-reach>c[3] or c[1]>b[3]+reach: continue
            if not sat_overlap(sw[i],sw[j]): continue
            r=front(S[i],S[j],vx,vy); rel[(i,j)]=r
            if r>0: after[i].append(j);wait[j]+=1
            elif r<0: after[j].append(i);wait[i]+=1
    done=[False]*n;out=[];cyc=0
    for _ in range(n):
        best=-1
        for i in range(n):
            if done[i] or wait[i]>0: continue
            if best<0 or depth[i]<depth[best]: best=i
        if best<0:
            cyc+=1
            for i in range(n):
                if not done[i] and (best<0 or depth[i]<depth[best]): best=i
        done[best]=True;out.append(best)
        for t in after[best]: wait[t]-=1
    return out,rel,depth,cyc
print('slabs',len(S))
for deg in (0,35,90,150,215,300):
    yaw=math.radians(deg)
    out,rel,depth,cyc=order(yaw)
    pos={s:i for i,s in enumerate(out)}
    cen=sorted(range(len(S)),key=lambda i:depth[i]); cpos={s:i for i,s in enumerate(cen)}
    dec=[(i,j,r) for (i,j),r in rel.items() if r!=0]
    bad_new=sum(1 for i,j,r in dec if (pos[j]>pos[i])!=(r>0))
    bad_old=sum(1 for i,j,r in dec if (cpos[j]>cpos[i])!=(r>0))
    print(f'yaw {deg:3d}: decided pairs {len(dec):5d} | wrong order: centroid sort {bad_old:4d}  new {bad_new:3d}  cycles {cyc}')
