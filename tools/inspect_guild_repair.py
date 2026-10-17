import bpy,json
from pathlib import Path
bpy.ops.wm.open_mainfile(filepath='D:/code/rmmo_runtime/art_sources/axel_guild/finish_v1/entry_extension/axel_guild_entry.blend')
rows=[]
for o in bpy.data.objects:
    if o.get('asset_id') or o.get('door_group') or o.name.startswith(('203 TWIN side','204 TWIN side','05 WASHROOM','Banner','Facade')):
        rows.append(dict(name=o.name,type=o.type,parent=o.parent.name if o.parent else None,extras=dict(o.items()),materials=[m.name if m else '' for m in o.data.materials] if o.type=='MESH' else [],children=[c.name for c in o.children]))
Path('D:/code/rmmo_runtime/review_artifacts/axel_guild_finish_20261012/repair_inventory.json').write_text(json.dumps(rows,default=str,indent=2))
