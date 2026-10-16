"""Fix final GLB triangle clearance and thin roll shading; preserve PBR bytes."""
import copy, hashlib, json, struct, sys
from pathlib import Path
import numpy as np
from mathutils import Vector, Matrix, Quaternion
from mathutils.bvhtree import BVHTree
sys.path.insert(0,str(Path(__file__).parent))
from optimize_bridge_pennant_glb import Glb, digest, semantic

ART=Path('D:/code/rmmo_runtime/art_sources/axel_market_realism_20261016')
OUT=ART/'v6'

def array(g,index):
    a=g.j['accessors'][index];v=g.j['bufferViews'][a['bufferView']]
    dtype={5126:'<f4',5125:'<u4',5123:'<u2'}[a['componentType']]
    width={'VEC3':3,'VEC2':2,'VEC4':4,'SCALAR':1}[a['type']]
    assert 'byteStride' not in v
    return np.frombuffer(g.blob(a['bufferView']),dtype=dtype,offset=a.get('byteOffset',0),count=a['count']*width).reshape(-1,width).copy()

def transform(node):
    assert 'matrix' not in node
    q=node.get('rotation',[0,0,0,1])
    return Matrix.LocRotScale(Vector(node.get('translation',[0,0,0])),Quaternion((q[3],*q[:3])),Vector(node.get('scale',[1,1,1])))

def mesh(g,name):
    node=next(n for n in g.j['nodes'] if n['name']==name)
    p=g.j['meshes'][node['mesh']]['primitives'][0]
    pos=array(g,p['attributes']['POSITION']);idx=array(g,p['indices']).ravel().reshape(-1,3)
    return node,p,pos,idx,[transform(node)@Vector(v) for v in pos]

def frames(pos,uv,idx,normal=None):
    tri=pos[idx];e1=tri[:,1]-tri[:,0];e2=tri[:,2]-tri[:,0]
    if normal is None:
        normal=np.zeros_like(pos,dtype=np.float64)
        face=np.cross(e1,e2)
        for k in range(3):np.add.at(normal,idx[:,k],face)
        normal/=np.maximum(np.linalg.norm(normal,axis=1)[:,None],1e-20)
    uvtri=uv[idx];d1=uvtri[:,1]-uvtri[:,0];d2=uvtri[:,2]-uvtri[:,0]
    det=d1[:,0]*d2[:,1]-d2[:,0]*d1[:,1];r=np.zeros_like(det);np.divide(1,det,out=r,where=np.abs(det)>1e-16)
    tf=(e1*d2[:,1,None]-e2*d1[:,1,None])*r[:,None]
    bf=(e2*d1[:,0,None]-e1*d2[:,0,None])*r[:,None]
    t=np.zeros_like(pos,dtype=np.float64);b=t.copy()
    for k in range(3):np.add.at(t,idx[:,k],tf);np.add.at(b,idx[:,k],bf)
    t-=normal*np.sum(normal*t,axis=1)[:,None]
    ln=np.linalg.norm(t,axis=1);assert np.min(ln)>1e-12
    t/=ln[:,None]
    sign=np.where(np.sum(np.cross(normal,t)*b,axis=1)<0,-1,1)
    return normal.astype('<f4'),np.column_stack([t,sign]).astype('<f4')

