"""Lossless fixed-input market GLB dependency compaction; CPU only.

Keeps every mesh/node, referenced attribute/index/image byte and material recipe.
Never imports Blender, rewrites source assets, publishes, or edits a map/catalog.
"""
from pathlib import Path
import copy, hashlib, io, json, struct
import numpy as np
from PIL import Image
from optimize_bridge_pennant_glb import Glb, digest, semantic, texture_slots

ROOT = Path('D:/code/rmmo')
RUNTIME = Path('D:/code/rmmo_runtime')
OUT = RUNTIME/'art_sources/axel_market_optimization_20261016'
INPUT = RUNTIME/'review_artifacts/axel_town_layout_20261016'
ASSETS = RUNTIME/'packs/default/assets'
SOURCES = [
    ('pottery', '陶器摊棚', '83a93afb17e96ffcb7301cb5d28bcfe6f79b3c9d3ae1868f379be6509c736993'),
    ('scroll', '卷轴摊棚', '6ede67924282890aa378b1428fb6045448768eb4e11860336178790c95525d9b'),
    ('potion', '魔法药水摊棚', '9628485aed28b5605c87cb02c005bb187aea25fd32fe6e2456ea373c33c8c29a'),
    ('ore', '矿石摊棚', 'ea67aae0d90abdeee63df92fcb817ff21602301838279683e55392c7d8d12dba'),
]
TABLES = {'materials','textures','images','samplers','accessors','bufferViews','buffers'}
TOP = TABLES | {'asset','scene','scenes','nodes','meshes','cameras','extensionsUsed','extensionsRequired','extras','animations','skins'}
DECLARATIONS = {'KHR_materials_ior','KHR_materials_transmission'}

def canonical(x): return json.dumps(x,ensure_ascii=False,sort_keys=True,separators=(',',':'))
def sha_json(x): return hashlib.sha256(canonical(x).encode()).hexdigest()
def sha_bytes(x): return hashlib.sha256(x).hexdigest()
def save_json(p,x): p.write_text(json.dumps(x,ensure_ascii=False,indent=2),encoding='utf-8')

def guard(j):
    assert not set(j)-TOP, 'Unknown dependency table'
    assert not j.get('animations') and not j.get('skins'), 'Unsupported animation/skin graph'
    assert not j.get('extensionsRequired'), 'Required extension rejected'
    assert set(j.get('extensionsUsed') or []) <= DECLARATIONS
    def walk(x):
        if isinstance(x,dict):
            assert not x.get('extensions'), 'Active extension references require a resolver'
            assert not x.get('extras'), 'Opaque extras references require explicit review'
            for v in x.values(): walk(v)
        elif isinstance(x,list):
            for v in x: walk(v)
    walk(j)
    assert all('uri' not in im and 'bufferView' in im for im in j['images'])
    assert all('sparse' not in a and 'bufferView' in a for a in j['accessors'])
    assert all(set(v)<={'buffer','byteOffset','byteLength','byteStride','target','name'} and v['buffer']==0 for v in j['bufferViews'])
    for m in j['meshes']:
        assert not set(m)-{'name','primitives','weights','extras'}
        for p in m['primitives']:
            assert p.get('mode',4)==4
            assert not set(p)-{'attributes','indices','material','mode','targets','extras'}

def usage(j):
    # Preserve all meshes, including any not instantiated in the selected scene.
    mats=set(); acc=set()
    for m in j['meshes']:
        for p in m['primitives']:
            mats.update([p['material']] if 'material' in p else [])
            acc.update(p['attributes'].values())
            if 'indices' in p: acc.add(p['indices'])
            for t in p.get('targets',[]): acc.update(t.values())
    tex={s['index'] for i in mats for s in texture_slots(j['materials'][i])}
    return {'materials':mats,'accessors':acc,'textures':tex,
            'images':{j['textures'][i]['source'] for i in tex},
            'samplers':{j['textures'][i]['sampler'] for i in tex if 'sampler' in j['textures'][i]}}

