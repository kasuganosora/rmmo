"""Read-only GLB geometry inventory for macro placement, no material loading."""
import hashlib, json, struct
from pathlib import Path
import numpy as np

OUT=Path('D:/code/rmmo_runtime/review_artifacts/axel_town_houses_20261014')
ASSETS=Path('D:/code/rmmo_runtime/packs/default/assets')
SOURCES={'guild':'7824a14b75aa5ab2e65e785199391a60594706fad17cab9a448a15e8a48d09fd','alarm':'af248d5044ebad82c27a48d1f4b9be903cf884ea518d5f939b60699199db638e'}

def inspect(key,sha):
    raw=(ASSETS/(sha+'.glb')).read_bytes(); offset=12; data=None; binary=None
    while offset<len(raw):
        length,kind=struct.unpack_from('<II',raw,offset);offset+=8
        block=raw[offset:offset+length];offset+=length
        if kind==0x4E4F534A:data=json.loads(block)
        elif kind==0x004E4942:binary=block
    def accessor(index):
        a=data['accessors'][index];v=data['bufferViews'][a['bufferView']]
        dtype={5126:'<f4',5125:'<u4',5123:'<u2',5121:'u1'}[a['componentType']]
        n={'VEC3':3,'SCALAR':1}[a['type']];size=np.dtype(dtype).itemsize
        return np.ndarray((a['count'],n),dtype=dtype,buffer=binary,offset=v.get('byteOffset',0)+a.get('byteOffset',0),strides=(v.get('byteStride',n*size),size)).copy()
    def matrix(node):
        if 'matrix' in node:return np.array(node['matrix']).reshape((4,4),order='F')
        x,y,z,w=node.get('rotation',[0,0,0,1]);m=np.eye(4)
        m[:3,:3]=np.array([[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],[2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],[2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]])@np.diag(node.get('scale',[1,1,1]))
        m[:3,3]=node.get('translation',[0,0,0]);return m
    rows=[]
    def walk(i,parent):
        node=data['nodes'][i];pose=parent@matrix(node)
        if 'mesh' in node:
            arrays=[]
            for primitive in data['meshes'][node['mesh']]['primitives']:
                a=accessor(primitive['attributes']['POSITION']);arrays.append(a@pose[:3,:3].T+pose[:3,3])
            vertices=np.concatenate(arrays)
            rows.append({'node':i,'name':node.get('name',''),'min':vertices.min(0).tolist(),'max':vertices.max(0).tolist(),'extras':node.get('extras',{}),'vertices':len(vertices)})
        for child in node.get('children',[]):walk(child,pose)
    for i in data['scenes'][data.get('scene',0)]['nodes']:walk(i,np.eye(4))
    result={'source':str(ASSETS/(sha+'.glb')),'sha256':hashlib.sha256(raw).hexdigest(),'min':np.array([r['min'] for r in rows]).min(0).tolist(),'max':np.array([r['max'] for r in rows]).max(0).tolist(),'meshes':rows}
    (OUT/(key+'_macro_source_geometry.json')).write_text(json.dumps(result,indent=2,ensure_ascii=False),encoding='utf8')
    print(json.dumps({'source':key,'bounds':[result['min'],result['max']],'meshes':len(rows),'report':str(OUT/(key+'_macro_source_geometry.json'))},ensure_ascii=False))

if __name__=='__main__':
    for key,sha in SOURCES.items():inspect(key,sha)
