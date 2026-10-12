"""Retain the delivered default-scene tower; retire its obsolete alternate scene.

No mesh/material/image bytes are rewritten. LOD culling boxes gain 5 cm margin.
"""
import copy,json,struct,hashlib
from pathlib import Path
source=Path('D:/code/rmmo/review_artifacts/alarm_tower_game_20261011/guild_alarm_tower_game.glb')
out=Path('D:/code/rmmo_runtime/art_sources/axel_guild/repair_v2/guild_alarm_tower.glb')
b=source.read_bytes();n,k=struct.unpack_from('<II',b,12);j=json.loads(b[20:20+n]);old=copy.deepcopy(j)
assert not j.get('animations') and not j.get('skins')
live=set()
def visit(i):
    if i in live:return
    live.add(i)
    for c in j['nodes'][i].get('children',[]):visit(c)
scene=j['scenes'][j.get('scene',0)]
for i in scene['nodes']:visit(i)
mapping={old:new for new,old in enumerate(sorted(live))}
j['nodes']=[j['nodes'][i] for i in sorted(live)]
changed=[]
for node in j['nodes']:
    if 'children' in node:node['children']=[mapping[i] for i in node['children']]
    lod=node.get('extras',{}).get('rmmo_visibility_range')
    if lod:
        before=list(lod['bounds']);lod['bounds'][4]+=.05
        changed.append({'node':node['name'],'before':before,'after':lod['bounds']})
j['scenes']=[dict(scene,nodes=[mapping[i] for i in scene['nodes']])];j['scene']=0
payload=json.dumps(j,ensure_ascii=False,separators=(',',':')).encode();payload+=b' '*(-len(payload)%4);binary=b[20+n:]
out.write_bytes(struct.pack('<IIIII',0x46546c67,2,20+len(payload)+len(binary),len(payload),k)+payload+binary)
assert j['meshes']==old['meshes'] and j['materials']==old['materials'] and j['images']==old['images']
report={'source':str(source),'source_sha256':hashlib.sha256(b).hexdigest(),'path':str(out),'sha256':hashlib.sha256(out.read_bytes()).hexdigest(),'removed_nodes':len(old['nodes'])-len(j['nodes']),'old_scene_count':len(old['scenes']),'scene_count':1,'bounds_changes':changed,'geometry_material_texture_bytes_unchanged':True,'note':'Unused binary/table entries are conservatively retained; not a file-size optimization.'}
out.with_suffix('.repair.json').write_text(json.dumps(report,indent=2),encoding='utf8')
print(json.dumps({k:v for k,v in report.items() if k!='bounds_changes'}))
