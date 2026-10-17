"""Read-only asset inventory for the 2026-10-12 guild acceptance review."""
import hashlib, io, json, struct
from collections import Counter, defaultdict
from pathlib import Path
from PIL import Image

ROOT = Path('D:/code/rmmo_runtime/art_sources/axel_guild')
OUT = Path('D:/code/rmmo_runtime/review_artifacts/axel_guild_finish_20261012/full_review')
MAIN = ROOT / 'finish_v1/entry_extension/axel_guild_entry.glb'

def read(path):
    data = path.read_bytes()
    size = struct.unpack_from('<I', data, 12)[0]
    j = json.loads(data[20:20+size])
    return j, data[28+size:], hashlib.sha256(data).hexdigest(), len(data)

def audit(path):
    j, binary, sha, size = read(path)
    meshes = []
    for m in j.get('meshes', []):
        meshes.append(sum(j['accessors'][p.get('indices', p['attributes']['POSITION'])]['count']//3
                          for p in m['primitives'] if p.get('mode',4)==4))
    roots = j['scenes'][j.get('scene',0)]['nodes']; live=set()
    def visit(i):
        if i in live:return
        live.add(i)
        for c in j['nodes'][i].get('children',[]):visit(c)
    for i in roots:visit(i)
    images=[]
    for im in j.get('images',[]):
        v=j['bufferViews'][im['bufferView']];b=binary[v.get('byteOffset',0):v.get('byteOffset',0)+v['byteLength']]
        pic=Image.open(io.BytesIO(b))
        images.append(dict(name=im.get('name',''),sha256=hashlib.sha256(b).hexdigest(),size=list(pic.size),encoded_bytes=len(b),rgba_base_bytes=pic.width*pic.height*4))
    groups=defaultdict(list)
    for i in sorted(live):
        n=j['nodes'][i];e=n.get('extras',{})
        if e.get('asset_id'):groups[e['asset_id']].append(dict(index=i,name=n.get('name'),extras=e))
    return dict(path=str(path).replace('\\','/'),sha256=sha,source_bytes=size,
        unique_triangles=sum(meshes),default_scene_instance_triangles=sum(meshes[j['nodes'][i]['mesh']] for i in live if 'mesh' in j['nodes'][i]),
        mesh_nodes=sum('mesh' in j['nodes'][i] for i in live),surfaces=sum(len(m['primitives']) for m in j.get('meshes',[])),
        materials=len(j.get('materials',[])),images=images,animations=[a.get('name') for a in j.get('animations',[])],
        unused_scene_nodes=len(j['nodes'])-len(live),extensions=j.get('extensionsUsed',[]),
        actual_collision_tags=dict(Counter(j['nodes'][i].get('extras',{}).get('rmmo_collision','absent') for i in live)),
        author_collision_review_count=sum(j['nodes'][i].get('extras',{}).get('collision_review',False) for i in live),
        asset_groups=dict(groups),lod_tag_count=sum('rmmo_visibility_range' in j['nodes'][i].get('extras',{}) for i in live))

def main():
    OUT.mkdir(parents=True,exist_ok=True)
    assets=[]
    for group in ['furniture_v1','furnishings_v1','guestroom_v1','textiles_sanitary_v1']:
        meta=json.loads((ROOT/group/'manifest.json').read_text(encoding='utf8'))
        for key,v in meta['assets'].items():
            p=ROOT/group/'game'/(v['asset_id']+'.glb')
            row=audit(p);row.update(id=v['asset_id'],label=v['label'],group=group,references=v.get('references',v.get('reference_ids','')))
            assets.append(row)
    extra=[('guild_statue_decorative_panel',ROOT/'decorative_panel_v1/guild_statue_decorative_panel_game.glb'),
           ('guild_hanging_skeleton',ROOT/'landmarks_v2/guild_hanging_skeleton.glb'),
           ('guild_fab_knight_statue',ROOT/'fab_knight_statue_v1/guild_knight_statue_whitebox.glb'),
           ('guild_hall_magic_lantern',Path('D:/code/rmmo_runtime/review_artifacts/axel_guild_materials_20261011/guild_hall_magic_lantern.glb')),
           ('guild_entrance_crescent_standard',ROOT/'finish_v1/guild_entrance_crescent_standard.glb'),
           ('guild_alarm_tower_game',Path('D:/code/rmmo_runtime/review_artifacts/alarm_tower_game_20261011/guild_alarm_tower_game.glb'))]
    for name,path in extra:
        if path.exists():
            row=audit(path);row.update(id=name,label=name,group='special');assets.append(row)
    data=dict(main=audit(MAIN),assets=assets,scope='Current approved assembly plus reusable standalone inventory. Old library resources are not assumed equivalent to assembly material variants.')
    (OUT/'inventory.json').write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf8')
    print('INVENTORY',len(assets),'library assets;',len(data['main']['asset_groups']),'assembly asset kinds')

if __name__=='__main__':main()
