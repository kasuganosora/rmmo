"""Write the two-asset handoff only after both real-library HTTP checks pass."""
import hashlib,json
from pathlib import Path

ROOT=Path('D:/code/rmmo_runtime');HOUSE=ROOT/'review_artifacts/s1_bridge_left_residence_20261017';STAIRS=ROOT/'review_artifacts/s1_five_step_doorstep_20261017'
def read(p):return json.loads(p.read_text(encoding='utf-8'))
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def ident(p):return {'path':p.as_posix(),'sha256':sha(p)}
items=[]
for p in [HOUSE/'v5_delivery/handoff.json',STAIRS/'handoff.json']:
    d=read(p);http=read(Path(d['formal_http']['path']))
    assert http['passed'] and http['completed']
    for key in ['source','formal_asset','acceptance','publication','formal_http','master']:
        assert sha(d[key]['path'])==d[key]['sha256'],key
    items.append({'id':d['id'],'handoff':ident(p),'formal_asset':d['formal_asset'],'bounds':d['bounds'],'anchors':d['anchors']})
assembly=HOUSE/'v5/report.json';a=read(assembly)
assert a['passed'] and all(r['passed'] for r in a['approach_routes'])
assert a['identity']['sha256']==items[0]['formal_asset']['sha256']
assert a['assembly_inputs'][0]['sha256']==items[1]['formal_asset']['sha256']
p=HOUSE/'handoff.json';assert not p.exists()
report={'completed':True,'stage':'structure_and_layout_candidate','items':items,'assembly_review':ident(assembly),'map_deployment':'No formal map changes here. Final terrain bedding, S1 framing and outdoor traversal belong to layout task.','layout_latest_proposal':{'house_position':[324,6.15,253],'house_yaw':-90,'stairs_position':[314.18,5.39,253.6],'stairs_yaw':-90,'stairs_top_world_y':6.19,'house_threshold_world_y':6.31,'status':'supplied by layout task; final scene traversal pending there; isolated sample covered 8cm difference'},'near_material_pending':read(HOUSE/'v5_delivery/acceptance.json')['near_material_pending'],'documentation':'D:/code/rmmo/docs/s1_bridge_left_residence_20261017.md','gpu_status':'All owned publication/review processes completed before handoff. Check current process list before the next GPU task.'}
p.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
doc=Path('D:/code/rmmo/docs/s1_bridge_left_residence_20261017.md');text=doc.read_text(encoding='utf-8')
text=text.replace('住宅v5已发布；石阶发布与两件正式HTTP使用验证进行中，最终见交付收据。','两件已发布并各自通过真实HTTP发现、放置、选择、撤销重做、保存重开；住宅附加逐层可选/隐藏、物理掩码和室内区域检查，石阶附加实际材质像素SHA与中心踏面支撑检查。')
text+='\n最终双件交付入口：`D:/code/rmmo_runtime/review_artifacts/s1_bridge_left_residence_20261017/handoff.json`；每件收据绑定正式GLB、母版、图审和真实HTTP报告SHA。正式素材库可用与正式地图部署分开记录。\n'
doc.write_text(text,encoding='utf-8')
print('S1_TWO_ASSET_DELIVERY',p)
