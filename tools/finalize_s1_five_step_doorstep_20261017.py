"""Publish the separately reviewed, exact-size S1 five-step doorstep."""
import argparse,hashlib,io,json,struct,subprocess
from pathlib import Path
from PIL import Image
from run_godot_background import run_background
P=argparse.ArgumentParser();P.add_argument('phase',choices=['accept','publish','handoff']);A=P.parse_args()
ROOT=Path('D:/code/rmmo_runtime');OUT=ROOT/'review_artifacts/s1_five_step_doorstep_20261017';SRC=ROOT/'art_sources/s1_five_step_doorstep_20261017/v1';ID='s1_doorstep_stairs_5';SOURCE=SRC/(ID+'.glb')
def read(p):return json.loads(Path(p).read_text(encoding='utf-8'))
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def ident(p):return {'path':Path(p).as_posix(),'sha256':sha(p),'bytes':Path(p).stat().st_size}
def write(p,d):
    p=Path(p);assert not p.exists(),'Immutable evidence exists';p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
if A.phase=='accept':
    report=OUT/'v1/report.json';gpu=read(report);cpu=read(OUT/'cpu'/(ID+'_cpu_audit.json'));author=read(SRC/(ID+'_authoring.json'))
    assert gpu['passed'] and cpu['resource_passed'] and author['sha256']==cpu['sha256']==gpu['identity']['sha256']==sha(SOURCE)
    raw=SOURCE.read_bytes();n=struct.unpack_from('<I',raw,12)[0];d=json.loads(raw[20:20+n]);blob=raw[28+n:]
    def pixels(t):
        im=d['images'][d['textures'][t]['source']];v=d['bufferViews'][im['bufferView']];o=v.get('byteOffset',0)
        return hashlib.sha256(Image.open(io.BytesIO(blob[o:o+v['byteLength']])).convert('RGBA').tobytes()).hexdigest()
    m=next(m for m in d['materials'] if m.get('normalTexture'));p=m['pbrMetallicRoughness'];expected={'albedo':pixels(p['baseColorTexture']['index']),'normal':pixels(m['normalTexture']['index']),'roughness':pixels(p['metallicRoughnessTexture']['index'])}
    pictures=[]
    for p in (OUT/'v1').glob('*.webp'):
        receipt=read(str(p)+'.review-image.json');assert receipt['quality']==90 and not receipt['lossless'] and receipt['sha256']==sha(p);pictures.append(ident(p))
    assert len(pictures)==7
    write(OUT/'acceptance.json',{'passed':True,'acceptance_stage':'structure_and_layout_candidate','source_path':SOURCE.as_posix(),'source_sha256':sha(SOURCE),'generator':gpu['generator'],'gpu_report':ident(report),'cpu_audit':ident(OUT/'cpu'/(ID+'_cpu_audit.json')),'authoring':ident(SRC/(ID+'_authoring.json')),'master':ident(SRC/(ID+'_master.blend')),'expected_texture_rgba8':expected,'pictures':pictures,'anchors':author['anchors'],'bounds':gpu['bounds'],'manual_visual_review':'Seven actual native views inspected. Five 0.16m rises, 0.40m exposed treads and 0.80m upper landing; open seam issue avoided with a real closed 4mm recessed mortar bed. Material matches approved S12 worked limestone. Separate house approach assembly reviewed with house v4.','near_material_pending':[],'resource_status':'pass; 3804 triangles, 2 meshes, 2 materials, no forced LOD','pipeline_status':'pass; native save/reopen, 35 support rays and 10 production controller route samples','integration_status':'formal shared library HTTP pending; not placed in real map'})
    print('FIVE_STEP_ACCEPTANCE',sha(SOURCE))
elif A.phase=='publish':
    proof=OUT/'acceptance.json';assert read(proof)['source_sha256']==sha(SOURCE)
    active=subprocess.check_output(['powershell','-NoProfile','-Command',"Get-CimInstance Win32_Process -Filter \"Name LIKE '%Godot%'\" | Where-Object { $_.CommandLine -notmatch '--headless' } | Select-Object -ExpandProperty ProcessId"],text=True).strip();assert not active,'Other GPU '+active
    guards={p.as_posix():sha(p) for p in [ROOT/'packs/default/maps/axel_town/map.gltf',ROOT/'maps/medieval_river_town/map.gltf'] if p.exists()}
    receipt=OUT/'publication_raw.json';assert not receipt.exists()
    cmd=['D:/tools/godot/Godot_v4.7.2-stable_win64.exe','--path','D:/code/rmmo','--script','res://tools/import_s12_residential_library.gd','--','--publish','--source='+SOURCE.as_posix(),'--sha256='+sha(SOURCE),'--review='+proof.as_posix(),'--review-sha256='+sha(proof),'--out='+receipt.as_posix(),'--id='+ID,'--label=S1 五级门前石阶（0.8米平台）','--category=街景设施']
    r=run_background(cmd,cwd='D:/code/rmmo',timeout=360);(OUT/'publication.log').write_bytes(r.stdout);assert r.returncode==0
    raw=read(receipt);assert raw['ok'] and raw['completed']
    for p,h in guards.items():assert sha(p)==h
    cat=ROOT/'packs/default/assets/library.json';write(OUT/'publication.json',{'ok':True,'completed':True,'items':raw['items'],'receipts':[ident(receipt)],'catalog_path':cat.as_posix(),'catalog_sha_after':sha(cat),'formal_map_modified':False,'protected_maps':guards,'stage':'structure_and_layout_candidate'});print('FIVE_STEP_PUBLISHED',raw['items'][0]['target'])
else:
    formal=OUT/'formal_http/editor_verification.json';assert read(formal)['passed'] and read(formal)['completed']
    item=read(OUT/'publication.json')['items'][0];proof=read(OUT/'acceptance.json');gpu=read(OUT/'v1/report.json');cpu=read(OUT/'cpu'/(ID+'_cpu_audit.json'))
    write(OUT/'handoff.json',{'id':ID,'label':item['label'],'source':ident(SOURCE),'formal_asset':ident(item['target']),'acceptance':ident(OUT/'acceptance.json'),'publication':ident(OUT/'publication.json'),'formal_http':ident(formal),'master':ident(SRC/(ID+'_master.blend')),'bounds':proof['bounds'],'anchors':proof['anchors'],'cost':{'source_bytes':SOURCE.stat().st_size,'native_bytes':gpu['native_bytes'],'triangles':cpu['statistics']['triangles'],'rgba8_mip_budget_bytes':cpu['statistics']['rgba8_mip_budget_bytes'],'measured_rss_vram':None},'house_connection':{'relative_origin':[.6,-.72,9.84],'relative_yaw':0,'top_y_relative_house':.08,'threshold_y_relative_house':.16,'back_edge_z_relative_house':7.44,'world_proposal_if_house_at_324_6p15_253_yaw_m90':{'position':[314.16,5.43,253.6],'yaw_degrees':-90},'note':'Top platform meets the front threshold edge horizontally and sits 8cm below the original threshold. The actual house v5 controller roundtrip passed with this arrangement; choose final grounded height in layout without scaling risers. This is a tested placement example, not an approved terrain placement. No formal map change here.'}});print('FIVE_STEP_HANDOFF_COMPLETE')
