"""Bind watermill handoff to the latest CPU-checked candidate only."""
from pathlib import Path
import json,math,hashlib,sys
import numpy as np
sys.path.insert(0,'D:/code/rmmo/tools')
from repair_s12_stone_materials import read_glb,accessor
BASE=Path('D:/code/rmmo_runtime/art_sources/axel_landmarks_20261016/watermill')
OUT=Path(__file__).resolve().parent
version='v11';manifest=json.loads((BASE/version/'manifest.json').read_text(encoding='utf-8'));audit=json.loads((OUT/f'cpu_audit_{version}.json').read_text(encoding='utf-8'))
manifest['master']['sha256']=hashlib.sha256(Path(manifest['master']['file']).read_bytes()).hexdigest()
assert audit['fail']==0 and manifest['exports'][0]['sha256']==audit['sha256']
def write(p,j):p.write_text(json.dumps(j,ensure_ascii=False,indent=2),encoding='utf-8')
design=json.loads((BASE/'design.json').read_text(encoding='utf-8'))
design.update(status=f'{version}_cpu_pass_ready_for_root_gpu_native_review',candidate_manifest=str(BASE/version/'manifest.json'),candidate_glb=manifest['exports'][0],actual_aabb_min=audit['bounds_min'],actual_aabb_max=audit['bounds_max'],river_foundation=manifest['river_foundation'],placement_anchor=manifest['placement_anchor'],material_repairs=manifest['v10_material_repairs'])
design['access_repair']=manifest['v11_access_repair']
design['waterwheel'].update(flow_from=[6.85,-1.,-4.],flow_to=[6.85,-1.,4.],input_axis=[1,0,0],input_drive_sign=-1,surveyed_bed_local_range=[-1.8,-1.4759],minimum_surveyed_wheel_bed_clearance=.2759,requirement='Actual river flows local -Z to +Z and drives negative X rotation. Preserve existing riverbed/water surface; sampled bed clears unchanged wheel by at least 0.2759 m. Foundation is the explicit union of seven support polygons, not the complete assembly AABB.')
origin=np.array(manifest['placement_anchor']['origin_world']);yaw=math.radians(manifest['placement_anchor']['yaw_degrees']);c,s=math.cos(yaw),math.sin(yaw)
rotation=np.array([[c,0,s],[0,1,0],[-s,0,c]])
anchors={'front_door':[-1.5,0,5.4],'rear_service_door':[-2.2,0,-5.4],'wheel_axis':[6.85,1.1,0],'outer_bearing':[8.3,1.1,0],'flow_from':[6.85,-1.,-4.],'flow_to':[6.85,-1.,4.]}
design['anchors']={k:{'local':p,'world':(origin+rotation@p).tolist()} for k,p in anchors.items()}
for m in design['river_foundation']['modules']:
    m['support_polygon_world']=[(origin+rotation@[x,m['bottom_y'],z]).tolist() for x,z in m['support_polygon_xz']]
