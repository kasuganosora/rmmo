import bpy,json
from pathlib import Path
from mathutils import Vector
bpy.ops.wm.open_mainfile(filepath='D:/code/rmmo/review_artifacts/axel_guild_materials_20261011/axel_guild_whitebox_v13.blend')
deps=bpy.context.evaluated_depsgraph_get()
rows=[]
for x in [1,7,13,20,31]:
 for y in [-.4,-.2,-.05,0,.05,.2,.4,.5,.7]:
  hits=[]
  for o in bpy.data.objects:
   if o.type!='MESH' or o.get('semantic_group','').startswith(('60','70','71','90')):continue
   ev=o.evaluated_get(deps); inv=ev.matrix_world.inverted()
   hit,p,n,i=ev.ray_cast(inv@Vector((x,y,16)),(inv.to_3x3()@Vector((0,0,-1))).normalized(),distance=30)
   if hit:
    wp=ev.matrix_world@p
    if wp.z>7:hits.append([o.name,round(wp.z,5)])
  rows.append({'x':x,'y':y,'hits':sorted(hits,key=lambda k:-k[1])[:5]})
Path('D:/code/rmmo/review_artifacts/axel_guild_materials_20261011/roof_probe.json').write_text(json.dumps(rows,indent=2))
