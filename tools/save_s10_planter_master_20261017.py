import bpy,json,hashlib
from pathlib import Path
p=Path('D:/code/rmmo_runtime/art_sources/s10_warm_brick_planter_20261017/v1/s10_warm_redbrick_planter.glb')
bpy.ops.wm.read_factory_settings(use_empty=True);bpy.ops.import_scene.gltf(filepath=str(p))
m=p.with_name(p.stem+'_master.blend');assert not m.exists();bpy.ops.wm.save_as_mainfile(filepath=str(m),compress=True)
a=p.with_name(p.stem+'_authoring.json');d=json.loads(a.read_text(encoding='utf-8'));d.update(master=m.as_posix(),master_sha256=hashlib.sha256(m.read_bytes()).hexdigest());a.write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
