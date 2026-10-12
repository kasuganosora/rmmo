import bpy,json
from pathlib import Path
bpy.ops.wm.open_mainfile(filepath='D:/code/rmmo/review_artifacts/axel_guild_materials_20261011/axel_guild_materials_v1.blend')
print('ROOTS',json.dumps([{'name':o.name,'source':o.get('asset_source'),'asset':o.get('asset_id'),'children':len(o.children)} for o in bpy.data.objects if o.get('asset_source')],ensure_ascii=False))
for folder,file in [('furniture_v1','guild_furniture.blend'),('guestroom_v1','guild_furniture.blend'),('decorative_panel_v1','guild_decorative_panel.blend')]:
 with bpy.data.libraries.load('D:/code/rmmo_runtime/art_sources/axel_guild/'+folder+'/'+file) as (a,b):
  print('LIBRARY',folder,a.collections)
