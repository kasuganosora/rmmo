"""Validate the actual standalone statue and v9 scene exports."""
import hashlib,json,struct
from pathlib import Path
base=Path(__file__).resolve().parents[2]/'rmmo_runtime/art_sources/axel_guild'
out=base/'whitebox_v9';asset=base/'fab_knight_statue_v1'
def read_glb(path):
    raw=path.read_bytes();size,kind=struct.unpack_from('<II',raw,12)
    assert kind==0x4e4f534a
    return json.loads(raw[20:20+size]),hashlib.sha256(raw).hexdigest()
gltf,digest=read_glb(out/'axel_guild_whitebox.glb')
single,single_digest=read_glb(asset/'guild_knight_statue_whitebox.glb')
current=json.loads((out/'manifest.json').read_text(encoding='utf8'))
previous=json.loads((base/'whitebox_v8/manifest.json').read_text(encoding='utf8'))
play=json.loads((out/'statue_playability_review.json').read_text(encoding='utf8'))
nodes=gltf['nodes'];standalone=single['nodes']
def triangles(data):
    return sum(data['accessors'][p['indices']]['count']//3 for m in data['meshes'] for p in m['primitives'])
checks={
    'actual_source_triangles_preserved':triangles(single)==3274,
    'two_independent_meshes':len(single['meshes'])==2,
    'one_scene_statue_root':sum(n.get('extras',{}).get('asset_id')=='guild_fab_knight_statue' for n in nodes)==1,
    'no_old_humanoid_placeholder':not any(n.get('name','').startswith(('Statue head','Statue torso','Statue breastplate','Statue cloak','Statue hand','Statue sword','Statue shoulder')) for n in nodes),
    'no_textures_in_scene_or_statue':not any(d.get('images') or d.get('textures') for d in [gltf,single]),
    'rooms_dimensions_furniture_unchanged':all(current[k]==previous[k] for k in ['rooms','dimensions_m','furniture_instances','stairs','decorative_panels']),
    'matches_playtested_export':digest==play['glb_sha256']==current['exports']['axel_guild_whitebox.glb'],
    'actual_walk_and_camera_pass':not play['failures'] and not play['camera_errors'],
    'standalone_uvs_preserved':all('TEXCOORD_0' in p['attributes'] for m in single['meshes'] for p in m['primitives'])}
report={'checks':checks,'failures':[k for k,v in checks.items() if not v],
        'scene_sha256':digest,'standalone_sha256':single_digest,
        'statue_triangles':triangles(single),'unique_mesh_triangles':triangles(gltf),
        'scene_triangles':current['triangles_evaluated'],
        'camera_samples':play['camera_samples'],'routes':len(play['routes']),'orbits':len(play['orbits']),
        'dimensions_m':current['fab_statue']['dimensions_m'],
        'review_views':['09_statue_decorative_panels.png','10_decorative_panels_side.png'],
        'optimization':'No reduction: 3274 source triangles retained; source archive and blend preserved.',
        'scope':'Offline whitebox replacement; user-approved style exception for this statue only; no editor publication.'}
(out/'statue_delivery_review.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps(report,ensure_ascii=False,indent=2))
raise SystemExit(bool(report['failures']))
