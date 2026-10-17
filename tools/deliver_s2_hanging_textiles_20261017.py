"""Bind manually viewed evidence, then use normal library/real HTTP contracts.

No official map writes. Functional GPU jobs use the shared private-desktop
runner; they do not record performance conclusions. Never overwrite a receipt.
"""
import argparse,hashlib,json,subprocess,struct,io
from PIL import Image
from pathlib import Path
from run_godot_background import run_background
P=argparse.ArgumentParser();P.add_argument('stage',choices=['accept','publish','http','handoff']);P.add_argument('--version',default='v4');P.add_argument('--http-run',default='formal_http');A=P.parse_args()
ROOT=Path('D:/code/rmmo');RT=ROOT.parent/'rmmo_runtime';SRC=RT/'art_sources/s2_hanging_textiles_20261017'/A.version;OUT=RT/'review_artifacts/s2_hanging_textiles_20261017';REV=OUT/A.version
assert Path(A.http_run).name==A.http_run and A.http_run.startswith('formal_http')
HTTP=OUT/A.http_run
MODELS=[('s2_yellow_rectangular_festoon_8m','S2 黄色短矩形跨街布旗串 · 8米','牌匾/旗帜'),('s2_wall_to_wall_white_laundry_36m','S2 墙间白布晾绳 · 3.6米','街景道具'),('s2_ochre_long_banner','S2 黄底纹样长竖幡 · 独立布旗','牌匾/旗帜'),('s2_bronze_lamp_long_ochre_banner','S2 古铜旗灯 · 黄底长竖幡样式','街景灯具')]
def read(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def identity(p):p=Path(p);return {'path':p.as_posix(),'sha256':sha(p),'bytes':p.stat().st_size}
def write(p,d,immutable=False):
    p=Path(p);p.parent.mkdir(parents=True,exist_ok=True)
    if immutable and p.exists():raise RuntimeError('Existing evidence '+str(p))
    p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def gpu(script,args,log,timeout=360):
    r=run_background(['D:/tools/godot/Godot_v4.7.2-stable_win64.exe','--path',str(ROOT),'--script','res://tools/'+script,'--']+args,cwd=ROOT,timeout=timeout);Path(log).write_bytes(r.stdout)
    if r.returncode:raise RuntimeError('Failed; see '+str(log))
if A.stage=='accept':
    decision=read(REV/'visual_decisions.json');assert decision['selected_version']==A.version
    rows=[]
    for name,label,category in MODELS:
        src=SRC/(name+'.glb');author=read(SRC/(name+'_authoring.json'));cp=REV/(name+'_cpu_audit.json');gp=REV/name/'report.json';cpu=read(cp);gpu_report=read(gp)
        assert sha(src)==author['sha256']==cpu['sha256']==gpu_report['identity']['sha256']
        assert cpu['resource_passed'] and gpu_report['passed'] and decision['items'][name]['passed']
        raw=src.read_bytes();jl=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+jl]);blob=raw[28+jl:];normal_pixels=set()
        for mat in doc.get('materials',[]):
            if 'normalTexture' not in mat:continue
            tex=doc['textures'][mat['normalTexture']['index']];im=doc['images'][tex['source']];view=doc['bufferViews'][im['bufferView']];off=view.get('byteOffset',0)
            pixels=Image.open(io.BytesIO(blob[off:off+view['byteLength']])).convert('RGBA').tobytes();normal_pixels.add(hashlib.sha256(pixels).hexdigest())
        assert all(m['normal_pixel_sha256'] in normal_pixels for m in gpu_report['active_cloth_materials']),'Actual native normal pixels differ from exported source'
        views=[]
        for view in decision['items'][name]['viewed']:
            p=REV/name/(view+'.webp');receipt=read(str(p)+'.review-image.json');assert receipt['sha256']==sha(p) and receipt['quality']==90 and receipt['lossless']==False
            views.append({**identity(p),'compression_receipt':identity(str(p)+'.review-image.json'),'manually_viewed':True})
        assert {'near','medium','far','back','cloth_detail','attachment','wind_t1','wind_t4'}.issubset(set(decision['items'][name]['viewed']))
        native=gp.parent/'asset.scn';assert sha(native)==gpu_report['native_sha'];assert sha(author['master'])==author['master_sha256']
        s=cpu['statistics'];unique={i['sha256']:i for i in s['embedded_images']}
        cost={'source_bytes':src.stat().st_size,'native_bytes':native.stat().st_size,'triangles':s['triangles'],'mesh_nodes':cpu['mesh_nodes'],'source_material_descriptors':cpu['materials'],'actual_native_materials':gpu_report['material_count'],'surfaces':s['primitives'],'unique_rgba8_mip_budget_bytes':sum(v['rgba8_mip_budget_bytes'] for v in unique.values()),'images':list(unique.values()),'near_draw_calls_including_ground':gpu_report['screenshots'][0]['draw_calls_with_ground'],'actual_RSS_VRAM':'not measured','LOD_decision':'No forced decimation or extra LOD. Preserve cloth fold segments, individual top anchors and visible knots. Source/master retained; no city-performance claim.'}
        proof={'id':name,'passed':True,'acceptance_stage':'structure_and_layout_candidate','source_path':src.as_posix(),'source_sha256':sha(src),'master':identity(author['master']),'native':identity(native),'cpu_report':identity(cp),'gpu_report':identity(gp),'generator':gpu_report['generator'],'bounds':gpu_report['bounds'],'anchors':author['anchors'],'cost':cost,'visual_evidence':views,'visual_decision':decision['items'][name],'status':{'resources':'passed','reference_and_cloth_visuals':'passed for listed views','runtime_pipeline':'passed native save/reopen and affected wind/picking semantics','formal_library':'await publication and real HTTP','formal_map':'not modified'},'near_material_pending':None,'inherited_lamp_scope':'Lamp metal/glass/crystal channels retained unchanged; existing lighting contract reused, not a new full lamp material/night-lighting review.' if 'bronze_lamp' in name else None,'scope':'S2 missing textile silhouettes, cloth, attachments and static supports only; no formal-map layout, no architecture/performance expansion.'}
        pp=OUT/'acceptance'/(name+'.json');write(pp,proof,True)
        rows.append({'id':name,'label':label,'category':category,'version':A.version,'source':identity(src),'acceptance':identity(pp),'master':identity(author['master']),'native':identity(native),'bounds':gpu_report['bounds'],'anchors':author['anchors'],'cost':cost})
    write(OUT/'handoff.json',{'date':'2026-10-17','stage':'reviewed candidates; library publication pending','items':rows,'reference':'D:/code/rmmo/docs/references/town_required_shots_20261012/03_festival_residential_lane.webp','formal_map_modified':False,'placement_semantics':'Anchors are local ROOT coordinates. place_asset.position is the AABB bottom surface: upright input_y = desired_root_y + bounds.position.y * scale.y. Suspended assets have negative lower bounds.','reuse':'Keep existing S1 pennants, S2 coloured posts, S12 wall flags, original red-flag lamp and freestanding laundry line unchanged.'})
