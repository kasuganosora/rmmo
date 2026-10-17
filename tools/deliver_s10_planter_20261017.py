"""Publish reviewed independent S10 masonry variant, never replace a map model."""
import argparse,copy,hashlib,io,json,struct
from pathlib import Path
import numpy as np
from PIL import Image
from run_godot_background import run_background

P=argparse.ArgumentParser();P.add_argument('stage',choices=['audit','accept','publish','resume','http','handoff']);A=P.parse_args()
ROOT=Path('D:/code/rmmo');RT=ROOT.parent/'rmmo_runtime';NAME='s10_warm_redbrick_planter'
SRC=RT/'art_sources/s10_warm_brick_planter_20261017/v1';OUT=RT/'review_artifacts/s10_warm_brick_planter_20261017';REV=OUT/'v1'
GLB=SRC/(NAME+'.glb');GP=REV/NAME/'report.json';PROOF=OUT/'acceptance'/f'{NAME}.json';PUB=OUT/'publication/receipt.json';HTTP=OUT/'formal_http'
FAILED_PUB=PUB
if A.stage=='resume' or (OUT/'publication/receipt_resumed.json').exists():PUB=OUT/'publication/receipt_resumed.json'
def read(p):return json.loads(Path(p).read_text(encoding='utf-8-sig'))
def sha(p):
    with Path(p).open('rb') as f:return hashlib.file_digest(f,'sha256').hexdigest()
def ident(p):p=Path(p);return {'path':p.as_posix(),'sha256':sha(p),'bytes':p.stat().st_size}
def write(p,d,immutable=True):
    p=Path(p);p.parent.mkdir(parents=True,exist_ok=True)
    if immutable and p.exists():assert read(p)==d,'Immutable evidence differs: '+str(p);return
    p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def gpu(script,args,log,timeout=600):
    r=run_background(['D:/tools/godot/Godot_v4.7.2-stable_win64.exe','--path',str(ROOT),'--script','res://tools/'+script,'--']+args,cwd=ROOT,timeout=timeout);Path(log).parent.mkdir(parents=True,exist_ok=True);Path(log).write_bytes(r.stdout)
    if r.returncode:raise RuntimeError('Failed, inspect '+str(log))
def image_evidence(folder,views):
    result=[]
    for view in views:
        p=folder/(view+'.webp');r=read(str(p)+'.review-image.json')
        assert r['sha256']==sha(p) and r['quality']==90 and not r['lossless'] and r['dimensions']==[1200,1000]
        result.append({**ident(p),'compression_receipt':ident(str(p)+'.review-image.json'),'manually_viewed':True})
    return result

if A.stage=='audit':
    cp=REV/(NAME+'_cpu_audit.json');cpu=read(cp);tp=REV/'production_tangent_probe.json';t=read(tp);author=read(SRC/(NAME+'_authoring.json'))
    assert sha(GLB)==cpu['sha256']==author['sha256']==t['rows'][1]['source_sha256']
    assert cpu['failures']==['normal_mapped_without_tangents'] and cpu['statistics']['normal_mapped_without_tangents']==1
    assert t['passed'] and t['same_generated_foliage_tangents'] and all(s['valid'] for row in t['rows'] for s in row['surfaces'])
    assert sha(author['source'])==author['source_sha256'] and sha(author['master'])==author['master_sha256']
    raw=GLB.read_bytes();jl=struct.unpack_from('<I',raw,12)[0];d=json.loads(raw[20:20+jl]);b=raw[28+jl:]
    def pixels(texture):
        i=d['textures'][texture]['source'];v=d['bufferViews'][d['images'][i]['bufferView']];a=v.get('byteOffset',0)
        return np.array(Image.open(io.BytesIO(b[a:a+v['byteLength']])).convert('RGB'))
    channels=[]
    for mat in d['materials']:
        if mat.get('name') not in ['S10 fired clay brick','S10 planting earth']:continue
        record=author['masonry']['source_inputs'][mat['name']];inputs=record['inputs']
        for item in inputs.values():assert sha(item['path'])==item['sha256']
        n=np.array(Image.open(inputs['normal_path']['path']).convert('RGB'));n[:,:,1]=255-n[:,:,1]
        actual=pixels(mat['normalTexture']['index']);delta=np.abs(actual.astype(int)-n.astype(int));assert delta.max()<=1
        color=pixels(mat['pbrMetallicRoughness']['baseColorTexture']['index']);expected=np.array(Image.open(inputs['texture_path']['path']).convert('RGB'));assert np.array_equal(color,expected)
        channels.append({'material':mat['name'],'base_color_pixels_exact':True,'normal_green_inverted_once_max_u8_delta':int(delta.max()),'normal_std_rgb':actual.std(axis=(0,1)).tolist(),'normal_strength':mat['normalTexture'].get('scale',1),'input_records':inputs})
    assert len(channels)==2
    old=read(REV/'baseline/report.json');new=read(GP);assert old['bounds']==new['bounds'],'Changed overall bounds'
    resolved=copy.deepcopy(cpu);resolved.update({'raw_cpu_report':ident(cp),'source_tangent_omission':{'node':'Foliage','status':'resolved by actual production importer; source foliage bytes unchanged','production_probe':ident(tp),'generated_tangents_identical_to_original':True},'failures':[],'resource_passed':True,'channel_validation':channels,'native_bounds_exactly_match_original':True,'compaction_scope':'Only newly assembled S10 planter. Removed unreachable old masonry graphs, preserving every live resolved payload. Historical generic compactor scope_note in its raw audit is not this asset scope.'})
    write(REV/(NAME+'_resource_resolved.json'),resolved)
