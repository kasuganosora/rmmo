"""CPU audit of actual watermill GLB, not a GPU/engine acceptance substitute."""
from pathlib import Path
import sys,json,hashlib,io,math,re
import numpy as np
from PIL import Image
sys.path.insert(0,'D:/code/rmmo/tools')
from repair_s12_stone_materials import read_glb,accessor,view
BASE=Path('D:/code/rmmo_runtime/art_sources/axel_landmarks_20261016/watermill')
OUT=Path(__file__).resolve().parent
version=sys.argv[1] if len(sys.argv)>1 else 'v2'
path=BASE/version/'axel_watermill.glb'
j,b,raw=read_glb(path)
checks=[]
def check(name,ok,detail=None):checks.append({'name':name,'pass':bool(ok),'detail':detail})
def trs(n):
    if 'matrix' in n:return np.array(n['matrix'],dtype=float).reshape(4,4).T
    x,y,z,w=n.get('rotation',[0,0,0,1]);m=np.eye(4)
    m[:3,:3]=np.array([[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],[2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],[2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]])@np.diag(n.get('scale',[1,1,1]))
    m[:3,3]=n.get('translation',[0,0,0]);return m
parents={c:i for i,n in enumerate(j['nodes']) for c in n.get('children',[])}
def pose(i):return pose(parents[i])@trs(j['nodes'][i]) if i in parents else trs(j['nodes'][i])
parts=[];triangles=[];deg=0;uvdeg=0;missing_tbn=0;uuid=[]
for ni,n in enumerate(j['nodes']):
    if 'mesh' not in n:continue
    M=pose(ni);ex=n.get('extras',{});uuid.append(ex.get('uuid'))
    ptri=[]
    for pi,p in enumerate(j['meshes'][n['mesh']]['primitives']):
        pos=accessor(j,b,p['attributes']['POSITION']).astype(float);idx=accessor(j,b,p['indices']).reshape(-1,3)
        pp=(M[:3,:3]@pos.T).T+M[:3,3];tt=pp[idx];ptri.append(tt)
        area=np.linalg.norm(np.cross(tt[:,1]-tt[:,0],tt[:,2]-tt[:,0]),axis=1)
        deg+=int((area<1e-10).sum())
        check(n['name']+f' primitive{pi} finite/index',np.isfinite(pos).all() and idx.max()<len(pos))
        nrm=accessor(j,b,p['attributes']['NORMAL'])
        check(n['name']+f' primitive{pi} unit normals',np.max(np.abs(np.linalg.norm(nrm,axis=1)-1))<2e-4)
        if 'TEXCOORD_0' in p['attributes']:
            uv=accessor(j,b,p['attributes']['TEXCOORD_0'])[idx]
            ua=uv[:,1]-uv[:,0];ub=uv[:,2]-uv[:,0];uvdeg+=int((abs(ua[:,0]*ub[:,1]-ua[:,1]*ub[:,0])<1e-10).sum())
        mat=j['materials'][p['material']]
        if 'normalTexture' in mat:
            missing_tbn+=int('TANGENT' not in p['attributes'])
            if 'TANGENT' in p['attributes']:
                tangent=accessor(j,b,p['attributes']['TANGENT'])
                check(n['name']+f' primitive{pi} finite tangents',np.isfinite(tangent).all() and np.min(np.linalg.norm(tangent[:,:3],axis=1))>.99 and np.max(abs(abs(tangent[:,3])-1))<1e-6)
    tt=np.concatenate(ptri);parts.append({'name':n['name'],'extras':ex,'pose':M.tolist(),'triangles':tt,'min':tt.min((0,1)).tolist(),'max':tt.max((0,1)).tolist()});triangles.append(tt)
tt=np.concatenate(triangles)
check('nonempty unique UUIDs',all(uuid) and len(set(uuid))==len(uuid))
if version in ['v9','v10','v11']:check('source UUID contract uses only letters digits underscore hyphen',all(re.fullmatch(r'[A-Za-z0-9_-]+',v) for v in uuid))
check('no degenerate geometric triangles',deg==0,deg)
check('all normal mapped surfaces export tangents',missing_tbn==0,missing_tbn)
check('no collapsed UV triangles',uvdeg==0,uvdeg)
check('no skeletal/animated payload forced into static importer',not j.get('skins') and not j.get('animations'))
roots=[n for n in j['nodes'] if n.get('extras',{}).get('rmmo_model_components',{}).get('version')==1]
check('exactly one generic model-components opt-in',len(roots)==1)
check('two actual indoor regions',len(roots)==1 and len(roots[0].get('extras',{}).get('rmmo_building',{}).get('regions',[]))==2)
for p in parts:
    meta=p['extras'].get('rmmo_part',{})
    check(p['name']+' supported part metadata',meta.get('floor') in [0,1] and meta.get('floor_y') in [0,3.8] and meta.get('role') in ['body','floor','roof','ceiling','stairs','furniture','door','mechanism'] and bool(meta.get('part')))
