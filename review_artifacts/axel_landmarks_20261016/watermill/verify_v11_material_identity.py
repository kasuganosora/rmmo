"""Resolve material image references before comparing the unchanged v10 recipe."""
import sys,json,hashlib
from pathlib import Path
sys.path.insert(0,'D:/code/rmmo/tools')
from repair_s12_stone_materials import read_glb,view
BASE=Path('D:/code/rmmo_runtime/art_sources/axel_landmarks_20261016/watermill')
def recipe(version):
    j,b,_=read_glb(BASE/version/'axel_watermill.glb')
    hashes=[hashlib.sha256(view(j,b,i['bufferView'])).hexdigest() for i in j['images']]
    def resolved(value,key=''):
        if isinstance(value,list):return [resolved(x) for x in value]
        if not isinstance(value,dict):return value
        result={k:resolved(v,k) for k,v in value.items()}
        if key.endswith('Texture') and 'index' in value:
            t=j['textures'][value['index']];result['index']={'image_sha256':hashes[t['source']],'sampler':j.get('samplers',[])[t['sampler']] if 'sampler' in t else None}
        return result
    return {'materials':{m['name']:resolved(m) for m in j['materials']},'images':sorted(hashes),'glass_extras':{n['name']:n['extras']['rmmo_tinted_glass'] for n in j['nodes'] if 'rmmo_tinted_glass' in n.get('extras',{})}}
a,b=recipe('v10'),recipe('v11')
assert a==b,'Unexpected material/image/consumed glass contract change'
out={'old_version':'v10','new_version':'v11','all_resolved_material_recipes_equal':True,'all_encoded_image_sha256_equal':True,'consumed_glass_metadata_equal':True,'material_count':len(a['materials']),'image_count':len(a['images']),'old_source_sha256':hashlib.sha256((BASE/'v10/axel_watermill.glb').read_bytes()).hexdigest(),'new_source_sha256':hashlib.sha256((BASE/'v11/axel_watermill.glb').read_bytes()).hexdigest(),'resolved':a}
Path(__file__).with_name('v10_v11_material_identity.json').write_text(json.dumps(out,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps({k:v for k,v in out.items() if k!='resolved'}))
