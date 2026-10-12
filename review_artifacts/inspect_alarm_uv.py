import bpy
bpy.ops.wm.open_mainfile(filepath='D:/code/rmmo/review_artifacts/axel_guild_materials_20261011/axel_guild_materials_v4.blend')
for o in bpy.data.objects:
 if o.name.startswith(('Alarm tower context shaft','Crown hollow masonry drum','Conical roof shell')):print('BEFORE',o.name,[list(x) for x in o.matrix_world],flush=True)
for c in bpy.data.collections:c.hide_viewport=False
bpy.context.view_layer.update()
for o in bpy.data.objects:
 if o.name.startswith(('Alarm tower context shaft','Crown hollow masonry drum','Conical roof shell')):print('AFTER',o.name,[list(x) for x in o.matrix_world],flush=True)
