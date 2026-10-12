import bpy,json
from mathutils import Vector
bpy.ops.wm.open_mainfile(filepath='D:/code/rmmo/review_artifacts/alarm_tower_materials_20261011/guild_and_alarm_tower_materials.blend')
for c in bpy.data.collections:c.hide_viewport=False
bpy.context.view_layer.update()
objs=[o for o in bpy.data.objects if o.get('semantic_group')=='70_Alarm_Tower_Context']
before={o.name:(o.parent.name if o.parent else '',[list(r) for r in o.matrix_world]) for o in bpy.data.objects}
top=[o for o in objs if o.parent and o.parent.get('semantic_group')=='70_Alarm_Tower_Context' and not o.parent.get('asset_id')]
print('TOP',[(o.name,list(o.location)) for o in top])
saved={o:o.matrix_basis.copy() for o in top}
for o in top:o.location-=Vector((23,42,0))
bpy.context.view_layer.update()
for o,matrix in saved.items():o.matrix_basis=matrix
bpy.context.view_layer.update()
roots=[o for o in objs if o.get('asset_id') and o.type=='EMPTY']
for asset in ['guild_alarm_crown','guild_alarm_conical_roof','guild_alarm_ring_supports','guild_alarm_horn']:
 r=next(o for o in roots if o.get('asset_id')==asset)
 parent=r.parent;pose=r.matrix_basis.copy();r.parent=None;r.matrix_basis.identity();bpy.context.view_layer.update()
 r.parent=parent;r.matrix_basis=pose;bpy.context.view_layer.update()
for o in bpy.data.objects:
 p,m=before[o.name];error=max(abs(a-b) for ra,rb in zip(m,o.matrix_world) for a,b in zip(ra,rb))
 if error>1e-7:print('DIFF',o.name,error,m,[list(r) for r in o.matrix_world])
