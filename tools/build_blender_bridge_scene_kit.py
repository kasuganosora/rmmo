"""Missing scenery for bridge/street reference; offline review kit only."""
import bpy,math,random,json
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1];RUNTIME=ROOT.parent/'rmmo_runtime'
OUT=RUNTIME/'art_sources/bridge_street_kit';OUT.mkdir(exist_ok=True);(OUT/'models').mkdir(exist_ok=True)
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False);random.seed(10573)
def material(name,color):
    m=bpy.data.materials.new(name);m.use_nodes=True;m.diffuse_color=(*color,1)
    p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*color,1);p.inputs['Roughness'].default_value=.85;return m
def pbr(folder):
    path=RUNTIME/'packs/default/assets/materials'/folder;spec=json.loads((path/'material.json').read_text(encoding='utf-8-sig'))['material']
    m=material(folder,(.5,.45,.35));nt=m.node_tree;p=nt.nodes.get('Principled BSDF');coord=nt.nodes.new('ShaderNodeTexCoord')
    for key,socket in [('texture_path','Base Color'),('roughness_path','Roughness'),('normal_path','Normal')]:
        if key not in spec:continue
        im=bpy.data.images.load(str(path/spec[key]),check_existing=True);im.pack()
        if key!='texture_path':im.colorspace_settings.name='Non-Color'
        tex=nt.nodes.new('ShaderNodeTexImage');tex.image=im;tex.projection='BOX';tex.projection_blend=.25;nt.links.new(coord.outputs['Object'],tex.inputs['Vector'])
        if key=='normal_path':
            normal=nt.nodes.new('ShaderNodeNormalMap');normal.inputs['Strength'].default_value=.45;nt.links.new(tex.outputs[0],normal.inputs['Color']);nt.links.new(normal.outputs[0],p.inputs[socket])
        else:nt.links.new(tex.outputs[0],p.inputs[socket])
    return m
stone=pbr('walls/stone_tiles_facade');rock=pbr('terrain/beach_cliff');wood=pbr('wood/solid_timber');tiles=pbr('roofs/terracotta_plain');grassground=pbr('terrain/mossy_grass_vcjmej0s')
bark=material('Rough living tree bark',(.16,.13,.085));nt=bark.node_tree;p=nt.nodes.get('Principled BSDF')
coord=nt.nodes.new('ShaderNodeTexCoord');mapping=nt.nodes.new('ShaderNodeVectorMath');mapping.operation='MULTIPLY';mapping.inputs[1].default_value=(7,7,.6);nt.links.new(coord.outputs['Object'],mapping.inputs[0])
n=nt.nodes.new('ShaderNodeTexNoise');n.inputs['Scale'].default_value=5;n.inputs['Detail'].default_value=5;nt.links.new(mapping.outputs[0],n.inputs['Vector'])
ramp=nt.nodes.new('ShaderNodeValToRGB');ramp.color_ramp.elements[0].color=(.045,.038,.024,1);ramp.color_ramp.elements[1].color=(.26,.23,.17,1);nt.links.new(n.outputs['Fac'],ramp.inputs[0]);nt.links.new(ramp.outputs[0],p.inputs['Base Color'])
bump=nt.nodes.new('ShaderNodeBump');bump.inputs['Strength'].default_value=.6;bump.inputs['Distance'].default_value=.045;nt.links.new(n.outputs['Fac'],bump.inputs['Height']);nt.links.new(bump.outputs[0],p.inputs['Normal'])
with bpy.data.libraries.load(str(RUNTIME/'art_sources/town_planters/boxwood_review/optimized/town_planters_boxwood_optimized.blend'),link=False) as (src,dst):dst.materials=[next(n for n in src.materials if n.startswith('Quixel Boxwood'))]
scan_leaf=dst.materials[0]
leaves=[material('Summer leaf '+str(i),c) for i,c in enumerate([(.08,.20,.023),(.16,.31,.045),(.22,.37,.060),(.10,.25,.035)])]
for m in leaves:
    p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Subsurface Weight'].default_value=.045;p.inputs['Roughness'].default_value=.68
    nt=m.node_tree;n=nt.nodes.new('ShaderNodeTexNoise');n.inputs['Scale'].default_value=30;b=nt.nodes.new('ShaderNodeBump');b.inputs['Strength'].default_value=.18;b.inputs['Distance'].default_value=.001;nt.links.new(n.outputs['Fac'],b.inputs['Height']);nt.links.new(b.outputs[0],p.inputs['Normal'])
