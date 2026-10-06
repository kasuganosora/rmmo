"""Blender background: realistic modular low stone walls and gate piers.
Offline review; uses existing acquired Quixel stone PBR. Metres, editable master.
"""
import bpy,bmesh,random,math,json,hashlib,argparse,sys
from pathlib import Path
from mathutils import Vector
p=argparse.ArgumentParser();p.add_argument('--length',type=float,default=2.4);p.add_argument('--seed',type=int,default=61007);p.add_argument('--height',type=float,default=1.5)
a=p.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
assert .8<=a.length<=12 and .5<=a.height<=2.5
root=Path(__file__).resolve().parents[2]/'rmmo_runtime'
out=root/'art_sources/garden_boundary'/('height_%d'%round(a.height*100));out.mkdir(parents=True,exist_ok=True)
models=out/'models';models.mkdir(exist_ok=True)
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
sc=bpy.context.scene;sc.unit_settings.system='METRIC';r=random.Random(a.seed)
# Reuse the approved small-scale stone UV mapping, scanned PBR and worn arrises.
source=(Path(__file__).parent/'build_street_edge_stones.py').read_text(encoding='utf8')
helpers=source[source.index('def surface('):source.index('for variant in range(3):')]
# User correction: straight dressed masonry; apparent missing top is foliage occlusion.
helpers=helpers.replace('r.uniform(.07,.20)','r.uniform(.018,.04)').replace('r.uniform(-.021,.021)','r.uniform(-.002,.002)').replace('r.uniform(-.018,.018)','r.uniform(-.002,.002)').replace('r.uniform(.002,.012)','r.uniform(.001,.003)').replace('r.uniform(-.004,.004)','r.uniform(-.001,.001)')
exec(helpers)
mortar=bpy.data.materials.new('Recessed warm lime mortar');mortar.use_nodes=True
bs=next(n for n in mortar.node_tree.nodes if n.type=='BSDF_PRINCIPLED');bs.inputs['Base Color'].default_value=(.28,.255,.20,1);bs.inputs['Roughness'].default_value=.97
def core(name,loc,size):
    bpy.ops.mesh.primitive_cube_add(size=1,location=loc);o=bpy.context.object;o.name=name;o.scale=size;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.data.materials.append(mortar);o.data.uv_layers.active.name='StoneUV';return o
def wall(length,origin=(0,0,0),angle=0):
    objects=[];width=.44;cap_z=a.height-.095;rows=round((cap_z+.04)/.166);course=(cap_z+.04)/rows
    def point(x,y,z):return (origin[0]+x*math.cos(angle)-y*math.sin(angle),origin[1]+x*math.sin(angle)+y*math.cos(angle),origin[2]+z)
    o=core('Recessed lime core',point(length/2,0,(cap_z-.04)/2),(length-.05,width-.06,cap_z+.025));o.rotation_euler.z=angle;objects.append(o)
    for row in range(rows):
        # Offset alternate courses, with variable lengths, avoid continuous joints.
        cuts=[0];cursor=.17 if row%2 else .30
        while cursor<length-.15:cuts.append(cursor);cursor+=r.uniform(.25,.38)
        cuts.append(length)
        for left,right in zip(cuts,cuts[1:]):
            objects.append(slab('Wall course stone',right-left-.012,width,course-.011,point((left+right)/2,0,-.04+row*course),angle))
    cap_count=max(2,round(length/.40));pitch=length/cap_count
    for i in range(cap_count):objects.append(slab('Level stone coping',pitch-.013,.47,.095,point((i+.5)*pitch,0,cap_z),angle))
    return objects
def pier(height,width=.50):
    objects=[core('Pier lime core',(0,0,(height-.12)/2),(width-.06,width-.06,height-.12))]
    rows=round((height-.10)/.167);course=(height-.10)/rows
    for row in range(rows):
        for side in [-1,1]:
            x=side*width/4;y=0
            if row%2:x,y=0,x
            objects.append(slab('Bonded pier stone',width/2-.01,width-.006,course-.012,(x,y,row*course),math.pi/2 if row%2 else 0))
    objects.append(slab('Plain square pier cap',width+.04,width+.04,.10,(0,0,height-.10)))
    return objects
