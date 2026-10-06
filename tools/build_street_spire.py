"""Blender offline street landmark. Editable sections, real window apertures.
Run Blender -b --python tools/build_street_spire.py -- --shaft-height 20 --roof-height 7.5 --finial-height 2.4 --radius 1.8
"""
import bpy, bmesh, math, random, argparse, sys, json, hashlib
from pathlib import Path
from mathutils import Vector

p=argparse.ArgumentParser()
p.add_argument('--shaft-height',type=float,default=20)
p.add_argument('--roof-height',type=float,default=7.5)
p.add_argument('--finial-height',type=float,default=2.4)
p.add_argument('--radius',type=float,default=1.8)
a=p.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
assert 10<=a.shaft_height<=30 and 4<=a.roof_height<=14 and 1.5<=a.radius<=4
root=Path(__file__).resolve().parents[2]/'rmmo_runtime'
out=root/'art_sources/street_red_spire'/('square_3window_shaft_%d_roof_%d_finial_%d'%(round(a.shaft_height*100),round(a.roof_height*100),round(a.finial_height*100)));out.mkdir(parents=True,exist_ok=True)
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
sc=bpy.context.scene;sc.unit_settings.system='METRIC';rng=random.Random(61006)
H=a.shaft_height;R=a.radius;RH=a.roof_height
src=(Path(__file__).parent/'build_street_edge_stones.py').read_text(encoding='utf8')
exec(src[src.index('def surface('):src.index('stone=surface(')])
stone=surface('Light limestone trim','terrain/beach_cliff')
plaster=surface('Warm limewash with scanned plaster relief','walls/troweled_plaster')
bs=next(n for n in plaster.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
for link in list(plaster.node_tree.links):
    if link.to_socket==bs.inputs['Base Color']:plaster.node_tree.links.remove(link)
bs.inputs['Base Color'].default_value=(.68,.62,.45,1)
def plain(name,color,rough=.8,metal=0):
    m=bpy.data.materials.new(name);m.use_nodes=True;b=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    b.inputs['Base Color'].default_value=(*color,1);b.inputs['Roughness'].default_value=rough;b.inputs['Metallic'].default_value=metal
    return m
iron=plain('Dark weathered iron',(.035,.03,.023),.65,.7)
wood=plain('Dark oak door',(.10,.054,.021))
tiles=[]
for i in range(7):
    m=plain('Fired red clay %d'%i,(.31+i*.013,.070+i*.005,.027+i*.002),.88)
    nt=m.node_tree;b=next(n for n in nt.nodes if n.type=='BSDF_PRINCIPLED')
    n=nt.nodes.new('ShaderNodeTexNoise');n.inputs['Scale'].default_value=95;n.inputs['Detail'].default_value=3
    bump=nt.nodes.new('ShaderNodeBump');bump.inputs['Strength'].default_value=.20;bump.inputs['Distance'].default_value=.015
    nt.links.new(n.outputs['Fac'],bump.inputs['Height']);nt.links.new(bump.outputs[0],b.inputs['Normal']);tiles.append(m)
objects=[];bevels=[]
def mesh(name,v,f,mat,bevel=0):
    me=bpy.data.meshes.new(name);me.from_pydata(v,[],f);me.update()
    bm=bmesh.new();bm.from_mesh(me);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(me);bm.free();me.update()
    o=bpy.data.objects.new(name,me);sc.collection.objects.link(o);me.materials.append(mat);objects.append(o)
    uv=me.uv_layers.new(name='UVMap')
    for poly in me.polygons:
        axis=max(range(3),key=lambda k:abs(poly.normal[k]))
        for li in poly.loop_indices:
            c=me.vertices[me.loops[li].vertex_index].co
            uv.data[li].uv=((c.x,c.y) if axis==2 else ((c.x,c.z) if axis==1 else (c.y,c.z)))
    if bevel:
        mod=o.modifiers.new('Edge rounding master4 game2','BEVEL');mod.width=bevel;mod.segments=4;bevels.append(mod)
        mod=o.modifiers.new('Keep planar normals','WEIGHTED_NORMAL');mod.keep_sharp=True
    return o
def box(name,loc,size,mat,bevel=.015):
    x,y,z=loc;w,d,h=[s/2 for s in size]
    return mesh(name,[(x+sx*w,y+sy*d,z+sz*h) for sz in [-1,1] for sy in [-1,1] for sx in [-1,1]],[(0,2,3,1),(4,5,7,6),(0,1,5,4),(2,6,7,3),(0,4,6,2),(1,3,7,5)],mat,bevel)
def ring(name,outer,inner,z,h,mat,n=4):
    corners=[(-1,-1),(1,-1),(1,1),(-1,1)]
    v=[(rad*x,rad*y,zz) for zz,rad in [(z,outer),(z+h,outer),(z,inner),(z+h,inner)] for x,y in corners]
    f=[]
    for i in range(n):
        j=(i+1)%n;f.extend([(i,j,n+j,n+i),(2*n+j,2*n+i,3*n+i,3*n+j),(n+i,n+j,3*n+j,3*n+i),(j,i,2*n+i,2*n+j)])
    return mesh(name,v,f,mat)
def arch_prism(name,w,bottom,spring,yfront,yback,mat):
    points=[(-w/2,bottom),(w/2,bottom)]+[(w/2*math.cos(t*math.pi/16),spring+w/2*math.sin(t*math.pi/16)) for t in range(17)]
    n=len(points);v=[(x,y,z) for y in [yfront,yback] for x,z in points]
    return mesh(name,v,[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)],mat)
