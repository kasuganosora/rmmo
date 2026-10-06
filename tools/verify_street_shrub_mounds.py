from pathlib import Path
import json,struct,hashlib
from PIL import Image
import numpy as np
root=Path('D:/code/rmmo_runtime/art_sources/street_shrub_mounds')
manifest=json.loads((root/'manifest.json').read_text());failures=[];rows=[]
for spec in manifest['assets']:
    path=root/(spec['id']+'.glb');b=path.read_bytes();n=struct.unpack_from('<I',b,12)[0];g=json.loads(b[20:20+n])
    triangles=sum(g['accessors'][p['indices']]['count']//3 for m in g['meshes'] for p in m['primitives'])
    leaves=[m for m in g['materials'] if 'boxwood' in m.get('name','').lower()]
    checks={'sha256':hashlib.sha256(b).hexdigest()==spec['sha256'],'triangles':triangles==spec['game_triangles'],'separate_stems':len(g['meshes'])==2,'masked_leaves':len(leaves)==1 and leaves[0].get('alphaMode')=='MASK' and leaves[0].get('doubleSided'),'embedded_textures':all('bufferView' in image for image in g.get('images',[]))}
    failures += [spec['id']+':'+k for k,v in checks.items() if not v]
    rows.append(dict(id=spec['id'],triangles=triangles,checks=checks))
comparison={}
for view in ['overview','close']:
    a=np.array(Image.open(root/('master_'+view+'.png')).convert('RGB')).astype(float)
    b=np.array(Image.open(root/('optimized_'+view+'.png')).convert('RGB')).astype(float)
    d=np.abs(a-b);comparison[view]={'mean_rgb_255':float(d.mean()),'pixels_delta_gt_10':float((d.max(axis=2)>10).mean())}
report=dict(failures=failures,assets=rows,comparison=comparison)
(root/'validation.json').write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2))
raise SystemExit(bool(failures))
