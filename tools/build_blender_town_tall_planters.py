"""Additional tall planting variants; preserve the accepted optimized originals."""
import bpy,math,random,json,argparse,sys
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT.parent/'rmmo_runtime/art_sources/town_planters/boxwood_review/optimized'
OUT=BASE.parent/'tall_plant_review';OUT.mkdir(exist_ok=True)
bpy.ops.wm.open_mainfile(filepath=str(BASE/'town_planters_boxwood_optimized.blend'))
random.seed(10552)
parser=argparse.ArgumentParser();parser.add_argument('--extra-height',type=float,default=.72)
args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
extra_height=args.extra_height
if not .2<=extra_height<=1.2:raise ValueError('extra-height must be between 0.2 and 1.2 m')
report={}
for col in list(bpy.data.collections):
    if col.name[:2].isdigit() and not col.name.startswith(('01_','07_')):
        for obj in list(col.objects):bpy.data.objects.remove(obj,do_unlink=True)
        bpy.data.collections.remove(col)
for index,prefix in enumerate(('01_','07_')):
    col=next(c for c in bpy.data.collections if c.name.startswith(prefix));col.hide_render=False;col.hide_viewport=False
    col.name=('08_tall_plant_straight','09_tall_plant_corner')[index]
    for obj in col.objects:obj.location=(-2.1 if index==0 else 2.0,0,0)
    leaves=next(o for o in col.objects if o.name.startswith('Boxwood scanned'))
    stems=next(o for o in col.objects if o.name.startswith('Rooted woody'))
    old=leaves.data
    uvmap={lp.vertex_index:old.uv_layers.active.data[lp.index].uv.copy() for lp in old.loops}
    verts=[];faces=[];uv=[];normals=[];sv=[];sf=[]
    for layer in [0,1]:
        for card,start in enumerate(range(0,len(old.vertices),9)):
            if layer==0 and random.random()>.52:continue
            center=sum((old.vertices[start+j].co for j in range(9)),Vector())/9
            lift=extra_height*(.48 if layer==0 else 1)+.075*math.sin(center.x*3.4+center.y*2.7)+random.uniform(-.065,.065)
            delta=Vector((random.uniform(-.035,.035),random.uniform(-.035,.035),lift))
            base=len(verts)
            for j in range(9):
                verts.append(old.vertices[start+j].co+delta);uv.append(uvmap[start+j]);normals.append(old.vertices[start+j].normal.copy())
            for row in range(2):
                for column in range(2):
                    q=base+row*3+column;faces.append((q,q+1,q+4,q+3))
            # Root remains in soil while the matching branch tip rises with its leaves.
            base=len(sv)
            for j in range(6):sv.append(stems.data.vertices[card*6+j].co+(delta if j>=3 else Vector()))
            for j in range(3):sf.append((base+j,base+(j+1)%3,base+3+(j+1)%3,base+3+j))
    def make(name,vs,fs,mat):
        data=bpy.data.meshes.new(name);data.from_pydata(vs,[],fs);data.update()
        obj=bpy.data.objects.new(name,data);col.objects.link(obj);obj.location=leaves.location;data.materials.append(mat);return obj
    crown=make('Tall crown scanned branches',verts,faces,leaves.data.materials[0])
    for poly in crown.data.polygons:poly.use_smooth=True
    crown.data.normals_split_custom_set_from_vertices(normals)
    layer=crown.data.uv_layers.new(name='BoxwoodAtlas')
    for lp in crown.data.loops:layer.data[lp.index].uv=uv[lp.vertex_index]
    make('Tall crown rooted stems',sv,sf,stems.data.materials[0])
    col['extra_canopy_height_m']=extra_height
    triangles=0
    for obj in col.objects:
        if obj.type=='MESH':obj.data.calc_loop_triangles();triangles+=len(obj.data.loop_triangles)
    top=max(v.co.z for v in crown.data.vertices)
    report[col.name]={'plant_top_m':round(top,3),'extra_canopy_height_m':extra_height,'triangles':triangles,'leaf_card_triangles':8}
scene=bpy.context.scene;cam=scene.camera
cam.location=(5,-12,6);cam.rotation_euler=(Vector((0,0,1.0))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=9
scene.render.resolution_x=1600;scene.render.resolution_y=1100;scene.cycles.samples=32
scene.render.filepath=str(OUT/'tall_planters_review.png')
bpy.ops.file.pack_all();bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'town_tall_planters.blend'))
(OUT/'geometry_report.json').write_text(json.dumps(report,indent=2),encoding='utf8')
bpy.ops.render.render(write_still=True)
cam.location=(1,-7,3.1);cam.rotation_euler=(Vector((-2.1,0,1.25))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=4.3
scene.render.filepath=str(OUT/'tall_planter_detail.png');bpy.ops.render.render(write_still=True)
print('TALL_PLANTERS_COMPLETE',json.dumps(report))
