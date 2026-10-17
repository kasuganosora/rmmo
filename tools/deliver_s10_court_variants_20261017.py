"""Publish exact reviewed S10 tree/house using the shared UI importer and HTTP."""
import argparse,hashlib,json
from pathlib import Path
from run_godot_background import run_background

P=argparse.ArgumentParser();P.add_argument('stage',choices=['accept','publish','http','handoff']);P.add_argument('--http-run',default='formal_http');A=P.parse_args()
ROOT=Path('D:/code/rmmo');RT=ROOT.parent/'rmmo_runtime';SRC=RT/'art_sources/s10_court_variants_20261017/v2';OUT=RT/'review_artifacts/s10_court_variants_20261017';REV=OUT/'v2'
assert Path(A.http_run).name==A.http_run and A.http_run.startswith('formal_http')
HTTP=OUT/A.http_run
PUBLICATION=OUT/'publication/receipt_v5.json'
MODELS=[('s10_mature_redfruit_courtyard','S10 庭院成熟红果树 · 宽冠高净空','植物/树木'),('s10_court_shutter_house','S10 果树庭院住宅 · 高窗百叶木门','住宅')]
def read(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def sha(p):
    with Path(p).open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def identity(p):p=Path(p);return {'path':p.as_posix(),'sha256':sha(p),'bytes':p.stat().st_size}
def write(p,d,immutable=False):
    p=Path(p);p.parent.mkdir(parents=True,exist_ok=True)
    if immutable and p.exists():raise RuntimeError('Existing evidence '+str(p))
    p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def gpu(script,args,log,timeout=600):
    r=run_background(['D:/tools/godot/Godot_v4.7.2-stable_win64.exe','--path',str(ROOT),'--script','res://tools/'+script,'--']+args,cwd=ROOT,timeout=timeout);Path(log).write_bytes(r.stdout)
    if r.returncode:raise RuntimeError('Failed; see '+str(log))
if A.stage=='accept':
    rows=[]
    for name,label,category in MODELS:
        version='v5' if 'shutter_house' in name else 'v2'
        SRC=RT/'art_sources/s10_court_variants_20261017'/version;REV=OUT/version
        decision=read(REV/'visual_decisions.json');assert decision['selected_version']==version
        src=SRC/(name+'.glb');ap=SRC/(name+'_authoring.json');author=read(ap);cp=REV/(name+'_cpu_audit.json');gp=REV/name/'report.json';cpu=read(cp);g=read(gp);vd=decision['items'][name]
        assert sha(src)==author['sha256']==cpu['sha256']==g['identity']['sha256']
        assert cpu['resource_passed'] and g['passed'] and vd['structure_passed']
        views=[]
        for view in vd['viewed']+vd.get('inherited_viewed',[]):
            p=REV/name/(view+'.webp');receipt=read(str(p)+'.review-image.json');assert receipt['sha256']==sha(p) and receipt['quality']==90 and receipt['lossless']==False
            evidence={**identity(p),'compression_receipt':identity(str(p)+'.review-image.json'),'manually_viewed':view in vd['viewed']}
            if view in vd.get('inherited_viewed',[]):
                comparison=read(REV/'declaration_only_visual_comparison.json');item=next(v for v in comparison if v['name']==view)
                assert item['max_channel_delta']==0 and item['different_pixels']==0
                baseline=OUT/'v2'/name/(view+'.webp');prior=read(OUT/'acceptance'/(name+'.json'))
                assert any(e['path']==baseline.as_posix() and e['sha256']==sha(baseline) and e['manually_viewed'] for e in prior['visual_evidence'])
                evidence.update(inherited_manually_viewed=identity(baseline),exact_pixel_comparison=identity(REV/'declaration_only_visual_comparison.json'))
            views.append(evidence)
        required={'near_still','medium_still','far_still','trunk_still','near_wind_t1','near_wind_t4'} if 'redfruit' in name else {'near','medium','far','back','front','door_open','shutter_detail','roof_join'}
        assert required.issubset(set(vd['viewed']+vd.get('inherited_viewed',[])))
        native=gp.parent/'asset.scn';assert sha(native)==g['native_sha'];assert sha(author['master'])==author['master_sha256']
        s=cpu['statistics'];unique={i['sha256']:i for i in s['embedded_images']};screen=g['screenshots'][0]
        cost={'source_bytes':src.stat().st_size,'native_bytes':native.stat().st_size,'all_exported_triangles':s['triangles'],'mesh_nodes':cpu['mesh_nodes'],'source_material_descriptors':cpu['materials'],'actual_native_materials':g['material_count'],'surfaces':s['primitives'],'unique_rgba8_mip_budget_bytes':sum(v['rgba8_mip_budget_bytes'] for v in unique.values()),'images':list(unique.values()),'near_draw_calls_with_ground':screen.get('draw_calls_with_ground',screen.get('draw_calls')),'near_primitives_with_ground':screen.get('primitives_with_ground'),'actual_RSS_VRAM':'not measured','LOD_decision':vd['LOD_decision']}
        proof={'id':name,'passed':True,'acceptance_stage':'structure_and_layout_candidate','source_path':src.as_posix(),'source_sha256':sha(src),'authoring':identity(ap),'master':identity(author['master']),'native':identity(native),'cpu_report':identity(cp),'gpu_report':identity(gp),'generator':g['generator'],'bounds':g['bounds'],'anchors':author['anchors'],'cost':cost,'visual_evidence':views,'visual_decision':vd,'status':{'resources':'passed','reference_and_structure':'passed for listed views; see dimensional limitations','runtime_pipeline':'passed affected native save/reopen, collision, components or wind/LOD','formal_library':'await publication and real HTTP','formal_map':'not modified'},'near_material_pending':vd['near_material_pending'],'scope':'S10 front-house layout and tree silhouette variants. Not final material approval, not formal map deployment, not a new full interior lighting review.'}
        if 'shutter_house' in name:
            preflight=SRC/(name+'_contract_preflight.json');pf=read(preflight)
            assert pf['passed'] and pf['source_sha256']==sha(src) and pf['first_json_roundtrip_same'] and pf['second_json_roundtrip_same']
            proof['full_descriptor_preflight']=identity(preflight)
        pp=OUT/'acceptance'/(name+('_'+version if version!='v2' else '')+'.json')
        if pp.exists():assert read(pp)==proof,'Existing immutable review differs'
        else:write(pp,proof,True)
        rows.append({'id':name,'label':label,'category':category,'version':version,'source':identity(src),'acceptance':identity(pp),'master':identity(author['master']),'authoring':identity(ap),'native':identity(native),'bounds':g['bounds'],'anchors':author['anchors'],'cost':cost,'near_material_pending':vd['near_material_pending'],'measured_shape':author.get('measured_shape'),'independent_lamp':author.get('independent_lamp')})
    write(OUT/'handoff.json',{'date':'2026-10-17','stage':'reviewed tree/house candidates; formal library pending','items':rows,'reference':'D:/code/rmmo/docs/references/town_required_shots_20261012/02_fruit_tree_residential_court.webp','formal_map_modified':False,'placement_semantics':'Anchors are model ROOT-local coordinates. place_asset.position uses AABB bottom: upright input_y=desired_root_y+bounds.position.y*scale.y. Crown center is measured from LOD0, not root. House foundation is below root.','planter_reuse':{'source_sha256':'8072add85cdbbcb157b0c372961af898fa635d9c8973543713ee1d613aaf657a','native_size_m':[3.620182,.9600887,1.235942],'recommended_scale':[1,1,1],'status':'Existing source only. Native-proportion structure usable for layout; warm small red-brick reference material NOT passed (pale large blocks). New planter variants deferred to material detailing; no replacement published.','evidence':(OUT/'planter_reuse/report.json').as_posix()},'reuse':'Existing wall lantern and planters remain independent. Do not distort one axis to match layout; adjust placement. Do not alter rear house, existing formal map or original variants.'})
elif A.stage=='publish':
    h=read(OUT/'handoff.json');folder=OUT/'publication';folder.mkdir(exist_ok=True)
    maps={str(p):sha(p) for p in [RT/'packs/default/maps/axel_town/map.gltf',RT/'maps/medieval_river_town/map.gltf'] if p.exists()};receipts=[]
    for row in h['items']:
        p=folder/(row['id']+('_'+row['version'] if row['version']!='v2' else '')+'.json');src=row['source'];proof=row['acceptance']
        if not p.exists():gpu('import_s12_residential_library.gd',['--publish','--source='+src['path'],'--sha256='+src['sha256'],'--review='+proof['path'],'--review-sha256='+proof['sha256'],'--out='+p.as_posix(),'--id='+row['id'],'--label='+row['label'],'--category='+row['category']],p.with_suffix('.log'))
        receipt=read(p);assert receipt['ok'] and receipt['completed'];assert receipt['source_sha256']==src['sha256'];receipts.append(identity(p))
        for mp,expected in maps.items():assert sha(mp)==expected,'External map changed during publication '+mp
    catalog=RT/'packs/default/assets/library.json'
    write(PUBLICATION,{'ok':True,'completed':True,'items':[read(r['path'])['items'][0] for r in receipts],'receipts':receipts,'catalog_path':catalog.as_posix(),'catalog_sha_after':sha(catalog),'protected_maps':maps,'formal_map_modified':False},True)
elif A.stage=='http':
    HTTP.mkdir(exist_ok=True);assert not (HTTP/'editor_verification.json').exists()
    gpu('test_s10_court_published_20261017.gd',['--receipt='+PUBLICATION.as_posix(),'--out='+HTTP.as_posix()],HTTP/'process.log',720)
elif A.stage=='handoff':
    p=OUT/'handoff.json';h=read(p);publication=read(PUBLICATION);http=read(HTTP/'editor_verification.json');assert http['passed'] and http['completed'] and http['verified_count']==len(MODELS)
    for row in h['items']:
        r=next(v for v in publication['items'] if v['id']==row['id']);item=read(HTTP/'items'/(row['id']+'.json'));assert item['http_passed']
        row.update({'formal_asset_id':r['target'],'formal_source':identity(r['target']),'formal_native_identity':item['formal_native_identity'],'formal_entry':item['entry'],'editor_verification':identity(HTTP/'items'/(row['id']+'.json')),'formal_library_status':'published; actual HTTP discover/place/select/undo/redo/save/reopen passed','formal_map_status':'not placed by this task'})
    h.update({'stage':'formal shared library ready; map placement handled separately','publication':identity(PUBLICATION),'formal_http':identity(HTTP/'editor_verification.json'),'report':'D:/code/rmmo/docs/s10_court_variants_20261017.md'});write(p,h)
print('S10_COURT_DELIVERY',A.stage,'complete',flush=True)
