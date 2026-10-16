"""Read actual church GLB; source-side checks do not replace Godot validation."""
from pathlib import Path
import hashlib,io,json,math,struct,sys
import numpy as np
from PIL import Image
BASE=Path('D:/code/rmmo_runtime/art_sources/axel_landmarks_20261016/church')
VERSION=sys.argv[1] if len(sys.argv)>1 else 'v3'
SRC=BASE/VERSION/'axel_church.glb';OUT=Path(__file__).parent/VERSION
OUT.mkdir(exist_ok=True,parents=True)
b=SRC.read_bytes();n=struct.unpack_from('<I',b,12)[0];j=json.loads(b[20:20+n]);blob=b[28+n:]
def acc(i):
 a=j['accessors'][i];v=j['bufferViews'][a['bufferView']];dim={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']];dtype={5126:'<f4',5125:'<u4',5123:'<u2',5121:'u1'}[a['componentType']];s=np.dtype(dtype).itemsize
 return np.ndarray((a['count'],dim),dtype=dtype,buffer=blob,offset=v.get('byteOffset',0)+a.get('byteOffset',0),strides=(v.get('byteStride',s*dim),s)).copy()
def trans(t):
 m=np.eye(4);m[:3,3]=t;return m
def rotation(q):
 x,y,z,w=q
 return np.array([[1-2*y*y-2*z*z,2*x*y-2*z*w,2*x*z+2*y*w,0],[2*x*y+2*z*w,1-2*x*x-2*z*z,2*y*z-2*x*w,0],[2*x*z-2*y*w,2*y*z+2*x*w,1-2*x*x-2*y*y,0],[0,0,0,1]])
def pose(node,opened):
 if 'matrix' in node:m=np.array(node['matrix']).reshape(4,4).T
 else:m=trans(node.get('translation',[0,0,0]))@rotation(node.get('rotation',[0,0,0,1]))@np.diag(node.get('scale',[1,1,1])+[1])
 h=node.get('extras',{}).get('rmmo_hinge')
 if opened and h:
  a=math.radians(h['angle']);r=np.array([[math.cos(a),0,math.sin(a),0],[0,1,0,0],[-math.sin(a),0,math.cos(a),0],[0,0,0,1]])
  m=m@trans(h['pivot'])@r@trans(-np.array(h['pivot']))
 return m
def triangles(opened):
 out=[];names=[]
 def walk(i,parent):
  node=j['nodes'][i];m=parent@pose(node,opened);e=node.get('extras',{})
  if 'mesh' in node and e.get('rmmo_collision')!='none':
   for p in j['meshes'][node['mesh']]['primitives']:
    pos=acc(p['attributes']['POSITION']);pos=np.c_[pos,np.ones(len(pos))]@m.T;ind=acc(p['indices']).ravel();a=pos[ind.reshape(-1,3),:3];out.append(a);names.extend([node.get('name',str(i))]*len(a))
  for child in node.get('children',[]):walk(child,m)
 for r in j['scenes'][j.get('scene',0)]['nodes']:walk(r,np.eye(4))
 return np.concatenate(out),np.array(names)
T,N=triangles(True)
def ray(a,b):
 a=np.array(a,float);d=np.array(b,float)-a;e1=T[:,1]-T[:,0];e2=T[:,2]-T[:,0];p=np.cross(d,e2);det=np.einsum('ij,ij->i',e1,p);valid=np.abs(det)>1e-9
 inv=np.zeros_like(det);inv[valid]=1/det[valid];s=a-T[:,0];u=np.einsum('ij,ij->i',s,p)*inv;q=np.cross(s,e1);v=np.einsum('j,ij->i',d,q)*inv;t=np.einsum('ij,ij->i',e2,q)*inv
 hit=valid&(u>=-1e-7)&(v>=-1e-7)&(u+v<=1+1e-7)&(t>1e-5)&(t<.99999)
 ids=np.flatnonzero(hit);norm=np.cross(e1,e2)
 return [{'node':str(N[k]),'t':float(t[k]),'normal_y':float(norm[k,1]/max(1e-12,np.linalg.norm(norm[k])))} for k in ids]
checks=[]
def check(name,passed,detail=None):checks.append({'name':name,'passed':bool(passed),'detail':detail})
mesh_nodes=[n for n in j['nodes'] if 'mesh' in n];root=[n for n in j['nodes'] if 'rmmo_building' in n.get('extras',{})]
check('one_building_contract_root',len(root)==1)
check('generic_component_contract',len(root)==1 and root[0]['extras'].get('rmmo_model_components')=={'version':1})
check('all_meshes_part_contract',all(set(n.get('extras',{}).get('rmmo_part',{}))=={'floor','floor_y','role','part'} for n in mesh_nodes))
uuids=[n['extras'].get('uuid') for n in mesh_nodes];check('stable_unique_mesh_uuids',all(uuids) and len(set(uuids))==len(uuids))
hinges=[{'node':n['name'],'hinge':n['extras']['rmmo_hinge']} for n in mesh_nodes if n.get('extras',{}).get('rmmo_hinge')]
check('seven_activity_groups',len(hinges)==7,hinges)
for x in [-.7,0,.7]:
 for y in [.6,1.4,2.5]:
  hit=ray([x,y,13.35],[x,y,9.7]);check('main_open_door_clear_'+str((x,y)),not hit,hit)
for title,a,z in [('central_nave',[0,1.35,9.7],[0,1.35,-7.0]),('side_connection',[0,1.35,.3],[-6,1.35,.3]),('service_corridor',[-6,1.35,7.0],[-6,1.35,-4.4])]:
 hit=ray(a,z);check(title,not hit,hit)
for z in [-1.8,1.95,5.8]:
 hit=ray([-6,1.35,z],[-7.4,1.35,z]);check('service_room_open_door_'+str(z),not hit,hit)
hit=ray([-11.9,1.35,-4.85],[-9.7,1.35,-4.85]);check('tower_side_open_door',not hit,hit)
for f in range(5):
 for side,x in [('left',-8.95),('right',-6.65)]:
  for i in range(9):
   top=.3+3*f+(i+1)/6+(1.5 if side=='right' else 0);z=-5.34-(i+.5)*.27 if side=='left' else -7.77+(i+.5)*.27
   hit=ray([x,top+.04,z],[x,top-.04,z]);check('stair_top_'+str((f,side,i)),bool(hit) and all(h['normal_y']>.9 for h in hit),hit)
   head=ray([x,top+.05,z],[x,top+2.35,z]);check('stair_headroom_2m35_'+str((f,side,i)),not head,head)
for x,z in [(0,7),(0,0),(0,-6),(-6,5),(-6,0),(-7.8,-4.8)]:
 hit=ray([x,.8,z],[x,.1,z]);check('ground_walk_'+str((x,z)),bool(hit) and all(h['normal_y']>.9 for h in hit),hit)
images=[]
for im in j.get('images',[]):
 v=j['bufferViews'][im['bufferView']];d=blob[v.get('byteOffset',0):v.get('byteOffset',0)+v['byteLength']];img=Image.open(io.BytesIO(d));rgba=img.convert('RGBA');w,h=img.size
 images.append({'name':im.get('name'),'dimensions':[w,h],'mode':img.mode,'encoded_bytes':len(d),'encoded_sha256':hashlib.sha256(d).hexdigest(),'rgba8_base_bytes':w*h*4,'rgba8_mip_budget':sum(max(1,w>>k)*max(1,h>>k)*4 for k in range(int(math.log2(max(w,h)))+1)),'rgba8_pixel_sha256':hashlib.sha256(rgba.tobytes()).hexdigest()})
cost={'source_glb_bytes':len(b),'blend_bytes':(BASE/VERSION/'axel_church_master.blend').stat().st_size,'images':images,'rgba8_base_bytes':sum(x['rgba8_base_bytes'] for x in images),'rgba8_mip_budget':sum(x['rgba8_mip_budget'] for x in images),'actual_rss_vram':'NOT_MEASURED','native':'PENDING_ROOT_ACTUAL_IMPORT','notes':'Texture costs count unique embedded images, not model instances. PNG/GLB byte size is not VRAM.'}
report={'version':VERSION,'source':str(SRC),'source_sha256':hashlib.sha256(b).hexdigest(),'checks':checks,'passed':sum(c['passed'] for c in checks),'failed':sum(not c['passed'] for c in checks),'resource_costs':cost,'scope':'Actual GLB geometry, metadata, source-side segment rays after mathematical authored hinge poses; does not replace runtime physics/controller/native save/reopen or visual review.'}
(OUT/'source_geometry_semantic_checks.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({'passed':report['passed'],'failed':report['failed'],'failures':[c for c in checks if not c['passed']],'rgba8_mip_budget':cost['rgba8_mip_budget'],'report':str(OUT/'source_geometry_semantic_checks.json')},ensure_ascii=False))
sys.exit(1 if report['failed'] else 0)
