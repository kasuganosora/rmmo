import bpy,hashlib,json,sys
from pathlib import Path
folder=Path(sys.argv[sys.argv.index('--')+1]);name='s2_bronze_lamp_long_ochre_banner'
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(folder/(name+'.glb')))
master=folder/(name+'_master.blend');bpy.ops.wm.save_as_mainfile(filepath=str(master),compress=True)
p=folder/(name+'_authoring.json');d=json.loads(p.read_text(encoding='utf-8'));d['master_sha256']=hashlib.sha256(master.read_bytes()).hexdigest();p.write_text(json.dumps(d,ensure_ascii=False,indent=2),encoding='utf-8')
