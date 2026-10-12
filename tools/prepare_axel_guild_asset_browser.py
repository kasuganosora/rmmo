"""Make a reusable Blender collection asset library from the reviewed furniture."""
import json
import shutil
import argparse
import sys
from pathlib import Path
import bpy
from mathutils import Vector

parser=argparse.ArgumentParser();parser.add_argument('--set',choices=['furniture','furnishings','textiles_sanitary','guestroom'],default='furniture')
args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
OUT=Path(__file__).resolve().parents[2]/('rmmo_runtime/art_sources/axel_guild/'+args.set+'_v1')
data=json.loads((OUT/'manifest.json').read_text(encoding='utf8'))
bpy.ops.wm.open_mainfile(filepath=str(OUT/'guild_furniture.blend'))
for index,(kind,item) in enumerate(data['assets'].items()):
    col=bpy.data.collections[kind+'_game'];col.hide_viewport=False;col.hide_render=False
    root=next(o for o in col.objects if o.get('asset_id')==item['asset_id'])
    root.location=(index%4*5,index//4*3.5,0)
    # Collection assets instantiate relative to their own ground pivot, not the
    # contact-sheet position in this presentation scene.
    col.instance_offset=root.location
    col.asset_mark();col.asset_data.description=item['label']+' | metres; floor pivot; independent model'
    for tag in ['Guild','Furniture','Realistic']:col.asset_data.tags.new(tag)
    col['asset_id']=item['asset_id'];col['game_glb']='game/'+item['asset_id']+'.glb'
    master=bpy.data.collections[kind+'_master'];master.hide_viewport=True;master.hide_render=True
    path=OUT/'preview'/(kind+'.png')
    with bpy.context.temp_override(id=col):bpy.ops.ed.lib_id_load_custom_preview(filepath=str(path))
cam=bpy.context.scene.camera;cam.location=(22,-22,24);target=Vector((7.5,5.0,1))
cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler()
cam.data.type='ORTHO';cam.data.ortho_scale=24
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':
            area.spaces.active.region_3d.view_location=target
            area.spaces.active.region_3d.view_distance=25
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'guild_furniture_library.blend'),compress=True)
shutil.copyfile(Path(__file__),OUT/Path(__file__).name)
print('BLENDER_COLLECTION_ASSETS',len(data['assets']))
