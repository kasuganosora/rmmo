import bpy,json
from pathlib import Path
root=Path('D:/code/rmmo_runtime/art_sources')
files=['town_planters/boxwood_review/optimized/town_planters_boxwood_optimized.blend','town_planters/boxwood_review/tall_plant_review/town_tall_planters.blend','town_low_fence/town_low_fence.blend','town_festival_posts/festival_posts.blend','town_market_stalls/town_market_stalls.blend','bridge_street_kit/bridge_street_missing_assets.blend','small_wall_lantern/small_wall_lantern.blend']
result=[]
for f in files:
    bpy.ops.wm.open_mainfile(filepath=str(root/f))
    result.append({'file':f,'collections':[{'name':c.name,'count':len(c.all_objects),'examples':[o.name for o in list(c.objects)[:5]]} for c in bpy.data.collections]})
(root/'town_prop_source_inventory.json').write_text(json.dumps(result,indent=2),encoding='utf8')