def graph(g):
    return {'render':semantic(g),'untouched':{k:v for k,v in g.j.items() if k not in TABLES|{'meshes'}}}

def array(g,index):
    a=g.j['accessors'][index];v=g.j['bufferViews'][a['bufferView']]
    dtype=np.dtype({5120:'i1',5121:'u1',5122:'<i2',5123:'<u2',5125:'<u4',5126:'<f4'}[a['componentType']])
    n={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[a['type']]
    stride=v.get('byteStride',dtype.itemsize*n)
    return np.ndarray((a['count'],n),dtype=dtype,buffer=g.blob(a['bufferView']),offset=a.get('byteOffset',0),strides=(stride,dtype.itemsize)).copy()

def node_matrix(n):
    if 'matrix' in n: return np.array(n['matrix'],dtype=float).reshape(4,4).T
    x,y,z,w=n.get('rotation',[0,0,0,1]);m=np.eye(4)
    m[:3,:3]=np.array([[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],[2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],[2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]])@np.diag(n.get('scale',[1,1,1]))
    m[:3,3]=n.get('translation',[0,0,0]);return m

def geometry(g):
    j=g.j;parents={c:i for i,n in enumerate(j['nodes']) for c in n.get('children',[])}
    def pose(i,seen=()):
        assert i not in seen, 'Cyclic node hierarchy'
        return pose(parents[i],seen+(i,))@node_matrix(j['nodes'][i]) if i in parents else node_matrix(j['nodes'][i])
    meshes=[]
    for mi,m in enumerate(j['meshes']):
        primitives=[]
        for pi,p in enumerate(m['primitives']):
            attributes={k:{'shape':list(array(g,v).shape),'decoded_sha256':sha_bytes(array(g,v).tobytes())} for k,v in p['attributes'].items()}
            positions=array(g,p['attributes']['POSITION'])
            indices=array(g,p['indices']).reshape(-1) if 'indices' in p else np.arange(len(positions))
            assert np.isfinite(positions).all() and len(indices)%3==0 and indices.max()<len(positions)
            primitives.append({'primitive':pi,'triangles':len(indices)//3,'attributes':attributes,'index_decoded_sha256':sha_bytes(indices.tobytes()),'local_bounds_min':positions.min(0).tolist(),'local_bounds_max':positions.max(0).tolist()})
        meshes.append({'mesh':mi,'name':m.get('name'),'primitives':primitives})
    nodes=[];all_points=[]
    for ni,n in enumerate(j['nodes']):
        if 'mesh' not in n: continue
        M=pose(ni);positions=np.concatenate([array(g,p['attributes']['POSITION']) for p in j['meshes'][n['mesh']]['primitives']]);world=(M[:3,:3]@positions.T).T+M[:3,3]
        nodes.append({'node':ni,'name':n.get('name'),'mesh':n['mesh'],'world_matrix':M.tolist(),'bounds_min':world.min(0).tolist(),'bounds_max':world.max(0).tolist()});all_points.append(world)
    world=np.concatenate(all_points)
    return {'meshes':meshes,'nodes':nodes,'bounds_min':world.min(0).tolist(),'bounds_max':world.max(0).tolist(),'collision_evidence':'Exact node names/transforms and all position/index bytes preserved; no explicit collider metadata in source. Native generated collision requires parent import verification.'}

def image_stats(g):
    used=usage(g.j)['images'];rows=[]
    for i,im in enumerate(g.j['images']):
        raw=g.blob(im['bufferView']);pic=Image.open(io.BytesIO(raw));pic.load();w,h=pic.size
        mip=0;mw,mh=w,h
        while True:
            mip+=mw*mh*4
            if mw==mh==1: break
            mw=max(1,mw//2);mh=max(1,mh//2)
        rows.append({'index':i,'name':im.get('name'),'active':i in used,'format':pic.format,'dimensions':[w,h],'encoded_bytes':len(raw),'encoded_sha256':sha_bytes(raw),'decoded_rgba_sha256':sha_bytes(pic.convert('RGBA').tobytes()),'native_decoded_bytes':len(pic.tobytes()),'rgba8_base_budget':w*h*4,'rgba8_mip_budget':mip})
    return rows

def stats(g,images,geom):
    used=usage(g.j);geom_views={g.j['accessors'][i]['bufferView'] for i in used['accessors']}
    active_views=geom_views|{g.j['images'][i]['bufferView'] for i in used['images']}
    return {'tables':{k:len(g.j.get(k,[])) for k in ['nodes','meshes','materials','textures','images','samplers','accessors','bufferViews','animations','skins']},'active_tables':{k:len(v) for k,v in used.items()},'unique_mesh_triangles':sum(p['triangles'] for m in geom['meshes'] for p in m['primitives']),'mesh_surfaces':sum(len(m['primitives']) for m in g.j['meshes']),'bin_bytes':g.j['buffers'][0]['byteLength'],'bin_sha256':sha_bytes(g.raw[g.start:g.start+g.j['buffers'][0]['byteLength']]),'unreferenced_view_bytes':sum(v['byteLength'] for i,v in enumerate(g.j['bufferViews']) if i not in active_views),'geometry_view_bytes':sum(g.j['bufferViews'][i]['byteLength'] for i in geom_views),'all_encoded_image_bytes':sum(i['encoded_bytes'] for i in images),'active_encoded_image_bytes':sum(i['encoded_bytes'] for i in images if i['active']),'all_rgba8_mip_budget':sum(i['rgba8_mip_budget'] for i in images),'active_rgba8_mip_budget':sum(i['rgba8_mip_budget'] for i in images if i['active'])}

def compact(slug,label,expected):
    source=ASSETS/(expected+'.glb');assert digest(source)==expected
    src=Glb(source);j=src.j;guard(j);used=usage(j);r=copy.deepcopy(j);maps={};removed={}
    for key in ['materials','accessors','samplers']:
        maps[key]={old:new for new,old in enumerate(sorted(used[key]))};r[key]=[copy.deepcopy(j[key][i]) for i in sorted(used[key])]
    # Require full retained image metadata equality (including names) for aliasing.
    maps['images']={};r['images']=[];seen={}
    for old in sorted(used['images']):
        im=copy.deepcopy(j['images'][old]);recipe=copy.deepcopy(im);v=recipe.pop('bufferView');vr=copy.deepcopy(j['bufferViews'][v]);vr.pop('byteOffset',None)
        key=(sha_json(recipe),sha_json(vr),sha_bytes(src.blob(v)))
        if key not in seen: seen[key]=len(r['images']);r['images'].append(im)
        maps['images'][old]=seen[key]
    maps['textures']={};r['textures']=[];seen={}
    for old in sorted(used['textures']):
        t=copy.deepcopy(j['textures'][old]);t['source']=maps['images'][t['source']]
        if 'sampler' in t: t['sampler']=maps['samplers'][t['sampler']]
        key=sha_json(t)
        if key not in seen: seen[key]=len(r['textures']);r['textures'].append(t)
        maps['textures'][old]=seen[key]
    for m in r['meshes']:
        for p in m['primitives']:
            p['attributes']={k:maps['accessors'][v] for k,v in p['attributes'].items()}
            if 'indices' in p: p['indices']=maps['accessors'][p['indices']]
            if 'material' in p: p['material']=maps['materials'][p['material']]
            for target in p.get('targets',[]):
                for k,v in target.items(): target[k]=maps['accessors'][v]
    for m in r['materials']:
        for slot in texture_slots(m): slot['index']=maps['textures'][slot['index']]
    views=sorted({a['bufferView'] for a in r['accessors']}|{im['bufferView'] for im in r['images']})
    maps['bufferViews']={};r['bufferViews']=[];seen={};binary=bytearray()
    for old in views:
        v=copy.deepcopy(j['bufferViews'][old]);raw=src.blob(old);recipe=copy.deepcopy(v);recipe.pop('byteOffset',None);key=(sha_json(recipe),sha_bytes(raw))
        if key not in seen:
            binary.extend(b'\0'*((-len(binary))%4));v['byteOffset']=len(binary);binary.extend(raw);seen[key]=len(r['bufferViews']);r['bufferViews'].append(v)
        maps['bufferViews'][old]=seen[key]
    for a in r['accessors']: a['bufferView']=maps['bufferViews'][a['bufferView']]
    for im in r['images']: im['bufferView']=maps['bufferViews'][im['bufferView']]
    r['buffers']=copy.deepcopy(j['buffers']);r['buffers'][0]['byteLength']=len(binary)
    encoded=canonical(r).encode();encoded+=b' '*((-len(encoded))%4);binary+=b'\0'*((-len(binary))%4)
    payload=struct.pack('<III',0x46546c67,2,28+len(encoded)+len(binary))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+struct.pack('<II',len(binary),0x004e4942)+binary
    target=OUT/(slug+'_lossless.glb');assert target.resolve().parent==OUT.resolve() and target.resolve()!=source.resolve()
    if target.exists(): assert digest(target)==sha_bytes(payload), 'Do not overwrite a different candidate'
    else: target.write_bytes(payload)
    dst=Glb(target);guard(dst.j);before=graph(src);after=graph(dst);assert before==after
    view_proofs=[]
    for old,new in maps['bufferViews'].items():
        a=src.blob(old);b=dst.blob(new);assert a==b
        view_proofs.append({'source_view':old,'candidate_view':new,'bytes':len(a),'source_offset':j['bufferViews'][old].get('byteOffset',0),'candidate_offset':r['bufferViews'][new].get('byteOffset',0),'sha256':sha_bytes(a),'byte_equal':True})
    a_geom,b_geom=geometry(src),geometry(dst);assert a_geom==b_geom
    a_images,b_images=image_stats(src),image_stats(dst);image_proofs=[]
    for old,new in maps['images'].items():
        a,b=a_images[old],b_images[new]
        for key in ['encoded_bytes','encoded_sha256','dimensions','decoded_rgba_sha256','native_decoded_bytes']: assert a[key]==b[key]
        image_proofs.append({'source_index':old,'candidate_index':new,**{k:a[k] for k in ['name','dimensions','encoded_bytes','encoded_sha256','decoded_rgba_sha256']},'encoded_and_decoded_equal':True})
    material_proofs=[{'source_index':old,'candidate_index':new,'name':j['materials'][old].get('name'),'source_recipe_sha256':sha_json(j['materials'][old]),'candidate_recipe_sha256':sha_json(r['materials'][new]),'recipe_equal_after_resolving_texture_indices':True} for old,new in maps['materials'].items()]
    for key in maps: removed[key]=sorted(set(range(len(j[key])))-set(maps[key]))
    assert digest(source)==expected
    report={'asset':slug,'label':label,'source':str(source),'source_sha256':expected,'candidate':str(target),'candidate_sha256':digest(target),'source_bytes':source.stat().st_size,'candidate_bytes':target.stat().st_size,'saved_bytes':source.stat().st_size-target.stat().st_size,'saved_fraction':1-target.stat().st_size/source.stat().st_size,'source_stats':stats(src,a_images,a_geom),'candidate_stats':stats(dst,b_images,b_geom),'source_images':a_images,'candidate_images':b_images,'resolved_graph_sha256':sha_json(before),'resolved_graph_exact':True,'nodes_transforms_exact':j['nodes']==r['nodes'],'all_kept_buffer_views_byte_equal':True,'all_geometry_uv_normal_index_data_exact':True,'bounds_exact':True,'source_unchanged':True,'geometry':a_geom,'remaps':maps,'removed_resources':removed,'buffer_view_proofs':view_proofs,'active_image_proofs':image_proofs,'active_material_proofs':material_proofs,'extensions_declarations_preserved':j.get('extensionsUsed')==r.get('extensionsUsed'),'no_resize_reencode_decimation':True,'budget_note':'Source/decode byte accounting only. Removing orphan payload reduces GLB/download/import exposure; active rendered texture memory is unchanged. Not measured native RSS/VRAM.','stages':{'resource':'PASS: resolved graph, direct kept byte comparisons, actual decoded geometry/bounds and image pixels agree','visual':'PENDING parent serial GPU comparison','pipeline':'PENDING native import/collision/save-reopen comparison','integration':'NOT published; no catalog/map/handoff modified'}}
    save_json(OUT/(slug+'_audit.json'),report);src.close();dst.close()
    summary={k:report[k] for k in ['asset','label','source','source_sha256','candidate','candidate_sha256','source_bytes','candidate_bytes','saved_bytes','saved_fraction','source_stats','candidate_stats','resolved_graph_sha256','stages']}
    print(canonical(summary),flush=True);return summary

def main():
    OUT.mkdir(parents=True,exist_ok=True)
    input_paths=[INPUT/'market_reused_assets_review.json',INPUT/'market_functional_layout_plan.json']
    input_sha={str(p):digest(p) for p in input_paths};inventory=json.loads(input_paths[0].read_text(encoding='utf-8'))
    # Layout is read for scope, never modified or promoted here.
    layout=json.loads(input_paths[1].read_text(encoding='utf-8'));assert isinstance(layout,dict)
    assert {sha for _,_,sha in SOURCES}<={r['sha256'] for r in inventory['records']}
    masters=[{'file':str(p),'sha256':digest(p),'bytes':p.stat().st_size,'preserved_in_place':True} for p in (RUNTIME/'art_sources/town_market_stalls').rglob('*.blend')]
    reports=[compact(*row) for row in SOURCES]
    assert all(digest(Path(p))==s for p,s in input_sha.items()), 'Input evidence changed during run'
    assert all(digest(Path(m['file']))==m['sha256'] for m in masters)
    summary={'date':'2026-10-16','method':'Lossless dependency reachability pruning and byte-identical buffer aliases. No Blender roundtrip, geometry edit, resize, texture reencoding or material adjustment.','builder':{'file':str(Path(__file__).resolve()),'sha256':digest(Path(__file__).resolve())},'input_evidence_sha256':input_sha,'source_masters':masters,'rows':reports,'source_bytes_total':sum(r['source_bytes'] for r in reports),'candidate_bytes_total':sum(r['candidate_bytes'] for r in reports),'saved_bytes_total':sum(r['saved_bytes'] for r in reports),'active_layout_variants':['pottery','scroll'],'gpu_pending':True,'formal_import_pending':True,'source_catalog_map_unchanged':True,'notes':['Potion variant retains its untextured glass materials; actual active material counts are reported per asset.','AABB and implicit collision input geometry are byte-exact; native collider instance validation is not yet performed.','No claim of existing wind/animation support: source animations and extras remain unchanged.']}
    save_json(OUT/'summary.json',summary)
    save_json(OUT/'gpu_review_request.json',{'scope':'Compare exact old/new SHA pairs from summary under identical camera, exposure and light; near/mid/far and cloth, wood, metal, glass/goods details. Keep characters hidden. Parent serial GPU runner only.','pipeline_checks':['Native actual material/surface counts','Implicit collision equality','Save/reopen retains instance identity and resource SHA'],'screenshots':'Before OpenAI viewing use actual lossy WebP Q90, original dimensions, receipt matched to output SHA.','rows':[{'asset':r['asset'],'source':r['source'],'source_sha256':r['source_sha256'],'candidate':r['candidate'],'candidate_sha256':r['candidate_sha256']} for r in reports]})
    print(canonical({k:summary[k] for k in ['source_bytes_total','candidate_bytes_total','saved_bytes_total','source_catalog_map_unchanged']}))

if __name__=='__main__': main()