def cut(obj,cutter):
    bpy.context.view_layer.objects.active=obj;m=obj.modifiers.new('Actual arched opening','BOOLEAN');m.operation='DIFFERENCE';m.object=cutter;bpy.ops.object.modifier_apply(modifier=m.name)
    objects.remove(cutter);bpy.data.objects.remove(cutter,do_unlink=True)
def arch_trim(w,bottom,spring,angle,label):
    made=[]
    for x in [-w/2-.09,w/2+.09]:
        for z in range(max(1,round((spring-bottom)/.26))):
            n=max(1,round((spring-bottom)/.26));dz=(spring-bottom)/n
            made.append(box(label+' jamb',(x,-R-.015,bottom+(z+.5)*dz),(.18,.24,dz-.007),stone,.008))
    for j in range(11):
        t0=j*math.pi/11+.009;t1=(j+1)*math.pi/11-.009
        v=[(rad*math.cos(t),y,spring+rad*math.sin(t)) for y in [-R-.13,-R+.13] for rad,t in [(w/2,t0),(w/2,t1),(w/2+.18,t1),(w/2+.18,t0)]]
        made.append(mesh(label+' arch stone',v,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],stone,.006))
    made.append(box(label+' sill',(0,-R-.015,bottom-.065),(w+.44,.36,.13),stone,.01))
    for o in made:o.rotation_euler.z=angle

# Hollow shaft in four independently editable vertical sections.
sections=[]
for i in range(4):sections.append(ring('Shaft section %d'%i,R,R-.38,i*H/4,H/4,plaster))
ring('Stone foundation',R+.13,R-.40,-.12,.50,stone)
for z in [.4,H-.37,H-.16]:ring('Limestone string / eave course',R+.10,R-.39,z,.16,stone)
window_levels=[H*t-.05 for t in [.30,.60,.90]]
for level in window_levels:
    for angle in [0,math.pi/2,math.pi,3*math.pi/2]:
        w=.56;spring=level+.80
        # Cut every section touched by an aperture, also at non-default heights.
        for index,section in enumerate(sections):
            if level<(index+1)*H/4 and spring+w/2>index*H/4:
                c=arch_prism('Window cutter',w,level,spring,-R-.5,-R+.65,stone);c.rotation_euler.z=angle
                cut(section,c)
        arch_trim(w,level,spring,angle,'Narrow window')