elif A.stage=='accept':
    cp=REV/(NAME+'_resource_resolved.json');cpu=read(cp);g=read(GP);dp=REV/(NAME+'_diagnostics/report.json');dg=read(dp);ap=SRC/(NAME+'_authoring.json');author=read(ap)
    assert cpu['resource_passed'] and g['passed'] and dg['passed'] and sha(GLB)==cpu['sha256']==g['identity']['sha256']==dg['identity']['sha256']
    assert sha(author['master'])==author['master_sha256'] and sha(GP.parent/'asset.scn')==g['native_sha']
    views=[v['name'] for v in g['screenshots']];diag=['leaf_edge_bright_still','leaf_edge_dark_still','soil_and_roots_still']
    assert len(views)==14
    evidence=image_evidence(GP.parent,views)+image_evidence(dp.parent,diag)
    stats=cpu['statistics'];cost={'source_bytes':GLB.stat().st_size,'native_bytes':g['native_bytes'],'triangles':stats['triangles'],'mesh_nodes':cpu['mesh_nodes'],'surfaces':stats['primitives'],'materials':cpu['materials'],'embedded_images':stats['embedded_images'],'rgba8_mip_budget_bytes':stats['rgba8_mip_budget_bytes'],'near_draw_calls_with_ground':g['screenshots'][0]['draw_calls_with_ground'],'actual_RSS_VRAM':'not measured','LOD_decision':'37,044 triangles for this scarce 3.6m courtyard prop; preserve real brick joint/edge silhouette and original foliage. No new LOD or forced decimation in this layout asset correction. Native automatic batching remains supported. 384 MiB RGBA8+mip conservative texture budget, primarily inherited foliage; not measured residency.'}
    decision={'structure_passed':True,'reference_correction':'Warm red small units and grey joints replace the unrelated cream large-block appearance; overall bounds exact and independent placement retained.','reviewed_scope':'Listed native normal/oblique light views and isolated foliage silhouettes. Soil diagnostic hides foliage for inspection only, never in export.','near_material_pending':['Close-range clay pores, irregular weathering and less uniform grey joints remain material-detail work; this is not final hero prop material approval.','Final map placement/lighting belongs to the layout task.','Continuous wind temporal stability is not proven by these two static wind samples.'],'LOD_decision':cost['LOD_decision'],'viewed':views,'diagnostic_views':diag,'process_log_caveat':'Native gallery process exits 0 but logs 5 ObjectDB instances / 2 resources still alive at harness shutdown. Native persistence, physics, images and source integrity pass; this is not a claim of a warning-free or leak-measured engine run.'}
    proof={'id':NAME,'passed':True,'acceptance_stage':'structure_and_layout_candidate','source_path':GLB.as_posix(),'source_sha256':sha(GLB),'authoring':ident(ap),'master':ident(author['master']),'native':ident(GP.parent/'asset.scn'),'cpu_report':ident(cp),'gpu_report':ident(GP),'diagnostic_report':ident(dp),'generator':g['generator'],'bounds':g['bounds'],'anchors':author['anchors'],'cost':cost,'visual_evidence':evidence,'baseline_viewed':image_evidence(REV/'baseline',['near_still','raking_light_still']),'visual_decision':decision,'near_material_pending':decision['near_material_pending'],'status':{'resources':'passed with explicit production tangent resolution','reference_and_structure':'passed for layout variant','runtime_pipeline':'isolated native save/reopen and collision passed','formal_library':'pending publication and HTTP','formal_map':'not modified'},'scope':'Independent S10 courtyard planter; foliage source graph unchanged. No global replacement, no user map write.'}
    write(PROOF,proof)
