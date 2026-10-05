"""Conservative review-only geometry reduction with scan maps/density unchanged."""
import bpy, math, json
from pathlib import Path
from mathutils import Vector

ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT.parent/'rmmo_runtime/art_sources/town_planters/boxwood_review'
OUT=BASE/'optimized'
OUT.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(BASE/'town_planters_boxwood.blend'))

def count(o):
    o.data.calc_loop_triangles()
    return len(o.data.loop_triangles)

report={}
for col in bpy.data.collections:
    if not col.name.startswith(('01_','03_','05_','06_','07_')):continue
    meshes=[o for o in col.objects if o.type=='MESH']
    before={o.name:count(o) for o in meshes}
    for o in meshes:
        old=o.data
        if o.name.startswith('Boxwood scanned'):
            assert len(old.vertices)%15==0
            source_uv={loop.vertex_index:old.uv_layers.active.data[loop.index].uv.copy() for loop in old.loops}
            verts=[];faces=[];uv=[];normals=[]
            for start in range(0,len(old.vertices),15):
                base=len(verts)
                for row in (0,2,4):
                    for column in range(3):
                        i=start+row*3+column
                        verts.append(old.vertices[i].co.copy());normals.append(old.vertices[i].normal.copy());uv.append(source_uv[i])
                for row in range(2):
                    for column in range(2):
                        q=base+row*3+column;faces.append((q,q+1,q+4,q+3))
            new=bpy.data.meshes.new(old.name+'_reduced');new.from_pydata(verts,[],faces);new.update()
            for p in new.polygons:p.use_smooth=True
            new.normals_split_custom_set_from_vertices(normals)
            layer=new.uv_layers.new(name='BoxwoodAtlas')
            for loop in new.loops:layer.data[loop.index].uv=uv[loop.vertex_index]
        elif o.name.startswith('Rooted woody stems'):
            assert len(old.vertices)%10==0
            verts=[];faces=[]
            for start in range(0,len(old.vertices),10):
                base=len(verts)
                for ring in (0,1):
                    points=[old.vertices[start+ring*5+i].co.copy() for i in range(5)]
                    centre=sum(points,Vector())/5
                    a=(points[0]-centre)
                    axis=(sum([old.vertices[start+5+i].co for i in range(5)],Vector())-sum([old.vertices[start+i].co for i in range(5)],Vector())).normalized()
                    b=axis.cross(a)
                    verts.extend([centre+a*math.cos(i*math.tau/3)+b*math.sin(i*math.tau/3) for i in range(3)])
                for i in range(3):faces.append((base+i,base+(i+1)%3,base+3+(i+1)%3,base+3+i))
            new=bpy.data.meshes.new(old.name+'_reduced');new.from_pydata(verts,[],faces);new.update()
        else:continue
        for m in old.materials:new.materials.append(m)
        o.data=new
    after={o.name:count(o) for o in meshes}
    report[col.name]={'before_triangles':sum(before.values()),'after_triangles':sum(after.values()),'reduction_percent':round(100*(1-sum(after.values())/sum(before.values())),2),'before_components':before,'after_components':after}

scene=bpy.context.scene
scene.render.filepath=str(OUT/'boxwood_L_optimized.png')
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'town_planters_boxwood_optimized.blend'))
(OUT/'geometry_report.json').write_text(json.dumps(report,indent=2),encoding='utf8')
bpy.ops.render.render(write_still=True)
cam=scene.camera;cam.location=(4.6,-11.5,3.7);cam.rotation_euler=(Vector((2.0,-7.7,1.1))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=2.4
scene.render.resolution_x=1200;scene.render.resolution_y=1000
scene.render.filepath=str(OUT/'boxwood_leaf_detail_optimized.png')
bpy.ops.render.render(write_still=True)
print('OPTIMIZED_BOXWOOD_COMPLETE',json.dumps(report))
