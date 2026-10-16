import bpy,json,hashlib
from mathutils import Vector
from pathlib import Path
rows=[]
for n in ['02_plum_vendor','04_scroll_vendor']:
 c=bpy.data.collections[n]; goods=[ch for ch in c.children if ch.name.endswith('_CONTENTS')][0]
 objs=[]
 for o in goods.all_objects:
  points=[o.matrix_world@Vector(v) for v in o.bound_box]
  objs.append({'name':o.name,'type':o.type,'location':list(o.location),'rotation':list(o.rotation_euler),'scale':list(o.scale),'bounds_min':[min(v[k] for v in points) for k in range(3)],'bounds_max':[max(v[k] for v in points) for k in range(3)],'materials':[m.name for m in o.data.materials]})
 rows.append({'collection':n,'goods':goods.name,'objects':objs})
Path('D:/code/rmmo/review_artifacts/axel_market_realism_20261016/pottery_scroll/source_inventory.json').write_text(json.dumps(rows,indent=2),encoding='utf-8')
print('INVENTORY',[(r['collection'],len(r['objects'])) for r in rows])
