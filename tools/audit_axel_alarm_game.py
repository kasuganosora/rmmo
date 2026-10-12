"""Audit exported resource costs and same-camera pixel differences (not FPS)."""
import io,json,struct,hashlib
from pathlib import Path
import numpy as np
from PIL import Image
BASE=Path('D:/code/rmmo/review_artifacts')
OUT=BASE/'alarm_tower_game_20261011'
def read(path):
    raw=path.read_bytes();n=struct.unpack_from('<I',raw,12)[0]
    return json.loads(raw[20:20+n]),raw[28+n:],len(raw)
def audit(path):
    j,b,size=read(path);rows=[]
    for im in j['images']:
        view=j['bufferViews'][im['bufferView']];offset=view.get('byteOffset',0)
        raw=b[offset:offset+view['byteLength']];pic=Image.open(io.BytesIO(raw))
        rows.append({'name':im.get('name'),'size':list(pic.size),'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest(),
                     'rgba8_mips_bytes_estimate':pic.width*pic.height*4*4/3})
    return {'file_bytes':size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
            'images':rows,'texture_rgba8_mips_mib_estimate':sum(r['rgba8_mips_bytes_estimate'] for r in rows)/1048576,
            'meshes':len(j['meshes']),'materials':len(j['materials'])}
def differences(a,b):
    x=np.asarray(Image.open(a).convert('RGB')).astype(np.float32)
    y=np.asarray(Image.open(b).convert('RGB')).astype(np.float32)
    diff=np.abs(x-y);changed=np.max(diff,axis=2)>4
    return {'mean_absolute_8bit':float(diff.mean()),'pixels_over_4_levels_fraction':float(changed.mean()),
            'p99_absolute_8bit':float(np.percentile(diff,99))}
source=audit(BASE/'alarm_tower_materials_v3_20261011/guild_alarm_tower.glb')
game=audit(OUT/'guild_alarm_tower_game.glb')
review=json.loads((OUT/'game_review.json').read_text(encoding='utf8'))
assert review['passed'] and review['sha256']==game['sha256'],'Engine review must match final GLB'
assert review.get('roundtrip_lod_nodes')==36,'LOD metadata roundtrip missing'
assert {r['sha256'] for r in source['images']}=={r['sha256'] for r in game['images']},'Texture pixels/encoding changed'
assert game['file_bytes']<source['file_bytes']
pairs={name:differences(OUT/f'master_{name}.png',OUT/f'game_{name}.png') for name in ['near','horn_close','medium','far']}
switches={str(d):differences(OUT/f'switch_{d}_previous.png',OUT/f'switch_{d}_automatic.png') for d in [42,112]}
report={'source':source,'game':game,'all_texture_payloads_preserved':True,'same_camera_comparisons':pairs,
        'lod_switch_comparisons':switches,'notes':['Pixel metrics cover full frames including background; manual visual review remains required.',
        'Texture memory is an RGBA8+mip estimate, not a measured VRAM allocation or compressed GPU size.']}
(OUT/'delivery_audit.json').write_text(json.dumps(report,indent=2),encoding='utf8')
manifest={'id':'guild_alarm_tower','label':'阿克塞尔告警塔·游戏优化版','file':'guild_alarm_tower_game.glb',
          'source_master':'../alarm_tower_materials_v3_20261011/guild_and_alarm_tower_materials.blend',
          'editable_game':'guild_alarm_tower_game.blend','sha256':game['sha256'],
          'lod_triangles':review['lod_triangles'],'lod_ranges_m':[0,40,110],
          'range_origin':'common tower bounds centre at Y=16.685m; far level has no distance cutoff',
          'independent_components':12,'material_count':6,'shooting_slits':16,
          'collision':'one permanent near mesh per shaft/crown/roof, none for duplicate LODs and brass ornaments',
          'engine_adapter':'scripts/world3d/asset_visibility_range.gd',
          'status':'offline game asset verified; not published to resource catalogue or user map',
          'interior_traversal_complete':False,'review':'game_review.json','audit':'delivery_audit.json'}
(OUT/'asset_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps({k:v for k,v in report.items() if k not in ['source','game']},indent=2))
print('RESOURCE_COSTS',source['file_bytes'],game['file_bytes'],source['texture_rgba8_mips_mib_estimate'],game['texture_rgba8_mips_mib_estimate'])
