"""Validate exported modules and the same-camera optimization comparison."""
import json,struct,hashlib
from pathlib import Path
import numpy as np
from PIL import Image
p=Path('D:/code/rmmo_runtime/art_sources/mmorpg_shop_signs/burned_brackets_v3_20261007')
m=json.loads((p/'manifest.json').read_text(encoding='utf8'))
assert len(m['assets'])==21
for a in m['assets']:
 raw=(p/(a['id']+'.glb')).read_bytes()
 assert hashlib.sha256(raw).hexdigest()==a['sha256']
 n=struct.unpack_from('<I',raw,12)[0];g=json.loads(raw[20:20+n])
 assert len(g['meshes'])==1
 tri=sum(g['accessors'][x['indices']]['count']//3 for x in g['meshes'][0]['primitives'])
 assert tri==a['triangles'],(a['id'],tri,a['triangles'])
 assert all('bufferView' in x for x in g.get('images',[]))
master=np.asarray(Image.open(p/'master_overview.png').convert('RGB'),dtype=float)
game=np.asarray(Image.open(p/'optimized_overview.png').convert('RGB'),dtype=float)
result=dict(modules=21,hashes_and_triangle_counts_match=True,embedded_images=True,
 master_triangles=sum(a['master_triangles'] for a in m['assets']),
 game_triangles=sum(a['triangles'] for a in m['assets']),
 mean_rgb_optimization_difference=float(np.abs(master-game).mean()),
 brace_chain_static_clearance_m=.435-(.30+.055+.012),
 editor_published=False)
(p/'validation.json').write_text(json.dumps(result,indent=2),encoding='utf8')
print(json.dumps(result))
