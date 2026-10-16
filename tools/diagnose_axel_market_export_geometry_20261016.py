"""CPU Blender BVH diagnostic on actual exported triangles, without writes."""
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parent))
import numpy as np
from mathutils import Vector, Matrix, Quaternion
from mathutils.bvhtree import BVHTree
from optimize_bridge_pennant_glb import Glb
def array(g,index):
    a=g.j['accessors'][index];v=g.j['bufferViews'][a['bufferView']]
    dtype={5126:'<f4',5125:'<u4',5123:'<u2'}[a['componentType']]
    width={'VEC3':3,'VEC2':2,'VEC4':4,'SCALAR':1}[a['type']]
    assert 'byteStride' not in v
    return np.frombuffer(g.blob(a['bufferView']),dtype=dtype,offset=a.get('byteOffset',0),count=a['count']*width).reshape(-1,width)

def transform(node):
    assert 'matrix' not in node
    q=node.get('rotation',[0,0,0,1])
    return Matrix.LocRotScale(Vector(node.get('translation',[0,0,0])),Quaternion((q[3],*q[:3])),Vector(node.get('scale',[1,1,1])))

def mesh(g,name):
    node=next(n for n in g.j['nodes'] if n['name']==name)
    p=g.j['meshes'][node['mesh']]['primitives'][0]
    pos=array(g,p['attributes']['POSITION']);idx=array(g,p['indices']).ravel().reshape(-1,3)
    return node,p,pos,idx,[transform(node)@Vector(v) for v in pos]

g=Glb(Path('D:/code/rmmo_runtime/art_sources/axel_market_realism_20261016/v5/pottery.glb'))
_,_,_,ci,cp=mesh(g,'CanopyCloth');_,_,_,ti,tp=mesh(g,'CanopyTrim')
tree=BVHTree.FromPolygons(cp,ci,all_triangles=True)
overlaps=tree.overlap(BVHTree.FromPolygons(tp,ti,all_triangles=True))
print('ACTUAL_EXPORTED_TRIANGLE_INTERSECTIONS',len(overlaps))
gap=[]
for tri in ti:
    p=[tp[i] for i in tri];center=sum(p,Vector())/3
    cross=(p[1]-p[0]).cross(p[2]-p[0]);axis=0 if abs(cross.x)>abs(cross.z) else 2
    normal=Vector();normal[axis]=1 if center[axis]>0 else -1
    for i in range(7):
        for j in range(7-i):
            x=p[0]*(i/6)+p[1]*(j/6)+p[2]*(1-(i+j)/6)
            hit,_,_,_=tree.ray_cast(x+normal*.05,-normal,.1)
            if hit is not None:gap.append((x-hit).dot(normal))
print('GAP_MIN_MAX',min(gap),max(gap),'NEGATIVE',sum(v<0 for v in gap),'COUNT',len(gap))
g.close()
