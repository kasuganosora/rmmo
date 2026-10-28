"""Record inspected S1 candidate, publish via shared importer, or finish handoff.

The accept phase is run only after actual image inspection; it cannot infer image
quality from a test pass. Real map files are guarded but never opened for writing.
"""
import argparse, hashlib, io, json, struct, subprocess
from pathlib import Path
from PIL import Image
from run_godot_background import run_background

P=argparse.ArgumentParser();P.add_argument('phase',choices=['accept','publish','handoff']);P.add_argument('--version',default='v5');P.add_argument('--resume-receipt');A=P.parse_args()
ROOT=Path('D:/code/rmmo_runtime');OUT=ROOT/'review_artifacts/s1_bridge_left_residence_20261017';SRC=ROOT/'art_sources/s1_bridge_left_residence_20261017'/A.version
DELIVERY=OUT if A.version=='v2' else OUT/(A.version+'_delivery')
ID='s1_bridge_left_residence';REPORT=OUT/A.version/'report.json';SOURCE=SRC/(ID+'.glb')
def read(p):return json.loads(Path(p).read_text(encoding='utf-8'))
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def ident(p):return {'path':Path(p).as_posix(),'sha256':sha(p),'bytes':Path(p).stat().st_size}
def write(p,data):
    p=Path(p)
    if p.exists():raise RuntimeError('Immutable evidence already exists: '+str(p))
    p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

if A.phase=='accept':
    gpu=read(REPORT);cpu_path=OUT/(A.version+'_cpu')/(ID+'_cpu_audit.json');cpu=read(cpu_path);author=read(SRC/(ID+'_authoring.json'))
    assert gpu['passed'] and cpu['resource_passed'] and gpu['identity']['sha256']==cpu['sha256']==author['sha256']==sha(SOURCE)
    pictures=[]
    for row in gpu['screenshots']:
        pic=Path(row['path']).with_suffix('.webp');record=read(str(pic)+'.review-image.json')
        assert record['quality']==90 and not record['lossless'] and record['sha256']==sha(pic)
        pictures.append({'name':row['name'],**ident(pic),'encoding_receipt':str(pic)+'.review-image.json'})
    raw=SOURCE.read_bytes();n=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+n]);blob=raw[28+n:]
    def pixel_sha(index):
        image=doc['images'][doc['textures'][index]['source']];v=doc['bufferViews'][image['bufferView']];o=v.get('byteOffset',0)
        return hashlib.sha256(Image.open(io.BytesIO(blob[o:o+v['byteLength']])).convert('RGBA').tobytes()).hexdigest()
    expected={}
    for m in doc['materials']:
        pbr=m.get('pbrMetallicRoughness',{})
        if not m.get('normalTexture'):continue
        expected[m['name']]={'normal_scale':m['normalTexture'].get('scale',1),'textures':{'albedo':pixel_sha(pbr['baseColorTexture']['index']),'normal':pixel_sha(m['normalTexture']['index']),'roughness':pixel_sha(pbr['metallicRoughnessTexture']['index'])}}
    assert len(expected)==5
    proof={'passed':True,'acceptance_stage':'structure_and_layout_candidate','source_path':SOURCE.as_posix(),'source_sha256':sha(SOURCE),'generator':gpu['generator'],'gpu_report':ident(REPORT),'cpu_audit':ident(cpu_path),'authoring':ident(SRC/(ID+'_authoring.json')),'master':ident(SRC/(ID+'_master.blend')),'pictures':pictures,'expected_material_textures':expected,
           'manual_visual_review':{'selected':A.version,'observed':'High swept gable, single tall front window, pale heavy door lintel and orange round-tail roof. Eave wall breakthrough and invisible inner roof from v1 corrected. Near/medium/far, back, open door, tile/stone/eave detail, loft and cutaway inspected.','rejected_versions':['v1: wall thickness caused a thin stone strip through eave; single-sided deck invisible from loft.']},
           'resource_status':'pass','visual_status':'structure/layout pass; inherited close material refinements remain pending','pipeline_status':'pass: actual native reopen, shader metadata and production collision/door/stair routes','integration_status':'formal library HTTP pending; formal map not deployed',
           'near_material_pending':['Existing dressed-stone trim and ground floor read too uniform at very close range; retain in separate material refinement list.','Roof tiles use normal-map relief on the body surface; individual geometric tails/contact shadows are not claimed.','Wall repetition, wood grain variation and assembled scene exposure remain separate near-field polish.'],
           'lod_assessment':'44k-triangle scarce landmark residence; no forced decimation or LOD at this structure/layout stage. Roof silhouette, hinges, floor parts preserved. Shared textures budgeted once; no actual RSS/VRAM or city FPS claim.',
           'anchors':author['anchors'],'bounds':gpu['bounds']}
    if A.version=='v3':
        delta=OUT/'v3_metadata_delta.json';pixels=OUT/'v3_visual_identity.json'
        assert read(delta)['passed'] and read(pixels)['passed']
        proof['metadata_only_delta']=ident(delta);proof['visual_identity_to_inspected_v2']=ident(pixels)
        proof['manual_visual_review']['observed']+=' v3 additionally excludes stair voids and wall thickness from indoor regions. Geometry/BIN and 12 exact PNG images unchanged from inspected v2.'
    if A.version in ('v4','v5'):
        proof['manual_visual_review']['observed']+=f" {A.version} includes a {-author['anchors']['foundation_bottom_y']:.2f}m deep closed perimeter foundation. Original floor/door height remains +0.16m. All 14 views including separate five-step approach assembly and below-ground foundation detail inspected."
        proof['assembly_inputs']=gpu['assembly_inputs'];proof['approach_routes']=gpu['approach_routes']
        proof['assembly_review_scope']='Gallery ground is deliberately lowered to foundation_bottom_y-0.01 to expose the complete footing. The separate doorstep is therefore above that diagnostic plane; grounded traversal uses its own floor at Y=-0.72. These images do not approve final terrain bedding. The model and step dimensions must be retained when layout seats both on actual ground.'
    write(DELIVERY/'acceptance.json',proof);print('S1_ACCEPTANCE_RECORDED',sha(SOURCE))
