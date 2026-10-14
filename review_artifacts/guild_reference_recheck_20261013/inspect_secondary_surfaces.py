import bpy, json, sys
sys.path.insert(0, 'D:/code/rmmo/tools')
from axel_guild_reference_materials import _asset_id
bpy.ops.wm.open_mainfile(filepath='D:/code/rmmo_runtime/art_sources/axel_guild/repair_v2/axel_guild_repaired.blend')
ids={'guild_bottle_round','guild_bottle_squat','guild_bottle_tall','guild_serving_jug','guild_wash_ewer','guild_wash_basin','guild_shower_tray','guild_towel_rail','guild_privacy_screen','guild_storage_cabinet','guild_bar_stool','guild_washstand','guild_privy_seat'}
rows=[]
seen=set()
for o in bpy.context.scene.objects:
    aid=_asset_id(o)
    if o.type!='MESH' or aid not in ids:continue
    root=o
    while root.parent and not root.get('asset_id'):root=root.parent
    if aid in seen and root.name not in chosen:continue
    if aid not in seen:
        seen.add(aid)
        if 'chosen' not in globals():chosen=set()
        chosen.add(root.name)
    rows.append(dict(name=o.name,asset_id=aid,vertices=len(o.data.vertices),faces=len(o.data.polygons),smooth=sum(p.use_smooth for p in o.data.polygons),modifiers=[(m.name,m.type) for m in o.modifiers],materials=[m.name for m in o.data.materials],images=[n.image.filepath for m in o.data.materials if m.use_nodes for n in m.node_tree.nodes if n.type=='TEX_IMAGE' and n.image],prop_part=o.get('prop_part'),uv=bool(o.data.uv_layers)))
open('D:/code/rmmo/review_artifacts/guild_reference_recheck_20261013/secondary_surface_inventory.json','w',encoding='utf8').write(json.dumps(rows,indent=2,ensure_ascii=False))
print('SECONDARY_INVENTORY',len(rows))