linen=material('Warm washed linen',(.78,.76,.65));nt=linen.node_tree;n=nt.nodes.new('ShaderNodeTexNoise');n.inputs['Scale'].default_value=190;b=nt.nodes.new('ShaderNodeBump');b.inputs['Strength'].default_value=.3;b.inputs['Distance'].default_value=.001;nt.links.new(n.outputs['Fac'],b.inputs['Height']);nt.links.new(b.outputs[0],nt.nodes.get('Principled BSDF').inputs['Normal'])
rope=material('Natural clothesline',(.33,.26,.13));dark=material('Window interior shadow',(.018,.022,.019))
assets=[]
def begin(name):
    global current,start
    current=bpy.data.collections.new(name);bpy.context.scene.collection.children.link(current);start=set(bpy.context.scene.objects)
def finish(location):
    objs=list(set(bpy.context.scene.objects)-start)
    for o in objs:
        for c in list(o.users_collection):c.objects.unlink(o)
        current.objects.link(o)
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:o.select_set(True)
    bpy.context.view_layer.objects.active=objs[0]
    bpy.ops.export_scene.gltf(filepath=str(OUT/'models'/(current.name+'.glb')),export_format='GLB',use_selection=True,export_yup=True)
    tris=0
    for o in objs:
        if o.type=='MESH':o.data.calc_loop_triangles();tris+=len(o.data.loop_triangles)
        o.location+=Vector(location)
    assets.append({'id':current.name,'file':'models/'+current.name+'.glb','objects':len(objs),'base_triangles':tris,'status':'offline_review','preview_origin':location})
def mesh(name,v,f,m):
    d=bpy.data.meshes.new(name);d.from_pydata(v,[],f);d.update();o=bpy.data.objects.new(name,d);bpy.context.collection.objects.link(o);d.materials.append(m)
    uv=d.uv_layers.new(name='SurfaceUV')
    for p in d.polygons:
        for i in p.loop_indices:
            co=d.vertices[d.loops[i].vertex_index].co;uv.data[i].uv=(co.x,co.z) if abs(p.normal.y)>.5 else (co.y,co.z)
    return o
def box(name,loc,size,m):
    bpy.ops.mesh.primitive_cube_add(size=1,location=loc);o=bpy.context.object;o.name=name;o.scale=size;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.data.materials.append(m)
    be=o.modifiers.new('Soft stone arris','BEVEL');be.width=.018;be.segments=1;return o
def tube(name,pts,rads,m,sides=9):
    vs=[];fs=[]
    for i,point in enumerate(pts):
        axis=(Vector(pts[min(i+1,len(pts)-1)])-Vector(pts[max(i-1,0)])).normalized();u=axis.cross(Vector((0,1,0))).normalized();v=axis.cross(u)
        for j in range(sides):vs.append(Vector(point)+rads[i]*(u*math.cos(j*math.tau/sides)+v*math.sin(j*math.tau/sides)))
    for i in range(len(pts)-1):
        for j in range(sides):fs.append((i*sides+j,i*sides+(j+1)%sides,(i+1)*sides+(j+1)%sides,(i+1)*sides+j))
    fs.extend([tuple(range(sides-1,-1,-1)),tuple((len(pts)-1)*sides+j for j in range(sides))]);o=mesh(name,vs,fs,m)
    for p in o.data.polygons:p.use_smooth=True
    return o
