import bpy,sys,json,hashlib,math,collections
from pathlib import Path
from mathutils import Vector
sys.path.insert(0,'D:/code/rmmo/tools')
import build_axel_market_realism_20261016 as build
import axel_market_realism_pottery_scroll as goods
out=Path('D:/code/rmmo/review_artifacts/axel_market_realism_20261016/pottery_scroll')
report={'build_script_sha256':hashlib.sha256(Path(build.__file__).read_bytes()).hexdigest(),'gpu_executed':False,'bake_executed':False,'assets':[]}
manifest=json.loads(Path('D:/code/rmmo_runtime/assets/town_props_20261006/manifest.json').read_text())
def tally(objects):
    result=collections.Counter()
    for o in objects:
        for f in o.data.polygons:result[o.data.materials[f.material_index].name]+=1
    return dict(result)
for asset,cn in [('pottery','02_plum_vendor'),('scroll','04_scroll_vendor')]:
    bpy.ops.wm.open_mainfile(filepath=str(build.MASTER))
    col=bpy.data.collections[cn];goods.apply(asset,col)
    contents=bpy.data.collections[cn+'_CONTENTS']
    originals=list(contents.all_objects)
    pivot=Vector(next(r['source_pivot'] for r in manifest if r['id']=='town_market_stalls_'+cn))
    deps=bpy.context.evaluated_depsgraph_get()
    parts=[build.evaluated_copy(o,deps,pivot) for o in originals]
    bpy.context.view_layer.update()
    orig=originals[0];part=parts[0]
    world_original=orig.matrix_world@orig.data.vertices[0].co
    world_copy=part.matrix_world@part.data.vertices[0].co
    source_coord=orig.matrix_world.inverted()@world_original
    copied_coord=orig.matrix_world.inverted()@world_copy
    before=tally(parts)
    build.select(parts);bpy.ops.object.join();obj=bpy.context.object
    bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
    after=tally([obj])
    # Reproduce only atlas setup, without any baking/rendering or source change.
    if not obj.data.uv_layers.get('SourceUV'):
        original=obj.data.uv_layers.active
        obj.data.uv_layers.new(name='SourceUV',do_init=True)
        obj.data.uv_layers.active=original
    source_uv=[tuple(x.uv) for x in obj.data.uv_layers['GoodsUV'].data]
    obj.data.uv_layers.new(name='GameAtlas');obj.data.uv_layers.active_index=len(obj.data.uv_layers)-1
    obj.data.uv_layers.active.active_render=True
    bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.uv.smart_project(angle_limit=math.radians(72),island_margin=.006)
    bpy.ops.object.mode_set(mode='OBJECT')
    unchanged=source_uv==[tuple(x.uv) for x in obj.data.uv_layers['GoodsUV'].data]
    uv=obj.data.uv_layers['GameAtlas'].data;obj.data.calc_loop_triangles();uvarea=collections.Counter()
    matranges={}
    for t in obj.data.loop_triangles:
        a,b,c=[uv[i].uv for i in t.loops]
        uvarea[obj.data.materials[t.material_index].name]+=abs((b.x-a.x)*(c.y-a.y)-(b.y-a.y)*(c.x-a.x))*.5
    for f in obj.data.polygons:
        name=obj.data.materials[f.material_index].name
        if 'WrittenParchment' in name:
            matranges.setdefault(name,[]).extend([tuple(uv[i].uv) for i in f.loop_indices])
    report['assets'].append({'asset':asset,'pivot':list(pivot),'first_source_object':orig.name,'coordinate_delta':list(copied_coord-source_coord),'joined_slot_face_counts_unchanged':before==after,'slots':len(obj.material_slots),'source_goods_uv_preserved':unchanged,'normal_bake_space':bpy.context.scene.render.bake.normal_space,'normal_swizzle':[bpy.context.scene.render.bake.normal_r,bpy.context.scene.render.bake.normal_g,bpy.context.scene.render.bake.normal_b],'atlas_uv_area_by_material':dict(uvarea),'written_uv_bounds':{k:[[min(p[i] for p in vs) for i in range(2)],[max(p[i] for p in vs) for i in range(2)]] for k,vs in matranges.items()}})
(out/'root_bake_readonly_audit.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print(json.dumps(report,indent=2))
