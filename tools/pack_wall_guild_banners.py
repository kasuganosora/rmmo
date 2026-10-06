"""Consolidate already exported rigid parts; cloth remains an independent wind mesh."""
import bpy,json,hashlib
from pathlib import Path
out=Path(__file__).resolve().parents[2]/'rmmo_runtime/art_sources/wall_guild_banners'
manifest=json.loads((out/'manifest.json').read_text(encoding='utf8'))
for row in manifest['assets']:
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    path=out/'models'/(row['id']+'.glb');bpy.ops.import_scene.gltf(filepath=str(path))
    meshes=[o for o in bpy.context.scene.objects if o.type=='MESH'];cloth=[o for o in meshes if 'rmmo_wind' in o];assert len(cloth)==1
    rigid=[o for o in meshes if o not in cloth];bpy.ops.object.select_all(action='DESELECT')
    for o in rigid:o.select_set(True)
    bpy.context.view_layer.objects.active=rigid[0];bpy.ops.object.join();support=bpy.context.object;support.name=row['id']+'_rigid_support'
    cloth[0].select_set(True);bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_extras=True,export_animations=False,export_morph=False)
    row['sha256']=hashlib.sha256(path.read_bytes()).hexdigest();row['export_meshes']=2
    for o in [support,cloth[0]]:o.data.calc_loop_triangles()
    row['export_triangles']=sum(len(o.data.loop_triangles) for o in [support,cloth[0]])
(out/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')
print('BANNER_RIGID_PACK_COMPLETE')