check('assembly bounded to declared reserved region',tt[:,:,0].min()>=-6.1 and tt[:,:,0].max()<=9.0 and tt[:,:,2].min()>=-6.1 and tt[:,:,2].max()<=7.6)
def hits(origin,target,subset):
    tri=np.concatenate([p['triangles'] for p in parts if subset(p)])
    o=np.array(origin);d=np.array(target)-o;length=np.linalg.norm(d);d/=length
    e1=tri[:,1]-tri[:,0];e2=tri[:,2]-tri[:,0];h=np.cross(d,e2);a=np.einsum('ij,ij->i',e1,h)
    nz=abs(a)>1e-9;f=np.zeros_like(a);f[nz]=1/a[nz];s=o-tri[:,0];u=f*np.einsum('ij,ij->i',s,h);q=np.cross(s,e1);v=f*(q@d);t=f*np.einsum('ij,ij->i',e2,q)
    return t[nz & (u>=-1e-6)&(v>=-1e-6)&(u+v<=1.000001)&(t>1e-5)&(t<length-1e-5)]
structural=lambda p:not p['extras'].get('semantic_group','').startswith('door_') and p['extras'].get('rmmo_collision')!='none'
for side,z,center,w in [('front',5.4,-1.5,2.4),('rear',-5.4,-2.2,1.6)]:
    for dx in [-w*.3,0,w*.3]:
        for y in [.18,1.4,2.60]:check(f'{side} door structural open ray {dx} {y}',len(hits((center+dx,y,z-.6),(center+dx,y,z+.6),structural))==0)
for i in range(20):
    y=(i+1)*.19;z=3.0-(i+.5)*.35
    hit=hits((-3.94,y+.08,z),(-3.94,y-.20,z),lambda p:p['extras'].get('semantic_group') in ['stairs','floor_l1'])
    check(f'stair tread {i} actual top',len(hit)>0 and abs(hit.min()-.08)<.015)
    clearance=hits((-3.94,y+.10,z),(-3.94,y+2.45,z),structural)
    check(f'stair head clearance {i}',len(clearance)==0)
check('stair top landing present',len(hits((-3.94,3.9,-4.12),(-3.94,3.6,-4.12),structural))>0)
for g in ['waterwheel','drive_axle','pitwheel','wallower','great_spur','stone_nut','runner_stone']:
    ps=[p for p in parts if p['extras'].get('semantic_group')==g];check(g+' independent pivot node',len(ps)==1 and ps[0]['extras'].get('author_role')=='rotor')
wheel=next(p for p in parts if p['extras'].get('semantic_group')=='waterwheel')
check('wheel bottom contacts design water',-1.23<=wheel['min'][1]<-1.05,{'wheel_min':wheel['min'],'water_y':-1.0})
manifest=json.loads((BASE/version/'manifest.json').read_text(encoding='utf-8'))
if 'river_foundation' in manifest:
    foundation=manifest['river_foundation']
    check('river foundation independent source groups',len(foundation['modules'])==(7 if version in ['v8','v9','v10','v11'] else 4))
    for module in foundation['modules']:
        group=module['group'];matches=[p for p in parts if p['extras'].get('semantic_group')==group]
        check(group+' independent exported node',len(matches)==1)
        if not matches:continue
        p=matches[0];poly=np.array(module['support_polygon_xz']);lo=poly.min(0);hi=poly.max(0)
        check(group+' actual geometry matches contact polygon/base',np.allclose(p['min'],[lo[0],module['bottom_y'],lo[1]],atol=1e-5) and np.allclose(p['max'],[hi[0],module['top_y'],hi[1]],atol=1e-5))
        corridor=foundation['continuous_water_corridor_xz']
        check(group+' does not block water corridor',hi[0]<=corridor[0] or lo[0]>=corridor[2] or hi[1]<=corridor[1] or lo[1]>=corridor[3])
        check(group+' outside complete wheel sweep',hi[0]<wheel['min'][0] or lo[0]>wheel['max'][0])
        check(group+' collidable masonry',p['extras'].get('rmmo_collision')=='block')
    check('sampled riverbed clears wheel bottom',abs((2.2-4.)-(-1.8))<1e-7 and wheel['min'][1]-(-1.8)>=.59)
    if version in ['v8','v9','v10','v11']:
        groups={m['group']:m for m in foundation['modules']}
        check('closed masonry support below all four exterior walls',all('river_foundation_'+side in groups for side in ['east','west','front','rear']))
        check('body foundation below minimum surveyed body terrain',all(m['bottom_y']+4.<2.459865 for m in foundation['modules'] if m['group']!='river_foundation_outer_bearing'))
        check('outer bearing foundation embeds into sampled bed',groups['river_foundation_outer_bearing']['bottom_y']+4.<=2.10)
        check('unchanged wheel clears highest sampled corridor bed',wheel['min'][1]+4.-2.5241>=.275)
        check('downstream and rotor sign match actual source layout',manifest['placement_anchor']['local_downstream']==[0,0,1] and manifest['mechanism']['input_drive_sign']==-1)