elif A.stage in ['publish','resume']:
    proof=read(PROOF);assert proof['passed'] and proof['source_sha256']==sha(GLB)
    PUB.parent.mkdir(parents=True,exist_ok=True);assert not PUB.exists()
    maps={p.as_posix():sha(p) for p in [RT/'packs/default/maps/axel_town/map.gltf',RT/'maps/medieval_river_town/map.gltf'] if p.exists()}
    args=['--publish','--source='+GLB.as_posix(),'--sha256='+sha(GLB),'--review='+PROOF.as_posix(),'--review-sha256='+sha(PROOF),'--out='+PUB.as_posix(),'--id='+NAME,'--label=S10 暖红细砖花池 · 原比例灌木','--category=庭院/花池']
    if A.stage=='resume':
        prior=read(FAILED_PUB);assert prior['import_result']['compiled_asset']['reason']=='cache_capacity';args.append('--resume-receipt='+FAILED_PUB.as_posix())
    gpu('import_s12_residential_library.gd',args,PUB.with_suffix('.log'))
    pub=read(PUB);assert pub['ok'] and pub['completed']
    for path,expected in maps.items():assert sha(path)==expected,'Formal map changed during import'
    write(PUB.parent/'map_guards.json',{'formal_maps_unchanged':maps,'map_modified_by_this_task':False})
elif A.stage=='http':
    HTTP.mkdir(parents=True,exist_ok=True);assert not (HTTP/'editor_verification.json').exists()
    gpu('test_s10_planter_published_20261017.gd',['--receipt='+PUB.as_posix(),'--out='+HTTP.as_posix()],HTTP/'process.log',720)
elif A.stage=='handoff':
    proof=read(PROOF);pub=read(PUB);http=read(HTTP/'editor_verification.json');item=read(HTTP/'items'/(NAME+'.json'));author=read(SRC/(NAME+'_authoring.json'))
    assert pub['ok'] and http['passed'] and http['completed'] and http['verified_count']==1 and item['http_passed']
    target=pub['items'][0]['target'];assert sha(target)==sha(GLB)==proof['source_sha256'];assert sha(author['source'])==author['source_sha256']
    result={'date':'2026-10-17','stage':'formal shared library ready; layout task handles map placement','id':NAME,'label':pub['items'][0]['label'],'source':ident(GLB),'formal_asset_id':target,'formal_source':ident(target),'formal_entry':item['entry'],'formal_native_identity':item['formal_native_identity'],'master':proof['master'],'original_planter':ident(author['source']),'bounds':proof['bounds'],'anchors':proof['anchors'],'recommended_scale':[1,1,1],'preserved':'Exact original overall AABB and root transforms, foliage geometry/material/UV/images/wind/extras. Structure walk-blocking and foliage nonblocking/pickable verified.','reference_correction':proof['visual_decision']['reference_correction'],'acceptance':ident(PROOF),'publication':ident(PUB),'formal_http':ident(HTTP/'editor_verification.json'),'cost':proof['cost'],'near_material_pending':proof['near_material_pending'],'report':'D:/code/rmmo/docs/s10_warm_brick_planter_20261017.md','formal_map_modified':False,'preview':proof['visual_evidence'][0],'placement_note':'Use normal place_asset root on ground, original native scale. Do not globally substitute the old cream planter; only chosen S10 instances.'}
    write(OUT/'handoff.json',result)
print('S10_PLANTER_DELIVERY',A.stage,'complete',flush=True)
