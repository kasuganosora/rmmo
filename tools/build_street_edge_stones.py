"""Offline realistic kerbs / stepping slabs; Blender 4.5 -b --python this.py.
Optional -- --length 4 --radius 2 --seed 61006; dimensions are metres.
Preserves editable master and renders matched 4/2-segment bevel comparisons.
"""
import argparse, json, math, random, sys, hashlib
from pathlib import Path
import bpy, bmesh
from mathutils import Vector

p=argparse.ArgumentParser();p.add_argument('--length',type=float,default=3);p.add_argument('--radius',type=float,default=1.8);p.add_argument('--seed',type=int,default=61006)
a=p.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
assert .6<=a.length<=30 and .8<=a.radius<=20
root=Path(__file__).resolve().parents[2]/'rmmo_runtime'
out=root/'art_sources/street_edge_stones';out.mkdir(parents=True,exist_ok=True)
models=out/'models';models.mkdir(exist_ok=True)
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
sc=bpy.context.scene;sc.unit_settings.system='METRIC'
r=random.Random(a.seed)

def surface(name,folder):
    base=root/'packs/default/assets/materials'/folder
    m=bpy.data.materials.new(name);m.use_nodes=True
    nt=m.node_tree;bs=next(n for n in nt.nodes if n.type=='BSDF_PRINCIPLED');bs.inputs['Roughness'].default_value=.85
    for file,socket in [('texture.jpg','Base Color'),('normal.png','Normal'),('roughness.png','Roughness')]:
        if not (base/file).exists():continue
        t=nt.nodes.new('ShaderNodeTexImage');t.image=bpy.data.images.load(str(base/file),check_existing=True);t.image.pack()
        if socket!='Base Color':t.image.colorspace_settings.name='Non-Color'
        if socket=='Normal':
            n=nt.nodes.new('ShaderNodeNormalMap');n.inputs['Strength'].default_value=.3;nt.links.new(t.outputs['Color'],n.inputs['Color']);nt.links.new(n.outputs[0],bs.inputs[socket])
        elif socket=='Roughness':
            sep=nt.nodes.new('ShaderNodeSeparateColor');nt.links.new(t.outputs[0],sep.inputs[0]);nt.links.new(sep.outputs['Red'],bs.inputs[socket])
        else:nt.links.new(t.outputs[0],bs.inputs[socket])
    return m
stone=surface('Weathered light stone - Quixel Beach Cliff','terrain/beach_cliff')
assets=[];all_stones=[]

