"""Incremental CPU bake: one existing PaperSheet only; source master untouched."""
import bpy, sys, json, hashlib
from pathlib import Path
from mathutils import Vector
ROOT=Path('D:/code/rmmo');ART=ROOT.parent/'rmmo_runtime/art_sources/axel_market_realism_20261016'
sys.path.insert(0,str(ROOT/'tools'))
import axel_market_realism_pottery_scroll as goods
import build_axel_market_realism_20261016 as builder
OUT=ART/'v4_scroll_sheet';OUT.mkdir(exist_ok=True)
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
source=ART/'v3/scroll/authoring.blend';before=sha(source)
bpy.ops.wm.open_mainfile(filepath=str(source))
sheet=bpy.data.objects['Goods_UnfurledManuscript']
assert sheet['rmmo_export_group']=='PaperSheet'
assert len(sheet.data.materials)==2
sheet.data.materials[1]=goods._written_material(sheet.data.materials[0])
sheet['rmmo_market_goods_revision']=goods.VERSION
sheet['rmmo_sheet_ink_revision']=4
bpy.ops.file.pack_all();bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'authoring_sheet.blend'))
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.device='CPU';scene.cycles.samples=8
scene.render.threads_mode='FIXED';scene.render.threads=4;scene.render.bake.margin=12
scene.frame_set(1);deps=bpy.context.evaluated_depsgraph_get()
pivot=Vector(json.loads((ART/'v3/scroll/build.json').read_text())['source_pivot'])
runtime=builder.evaluated_copy(sheet,deps,pivot)
for o in list(scene.objects):
    if o!=runtime:o.hide_render=True;o.hide_set(True)
runtime=builder.bake_group([runtime],'PaperSheet',OUT,1024,'scroll')
runtime.location-=pivot
builder.select([runtime]);runtime.data.calc_loop_triangles()
assert len(runtime.data.uv_layers)==1 and runtime.data.uv_layers[0].name=='GameAtlas'
bpy.ops.export_scene.gltf(filepath=str(OUT/'delta.glb'),export_format='GLB',use_selection=True,export_extras=True,export_animations=False,export_tangents=True)
bpy.ops.file.pack_all();bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'runtime_baked.blend'))
report={'version':4,'asset':'scroll','scope':'single PaperSheet delta only','cpu_bake':True,'gpu_executed':False,'visual_accepted':False,
        'source_authoring':str(source),'source_authoring_sha256':before,'source_authoring_unchanged':sha(source)==before,
        'module_sha256':sha(ROOT/'tools/axel_market_realism_pottery_scroll.py'),'baker_sha256':sha(ROOT/'tools/build_axel_market_realism_20261016.py'),
        'source_pivot':list(pivot),'groups':[{'group':runtime.name,'triangles':len(runtime.data.loop_triangles),'uv_layers':[uv.name for uv in runtime.data.uv_layers],'material':runtime.data.materials[0].name}],
        'delta_sha256':sha(OUT/'delta.glb'),'artifacts':{p.name:sha(p) for p in OUT.glob('*.png')}}
(OUT/'build.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print('PAPERSHEET_V4_COMPLETE '+json.dumps(report),flush=True)