# Front entrance is closed in this exterior study; no implied playable interior.
c=arch_prism('Door cut',1.12,.04,2.03,-R-.5,-R+.65,stone);cut(sections[0],c)
door=arch_prism('Separate closed door',1.10,.045,2.03,-R+.19,-R+.27,wood);arch_trim(1.12,.05,2.03,0,'Entrance')
for x in [-.40,-.20,0,.20,.40]:box('Door vertical joint',(x,-R+.181,1.03),(.013,.01,1.95),iron,0)
for z in [.5,1.55]:box('Door iron strap',(0,-R+.16,z),(1.02,.026,.065),iron,.006)
# Eaves and continuous under-roof; no floating tiles.
roofbase=H+.08;roofrad=R+.39
v=[(x*roofrad,y*roofrad,roofbase) for x,y in [(-1,-1),(1,-1),(1,1),(-1,1)]]+[(0,0,roofbase+RH)]
mesh('Four-sided pyramid roof deck',v,[(i,(i+1)%4,4) for i in range(4)]+[(3,2,1,0)],wood)
ring('Square eave timber fascia',roofrad,roofrad-.15,H-.04,.16,wood)
tile_objs=[]
rows=math.ceil(RH/.19)
for row in range(rows):
    z0=roofbase+row*RH/rows;z1=min(roofbase+RH-.015,z0+RH/rows+.07)
    rb=roofrad*(1-(z0-roofbase)/RH)+.018;rt=max(.015,roofrad*(1-(z1-roofbase)/RH)+.016)
    count=max(1,round(2*rb/.23))
    # Trapezoid cuts at hips; each roof slope stays planar.
    for side in range(4):
        angle=side*math.pi/2
        for j in range(count):
            lo=-1+2*j/count+.006;hi=-1+2*(j+1)/count-.006
            pts=[]
            for inset in [0,.026]:
                for x,y,z in [(lo*rb,-rb+inset,z0),((lo+hi)/2*rb,-rb+inset,z0-.015),(hi*rb,-rb+inset,z0),(hi*rt,-rt+inset,z1),(lo*rt,-rt+inset,z1)]:
                    pts.append((x*math.cos(angle)-y*math.sin(angle),x*math.sin(angle)+y*math.cos(angle),z))
            tile_objs.append(mesh('Overlapping red tile',pts,[(0,1,2,3,4),(9,8,7,6,5)]+[(k,(k+1)%5,(k+1)%5+5,k+5) for k in range(5)],rng.choice(tiles),.0035))
    # Folded terracotta hip caps close the four roof seams.
    for sx,sy in [(-1,-1),(1,-1),(1,1),(-1,1)]:
        pts=[]
        for dz in [0,-.023]:
            for rad,z in [(rb+.014,z0-.025),(rt+.014,z1)]:
                pts.extend([(sx*(rad-.075),sy*(rad+.006),z+dz),(sx*(rad+.012),sy*(rad+.012),z+.018+dz),(sx*(rad+.006),sy*(rad-.075),z+dz)])
        faces=[(0,1,4,3),(1,2,5,4),(9,10,7,6),(10,11,8,7),(0,3,9,6),(2,8,11,5),(0,6,7,8,2,1),(3,4,5,11,10,9)]
        tile_objs.append(mesh('Overlapping red tile hip cap',pts,faces,tiles[3],.0035))
