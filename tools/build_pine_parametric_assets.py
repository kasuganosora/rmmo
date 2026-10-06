"""Annotate accepted immutable meshes; geometry/textures remain byte-identical.

UV2 carries branch IDs through Godot's vertex reordering. The original material
does not use UV2. Full branch islands are retained/removed across every LOD.
"""
import json, struct, hashlib
from pathlib import Path
import numpy as np
from scipy.spatial import cKDTree
BASE=Path('D:/code/rmmo_runtime');OUT=BASE/'assets/pine_parametric'
def read(path):
 data=path.read_bytes();n=struct.unpack_from('<I',data,12)[0];doc=json.loads(data[20:20+n]);off=20+n;size=struct.unpack_from('<I',data,off)[0]
 return doc,bytearray(data[off+8:off+8+size])
def accessor(doc,blob,index):
 a=doc['accessors'][index];v=doc['bufferViews'][a['bufferView']];dtype={5126:'<f4',5125:'<u4',5123:'<u2',5121:'u1'}[a['componentType']];width={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']]
 assert 'byteStride' not in v
 return np.frombuffer(blob,dtype=dtype,count=a['count']*width,offset=v.get('byteOffset',0)+a.get('byteOffset',0)).reshape(-1,width).copy()
def islands(pos,indices,uv):
 # glTF may split vertices at normals/UV boundaries; combine equal positions
 # within this primitive before finding complete cards/backbones.
 _,inverse=np.unique(np.round(np.column_stack((pos,uv)),5),axis=0,return_inverse=True);parent=list(range(inverse.max()+1))
 def find(i):
  while parent[i]!=i:parent[i]=parent[parent[i]];i=parent[i]
  return i
 for tri in indices.reshape(-1,3):
  a,b,c=map(lambda v:find(inverse[v]),tri);parent[b]=a;parent[c]=a
 labels=np.array([find(i) for i in inverse]);return [np.flatnonzero(labels==x) for x in np.unique(labels)]
def main():
 manifest=[]
 for variant in ['compact','mature','windswept']:
  source=BASE/f'assets/baltic_pine_dense_v3_game/pine_dense_{variant}.glb';doc,blob=read(source)
  data=np.load(OUT/(variant+'_branches.npz'));tree=cKDTree(data['points']);anchors=data['anchors'];near_centers=[];near_ids=[];distances=[]
  foliage=next(n for n in doc['nodes'] if n['name']=='Foliage')
  mappings={}
  for pindex,p in enumerate(doc['meshes'][foliage['mesh']]['primitives']):
   points=accessor(doc,blob,p['attributes']['POSITION']);indices=accessor(doc,blob,p['indices']);distance,nearest=tree.query(points);distances.extend(distance.tolist())
   labels=data['ids'][nearest]
   for group in islands(points,indices,accessor(doc,blob,p['attributes']['TEXCOORD_0'])):
    branch=np.bincount(labels[group]).argmax();labels[group]=branch
    if len(group)<=8:near_centers.append(np.unique(np.round(points[group],6),axis=0).mean(axis=0));near_ids.append(branch)
   # The accepted LOD authoring also contains split triangle cards; their
   # scale pivot is the triangle centroid rather than the quad centroid.
   for tri in indices.reshape(-1,3):
    near_centers.append(points[tri].mean(axis=0));near_ids.append(int(np.bincount(labels[tri]).argmax()))
   mappings[(foliage['mesh'],pindex)]=labels
  assert max(distances)<.0001,(variant,max(distances))
  cardtree=cKDTree(near_centers);allpos=[]
  for node in doc['nodes']:
   if 'mesh' not in node:continue
   for pi,p in enumerate(doc['meshes'][node['mesh']]['primitives']):
    points=accessor(doc,blob,p['attributes']['POSITION']);allpos.extend(points.tolist())
    if node['name']=='Trunk':continue
    labels=mappings.get((node['mesh'],pi))
    if labels is None:
     labels=np.zeros(len(points),dtype=int)
     for group in islands(points,accessor(doc,blob,p['indices']),accessor(doc,blob,p['attributes']['TEXCOORD_0'])):
      distance,index=cardtree.query(np.unique(np.round(points[group],6),axis=0).mean(axis=0));assert distance<.001,(variant,distance)
      labels[group]=near_ids[index]
    uv=np.zeros((len(points),2),dtype='<f4');uv[:,0]=labels+1
    while len(blob)%4:blob.append(0)
    view=len(doc['bufferViews']);doc['bufferViews'].append({'buffer':0,'byteOffset':len(blob),'byteLength':uv.nbytes,'target':34962});blob.extend(uv.tobytes())
    acc=len(doc['accessors']);doc['accessors'].append({'bufferView':view,'componentType':5126,'count':len(uv),'type':'VEC2'})
    p['attributes']['TEXCOORD_1']=acc
  points=np.array(allpos);height=float(points[:,1].max());base=float(min(p[1] for p in near_centers));recipe={'version':1,'variant':variant,'height':height,'bare_trunk':base,'anchors':anchors.tolist()}
  for node in doc['nodes']:
   if 'mesh' in node:node.setdefault('extras',{})['rmmo_tree_recipe']=dict(recipe,role='trunk' if node['name']=='Trunk' else 'foliage')
  doc['buffers'][0]['byteLength']=len(blob);encoded=json.dumps(doc,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4)
  payload=struct.pack('<III',0x46546c67,2,28+len(encoded)+len(blob))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+struct.pack('<II',len(blob),0x004e4942)+blob
  target=OUT/(variant+'.glb');target.write_bytes(payload)
  manifest.append({'variant':variant,'file':str(target),'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'height':height,'bare_trunk':base,'branch_count':len(anchors),'mapping_max_error':max(distances)})
 (OUT/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8');print(json.dumps(manifest,indent=2))
if __name__=='__main__':main()
