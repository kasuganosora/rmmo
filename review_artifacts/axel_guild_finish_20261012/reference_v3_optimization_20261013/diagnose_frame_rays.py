import sys,json,math
from pathlib import Path
import numpy as np
sys.path.insert(0,'D:/code/rmmo/tools')
from audit_guild_reference_resources import parse,values
ROOT=Path(__file__).resolve().parent
doc,binary,digest,_=parse(Path('D:/code/rmmo_runtime/art_sources/axel_guild/repair_v3/axel_guild_repaired.glb'))
triangles=[];owners=[];meta=[]
def matrix(node):
    if 'matrix' in node:return np.array(node['matrix']).reshape(4,4).T
    x,y,z,w=node.get('rotation',[0,0,0,1])
    r=np.array([[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],[2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],[2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]])
    m=np.eye(4);m[:3,:3]=r@np.diag(node.get('scale',[1,1,1]));m[:3,3]=node.get('translation',[0,0,0]);return m
def visit(i,parent):
    n=doc['nodes'][i];m=parent@matrix(n)
    if 'mesh' in n:
        for p in doc['meshes'][n['mesh']]['primitives']:
            v=values(doc,binary,p['attributes']['POSITION']);v=v@m[:3,:3].T+m[:3,3]
            ix=values(doc,binary,p['indices']).ravel() if 'indices' in p else np.arange(len(v))
            t=v[ix].reshape(-1,3,3);o=len(meta);meta.append({'node':i,'name':n.get('name'),'mesh':n['mesh'],'triangles':len(t),'extras':n.get('extras',{}),'material':doc['materials'][p['material']].get('name')});triangles.append(t);owners.extend([o]*len(t))
    for c in n.get('children',[]):visit(c,m)
for n in doc['scenes'][doc.get('scene',0)]['nodes']:visit(n,np.eye(4))
triangles=np.concatenate(triangles);owners=np.array(owners);e1=triangles[:,1]-triangles[:,0];e2=triangles[:,2]-triangles[:,0]
def ray(eye,aim,fov,pixel):
    eye=np.array(eye);f=np.array(aim)-eye;f/=np.linalg.norm(f);r=np.cross(f,[0,1,0]);r/=np.linalg.norm(r);u=np.cross(r,f)
    x,y=pixel;d=f+r*((2*(x+.5)/1400-1)*1.4*math.tan(math.radians(fov/2)))+u*((1-2*(y+.5)/1000)*math.tan(math.radians(fov/2)));d/=np.linalg.norm(d)
    h=np.cross(d,e2);det=np.einsum('ij,ij->i',e1,h);inv=np.zeros_like(det);mask=np.abs(det)>1e-10;inv[mask]=1/det[mask]
    s=eye-triangles[:,0];a=inv*np.einsum('ij,ij->i',s,h);q=np.cross(s,e1);b=inv*(q@d);dist=inv*np.einsum('ij,ij->i',e2,q)
    hit=np.flatnonzero(mask&(a>=0)&(b>=0)&(a+b<=1)&(dist>0));hit=hit[np.argsort(dist[hit])][:8]
    return {'pixel':[x,y],'hits':[dict(meta[owners[j]],distance=float(dist[j]),position=(eye+d*dist[j]).tolist(),triangle=triangles[j].tolist()) for j in hit]}
tests=[('washroom',[28.1,6.15,-9.2],[30.4,5.5,-11.6],76,[(405,188),(363,208),(375,476),(310,480),(350,182),(350,198)]),('fanlight',[24.5,2.5,-7.3],[24.65,2.9,-10.9],38,[(506,416),(889,421)]),('stair',[12.5,1.7,-9.9],[3,5,-9.9],66,[(1017,605)])]
out={'source_sha256':digest,'rays':[]}
for name,eye,aim,fov,points in tests:
    for p in points:
        row=ray(eye,aim,fov,p);row['view']=name;out['rays'].append(row)
(ROOT/(sys.argv[1] if len(sys.argv)>1 else 'frame_rays.json')).write_text(json.dumps(out,indent=2))
for r in out['rays']:
    print(r['view'],r['pixel'],[(h['name'],h['triangles'],round(h['distance'],7),h['extras'].get('rmmo_auto_lod',False)) for h in r['hits'][:4]])