def slab(name,w,d,h,loc,angle=0):
    # Clipped uneven corners keep a broad, nearly flat walking surface.
    cut=[r.uniform(.07,.20) for _ in range(4)]
    pts=[(-.5+cut[0],-.5),(.5-cut[1],-.5),(.5,-.5+cut[1]),(.5,.5-cut[2]),(.5-cut[2],.5),(-.5+cut[3],.5),(-.5,.5-cut[3]),(-.5,-.5+cut[0])]
    pts=[(x*w+r.uniform(-.021,.021),y*d+r.uniform(-.018,.018)) for x,y in pts]
    outline=[]
    for i,(x,y) in enumerate(pts):
        nx,ny=pts[(i+1)%len(pts)];outline.append((x,y))
        if math.hypot(nx-x,ny-y)>.13:
            t=r.uniform(.35,.65);inset=r.uniform(.002,.012)
            outline.append(((x*(1-t)+nx*t)*(1-inset/w),(y*(1-t)+ny*t)*(1-inset/d)))
    pts=outline;n=len(pts)
    v=[(x*.98,y*.98,0) for x,y in pts]+[(x,y,h+r.uniform(-.004,.004)) for x,y in pts]
    f=[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    mesh=bpy.data.meshes.new(name);mesh.from_pydata(v,[],f);mesh.update()
    o=bpy.data.objects.new(name,mesh);sc.collection.objects.link(o);o.location=loc;o.rotation_euler.z=angle;mesh.materials.append(stone)
    uv=mesh.uv_layers.new(name='StoneUV');offset=(r.random(),r.random());uvangle=r.uniform(-.7,.7)
    for poly in mesh.polygons:
        axis=max(range(3),key=lambda k:abs(poly.normal[k]))
        for li in poly.loop_indices:
            c=mesh.vertices[mesh.loops[li].vertex_index].co;xy=(c.x,c.y) if axis==2 else ((c.x,c.z) if axis==1 else (c.y,c.z))
            uv.data[li].uv=((xy[0]*math.cos(uvangle)-xy[1]*math.sin(uvangle))/2+offset[0],(xy[0]*math.sin(uvangle)+xy[1]*math.cos(uvangle))/2+offset[1])
    be=o.modifiers.new('Worn arris | master 4 / game 2','BEVEL');be.width=.012;be.segments=4
    for poly in mesh.polygons:poly.use_smooth=True
    wn=o.modifiers.new('Preserve flat stone lighting','WEIGHTED_NORMAL');wn.keep_sharp=True;wn.weight=50
    all_stones.append(o);return o

def record(name,objs,preview,recipe):
    assets.append(dict(id=name,objects=objs,preview=preview,recipe=recipe))

for variant in range(3):
    objs=[];n=round(a.length/.43);lengths=[r.uniform(.8,1.2) for _ in range(n)];lengths=[v/sum(lengths)*a.length for v in lengths];cursor=0
    for i in range(n):
        pitch=lengths[i]
        objs.append(slab('Kerb_%d_%02d'%(variant,i),pitch-.035,r.uniform(.23,.31),r.uniform(.105,.13),(cursor+pitch*.5,r.uniform(-.015,.015),-.065),r.uniform(-.025,.025)));cursor+=pitch
    record('kerb_straight_'+str(variant+1),objs,(-3,variant*.65,0),dict(length=a.length,seed=a.seed,variant=variant))
for angle in [45,90]:
    arc=math.radians(angle);n=math.ceil(arc*a.radius/.38);step=arc/n;objs=[]
    for i in range(n):
        t=(i+.5)*step;w=2*(a.radius-.16)*math.tan(step/2)-.018
        objs.append(slab('Curve_%d_%02d'%(angle,i),w,r.uniform(.24,.28),.12,(a.radius*math.sin(t),a.radius*(1-math.cos(t)),-.065),t))
    record('kerb_curve_'+str(angle),objs,(-3,2.15 if angle==45 else 3.1,0),dict(radius=a.radius,angle=angle))
for i,(w,d) in enumerate([(.60,.43),(.74,.51),(.88,.57),(.67,.60),(.98,.62)]):
    record('stepping_slab_'+str(i+1),[slab('Slab_'+str(i+1),w,d,.115,(0,0,-.075))],(1.15+(i%2)*1.3,(i//2)*1.1,0),dict(width=w,depth=d,thickness=.115))
objs=[slab('Path_%02d'%i,r.uniform(.65,.80),r.uniform(.48,.56),.115,(r.uniform(-.045,.045),i*.65,-.075),r.uniform(-.15,.15)) for i in range(4)]
record('stepping_path_4',objs,(4,0,0),dict(count=4,spacing=.65))

def triangles(ob):
    mesh=ob.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh();mesh.calc_loop_triangles();n=len(mesh.loop_triangles);ob.evaluated_get(bpy.context.evaluated_depsgraph_get()).to_mesh_clear();return n

for asset in assets:
    asset['master_triangles']=sum(triangles(o) for o in asset['objects'])
    for o in asset['objects']:o.location+=Vector(asset['preview'])

def plane(name,loc,size,mat):
    bpy.ops.mesh.primitive_plane_add(size=2,location=loc);o=bpy.context.object;o.name=name;o.scale=(size[0]/2,size[1]/2,1);o.data.materials.append(mat)
    for uv in o.data.uv_layers.active.data:uv.uv*=5
    return o
ground=surface('Review only | soil and moss','terrain/mossy_grass_vcjmej0s')
plane('Review ground',(0,1.5,-.006),(200,200),ground)
sc.world.use_nodes=True;bg=next(n for n in sc.world.node_tree.nodes if n.type=='BACKGROUND');bg.inputs[0].default_value=(.66,.76,.92,1);bg.inputs[1].default_value=.4
bpy.ops.object.light_add(type='SUN',location=(2,-4,8));sun=bpy.context.object;sun.rotation_euler=(.45,-.5,-.4);sun.data.energy=2.2;sun.data.angle=.1
bpy.ops.object.camera_add(location=(8,-10,10));cam=bpy.context.object;sc.camera=cam;cam.data.type='ORTHO'
sc.render.engine='CYCLES';sc.cycles.samples=32;sc.cycles.use_denoising=True;sc.render.resolution_x=1400;sc.render.resolution_y=1000;sc.render.resolution_percentage=100;sc.view_settings.view_transform='AgX'
sc.view_settings.exposure=.8
def view(loc,target,scale):
    cam.location=loc;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=scale
def render(name):
    sc.render.filepath=str(out/(name+'.png'));bpy.ops.render.render(write_still=True)
view((8,-10,10),(1,1.9,0),10)
bpy.ops.file.pack_all();bpy.ops.wm.save_as_mainfile(filepath=str(out/'street_edge_stones_master.blend'),compress=True)
render('master_overview')
view((2.8,-2,1.6),(1.2,0,.02),1.6);render('master_close')
sun.rotation_euler=(1.25,-.2,2.4);render('master_grazing')
for o in all_stones:o.modifiers[0].segments=2
render('optimized_grazing')
sun.rotation_euler=(.45,-.5,-.4);render('optimized_close')
view((8,-10,10),(1,1.9,0),10);render('optimized_overview')
bpy.ops.wm.save_as_mainfile(filepath=str(out/'street_edge_stones_optimized.blend'),compress=True)
manifest=[]
for asset in assets:
    bpy.ops.object.select_all(action='DESELECT')
    for o in asset['objects']:o.location-=Vector(asset['preview']);o.select_set(True)
    bpy.context.view_layer.objects.active=asset['objects'][0]
    # One static mesh / one material per exported module, retain editable master.
    duplicates=[]
    for o in asset['objects']:
        dup=o.copy();dup.data=o.data.copy();sc.collection.objects.link(dup);duplicates.append(dup)
    bpy.ops.object.select_all(action='DESELECT')
    for dup in duplicates:
        dup.select_set(True);bpy.context.view_layer.objects.active=dup
        for mod in list(dup.modifiers):bpy.ops.object.modifier_apply(modifier=mod.name)
        dup.select_set(False)
    for dup in duplicates:dup.select_set(True)
    bpy.context.view_layer.objects.active=duplicates[0];bpy.ops.object.join();obj=bpy.context.object;obj.name=asset['id']
    bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    bm=bmesh.new();bm.from_mesh(obj.data);assert all(e.is_manifold for e in bm.edges);bm.free()
    obj.data.calc_loop_triangles();tri=len(obj.data.loop_triangles)
    file=models/(asset['id']+'.glb')
    bpy.ops.export_scene.gltf(filepath=str(file),export_format='GLB',use_selection=True,export_extras=True)
    manifest.append(dict(id=asset['id'],recipe=asset['recipe'],master_triangles=asset['master_triangles'],game_triangles=tri,sha256=hashlib.sha256(file.read_bytes()).hexdigest(),bytes=file.stat().st_size,manifold=True))
    bpy.data.objects.remove(obj,do_unlink=True)
    for o in asset['objects']:o.location+=Vector(asset['preview'])
(out/'manifest.json').write_text(json.dumps(dict(status='offline review; not published',parameters=vars(a),source_material='Quixel Beach Cliff; source material.json retained in project',assets=manifest),indent=2),encoding='utf8')
print('STREET_STONES_COMPLETE',len(manifest),flush=True)
