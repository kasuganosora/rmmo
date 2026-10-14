import sys,json,hashlib
from pathlib import Path
import bpy
sys.path.insert(0,'D:/code/rmmo/tools')
import axel_guild_reference_props as props
import axel_guild_reference_materials as materials
out=Path('D:/code/rmmo/review_artifacts/guild_reference_recheck_20261013')
bpy.ops.wm.open_mainfile(filepath='D:/code/rmmo_runtime/art_sources/axel_guild/repair_v2/axel_guild_repaired.blend')
def bounds(o):
 return [[min(v.co[k] for v in o.data.vertices),max(v.co[k] for v in o.data.vertices)] for k in range(3)]
before={o.name:bounds(o) for o in bpy.data.objects if o.type=='MESH' and materials._asset_id(o) in {'guild_bottle_tall','guild_bottle_round','guild_bottle_squat','guild_serving_jug','guild_wash_ewer'}}
props.apply()
r=materials.apply()
details=[]
for o in bpy.data.objects:
 if o.type!='MESH':continue
 aid=materials._asset_id(o)
 if aid in r['changed_asset_ids']:
  row={'name':o.name,'asset_id':aid,'materials':[m.name if m else None for m in o.data.materials]}
  if o.name in before:
   row.update(bounds_before=before[o.name],bounds_after=bounds(o))
   row['max_dimension_delta']=max(abs(a-b) for x,y in zip(before[o.name],bounds(o)) for a,b in zip(x,y))
  details.append(row)
r['object_checks']=details
(out/'interior_batch_validation.json').write_text(json.dumps(r,ensure_ascii=False,indent=2),encoding='utf-8')
print('BATCH_VALIDATION',json.dumps({'changed':r['changed_asset_ids'],'vessels':r['vessel_geometry'],'max_bound_delta':max((x.get('max_dimension_delta',0) for x in details),default=0)},ensure_ascii=False))
