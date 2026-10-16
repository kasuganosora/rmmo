"""Read-only actual GLB basal geometry; never imports textures or changes resources."""
import json,struct,pathlib,hashlib,numpy as np
OUT=pathlib.Path('D:/code/rmmo_runtime/review_artifacts/axel_town_layout_20261016')
plan=json.loads((OUT/'functional_vegetation_plan.json').read_text(encoding='utf-8'))
def hull(points):
 ps=sorted(set((round(float(x),8),round(float(z),8)) for x,z in points))
 def cross(o,a,b):return (a[0]-o[0])*(b[1]-o[1])-(a[1]-o[1])*(b[0]-o[0])
 lo=[];hi=[]
 for p in ps:
  while len(lo)>=2 and cross(lo[-2],lo[-1],p)<=0:lo.pop()
  lo.append(p)
 for p in reversed(ps):
  while len(hi)>=2 and cross(hi[-2],hi[-1],p)<=0:hi.pop()
  hi.append(p)
 return [list(x) for x in lo[:-1]+hi[:-1]]
def clipped(tri,y):
 out=[]
 for i,p in enumerate(tri):
  q=tri[(i+1)%len(tri)];inside=p[1]<=y;nextin=q[1]<=y
  if inside:out.append(p)
  if inside!=nextin:out.append(p+(q-p)*((y-p[1])/(q[1]-p[1])))
 return out
res={'mode':'read_only_actual_indexed_GLB_triangles','plan_sha256':hashlib.sha256((OUT/'functional_vegetation_plan.json').read_bytes()).hexdigest(),'assets':[],'limitations':['Basal bands are actual geometry measurements, not an invented root radius or automatic approval to plant on any slope.','No asset, terrain, or map is modified; final native collision/support acceptance remains required.']}
for a in plan['assets'][:2]:
 path=pathlib.Path(a['models'][0]['path']);raw=path.read_bytes();sha=hashlib.sha256(raw).hexdigest();assert sha==a['models'][0]['sha256'];size,typ=struct.unpack_from('<II',raw,12);assert typ==0x4e4f534a;g=json.loads(raw[20:20+size]);bo=28+size;assert struct.unpack_from('<I',raw,24+size)[0]==0x004e4942
 def accessor(i):
  ar=g['accessors'][i];bv=g['bufferViews'][ar['bufferView']];assert not ar.get('sparse');dt={5126:'<f4',5125:'<u4',5123:'<u2',5121:'u1'}[ar['componentType']];n={'VEC3':3,'VEC2':2,'SCALAR':1}[ar['type']];return np.ndarray((ar['count'],n),dtype=dt,buffer=raw,offset=bo+bv.get('byteOffset',0)+ar.get('byteOffset',0),strides=(bv.get('byteStride',np.dtype(dt).itemsize*n),np.dtype(dt).itemsize)).copy()
 if a['kind']=='prefab_path':
  rec=json.loads(pathlib.Path(a['asset_id']).read_text(encoding='utf-8'))['records'][0];low=np.array(rec['bounds_position']);bs=np.array(rec['bounds_size']);assert rec['rotation']==[0,0,0] and rec['size']==[1,1,1]
 else:low=np.array(a['entry']['bounds_position']);bs=np.array(a['bounds_size'])
 # Local origin offset after the helper places complete-bounds center XZ and bottom Y.
 shift=np.array([-low[0]-bs[0]/2,-low[1],-low[2]-bs[2]/2])
 parts=[];tris=[]
 for ni,n in enumerate(g['nodes']):
  if n.get('extras',{}).get('rmmo_collision')!='block':continue
  assert not any(k in n for k in ['matrix','rotation','translation','scale']);assert ni in g['scenes'][g.get('scene',0)]['nodes']
  for pi,prim in enumerate(g['meshes'][n['mesh']]['primitives']):
   assert prim.get('mode',4)==4;vs=accessor(prim['attributes']['POSITION']).astype('f8')+shift;ix=accessor(prim['indices']).ravel();ts=vs[ix].reshape((-1,3,3));valid=np.linalg.norm(np.cross(ts[:,1]-ts[:,0],ts[:,2]-ts[:,0]),axis=1)>1e-12;ts=ts[valid];tris.extend(ts);parts.append({'node_index':ni,'node_name':n['name'],'mesh':n['mesh'],'primitive':pi,'valid_triangles':len(ts),'position_accessor':prim['attributes']['POSITION'],'index_accessor':prim['indices']})
 tris=np.asarray(tris);base=float(tris[:,:,1].min());asset={'label':a['label'],'path':str(path),'sha256':sha,'bytes':len(raw),'full_crown_size':a['bounds_size'],'native_centered_origin_shift':shift.tolist(),'basal_min_y':base,'parts':parts,'bands':[]}
 for h in [.02,.05,.1,.2,.35,.5]:
  clip=[];touched=0
  for tri in tris[tris[:,:,1].min(axis=1)<=base+h]:
   pts=clipped(tri,base+h)
   if len(pts)>=3:clip.extend(pts);touched+=1
  ar=np.asarray(clip);poly=hull(ar[:,[0,2]]);asset['bands'].append({'height_above_actual_min_m':h,'contributing_triangles':touched,'aabb_min':ar.min(axis=0).tolist(),'aabb_max':ar.max(axis=0).tolist(),'xz_size':(ar.max(axis=0)-ar.min(axis=0))[[0,2]].tolist(),'hull_xz':poly})
 basal=tris[tris[:,:,1].min(axis=1)<=base+.35];verts=np.unique(basal.reshape((-1,3)),axis=0);verts=verts[verts[:,1]<=base+.35]
 asset['actual_bottom_vertices_below_035']=verts.tolist();res['assets'].append(asset)
 print(a['label'].encode('unicode_escape').decode(),[(b['height_above_actual_min_m'],[round(x,3) for x in b['xz_size']],b['contributing_triangles']) for b in asset['bands']])
res['script_sha256']=hashlib.sha256(pathlib.Path(__file__).read_bytes()).hexdigest();(OUT/'tree_basal_geometry_probe.json').write_text(json.dumps(res,indent=2,ensure_ascii=False),encoding='utf-8')
