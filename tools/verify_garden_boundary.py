"""Verify exported static modules and matched Blender reduction renders."""
from pathlib import Path
import json,struct,hashlib,sys
import numpy as np
from PIL import Image
OUT=Path(sys.argv[1] if len(sys.argv)>1 else 'D:/code/rmmo_runtime/art_sources/garden_boundary/height_150')
manifest=json.loads((OUT/'manifest.json').read_text(encoding='utf8'))
rows=[];failures=[]
for spec in manifest['assets']:
    p=OUT/'models'/(spec['id']+'.glb');b=p.read_bytes();n=struct.unpack_from('<I',b,12)[0];g=json.loads(b[20:20+n])
    triangles=sum(g['accessors'][v['indices']]['count']//3 for m in g['meshes'] for v in m['primitives'])
    surfaces=sum(len(m['primitives']) for m in g['meshes'])
    textured=[m for m in g['materials'] if 'baseColorTexture' in m.get('pbrMetallicRoughness',{})]
    positions=[g['accessors'][v['attributes']['POSITION']] for m in g['meshes'] for v in m['primitives']]
    top=max(pos['max'][1] for pos in positions)
    checks=dict(hash=hashlib.sha256(b).hexdigest()==spec['sha256'],triangles=triangles==spec['game_triangles'],one_mesh=len(g['meshes'])==1,two_surfaces=surfaces==2,stone_pbr=any('normalTexture' in m and 'metallicRoughnessTexture' in m['pbrMetallicRoughness'] for m in textured),embedded=all('bufferView' in im for im in g.get('images',[])),manifold=spec['manifold'])
    checks['height_matches_recipe']=abs(top-spec['recipe']['height'])<.005
    uv_valid=True
    for mesh in g['meshes']:
        for primitive in mesh['primitives']:
            material=g['materials'][primitive['material']]
            texture=material.get('pbrMetallicRoughness',{}).get('baseColorTexture')
            if texture is None:continue
            key='TEXCOORD_'+str(texture.get('texCoord',0))
            if key not in primitive['attributes']:uv_valid=False;continue
            accessor=g['accessors'][primitive['attributes'][key]];view=g['bufferViews'][accessor['bufferView']]
            uv=np.ndarray((accessor['count'],2),dtype='<f4',buffer=b,offset=28+n+view.get('byteOffset',0)+accessor.get('byteOffset',0),strides=(view.get('byteStride',8),4))
            uv_valid=uv_valid and bool(np.all(np.ptp(uv,axis=0)>.05))
    checks['textured_uv_nonconstant']=uv_valid
    failures.extend(spec['id']+':'+key for key,ok in checks.items() if not ok)
    rows.append(dict(id=spec['id'],triangles=triangles,top_metres=top,checks=checks))
comparison={}
for view in ['overview','close']:
    a=np.array(Image.open(OUT/('master_'+view+'.png')).convert('RGB')).astype(float)
    b=np.array(Image.open(OUT/('optimized_'+view+'.png')).convert('RGB')).astype(float)
    d=np.abs(a-b);comparison[view]=dict(mean_rgb_255=float(d.mean()),pixels_delta_gt_10=float((d.max(axis=2)>10).mean()))
(OUT/'comparison.json').write_text(json.dumps(comparison,indent=2),encoding='utf8')
(OUT/'validation.json').write_text(json.dumps(dict(failures=failures,assets=rows,scope='offline GLB structure and PBR; no editor publication'),indent=2),encoding='utf8')
print(json.dumps(dict(failures=failures,assets=rows,comparison=comparison),indent=2))
raise SystemExit(bool(failures))