# Weathered metal termination; slender gilded-looking tip, no invented insignia.
bpy.ops.mesh.primitive_cone_add(vertices=32,radius1=.065,radius2=.008,depth=a.finial_height,location=(0,0,roofbase+RH-.13+a.finial_height/2))
tip=bpy.context.object;tip.name='Metal finial';tip.data.materials.append(iron);objects.append(tip)
for o in objects:o['asset_role']='street_red_spire';o['rmmo_collision']='block'
asset_objects=list(objects)
ground=box('Review floor',(0,0,-.2),(200,200,.12),plain('Neutral floor',(.28,.30,.26)),0);objects.remove(ground)
sc.world.use_nodes=True;bg=next(n for n in sc.world.node_tree.nodes if n.type=='BACKGROUND');bg.inputs[0].default_value=(.68,.78,.95,1);bg.inputs[1].default_value=.45
bpy.ops.object.light_add(type='SUN');sun=bpy.context.object;sun.rotation_euler=(.5,-.45,-.6);sun.data.energy=2.5;sun.data.angle=.10
bpy.ops.object.camera_add();cam=bpy.context.object;sc.camera=cam;cam.data.type='ORTHO'
sc.render.engine='CYCLES';sc.cycles.samples=24;sc.cycles.use_denoising=True;sc.render.resolution_x=1000;sc.render.resolution_y=1500;sc.render.resolution_percentage=100;sc.view_settings.view_transform='AgX'
def view(close=False):
    cam.location=(10,-18,H+5) if close else (30,-48,26)
    target=Vector((0,0,H+1.7 if close else (H+RH)/2))
    cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=10 if close else H+RH+a.finial_height+2.1
def render(name,close=False):
    view(close);sc.render.filepath=str(out/(name+'.png'));bpy.ops.render.render(write_still=True)
def tris():
    total=0
    for o in asset_objects:
        ev=o.evaluated_get(bpy.context.evaluated_depsgraph_get());me=ev.to_mesh();me.calc_loop_triangles();total+=len(me.loop_triangles);ev.to_mesh_clear()
    return total
view();bpy.ops.file.pack_all();bpy.ops.wm.save_as_mainfile(filepath=str(out/'street_spire_master.blend'),compress=True)
master=tris();render('master_overview');render('master_close',True)
for mod in bevels:mod.segments=2
game=tris();render('optimized_close',True);render('optimized_overview')
view();bpy.ops.wm.save_as_mainfile(filepath=str(out/'street_spire_optimized.blend'),compress=True)
# Keep tile geometry in one roof mesh, wall sections and door separate.
bpy.ops.object.select_all(action='DESELECT')
for o in tile_objs:o.select_set(True)
bpy.context.view_layer.objects.active=tile_objs[0]
deps=bpy.context.evaluated_depsgraph_get()
evaluated_tiles=[bpy.data.meshes.new_from_object(o.evaluated_get(deps)) for o in tile_objs]
for o,data in zip(tile_objs,evaluated_tiles):
    o.modifiers.clear();o.data=data
bpy.ops.object.join();roof=bpy.context.object;roof.name='Roof tiles joined'
for m in tiles:
    # GLB cannot carry Blender procedural bump; export retains geometry/color/roughness.
    m['offline_procedural_micro_bump']=True
bpy.ops.object.select_all(action='DESELECT')
for o in sc.objects:
    if o.get('asset_role')=='street_red_spire':o.select_set(True)
glb=out/'street_spire_review.glb';bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',use_selection=True,export_extras=True,export_apply=True)
report=dict(status='offline exterior review',dimensions=dict(shaft_height=H,roof_height=RH,width=2*R,depth=2*R,plan='square',window_rows=3,window_bottom_heights=window_levels,finial_height=a.finial_height,total_height=roofbase+RH-.13+a.finial_height),master_triangles=master,optimized_triangles=game,reduction=1-game/master,tile_count=len(tile_objs),sha256=hashlib.sha256(glb.read_bytes()).hexdigest(),limitations=['No playable stairs or interior fit-out','Procedural clay micro-bump is Blender-only; bake before production import','No editor publication or map placement'])
(out/'manifest.json').write_text(json.dumps(report,indent=2),encoding='utf8')
print('SPIRE_COMPLETE',json.dumps(report),flush=True)
