import bpy,re
from pathlib import Path
bpy.ops.wm.open_mainfile(filepath=r'D:/code/rmmo_runtime/art_sources/axel_landmarks_20261016/watermill/v8/axel_watermill_master.blend')
for o in bpy.data.objects:
    if 'uuid' in o:o['uuid']=re.sub(r'[^A-Za-z0-9_-]','_',str(o['uuid']))
bpy.ops.wm.save_as_mainfile(filepath=r'D:/code/rmmo_runtime/art_sources/axel_landmarks_20261016/watermill/v9/axel_watermill_master.blend')
