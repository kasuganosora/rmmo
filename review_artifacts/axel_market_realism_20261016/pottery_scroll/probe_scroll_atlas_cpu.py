import bpy,sys,json,hashlib,math,collections
from pathlib import Path
from mathutils import Vector
sys.path.insert(0,'D:/code/rmmo/tools')
import build_axel_market_realism_20261016 as build
import axel_market_realism_pottery_scroll as goods
out=Path('D:/code/rmmo/review_artifacts/axel_market_realism_20261016/pottery_scroll')
bpy.ops.wm.open_mainfile(filepath=str(build.MASTER));col=bpy.data.collections['04_scroll_vendor'];goods.apply('scroll',col)
contents=bpy.data.collections['04_scroll_vendor_CONTENTS'];deps=bpy.context.evaluated_depsgraph_get()
report={'source_module_sha256':hashlib.sha256(Path(goods.__file__).read_bytes()).hexdigest(),'build_sha256':hashlib.sha256(Path(build.__file__).read_bytes()).hexdigest(),'gpu_executed':False,'bake_executed':False,'tests':[]}
source=[o for o in contents.all_objects if o.get('rmmo_export_group','GoodsOpaque')=='GoodsOpaque']
for margin in [.006,.003,.0015]:
    parts=[build.evaluated_copy(o,deps,Vector((0,0,0))) for o in source]
    for part in parts:
        attr=part.data.attributes.new('audit_surface_role','INT','FACE')
        steps=(len(part.data.polygons)-2)//4
        for f in part.data.polygons:
            if part.get('goods_kind')=='rolled_thin_parchment':
                value=1 if f.index<steps*4 and f.index%4==0 and f.index//4>=steps-40 else 2 if f.index<steps*4 and f.index%4 in (2,3) else 0
            else:value=3
            attr.data[f.index].value=value
    build.select(parts);bpy.ops.object.join();obj=bpy.context.object
    obj.data.uv_layers.new(name='GameAtlas');obj.data.uv_layers.active_index=len(obj.data.uv_layers)-1
    bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(72),island_margin=margin)
    bpy.ops.object.mode_set(mode='OBJECT')
    uv=obj.data.uv_layers['GameAtlas'].data;obj.data.calc_loop_triangles();role_area=collections.Counter();outer_roll=collections.Counter()
    attr=obj.data.attributes['audit_surface_role']
    for t in obj.data.loop_triangles:
        a,b,c=[uv[i].uv for i in t.loops]
        area=abs((b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x))*.5
        role=attr.data[t.polygon_index].value;role_area[role]+=area
        if role==1:outer_roll[obj.data.materials[t.material_index].name]+=area
    report['tests'].append({'margin':margin,'total_uv_area':sum(role_area.values()),'role_area':dict(role_area),'role_definition':{'0':'mostly occluded inner/interior paper','1':'visible outermost coil skin','2':'thin exposed spiral end sections','3':'bindings'},'outer_roll_pixels_at_2048':{k:v*2048*2048 for k,v in outer_roll.items()},'outer_roll_average_texels':role_area[1]*2048*2048/9})
    bpy.data.objects.remove(obj,do_unlink=True)
# A separate 1024 atlas for the open sheet, retaining its source GoodsUV.
sheet=next(o for o in contents.all_objects if o.get('rmmo_export_group')=='PaperSheet')
obj=build.evaluated_copy(sheet,deps,Vector((0,0,0)));build.select([obj])
obj.data.uv_layers.new(name='GameAtlas');obj.data.uv_layers.active_index=len(obj.data.uv_layers)-1
bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT')
bpy.ops.uv.smart_project(angle_limit=math.radians(72),island_margin=.006)
bpy.ops.object.mode_set(mode='OBJECT')
points=[obj.data.uv_layers['GameAtlas'].data[i].uv for f in obj.data.polygons if f.material_index==1 for i in f.loop_indices]
report['sheet_front_dimensions_at_1024']=[(max(p[k] for p in points)-min(p[k] for p in points))*1024 for k in range(2)]
(out/'scroll_atlas_cpu_probe.json').write_text(json.dumps(report,indent=2),encoding='utf-8');print(json.dumps(report,indent=2))