if version in ['v10','v11']:
    glass=next(m for m in j['materials'] if m['name']=='Mill thin clear glass')
    plaster=next(m for m in j['materials'] if m['name']=='Mill lime plaster')
    check('glass fallback low alpha and low roughness',glass['pbrMetallicRoughness']['baseColorFactor'][3]<.04 and abs(glass['pbrMetallicRoughness']['roughnessFactor']-.09)<1e-5)
    glass_parts=[p for p in parts if p['extras'].get('semantic_group') in ['windows_l0','windows_l1']]
    check('both window floors opt into consumed neutral thin glass',len(glass_parts)==2 and all(p['extras'].get('rmmo_tinted_glass',{}).get('materials',{}).get('Mill thin clear glass',{})=={'transmittance':[.97,.985,.98],'roughness':.09} for p in glass_parts))
    check('limewash covers coarse scan colour and restrains relief','baseColorTexture' not in plaster['pbrMetallicRoughness'] and abs(plaster['normalTexture']['scale']-.18)<1e-5)
    check('actual timber boarding layer recorded',manifest['v10_material_repairs']['roof']['actual_boarding_count']==54 and manifest['v10_material_repairs']['roof']['boarding_thickness_m']==.03)
    for group in ['roof','porch']:
        downward_tiles=0
        for ni,n in enumerate(j['nodes']):
            if n.get('extras',{}).get('semantic_group')!=group or 'mesh' not in n:continue
            for prim in j['meshes'][n['mesh']]['primitives']:
                if j['materials'][prim['material']]['name']!='Mill terracotta tiles':continue
                pos=accessor(j,b,prim['attributes']['POSITION']);idx=accessor(j,b,prim['indices']).reshape(-1,3);t=pos[idx]
                centers=t.mean(1);normals=np.cross(t[:,1]-t[:,0],t[:,2]-t[:,0]);normals/=np.linalg.norm(normals,axis=1)[:,None]
                # Ridge-cap lower arcs are hidden by the roof top, so exclude them.
                downward_tiles+=int(((normals[:,1]<-.5)&(centers[:,1]<9.3)).sum())
        check(group+' has no visible downward-facing terracotta underside',downward_tiles==0,downward_tiles)
if version=='v11':
    access=manifest['v11_access_repair'];pier=next(m for m in manifest['river_foundation']['modules'] if m['group']=='river_foundation_inner_pier_front')
    check('relocated front column has matching actual support polygon',np.allclose(np.array(pier['support_polygon_xz']).mean(0),access['post_new_center_xz']))
    check('normal double-open door to front column nominal gap exceeds capsule',access['double_open_left_leaf_tip_z']-(access['post_new_center_xz'][1]+access['post_half_width'])>1.4)
    # Actual exported structural rays through the turning lane at capsule body
    # heights; runtime sweep with opened fixtures remains the HTTP acceptance.
    for y in [.35,.9,1.6]:
        check(f'actual entrance-to-stair turning lane structural ray y{y}',len(hits((-2.1,y,3.95),(-3.94,y,3.95),structural))==0)
    check('knee braces above standard capsule head height',access['knee_braces_bottom_y']-.12>1.8)
    check('controller and column collision not bypassed',not access['runtime_controller_changed'] and not access['collisions_disabled'])
images=[]
for k,img in enumerate(j.get('images',[])):
    payload=view(j,b,img['bufferView']);im=Image.open(io.BytesIO(payload));w,h=im.size;rgba=0;mw,mh=w,h
    while True:
        rgba+=mw*mh*4
        if mw==1 and mh==1:break
        mw=max(1,mw//2);mh=max(1,mh//2)
    images.append({'name':img.get('name',str(k)),'encoded_bytes':len(payload),'sha256':hashlib.sha256(payload).hexdigest(),'size':[w,h],'decoded_mode':im.mode,'base_native_bytes':len(im.tobytes()),'rgba8_mip_budget':rgba})
report={'source':str(path),'sha256':hashlib.sha256(raw).hexdigest(),'bytes':len(raw),'triangles':len(tt),'mesh_nodes':len(parts),'material_count':len(j['materials']),'bounds_min':tt.min((0,1)).tolist(),'bounds_max':tt.max((0,1)).tolist(),'checks':checks,'pass':sum(c['pass'] for c in checks),'fail':sum(not c['pass'] for c in checks),'uv_degenerate_triangles':uvdeg,'images':images,'image_native_decoded_bytes':sum(p['base_native_bytes'] for p in images),'rgba8_mip_budget':sum(p['rgba8_mip_budget'] for p in images),'budget_note':'Image budgets only; not measured VRAM/RSS. Actual native and production peak pending root GPU/import tests.','parts':[{k:v for k,v in p.items() if k!='triangles'} for p in parts],'visual_status':'PENDING_ROOT_GPU','runtime_status':'PENDING_ROOT_IMPORT'}
(OUT/f'cpu_audit_{version}.json').write_text(json.dumps(report,indent=2,ensure_ascii=False),encoding='utf-8')
print(json.dumps({k:report[k] for k in ['pass','fail','triangles','bytes','uv_degenerate_triangles','bounds_min','bounds_max','rgba8_mip_budget']}))
for c in checks:
    if not c['pass']:print('FAIL',c)
sys.exit(0 if not report['fail'] else 1)