elif A.phase=='publish':
    proof=DELIVERY/'acceptance.json';data=read(proof);assert data['passed'] and data['source_sha256']==sha(SOURCE)
    maps=[ROOT/'packs/default/maps/axel_town/map.gltf',ROOT/'maps/medieval_river_town/map.gltf'];guards={p.as_posix():sha(p) for p in maps if p.exists()}
    active=subprocess.check_output(['powershell','-NoProfile','-Command',"Get-CimInstance Win32_Process -Filter \"Name LIKE '%Godot%'\" | Where-Object { $_.CommandLine -notmatch '--headless' } | Select-Object -ExpandProperty ProcessId"],text=True).strip()
    if active:raise RuntimeError('Other GPU job active: '+active)
    receipt=DELIVERY/('publication_resumed_raw.json' if A.resume_receipt else 'publication_raw.json');assert not receipt.exists()
    label='S1 石桥左侧陡山墙住宅'+({'v3':'（楼层范围修订）','v4':'（石地基版）','v5':'（1.1米石地基）'}.get(A.version,''))
    cmd=['D:/tools/godot/godot.windows.editor.x86_64.exe','--path','D:/code/rmmo','--script','res://tools/import_s12_residential_library.gd','--','--publish','--source='+SOURCE.as_posix(),'--sha256='+sha(SOURCE),'--review='+proof.as_posix(),'--review-sha256='+sha(proof),'--out='+receipt.as_posix(),'--id='+ID,'--label='+label,'--category=居民住宅']
    if A.resume_receipt:cmd.append('--resume-receipt='+Path(A.resume_receipt).as_posix())
    result=run_background(cmd,cwd='D:/code/rmmo',timeout=360);(DELIVERY/('publication_resumed.log' if A.resume_receipt else 'publication.log')).write_bytes(result.stdout)
    if result.returncode:raise RuntimeError('Publication failed; inspect immutable receipt')
    raw=read(receipt);assert raw['ok'] and raw['completed']
    for p,h in guards.items():assert sha(p)==h,'Concurrent protected map changed; do not overwrite it'
    catalog=ROOT/'packs/default/assets/library.json'
    write(DELIVERY/'publication.json',{'ok':True,'completed':True,'items':raw['items'],'receipts':[ident(receipt)],'catalog_path':catalog.as_posix(),'catalog_sha_after':sha(catalog),'formal_map_modified':False,'protected_maps':guards,'stage':'structure_and_layout_candidate'})
    print('S1_PUBLISHED',raw['items'][0]['target'])
else:
    proof=read(DELIVERY/'acceptance.json');publication=read(DELIVERY/'publication.json');formal=DELIVERY/'formal_http/editor_verification.json';verification=read(formal)
    assert verification.get('ok',verification.get('passed',False)),verification.keys()
    item=publication['items'][0];gpu=read(REPORT);cpu=read(OUT/(A.version+'_cpu')/(ID+'_cpu_audit.json'))
    write(DELIVERY/'handoff.json',{'id':ID,'label':item['label'],'stage':'structure_and_layout_candidate','source':ident(SOURCE),'formal_asset':ident(item['target']),'acceptance':ident(DELIVERY/'acceptance.json'),'publication':ident(DELIVERY/'publication.json'),'formal_http':ident(formal),'master':ident(SRC/(ID+'_master.blend')),'bounds':proof['bounds'],'anchors':proof['anchors'],'cost':{'source_bytes':SOURCE.stat().st_size,'native_bytes':gpu['native_bytes'],'triangles':cpu['statistics']['triangles'],'mesh_nodes':cpu['mesh_nodes'],'materials':cpu['materials'],'rgba8_mip_budget_bytes':cpu['statistics']['rgba8_mip_budget_bytes'],'measured_rss_vram':None},'near_material_pending':proof['near_material_pending'],'map_deployment':'Not placed or saved to axel_town here. Layout task owns final yaw -90, courtyard, trees and shot alignment.','footprint_note':'8.5x14m actual wall envelope. Full bounds also include eaves, frame projections, ridge caps and entrance threshold; use exact AABB for placement. Selected v5 includes closed stone perimeter foundation to Y=-1.10m; first finished floor and threshold remain Y=+0.16m.'})
    print('S1_HANDOFF_COMPLETE',item['target'])
