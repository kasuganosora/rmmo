"""Independent exported-GLB CPU checks; does not replace engine/GPU acceptance."""
from pathlib import Path
import io, json, struct, hashlib, sys, math
import numpy as np
from PIL import Image

base=Path('D:/code/rmmo_runtime/art_sources/axel_landmarks_20261016/guardhouse')
version=sys.argv[1] if len(sys.argv)>1 else 'v2'
source=base/version/'axel_guardhouse.glb';raw=source.read_bytes()
size=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+size]);binary=raw[28+size:]
sha=lambda b:hashlib.sha256(b).hexdigest()
checks=[]
def check(name,ok,detail=None):checks.append({'name':name,'pass':bool(ok),'detail':detail})
def accessor(i):
 a=doc['accessors'][i];v=doc['bufferViews'][a['bufferView']];n={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']]
 dt={5120:'i1',5121:'u1',5122:'<i2',5123:'<u2',5125:'<u4',5126:'<f4'}[a['componentType']]
 start=v.get('byteOffset',0)+a.get('byteOffset',0);width=np.dtype(dt).itemsize*n;stride=v.get('byteStride',width)
 return np.ndarray((a['count'],n),dtype=dt,buffer=binary,offset=start,strides=(stride,np.dtype(dt).itemsize)).copy()
def local(n):
 if 'matrix' in n:return np.array(n['matrix']).reshape(4,4).T
 t=np.eye(4);t[:3,3]=n.get('translation',[0,0,0]);q=n.get('rotation',[0,0,0,1]);x,y,z,w=q
 rot=np.array([[1-2*y*y-2*z*z,2*x*y-2*z*w,2*x*z+2*y*w],[2*x*y+2*z*w,1-2*x*x-2*z*z,2*y*z-2*x*w],[2*x*z-2*y*w,2*y*z+2*x*w,1-2*x*x-2*y*y]])
 t[:3,:3]=rot@np.diag(n.get('scale',[1,1,1]));return t
parents={c:i for i,n in enumerate(doc['nodes']) for c in n.get('children',[])}
world={}
def pose(i):
 if i not in world:world[i]=(pose(parents[i]) if i in parents else np.eye(4))@local(doc['nodes'][i])
 return world[i]
parts=[];total=0;attributes={};material_prims={};unique_uuid=[];roof_underside_clay_area=0.;roof_underside_wood_area=0.
for ni,node in enumerate(doc['nodes']):
 if 'mesh' not in node:continue
 ext=node.get('extras',{});M=pose(ni);tris=[]
 for p in doc['meshes'][node['mesh']]['primitives']:
  attrs={k:accessor(v) for k,v in p['attributes'].items()};v=attrs['POSITION'];idx=accessor(p['indices']).ravel() if 'indices' in p else np.arange(len(v))
  check(node['name']+' finite attributes '+str(p.get('material')),all(np.isfinite(a).all() for a in attrs.values()))
  check(node['name']+' indices',len(idx)%3==0 and idx.min()>=0 and idx.max()<len(v))
  wv=np.c_[v,np.ones(len(v))]@M.T;t=wv[idx].reshape(-1,3,4)[:,:,:3];tris.extend(t)
  area=np.linalg.norm(np.cross(t[:,1]-t[:,0],t[:,2]-t[:,0]),axis=1)
  check(node['name']+' nondegenerate',np.all(area>1e-10),{'min_twice_area':float(area.min())})
  mat=doc['materials'][p['material']]
  if ext.get('rmmo_part',{}).get('role')=='roof' and ext.get('rmmo_collision')=='block':
   normals=np.cross(t[:,1]-t[:,0],t[:,2]-t[:,0]);down=(normals[:,1]<-.5*area)&(area>1.)
   if 'red clay' in mat['name']:roof_underside_clay_area+=float(area[down].sum()/2)
   if 'oak joinery' in mat['name']:roof_underside_wood_area+=float(area[down].sum()/2)
  if mat.get('normalTexture'):check(node['name']+' normal map has tangents','TANGENT' in attrs and len(attrs['TANGENT'])==len(v))
  total+=len(t);material_prims[p['material']]=material_prims.get(p['material'],0)+1
 parts.append({'name':node['name'],'node':ni,'extras':ext,'triangles':np.asarray(tris)})
 unique_uuid.append(ext.get('uuid'))
check('stable uuid present and unique',all(unique_uuid) and len(set(unique_uuid))==len(unique_uuid))
roots=[n for n in doc['nodes'] if n.get('extras',{}).get('rmmo_model_components')=={'version':1}]
check('one generic component root opt-in',len(roots)==1)
if roots:
 regions=roots[0]['extras'].get('rmmo_building',{}).get('regions',[])
 check('actual interior regions present',len(regions)>=4 and all(all(a<b for a,b in zip(r['min'],r['max'])) and r['floor'] in [0,1] for r in regions))
for p in parts:
 part=p['extras'].get('rmmo_part',{})
 check(p['name']+' generic part contract',part.get('floor') in [0,1] and part.get('floor_y') in [.3,3.9] and part.get('role') in ['body','floor','roof','ceiling','stairs','furniture','door'] and bool(part.get('part')))
alltris=np.concatenate([p['triangles'] for p in parts]);lo=alltris.min(axis=(0,1));hi=alltris.max(axis=(0,1))
check('source game axes and scale',hi[1]>11.0 and hi[1]<11.5 and hi[0]-lo[0]<14.5 and hi[2]-lo[2]<12.5,{'min':lo.tolist(),'max':hi.tolist(),'size':(hi-lo).tolist()})
check('solid roof underside is wood decking not exterior tile fronts',roof_underside_clay_area==0 and roof_underside_wood_area>150,{'clay_area_m2':roof_underside_clay_area,'wood_area_m2':roof_underside_wood_area})

def ray(origin,direction,tri,maxdist=100):
 o=np.asarray(origin);d=np.asarray(direction);e1=tri[:,1]-tri[:,0];e2=tri[:,2]-tri[:,0];p=np.cross(d,e2);det=np.einsum('ij,ij->i',e1,p)
 inv=np.divide(1.,det,out=np.zeros_like(det),where=abs(det)>1e-10);tvec=o-tri[:,0];u=np.einsum('ij,ij->i',tvec,p)*inv;q=np.cross(tvec,e1);v=q@d*inv;t=np.einsum('ij,ij->i',e2,q)*inv
 good=(abs(det)>1e-10)&(u>=-1e-7)&(v>=-1e-7)&(u+v<=1+1e-7)&(t>1e-5)&(t<maxdist)
 return float(t[good].min()) if np.any(good) else None

walls=np.concatenate([p['triangles'] for p in parts if p['extras'].get('semantic_group') in ['10_Exterior_L0','11_Exterior_Upper']])
for name,x,z,w,h,front in [('front',0,4.8,2.2,2.95,True),('rear',3.7,-4.8,1.5,2.8,False)]:
 hits=[]
 for dx in [-w*.35,0,w*.35]:
  for y in [.65,1.6,h-.15]:
   hits.append(ray([x+dx,y,z+(1 if front else -1)],[0,0,-1 if front else 1],walls,2))
 check(name+' entrance wall aperture',all(x is None for x in hits),{'rays':len(hits),'hits':hits})

for side in [-1,1]:
 for x in [-4.5,-1.5,1.5,4.5]:
  check('upper window real hole '+str((side,x)),ray([x,5.5,side*5.5],[0,0,-side],walls,1.5) is None)

solid=np.concatenate([p['triangles'] for p in parts if p['extras'].get('rmmo_collision')!='none' and not p['extras'].get('rmmo_hinge')])
stair_samples=[]
for x,indices,base_y,zbase,sign in [(-5.05,range(10),.30,1.45,-1),(-3.12,range(10),2.10,-1.55,1)]:
 for i in indices:
  y=base_y+(i+1)*.18;z=zbase+sign*(i+.5)*.30
  support=ray([x,y+.1,z],[0,-1,0],solid,.25);clear=ray([x,y+.03,z],[0,1,0],solid,10)
  stair_samples.append({'position':[x,y,z],'support_m':support,'headroom_m':None if clear is None else clear+.03})
check('20 stair tread supports',all(p['support_m'] is not None and abs(p['support_m']-.1)<.02 for p in stair_samples),stair_samples)
check('stair headroom 2.4m',all(p['headroom_m'] is None or p['headroom_m']>=2.4 for p in stair_samples))
continuity=[]
for z in np.linspace(1.30,2.1,21):
 h=ray([-3.12,4.0,z],[0,-1,0],solid,.3)
 continuity.append({'z':float(z),'support':h})
check('stair top connects continuously to upper landing',all(p['support'] is not None and abs(p['support']-.1)<.025 for p in continuity),continuity)
for x in [-1.55,1.55]:
 # Sample the front of the pillar plinth, avoiding the pillar itself.
 check('porch plinth has level platform at front '+str(x),ray([x,.31,6.32],[0,-1,0],solid,.04) is not None)

doorparts=[p for p in parts if p['extras'].get('rmmo_hinge')]
check('five independent hinged leaves',len(doorparts)==5,{'ids':[p['extras']['rmmo_hinge']['id'] for p in doorparts]})
for p in doorparts:
 h=p['extras']['rmmo_hinge'];check(p['name']+' origin at local hinge',h['pivot']==[0,0,0] and abs(h['angle'])==100)
 check(p['name']+' iron hardware travels with leaf',len(doc['meshes'][doc['nodes'][p['node']]['mesh']]['primitives'])==2)
check('fixed hinge mounts remain separate',any(p['extras'].get('semantic_group')=='43_Doors_L0' and p['extras'].get('rmmo_collision')=='none' for p in parts))
glass=[m for m in doc['materials'] if 'clear slightly green' in m['name']]
check('glass portable fallback stays clear and nonemissive',len(glass)==1 and glass[0].get('alphaMode')=='BLEND' and 0<float(glass[0]['pbrMetallicRoughness']['baseColorFactor'][3])<=.06 and max(glass[0]['pbrMetallicRoughness']['baseColorFactor'][:3])<=.15 and glass[0]['pbrMetallicRoughness']['roughnessFactor']<=.1 and not any(glass[0].get('emissiveFactor',[0,0,0])))
glass_parts=[p for p in parts if any(doc['materials'][s['material']] in glass for s in doc['meshes'][doc['nodes'][p['node']]['mesh']]['primitives'])]
check('all glass meshes carry production transmission recipe',bool(glass_parts) and all(p['extras'].get('rmmo_tinted_glass')=={'version':1,'materials':{glass[0]['name']:{'transmittance':[.97,.985,.98],'roughness':.08}}} for p in glass_parts))
check('glass panes remain nonphysical',all(p['extras'].get('rmmo_collision')=='none' for p in glass_parts))
opened=[]
for p in doorparts:
 if 'Front watch entrance' not in p['name']:continue
 pivot=pose(p['node'])[:3,3];a=math.radians(p['extras']['rmmo_hinge']['angle']);rot=np.array([[math.cos(a),0,math.sin(a)],[0,1,0],[-math.sin(a),0,math.cos(a)]])
 opened.append((p['triangles']-pivot)@rot.T+pivot)
opened=np.concatenate(opened)
check('front leaves full open retain passage',all(ray([x,y,5.5],[0,0,-1],opened,1.8) is None for x in [-.75,0,.75] for y in [.8,1.6,2.8]))

images=[];decoded=0;gpu=0
for im in doc.get('images',[]):
 view=doc['bufferViews'][im['bufferView']];data=binary[view.get('byteOffset',0):view.get('byteOffset',0)+view['byteLength']]
 pil=Image.open(io.BytesIO(data));w,h=pil.size;dec=w*h*len(pil.getbands());decoded+=dec
 mw,mh=w,h;mips=0
 while True:
  mips+=mw*mh*4
  if mw==1 and mh==1:break
  mw=max(1,mw//2);mh=max(1,mh//2)
 gpu+=mips
 images.append({'name':im.get('name'),'dimensions':[w,h],'mode':pil.mode,'encoded_bytes':len(data),'encoded_sha256':sha(data),'decoded_bytes':dec,'rgba8_full_mip_budget':mips})
check('all images embedded',all('bufferView' in im and 'uri' not in im for im in doc.get('images',[])))
report={'source':str(source),'sha256':sha(raw),'source_bytes':len(raw),'version':version,'checks':checks,'passed':sum(c['pass'] for c in checks),'failed':sum(not c['pass'] for c in checks),'triangles':total,'mesh_nodes':len(parts),'surfaces':sum(material_prims.values()),'materials':len(doc.get('materials',[])),'images':images,'encoded_images_total':sum(i['encoded_bytes'] for i in images),'source_image_decode_bytes':decoded,'rgba8_mip_budget_bytes':gpu,'aabb':{'min':lo.tolist(),'max':hi.tolist(),'size':(hi-lo).tolist()},'scope':'CPU exported geometry and source resources; not runtime collision/visibility or visual acceptance; GPU/native remain pending','lod_decision':'No forced decimation for one landmark; component boundaries and real openings retained. Root GPU distant views determine whether further LOD is justified.','rss_vram_measured':False}
out=Path(__file__).parent/(version+'_cpu_audit.json');out.write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps({'report':str(out),'sha256':sha(out.read_bytes()),'passed':report['passed'],'failed':report['failed'],'triangles':total,'meshes':len(parts),'surfaces':report['surfaces'],'decoded_bytes':decoded,'rgba8_mips':gpu,'failed_checks':[c for c in checks if not c['pass']]},ensure_ascii=False))
sys.exit(1 if report['failed'] else 0)