record('garden_wall_240',wall(a.length),(-4,0,0),dict(length=a.length,height=a.height,depth=.44))
record('garden_wall_120',wall(a.length/2),(.8,0,0),dict(length=a.length/2,height=a.height,depth=.44))
record('garden_pier_tall',pier(a.height+.45),(-1.30,0,0),dict(height=a.height+.45,width=.50))
record('garden_pier_medium',pier(a.height+.30),(.40,0,0),dict(height=a.height+.30,width=.50))
corner=wall(1.6)+wall(1.38,(1.38,.22,0),math.pi/2)
# Perpendicular courses meet end-to-side, with no artificial broken silhouette.
record('garden_wall_corner',corner,(-3.8,2.5,0),dict(legs=[1.6,1.6],height=a.height,depth=.44))
record('garden_wall_short',wall(.8),(.8,2.6,0),dict(length=.8,height=a.height,depth=.44))
def tris(o):
    eo=o.evaluated_get(bpy.context.evaluated_depsgraph_get());me=eo.to_mesh();me.calc_loop_triangles();n=len(me.loop_triangles);eo.to_mesh_clear();return n
for asset in assets:
    asset['master_triangles']=sum(tris(o) for o in asset['objects'])
    for o in asset['objects']:o.location+=Vector(asset['preview'])
ground=bpy.data.materials.new('Review neutral ground');ground.diffuse_color=(.25,.27,.23,1)
bpy.ops.mesh.primitive_plane_add(size=200);floor=bpy.context.object;floor.name='Review ground';floor.location.z=0;floor.data.materials.append(ground)
sc.world.use_nodes=True;bg=next(n for n in sc.world.node_tree.nodes if n.type=='BACKGROUND');bg.inputs[0].default_value=(.72,.79,.9,1);bg.inputs[1].default_value=.5
bpy.ops.object.light_add(type='AREA',location=(-3,-4,8));light=bpy.context.object;light.data.energy=1700;light.data.size=5
light.rotation_euler=(Vector((-1,1,0))-light.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add();cam=bpy.context.object;sc.camera=cam;cam.data.type='ORTHO'
sc.render.engine='CYCLES';sc.cycles.samples=32;sc.cycles.use_denoising=True;sc.render.resolution_x=1500;sc.render.resolution_y=1000;sc.render.resolution_percentage=100;sc.view_settings.view_transform='AgX'
def view(loc,target,scale):cam.location=loc;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=scale
def render(name):sc.render.filepath=str(out/(name+'.png'));bpy.ops.render.render(write_still=True)
view((6,-10,7),(-1.1,1.35,.5),8.2)
bpy.ops.wm.save_as_mainfile(filepath=str(out/'garden_boundary_master.blend'),compress=True);render('master_overview')
view((1,-4,2.7),(-1.7,0,.8),2.4);render('master_close')
for o in all_stones:o.modifiers[0].segments=2
render('optimized_close');view((6,-10,7),(-1.1,1.35,.5),8.2);render('optimized_overview')
bpy.ops.wm.save_as_mainfile(filepath=str(out/'garden_boundary_optimized.blend'),compress=True)
manifest=[]
for asset in assets:
    duplicates=[]
    for o in asset['objects']:
        dup=o.copy();dup.data=o.data.copy();sc.collection.objects.link(dup);dup.location-=Vector(asset['preview']);duplicates.append(dup)
    bpy.ops.object.select_all(action='DESELECT')
    for o in duplicates:
        o.select_set(True);bpy.context.view_layer.objects.active=o
        for mod in list(o.modifiers):bpy.ops.object.modifier_apply(modifier=mod.name)
        o.select_set(False)
    for o in duplicates:o.select_set(True)
    bpy.context.view_layer.objects.active=duplicates[0];bpy.ops.object.join();obj=bpy.context.object;obj.name=asset['id'];bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    obj.data.calc_loop_triangles();tri=len(obj.data.loop_triangles)
    bm=bmesh.new();bm.from_mesh(obj.data);manifold=all(e.is_manifold for e in bm.edges);bm.free();assert manifold
    file=models/(asset['id']+'.glb');bpy.ops.export_scene.gltf(filepath=str(file),export_format='GLB',use_selection=True,export_extras=True)
    manifest.append(dict(id=asset['id'],recipe=asset['recipe'],master_triangles=asset['master_triangles'],game_triangles=tri,sha256=hashlib.sha256(file.read_bytes()).hexdigest(),manifold=manifold))
    bpy.data.objects.remove(obj,do_unlink=True)
(out/'manifest.json').write_text(json.dumps(dict(status='offline review; not published',assets=manifest,parameters=vars(a)),indent=2),encoding='utf8')
print('GARDEN_BOUNDARY_COMPLETE',flush=True)
