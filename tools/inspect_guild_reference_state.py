"""Read-only geometric/reference inventory of the accepted guild master."""
import bpy, json
from pathlib import Path
from mathutils import Vector

OUT=Path('D:/code/rmmo/review_artifacts/guild_reference_recheck_20261013')
OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.open_mainfile(filepath='D:/code/rmmo_runtime/art_sources/axel_guild/repair_v2/axel_guild_repaired.blend')
rows=[]
for o in bpy.data.objects:
    if o.type!='MESH': continue
    if any(k in o.name.lower() for k in ['registration','reception','fanlight','door','quest','floor','ceiling','roof']):
        b=[o.matrix_world@Vector(v) for v in o.bound_box]
        rows.append(dict(name=o.name,parent=o.parent.name if o.parent else None,extras=o.id_properties_ensure().to_dict(),bounds=[[min(p[i] for p in b) for i in range(3)],[max(p[i] for p in b) for i in range(3)]],materials=[m.name for m in o.data.materials if m]))
deps=bpy.context.evaluated_depsgraph_get()
rays=[]
for x in [22.8,24.65,26.5,28.35]:
    origin=Vector((x,10.0,1.85));hits=[]
    for _ in range(12):
        ok,loc,n,idx,obj,m=bpy.context.scene.ray_cast(deps,origin,Vector((0,1,0)),distance=4)
        if not ok: break
        hits.append(dict(name=obj.name,point=list(loc)));origin=loc+Vector((0,.002,0))
        if origin.y>14:break
    rays.append(dict(x=x,hits=hits))
(OUT/'master_inventory.json').write_text(json.dumps(dict(meshes=rows,reception_rays=rays),indent=2,default=str),encoding='utf8')
print('RECEPTION_RAYS',json.dumps(rays),flush=True)