elif A.stage=='publish':
    h=read(OUT/'handoff.json');folder=OUT/'publication';folder.mkdir(exist_ok=True)
    maps={str(p):sha(p) for p in [RT/'packs/default/maps/axel_town/map.gltf',RT/'maps/medieval_river_town/map.gltf'] if p.exists()};receipts=[]
    for row in h['items']:
        p=folder/(row['id']+'.json');src=row['source'];proof=row['acceptance']
        if not p.exists():
            gpu('import_s12_residential_library.gd',['--publish','--source='+src['path'],'--sha256='+src['sha256'],'--review='+proof['path'],'--review-sha256='+proof['sha256'],'--out='+p.as_posix(),'--id='+row['id'],'--label='+row['label'],'--category='+row['category']],p.with_suffix('.log'))
        receipt=read(p);assert receipt['ok'] and receipt['completed'];assert receipt['source_sha256']==src['sha256'];receipts.append(identity(p))
        for mp,expected in maps.items():assert sha(mp)==expected,'External map changed during publication '+mp
    catalog=RT/'packs/default/assets/library.json'
    write(folder/'receipt.json',{'ok':True,'completed':True,'items':[read(r['path'])['items'][0] for r in receipts],'receipts':receipts,'catalog_path':catalog.as_posix(),'catalog_sha_after':sha(catalog),'protected_maps':maps,'formal_map_modified':False},True)
elif A.stage=='http':
    folder=HTTP;folder.mkdir(exist_ok=True);assert not (folder/'editor_verification.json').exists()
    gpu('test_s2_hanging_textiles_published_20261017.gd',['--receipt='+(OUT/'publication/receipt.json').as_posix(),'--out='+folder.as_posix()],folder/'process.log',720)
elif A.stage=='handoff':
    p=OUT/'handoff.json';h=read(p);publication=read(OUT/'publication/receipt.json');http=read(HTTP/'editor_verification.json');assert http['passed'] and http['completed'] and http['verified_count']==4
    for row in h['items']:
        r=next(v for v in publication['items'] if v['id']==row['id']);item=read(HTTP/'items'/(row['id']+'.json'));assert item['http_passed']
        row.update({'formal_asset_id':r['target'],'formal_source':identity(r['target']),'formal_native_identity':item['formal_native_identity'],'formal_entry':item['entry'],'editor_verification':identity(HTTP/'items'/(row['id']+'.json')),'formal_library_status':'published; real HTTP discover/place/select/undo/redo/save/reopen passed','formal_map_status':'not placed by this task'})
    h.update({'stage':'formal shared library ready; S2 map placement pending','publication':identity(OUT/'publication/receipt.json'),'formal_http':identity(HTTP/'editor_verification.json'),'report':'D:/code/rmmo/docs/s2_hanging_textiles_20261017.md'});write(p,h)
print('S2_TEXTILE_DELIVERY',A.stage,'complete',flush=True)
