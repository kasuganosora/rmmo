"""Check delivered v8 GLB scope, texture-free materials and preserved L1 layout."""
import hashlib
import json
import struct
from pathlib import Path

base=Path(__file__).resolve().parents[2]/'rmmo_runtime/art_sources/axel_guild'
out=base/'whitebox_v8'
manifest=json.loads((out/'manifest.json').read_text(encoding='utf8'))
old=json.loads((base/'whitebox_v7/manifest.json').read_text(encoding='utf8'))
raw=(out/'axel_guild_whitebox.glb').read_bytes()
length,kind=struct.unpack_from('<II',raw,12)
assert kind==0x4e4f534a
gltf=json.loads(raw[20:20+length])
checks={}
checks['no_texture_images']=not gltf.get('images') and not gltf.get('textures')
checks['room_bounds_and_door_apertures_unchanged']=manifest['rooms']==old['rooms']
checks['building_dimensions_unchanged']=manifest['dimensions_m']==old['dimensions_m']
def upper_furniture(m):
    return [{k:v for k,v in f.items() if k!='name'} for f in m['furniture_instances'] if f['semantic_group']=='32_Furniture_L1']
checks['upper_furniture_placements_unchanged']=upper_furniture(manifest)==upper_furniture(old)
nodes=gltf['nodes']
def named(prefix):return [n for n in nodes if n.get('name','').startswith(prefix)]
checks['27_separate_treads']=len(named('Timber tread'))==27
checks['27_separate_risers_and_landing_riser']=len(named('Timber riser'))==27 and len(named('Top landing timber riser'))==1
checks['3_separate_stair_strings']=len(named('Timber stair string'))==3
checks['obsolete_stair_solid_blocks_removed']=not named('Stair tread')
checks['4_sloped_cloths_2_round_banners']=len(named('Slope cloth bay'))==4 and len(named('Round bottom long banner'))==2
checks['statue_cloak_and_hands_present']=len(named('Statue cloak silhouette'))==1 and len(named('Statue hand envelope'))==2
checks['reception_return_present']=len(named('Reception timber return'))==1
checks['roof_floor_ceiling_door_groups_preserved']=all(named(n) for n in ['20_Floor_L1','31_Doors_L1','33_Ceilings_L1','43_Entrance_Doors','50_Roof'])
play=json.loads((out/'layout_playability_review.json').read_text(encoding='utf8'))
digest=hashlib.sha256(raw).hexdigest()
checks['tested_glb_matches_delivery']=play['glb_sha256']==digest and manifest['exports']['axel_guild_whitebox.glb']==digest
checks['production_walk_and_camera_pass']=not play['failures'] and not play['camera_errors']
result={'checks':checks,'failures':[k for k,v in checks.items() if not v],
        'glb_sha256':digest,'triangles':manifest['triangles_evaluated'],
        'existing_asset_instances':len(manifest['furniture_instances']),
        'new_whitebox_cloth_instances':6,
        'routes':len(play['routes']),'orbits':len(play['orbits']),
        'limitations':['Whitebox geometry only; statue/skull anatomy remains schematic.',
          'Unchanged guest rooms use v7 playability evidence; no claim of dynamic cabinet clearance.',
          'No editor publication, navmesh baking or dynamic door interaction.']}
(out/'geometry_review.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps(result,ensure_ascii=False,indent=2))
raise SystemExit(bool(result['failures']))