# Spreading broadleaf tree: real branch hierarchy and individually bent leaves.
begin('01_spreading_broadleaf_tree')
tube('Irregular trunk',[(0,0,0),(.12,.03,1.7),(-.08,.1,3.2),(.18,0,4.8),(.25,.1,6.4)],[.37,.29,.23,.15,.045],bark,32)
lv=[];lf=[];luv=[]
rects=[(.084,.074,.176,.329),(.444,.054,.538,.350),(.574,.085,.673,.342),(.720,.099,.795,.320),(.856,.099,.952,.360)]
for branch in range(18):
    a=branch*2.399;z=2.5+branch*.15;extent=random.uniform(2.0,3.65);tip=Vector((math.cos(a)*extent,math.sin(a)*extent,5.3+random.uniform(-.3,2.1)))
    root=Vector((0,0,z));mid=root.lerp(tip,.48)+Vector((0,0,.4));tube('Primary tree limb',[root,mid,tip],[.13,.065,.014],bark,16)
    for twig in range(6):
        ta=a+random.uniform(-1.4,1.4);end=tip+Vector((math.cos(ta)*random.uniform(.3,1.0),math.sin(ta)*random.uniform(.3,1.0),random.uniform(-.4,.7)))
        tube('Crown twig',[mid.lerp(tip,.55),tip,end],[.025,.014,.0025],bark,10)
        for j in range(85):
            centre=end+Vector((random.gauss(0,.52),random.gauss(0,.52),random.gauss(0,.32)))
            a=random.random()*math.tau;axis=Vector((math.cos(a),math.sin(a),random.uniform(-.3,1))).normalized();u=Vector((-math.sin(a),math.cos(a),random.uniform(-.5,.5))).normalized();normal=axis.cross(u).normalized();length=random.uniform(.35,.55);x0,y0,x1,y1=random.choice(rects);width=length*(x1-x0)/(y1-y0)
            q=len(lv)
            for row in range(3):
                t=row/2
                for column in range(3):
                    s=column/2;lv.append(centre+axis*((t-.5)*length)+u*((s-.5)*width)+normal*(math.sin(t*math.pi)*.035));luv.append((x0+(x1-x0)*s,1-y1+(y1-y0)*t))
            for row in range(2):
                for column in range(2):b=q+row*3+column;lf.append((b,b+1,b+4,b+3))
o=mesh('Scanned leaf branches with alpha normal roughness',lv,lf,scan_leaf)
for lp in o.data.loops:o.data.uv_layers.active.data[lp.index].uv=luv[lp.vertex_index]
for p in o.data.polygons:p.use_smooth=True
finish((-5,4,0))
# Exposed rock bank plus reusable standalone boulders.
for variant in range(3):
    begin(['02_rock_bank_3m','03_river_boulder_large','04_river_boulder_small'][variant])
    for k in range(6 if variant==0 else 1):
        bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2,radius=1,location=((k-2.5)*.53 if variant==0 else 0,random.uniform(-.08,.08),.50 if variant==0 else .4));o=bpy.context.object;o.name='Weathered bank rock';o.scale=(random.uniform(.35,.5),random.uniform(.48,.65),random.uniform(.65,.98)) if variant==0 else ((1,.75,.78) if variant==1 else (.52,.38,.40));o.data.materials.append(rock)
        for v in o.data.vertices:v.co*=random.uniform(.86,1.10)
        sub=o.modifiers.new('Dense weathered rock surface','SUBSURF');sub.subdivision_type='SIMPLE';sub.levels=2
        tex=bpy.data.textures.new('Natural rock fractures','CLOUDS');tex.noise_scale=.16;tex.noise_depth=2
        disp=o.modifiers.new('Broken natural surface','DISPLACE');disp.texture=tex;disp.strength=.10;disp.mid_level=.5
        for poly in o.data.polygons:poly.use_smooth=True
        bevel=o.modifiers.new('Weathered corners','BEVEL');bevel.width=.025;bevel.segments=3
    finish(((variant-1)*3.3,0,0))
