"""Read actual S12 exports; local CPU geometry/image/semantic accounting."""
import argparse,hashlib,io,json,struct
from pathlib import Path
import numpy as np
from PIL import Image
P=argparse.ArgumentParser();P.add_argument('--version',default='v2');P.add_argument('--source-dir');P.add_argument('--out');A=P.parse_args()
BASE=Path(A.source_dir) if A.source_dir else Path('D:/code/rmmo_runtime/art_sources/s12_residential_details_20261017')/A.version
OUT=Path(A.out) if A.out else Path('D:/code/rmmo_runtime/review_artifacts/s12_residential_details_20261017')/A.version
OUT.mkdir(parents=True,exist_ok=True)
def sha(b):return hashlib.sha256(b).hexdigest()
reports=[]
for path in sorted(BASE.glob('*.glb')):
    raw=path.read_bytes();jl=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+jl]);blob=raw[28+jl:]
    def view(i):
        v=doc['bufferViews'][i];off=v.get('byteOffset',0);return blob[off:off+v['byteLength']]
    def accessor(i):
        a=doc['accessors'][i];v=doc['bufferViews'][a['bufferView']];dt=np.dtype({5126:'<f4',5125:'<u4',5123:'<u2',5121:'u1'}[a['componentType']]);size={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']]
        return np.ndarray((a['count'],size),dtype=dt,buffer=blob,offset=v.get('byteOffset',0)+a.get('byteOffset',0),strides=(v.get('byteStride',dt.itemsize*size),dt.itemsize)).copy()
    stats={'triangles':0,'vertices':0,'primitives':0,'degenerate_triangles':0,'uv_degenerate_triangles':0,'normal_mapped_without_tangents':0,'non_finite':0,'embedded_images':[],'rgba8_mip_budget_bytes':0}
    for mesh in doc['meshes']:
        for p in mesh['primitives']:
            stats['primitives']+=1;v=accessor(p['attributes']['POSITION']);indices=accessor(p['indices']).ravel().astype(int);tri=indices.reshape(-1,3);coords=v[tri]
            stats['triangles']+=len(tri);stats['vertices']+=len(v);stats['non_finite']+=int((~np.isfinite(v)).sum())
            area=np.linalg.norm(np.cross(coords[:,1]-coords[:,0],coords[:,2]-coords[:,0]),axis=1);stats['degenerate_triangles']+=int((area<1e-10).sum())
            material=doc['materials'][p['material']]
            if material.get('normalTexture'):
                stats['normal_mapped_without_tangents']+=int('TANGENT' not in p['attributes'])
                uv=accessor(p['attributes']['TEXCOORD_0'])[tri];a=uv[:,1]-uv[:,0];b=uv[:,2]-uv[:,0];det=a[:,0]*b[:,1]-a[:,1]*b[:,0]
                stats['uv_degenerate_triangles']+=int(((np.abs(det)<1e-12)&(area>=1e-10)).sum())
    for image in doc.get('images',[]):
        encoded=view(image['bufferView']);im=Image.open(io.BytesIO(encoded));w,h=im.size;budget=0
        while True:
            budget+=w*h*4
            if w==1 and h==1:break
            w=max(1,w//2);h=max(1,h//2)
        stats['embedded_images'].append({'name':image.get('name'),'sha256':sha(encoded),'format':im.format,'size':list(im.size),'encoded_bytes':len(encoded),'rgba8_mip_budget_bytes':budget});stats['rgba8_mip_budget_bytes']+=budget
    nodes=[n for n in doc['nodes'] if 'mesh' in n];extra=[n.get('extras',{}) for n in nodes]
    row={'id':path.stem,'path':str(path),'sha256':sha(raw),'bytes':len(raw),'statistics':stats,'mesh_nodes':len(nodes),'materials':len(doc['materials']),'wind_nodes':[n['name'] for n in nodes if n.get('extras',{}).get('rmmo_wind')],'hinges':[{ 'node':n['name'],'data':n['extras']['rmmo_hinge']} for n in nodes if n.get('extras',{}).get('rmmo_hinge')],'material_parameters':doc['materials'],'notes':['RGBA8 mip accounting is a budget, not measured VRAM.','Small scarce props retain silhouette; no forced decimation/LOD added.','Final visual acceptance requires actual native captures.']}
    failures=[]
    for field in ['degenerate_triangles','uv_degenerate_triangles','normal_mapped_without_tangents','non_finite']:
        if stats[field]:failures.append(field)
    if 'residence' in path.stem:
        if len(row['hinges'])!=1:failures.append('side door hinge count')
        if any('rmmo_part' not in e for e in extra):failures.append('missing component metadata')
        if len({e.get('uuid') for e in extra})!=len(extra):failures.append('duplicate part ids')
        if any('Dormer' in n.get('name','') and n['extras']['rmmo_part']['role']!='roof' for n in nodes):failures.append('dormer does not hide with roof')
    if 'pennant' in path.stem and len(row['wind_nodes'])!=1:failures.append('cloth-only wind')
    row['failures']=failures;row['resource_passed']=not failures
    target=OUT/(path.stem+'_cpu_audit.json')
    if target.exists():raise RuntimeError('Refusing evidence overwrite: '+str(target))
    target.write_text(json.dumps(row,ensure_ascii=False,indent=2)+'\n',encoding='utf-8');reports.append(row)
    print(path.stem,stats['triangles'],'triangles',stats['uv_degenerate_triangles'],'UV degeneracies',failures,flush=True)
if not all(r['resource_passed'] for r in reports):raise SystemExit(1)