write(BASE/'design.json',design)
manifest['anchors']=design['anchors']
manifest['metadata_finalizer']={'file':str(Path(__file__).resolve()),'sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
write(BASE/version/'manifest.json',manifest)
write(OUT/'candidate_manifest.json',manifest)
request=json.loads((OUT/'gpu_review_request.json').read_text(encoding='utf-8'))
request['candidate']=manifest['exports'][0];request['version']=version
request['v11_affected_views']=['door-to-stair turning lane with both doors fully open; real standard capsule traversal','relocated front-left post, knee braces and matching independent foundation pier']
request['v10_affected_views']=['window_detail: neutral clear transmitted glass with fine warm limewash','upper_millstone: actual timber boarding beneath roof, no terracotta ceiling','porch underside: timber backing','exterior_front/side: plaster scale and window transparency']
request['functional'].extend(['Check closed perimeter foundation and two internal piers seat into surveyed bank; outer bearing base world Y=2.05 is below sampled bed 2.200733','Keep wheel corridor clear; actual flow local -Z to +Z, future input rotation negative X','Render side elevation/cutaway low angle showing physical foundation rather than asserting full AABB support'])
request['functional']=list(dict.fromkeys(request['functional']))
write(OUT/'gpu_review_request.json',request)
standalone=[]
for row in manifest['exports'][1:]:
    j,b,raw=read_glb(Path(row['file']));nodes=[n for n in j['nodes'] if 'mesh' in n];points=[]
    for n in nodes:
        assert not n.get('rotation') and not n.get('matrix') and not n.get('scale')
        for p in j['meshes'][n['mesh']]['primitives']:points.append(accessor(j,b,p['attributes']['POSITION']).astype(float)+n.get('translation',[0,0,0]))
    p=np.concatenate(points)
    assert not any(n.get('extras',{}).get('rmmo_building') for n in j['nodes'])
    standalone.append({'path':row['file'],'sha256':row['sha256'],'mesh_nodes':len(nodes),'groups':row['groups'],'origin':row['origin'],'bounds_min':p.min(0).tolist(),'bounds_max':p.max(0).tolist(),'no_building_regions':True,'node_local_translations':[n.get('translation',[0,0,0]) for n in nodes]})
write(OUT/'independent_components.json',standalone)
# The river foundation is additive; the previous wheel/shaft/doors keep attributes.
def attributes(v):
    j,b,_=read_glb(BASE/v/'axel_watermill.glb');result={}
    for n in j['nodes']:
        if 'mesh' not in n:continue
        triangles=[]
        for p in j['meshes'][n['mesh']]['primitives']:
            data=np.concatenate([accessor(j,b,p['attributes'][k]).astype(float) for k in ['POSITION','NORMAL','TEXCOORD_0']],axis=1)
            idx=accessor(j,b,p['indices']).reshape(-1,3)
            material=j['materials'][p['material']]['name']
            for t in data[idx]:
                rounded=np.round(t,5);rounded[rounded==0]=0.
                triangles.append((material,tuple(sorted(tuple(v) for v in rounded))))
        result[n['name']]={'raw':[{'attributes':{k:hashlib.sha256(accessor(j,b,i).tobytes()).hexdigest() for k,i in p['attributes'].items()},'index':hashlib.sha256(accessor(j,b,p['indices']).tobytes()).hexdigest()} for p in j['meshes'][n['mesh']]['primitives']],'canonical_triangles':hashlib.sha256(repr(sorted(triangles)).encode()).hexdigest(),'triangle_list':triangles}
    return result
old,new=attributes('v10'),attributes(version)
comparisons={}
for k in old:
    def keyed(row):return {(m,tuple(tuple(v[:3]) for v in tri)):np.array(tri) for m,tri in row['triangle_list']}
    a,b=keyed(old[k]),keyed(new[k]);same_geometry=set(a)==set(b)
    max_delta=max(float(np.abs(a[q][:,3:]-b[q][:,3:]).max()) for q in a) if same_geometry else None
    comparisons[k]={'triangle_positions_and_materials_same_at_1e_5':same_geometry,'maximum_normal_uv_delta_after_1e_5_rounding':max_delta,'raw_accessors_byte_equal':old[k]['raw']==new[k]['raw']}
affected={'watermill_timber_l0','watermill_river_foundation_inner_pier_front'}
unchanged={k:v['triangle_positions_and_materials_same_at_1e_5'] and v['maximum_normal_uv_delta_after_1e_5_rounding']<.0001 for k,v in comparisons.items() if k not in affected}
assert all(unchanged.values()), {k:comparisons[k] for k,v in unchanged.items() if not v}
write(OUT/f'v10_{version}_geometry_identity.json',{'old_version':'v10','new_version':version,'all_unaffected_groups_preserved_at_1e_5':True,'intentionally_changed_groups':sorted(affected),'unaffected_group_count':len(unchanged),'comparison':comparisons,'new_nodes':sorted(set(new)-set(old)),'note':'Only left front support column, two knee braces and matching foundation pier changed. Unaffected per-triangle positions/material names use 1e-5 precision; normal/UV differences separately measured below 1e-4. Full material and image byte identity checked separately.'})
handoff={'model':'axel_watermill','candidate_version':version,'cpu_review':f"PASS_{audit['pass']}_0",'visual_review':'PENDING_ROOT','native_import':'PENDING_ROOT','formal_library':'PENDING_ROOT','map_modified':False,'gpu_never_started':True,'exports':manifest['exports'],'master':manifest['master'],'design':str(BASE/'design.json'),'cpu_report':str(OUT/f'cpu_audit_{version}.json'),'gpu_request':str(OUT/'gpu_review_request.json'),'report':'D:/code/rmmo/docs/axel_watermill_model_review_20261016.md'}
write(OUT/'handoff.json',handoff)
write(BASE/'latest.json',handoff)
print(json.dumps({'version':version,'sha256':audit['sha256'],'pass':audit['pass'],'unchanged_old_groups':len(unchanged),'new_foundation_groups':len(new)-len(old)}))