# Upright tapering grass: several densities, no flat ground texture masquerading as grass.
for idx,(n,radius,height) in enumerate([(180,.55,.65),(80,.32,.36),(260,.70,.85)]):
    begin('0'+str(5+idx)+'_grass_clump')
    vs=[];fs=[]
    for k in range(n):
        a=random.random()*math.tau;r=math.sqrt(random.random())*radius;root=Vector((r*math.cos(a),r*math.sin(a),0));a=random.random()*math.tau;axis=Vector((math.cos(a),math.sin(a),0));across=Vector((-math.sin(a),math.cos(a),0));h=height*random.uniform(.45,1)
        q=len(vs)
        for t in [0,.34,.70,1]:
            center=root+Vector((0,0,h*t))+axis*(h*.55*t*t)
            for side in [-1,1]:vs.append(center+across*side*.014*(1-t))
        for row in range(3):j=q+row*2;fs.append((j,j+1,j+3,j+2))
    o=mesh('Bent individual grass blades',vs,fs,leaves[1]);o.data.materials.append(leaves[2])
    for p in o.data.polygons:p.material_index=(p.index//3)%2
    finish((-3+idx*2,-2,0))
# Low coursed garden wall, matching the pale town masonry.
for variant in range(2):
    begin(('08_low_garden_wall','09_garden_gate_pier')[variant]);length=3 if variant==0 else .55;h=.92 if variant==0 else 1.4
    rows=5 if variant==0 else 7
    for row in range(rows):
        count=6 if variant==0 else 1
        for k in range(count):box('Coursed wall stone',(-length/2+(k+.5)*length/count,0,(row+.5)*h/rows),(length/count-.012,.38,h/rows-.012),stone)
    for k in range(6 if variant==0 else 1):
        count=6 if variant==0 else 1;box('Pale coping',(-length/2+(k+.5)*length/count,0,h+.05),(length/count-.008,.47,.12),stone)
    finish((3.4+variant*2,-2.6,0))
# Washing line with cloth folds and actual wooden pegs.
begin('10_laundry_line')
for x in [-1.9,1.9]:tube('Laundry oak upright',[(x,0,0),(x+.025,0,2.35)],[.065,.052],wood)
pts=[(-1.9+3.8*t,0,2.20-.13*math.sin(math.pi*t)) for t in [k/40 for k in range(41)]];tube('Sagging clothesline',pts,[.009]*41,rope,6)
for n in range(4):
    x0=-1.68+n*.88;vs=[];fs=[];width=.68;length=[1.12,.84,1.25,.90][n]
    for j in range(17):
        v=j/16
        for i in range(13):
            u=i/12;x=x0+u*width;top=2.20-.13*math.sin(math.pi*(x+1.9)/3.8)
            vs.append((x,.04*math.sin(u*math.tau*2+n)*v+.035*math.sin(v*math.pi),top-v*length))
    for j in range(16):
        for i in range(12):q=j*13+i;fs.append((q,q+1,q+14,q+13))
    o=mesh('Hanging washed linen',vs,fs,linen);o.modifiers.new('Thin cloth','SOLIDIFY').thickness=.0015
    for p in o.data.polygons:p.use_smooth=True
    for x in [x0+.06,x0+width-.06]:box('Wooden clothes peg',(x,-.013,2.21-.13*math.sin(math.pi*(x+1.9)/3.8)),(.021,.025,.095),wood)
finish((-3.5,-5.5,0))
# Distant tower is an exterior silhouette asset, not a playable or reserved building.
begin('11_distant_square_roof_tower')
box('Tower lower masonry',(0,0,3.6),(1.8,1.8,7.2),stone)
for side in range(4):
    for x in [-.66,.66]:
        o=box('Window side pier',(x,-.79,7.8),(.48,.22,1.2),stone);a=side*math.pi/2;o.location=Vector((o.location.x*math.cos(a)-o.location.y*math.sin(a),o.location.x*math.sin(a)+o.location.y*math.cos(a),o.location.z));o.rotation_euler.z=a
    o=box('Window head beam',(0,-.79,8.5),(1.8,.22,.25),stone);a=side*math.pi/2;o.location=Vector((-o.location.y*math.sin(a),o.location.y*math.cos(a),o.location.z));o.rotation_euler.z=a
box('Dark tower inner chamber',(0,0,7.8),(.70,.70,1.4),dark)
mesh('Terracotta pyramidal spire',[(-1.08,-1.08,8.65),(1.08,-1.08,8.65),(1.08,1.08,8.65),(-1.08,1.08,8.65),(0,0,12)],[(0,1,4),(1,2,4),(2,3,4),(3,0,4)],tiles)
finish((6,5,0))
# Ground shrubs reuse accepted scan geometry/materials without the planter shell.
begin('12_natural_boxwood_shrub')
source=RUNTIME/'art_sources/town_planters/boxwood_review/optimized/town_planters_boxwood_optimized.blend'
with bpy.data.libraries.load(str(source),link=False) as (src,dst):dst.objects=[next(n for n in src.objects if n.startswith('Boxwood scanned'))]
o=dst.objects[0];bpy.context.collection.objects.link(o);o.location=(0,0,-.66)
# Keep a centre segment from the source hedge, maintaining original scanned leaf size.
import bmesh
bm=bmesh.new();bm.from_mesh(o.data);remove=[v for v in bm.verts if abs(v.co.x)>.53];bmesh.ops.delete(bm,geom=remove,context='VERTS');bm.to_mesh(o.data);bm.free()
finish((1,-5.3,0))
# Carrying props seen on the bridge; compatible with later character posing.
begin('13_shoulder_pole_and_bundle')
tube('Long carrying pole',[(-.9,0,.09),(0,.015,.10),(.9,0,.13)],[.023,.026,.022],wood)
bpy.ops.mesh.primitive_uv_sphere_add(segments=16,ring_count=10,radius=.30,location=(.57,0,-.30));o=bpy.context.object;o.name='Cloth carrying bundle';o.scale=(1,.7,.7);o.data.materials.append(linen)
tube('Bundle suspension',[(.55,0,.11),(.55,0,-.12)],[.014,.014],rope,6)
finish((3.5,-5.3,.7))
scene=bpy.context.scene;box('Review floor',(0,0,-.12),(200,200,.2),material('Review sandstone',(.32,.31,.27)))
scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.65,.75,.9,1);scene.world.node_tree.nodes['Background'].inputs[1].default_value=.45
bpy.ops.object.light_add(type='SUN',location=(0,0,10));bpy.context.object.rotation_euler=(.5,-.5,-.4);bpy.context.object.data.energy=2;bpy.context.object.data.angle=.15
bpy.ops.object.light_add(type='AREA',location=(-5,-5,12));o=bpy.context.object;o.data.energy=2200;o.data.size=10;o.rotation_euler=(Vector((0,0,2))-o.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(location=(18,-28,20));cam=bpy.context.object;cam.rotation_euler=(Vector((0,1,3.5))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=24;scene.camera=cam
scene.render.engine='CYCLES';scene.cycles.samples=24;scene.cycles.use_denoising=True;scene.render.resolution_x=1800;scene.render.resolution_y=1300;scene.unit_settings.system='METRIC';scene.view_settings.view_transform='AgX'
bpy.ops.file.pack_all();bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'bridge_street_missing_assets.blend'))
(OUT/'new_assets_manifest.json').write_text(json.dumps(assets,indent=2),encoding='utf8')
scene.render.filepath=str(OUT/'missing_assets_overview.png');bpy.ops.render.render(write_still=True)
cam.location=(6,-14,6);cam.rotation_euler=(Vector((0,-3,1.0))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=14
scene.render.filepath=str(OUT/'ground_props_detail.png');bpy.ops.render.render(write_still=True)
print('BRIDGE_KIT_COMPLETE',len(assets))