def run(asset):
    source=ART/'v5'/(asset+'.glb');target=OUT/(asset+'.glb')
    assert not target.exists()
    g=Glb(source);doc=copy.deepcopy(g.j);views={i:g.blob(i) for i in range(len(doc['bufferViews']))}
    def replace(index,values):
        a=doc['accessors'][index];view=a['bufferView']
        assert sum(x.get('bufferView')==view for x in doc['accessors'])==1
        values=np.asarray(values);a['count']=len(values);a.pop('byteOffset',None)
        if values.dtype.kind=='f':values=values.astype('<f4');a['componentType']=5126
        else:values=values.astype('<u4');a['componentType']=5125
        if 'min' in a:a['min']=values.min(axis=0).reshape(-1).tolist()
        if 'max' in a:a['max']=values.max(axis=0).reshape(-1).tolist()
        views[view]=values.tobytes()
    _,_,_,ci,cp=mesh(g,'CanopyCloth');node,prim,pos,idx,points=mesh(g,'CanopyTrim')
    tree=BVHTree.FromPolygons(cp,ci,all_triangles=True)
    before=len(tree.overlap(BVHTree.FromPolygons(points,idx,all_triangles=True)))
    original=pos.copy();world=transform(node);inv=world.inverted();groups={}
    for i,p in enumerate(points):groups.setdefault(tuple(p),[]).append(i)
    key_for={i:key for key,ids in groups.items() for i in ids}
    directions=[]
    for tri in idx:
        p=[points[i] for i in tri];center=sum(p,Vector())/3
        cross=(p[1]-p[0]).cross(p[2]-p[0]);axis=0 if abs(cross.x)>abs(cross.z) else 2
        n=Vector();n[axis]=1 if center[axis]>0 else -1;directions.append(n)
    weights=[(i/6,j/6,1-(i+j)/6) for i in range(7) for j in range(7-i)]
    def samples():
        for tri,n in zip(idx,directions):
            p=[points[i] for i in tri]
            for u,v,w in weights:
                x=p[0]*u+p[1]*v+p[2]*w;hit,_,_,_=tree.ray_cast(x+n*.05,-n,.1)
                if hit is not None:yield (x-hit).dot(n),tri,n
    min_before=min(x[0] for x in samples())
    for iteration in range(10):
        corrections={}
        for distance,tri,n in samples():
            if distance<.00053:
                for i in tri:
                    key=key_for[i];shift=.00055-distance
                    if shift>corrections.get(key,(0,None))[0]:corrections[key]=(shift,n)
        if not corrections:break
        for key,(shift,n) in corrections.items():
            for i in groups[key]:points[i]+=shift*n
    gaps=[x[0] for x in samples()]
    assert min(gaps)>.00050
    after=len(tree.overlap(BVHTree.FromPolygons(points,idx,all_triangles=True)))
    assert after==0
    pos=np.array([inv@p for p in points],dtype='<f4')
    normals,tangents=frames(pos,array(g,prim['attributes']['TEXCOORD_0']),idx)
    for name,value in [('POSITION',pos),('NORMAL',normals),('TANGENT',tangents)]:replace(prim['attributes'][name],value)
    report={'asset':asset,'source':str(source),'source_sha256':digest(source),'export_triangle_intersections_before':before,'export_triangle_intersections_after':after,'minimum_gap_before_m':min_before,'minimum_gap_after_m':min(gaps),'dense_samples':len(gaps),'maximum_trim_shift_m':float(np.linalg.norm(pos-original,axis=1).max()),'geometry_triangles_added':0,'pbr_bytes_unchanged':True}
    if asset=='scroll':
        _,prim,pos,idx,_=mesh(g,'GoodsOpaque');attrs={name:array(g,a) for name,a in prim['attributes'].items()}
        tris=pos[idx];face=np.cross(tris[:,1]-tris[:,0],tris[:,2]-tris[:,0]);face/=np.linalg.norm(face,axis=1)[:,None]
        classes=np.where(np.abs(face[:,2])>.98,np.where(face[:,2]>0,1,2),0)
        # End cuts have independent normals. Body normals average only body
        # faces, preserving smooth spiral curvature; ties remain smooth too.
        normals_by_key={}
        for tri,normal,cls in zip(idx,face,classes):
            for i in tri:
                key=(*pos[i],int(cls));normals_by_key.setdefault(key,np.zeros(3));normals_by_key[key]+=normal
        old_ids=[];new_normals=[];mapped={};indices=[]
        for tri,cls in zip(idx,classes):
            out=[]
            for i in tri:
                key=(int(i),int(cls))
                if key not in mapped:
                    mapped[key]=len(old_ids);old_ids.append(i);normal=normals_by_key[(*pos[i],int(cls))];new_normals.append(normal/np.linalg.norm(normal))
                out.append(mapped[key])
            indices.append(out)
        indices=np.asarray(indices,dtype='<u4');normal=np.array(new_normals)
        normal,tangent=frames(pos[old_ids],attrs['TEXCOORD_0'][old_ids],indices,normal)
        for name,values in attrs.items():replace(prim['attributes'][name],normal if name=='NORMAL' else tangent if name=='TANGENT' else values[old_ids])
        replace(prim['indices'],indices.reshape(-1,1))
        assert np.array_equal(pos[idx],pos[old_ids][indices])
        assert np.array_equal(attrs['TEXCOORD_0'][idx],attrs['TEXCOORD_0'][old_ids][indices])
        report.update(roll_end_triangles=int(sum(classes!=0)),paper_position_uv_corner_identity=True,roll_old_vertices=len(pos),roll_new_vertices=len(old_ids))
    binary=bytearray()
    for i,view in enumerate(doc['bufferViews']):
        binary+=b'\0'*(-len(binary)%4);view['byteOffset']=len(binary);view['byteLength']=len(views[i]);binary+=views[i]
    doc['buffers'][0]['byteLength']=len(binary);data=json.dumps(doc,separators=(',',':'),ensure_ascii=False).encode();data+=b' '*(-len(data)%4);binary+=b'\0'*(-len(binary)%4)
    target.write_bytes(struct.pack('<III',0x46546c67,2,28+len(data)+len(binary))+struct.pack('<II',len(data),0x4e4f534a)+data+struct.pack('<II',len(binary),0x004e4942)+binary)
    changed=Glb(target)
    oldgraph=semantic(g);newgraph=semantic(changed)
    for key in ['materials','textures','images','samplers','nodes']:assert g.j.get(key)==changed.j.get(key),key
    for image in g.j['images']:assert g.blob(image['bufferView'])==changed.blob(image['bufferView'])
    for node in g.j['nodes']:
        if node['name'] not in ['CanopyTrim']+(['GoodsOpaque'] if asset=='scroll' else []):assert oldgraph['meshes'][node['mesh']]==newgraph['meshes'][node['mesh']]
    report.update(candidate=str(target),candidate_sha256=digest(target),patch_sha256=digest(Path(__file__)),other_meshes_exact=True,visual_accepted=False)
    (OUT/(asset+'_geometry_patch.json')).write_text(json.dumps(report,indent=2))
    g.close();changed.close();print('PATCH_RESULT',json.dumps(report),flush=True)

if __name__=='__main__':
    OUT.mkdir(exist_ok=True)
    for asset in ['pottery','scroll','potion','ore']:run(asset)
