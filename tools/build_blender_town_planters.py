"""Seven original street planters. Blender 4.5 --background --python this_file."""
import bpy, math, random, json, sys, argparse
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument('--config',default=str(ROOT/'tools/town_planters_parameters.json'))
parser.add_argument('--output',default=str(ROOT.parent/'rmmo_runtime/art_sources/town_planters'))
parser.add_argument('--no-render',action='store_true')
args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
parameters=json.loads(Path(args.config).read_text(encoding='utf-8-sig'))
OUT = Path(args.output)
EXPORT = OUT / 'review_exports'
OUT.mkdir(parents=True, exist_ok=True)
EXPORT.mkdir(parents=True, exist_ok=True)
random.seed(10525)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
mats=[]
for name,col in [('Limestone honey',(.57,.49,.35)),('Limestone cream',(.68,.60,.45)),('Limestone pale',(.76,.69,.55)),('Limestone weathered',(.49,.44,.33)),('Earth',(.075,.047,.022)),('Leaf shadow',(.024,.063,.014)),('Leaf forest',(.043,.13,.019)),('Leaf mid',(.10,.23,.029)),('Leaf sun',(.20,.32,.049)),('Stem',(.12,.085,.026)),('Lavender',(.30,.18,.45)),('Ivory flower',(.86,.78,.53)),('Flower heart',(.67,.38,.052))]:
    m=bpy.data.materials.new(name);m.diffuse_color=(*col,1);m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*col,1);p.inputs['Roughness'].default_value=.88
    mats.append(m)

def mesh(name,v,f,slots):
    data=bpy.data.meshes.new(name);data.from_pydata(v,[],f);data.update()
    ob=bpy.data.objects.new(name,data);bpy.context.collection.objects.link(ob)
    for m in mats:data.materials.append(m)
    for p,i in zip(data.polygons,slots):p.material_index=i
    return ob

def box(name,loc,size,slot):
    bpy.ops.mesh.primitive_cube_add(size=1,location=loc);o=bpy.context.object;o.name=name;o.scale=size
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);o.data.materials.append(mats[slot])
    mod=o.modifiers.new('Soft dressed edges','BEVEL');mod.width=.009;mod.segments=1
    bpy.ops.object.modifier_apply(modifier=mod.name)
    return o

def wall(a,b,h,brick=False):
    a,b=Vector(a),Vector(b);d=b-a;length=d.length
    for row in range(round(h/.18)):
        cuts=[0]+[x for x in [(.20 if row%2 else .43)+i*.44 for i in range(30)] if x<length]+[length]
        for l,r in zip(cuts,cuts[1:]):
            o=box('Dressed stone course',(*(a+d*((l+r)/2/length)),.09+row*.18),(r-l-.012,.19,.168),random.choice([0,1,1,2,3]))
            o.rotation_euler.z=math.atan2(d.y,d.x)
            if brick:o.data.materials[0]=brick_mats[random.randrange(4)]
    n=math.ceil(length/.55)
    for i in range(n):
        o=box('Overhanging coping',(*(a+d*((i+.5)/n)),h+.045),(length/n-.009,.245,.09),2)
        o.rotation_euler.z=math.atan2(d.y,d.x)
        if brick:o.data.materials[0]=brick_mats[1]

def masonry_ring(poly,h,brick=False):
    points=[Vector(p) for p in poly]
    def border(width):
        inside=[];outside=[]
        for i,p in enumerate(points):
            a=(p-points[i-1]).normalized();b=(points[(i+1)%len(points)]-p).normalized()
            na=Vector((-a.y,a.x));nb=Vector((-b.y,b.x));bis=(na+nb).normalized();delta=bis*(width/2/bis.dot(nb))
            inside.append(p+delta);outside.append(p-delta)
        return inside,outside
    for row in range(round(h/.18)+1):
        cap=row==round(h/.18);inner,outer=border(.245 if cap else .19)
        z=h if cap else row*.18;thick=.09 if cap else .174
        for i,a in enumerate(points):
            nxt=(i+1)%len(points);length=(points[nxt]-a).length
            step=.55 if cap else .44
            cuts=[0]+[x for x in [(.20 if row%2 and not cap else step)+j*step for j in range(30)] if x<length]+[length]
            for l,r in zip(cuts,cuts[1:]):
                t0=(l+.004)/length;t1=(r-.004)/length
                quad=[outer[i].lerp(outer[nxt],t0),outer[i].lerp(outer[nxt],t1),inner[i].lerp(inner[nxt],t1),inner[i].lerp(inner[nxt],t0)]
                vs=[(p.x,p.y,z+dz) for dz in [0,thick] for p in quad]
                slot=(13+random.randrange(4)) if brick else (2 if cap else random.choice([0,1,1,2,3]))
                o=mesh('Mitered coping' if cap else 'Bonded masonry',vs,[(3,2,1,0),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],[slot]*6)
                mod=o.modifiers.new('Dressed edges','BEVEL');mod.width=.005;mod.segments=1
                bpy.context.view_layer.objects.active=o;bpy.ops.object.modifier_apply(modifier=mod.name)

def plants(centres,base,high,flowers=False,broad=False):
    v=[];f=[];s=[]
    def face(points,slot):
        start=len(v);v.extend(points);f.append(tuple(range(start,start+len(points))));s.append(slot)
    def leaf(c,u,w,ln,wd,slot):
        # Folded six-sided leaf, explicit thickness silhouette without alpha cards.
        c=Vector(c);u=Vector(u).normalized();w=Vector(w).normalized()
        p=[c-u*ln*.5,c-u*ln*.20+w*wd*.5,c+u*ln*.25+w*wd*.38,c+u*ln*.5,c+u*ln*.25-w*wd*.38,c-u*ln*.20-w*wd*.5]
        ridge=c+u.cross(w)*.012
        for j in range(6):face([p[j],p[(j+1)%6],ridge],slot)
    for cx,cy in centres:
        top=base+high*random.uniform(.82,1.1)
        # Layered leafy sprays, with connected stems buried in the soil.
        for j in range(65 if not flowers else 24):
            a=random.random()*math.tau;r=math.sqrt(random.random())*.33
            z=base+.1+(top-base-.1)*random.random()
            c=Vector((cx+math.cos(a)*r,cy+math.sin(a)*r,z))
            # Slender branch connects each spray to the rooted plant centre.
            root=Vector((cx,cy,base-.025));side=Vector((.006,0,0))
            face([root-side,root+side,c+side,c-side],9)
            for k in range(5):
                ang=a+k*2.399;u=Vector((math.cos(ang),math.sin(ang),random.uniform(-.15,.8)))
                leaf(c+u*.055,u,(-math.sin(ang),math.cos(ang),.2),random.uniform(.17,.25) if broad else random.uniform(.13,.22),random.uniform(.08,.12) if broad else random.uniform(.065,.105),random.choices([5,6,7,8],[2,4,4,1])[0])
        if flowers:
            for j in range(15):
                a=random.random()*math.tau;r=random.random()*.24
                c=Vector((cx+math.cos(a)*r,cy+math.sin(a)*r,top+random.uniform(-.12,.18)))
                face([c+Vector((-.007,0,0)),c+Vector((.007,0,0)),(c.x+.007,c.y,base),(c.x-.007,c.y,base)],9)
                for k in range(5):
                    ang=k*math.tau/5;u=Vector((math.cos(ang),math.sin(ang),.2))
                    leaf(c+u*.035,u,(-math.sin(ang),math.cos(ang),0),.085,.057,10 if j%3 else 11)
    return mesh('Planting',v,f,s)

brick_mats=[]
for i,col in enumerate([(.47,.27,.15),(.60,.39,.23),(.55,.33,.19),(.66,.45,.28)]):
    m=bpy.data.materials.new('Warm brick '+str(i));m.diffuse_color=(*col,1);m.use_nodes=True;p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*col,1);p.inputs['Roughness'].default_value=.93;brick_mats.append(m);mats.append(m)
specs=[('01_wall_hedge',3.2,.9,.72,False),('02_window_flowers',2.1,.8,.36,True),('03_corner_garden',2.5,2.5,.54,False),('04_octagon_flowers',1.9,1.9,.54,True),('05_brick_leaf_border',3.1,.85,.54,False),('06_brick_leaf_corner',2.5,2.5,.54,False),('07_tall_hedge_corner',2.5,2.5,.72,False)]
# Validate the complete recipe before changing any exported asset.
for idx,(name,w,d,h,flowers) in enumerate(specs):
    p=parameters.get(name,{})
    w=float(p.get('length_m',w));d=float(p.get('depth_m',d));arm=float(p.get('arm_width_m',.87))
    if not all(math.isfinite(v) for v in (w,d,arm)) or not (1<=w<=10 and .7<=d<=10):raise ValueError('Invalid dimensions: '+name)
    if idx in (2,5,6) and not (.7<=arm<=1.5 and min(w,d)>=arm+.5):raise ValueError('Invalid L-shape arm width: '+name)
    if idx==3 and (w!=1.9 or d!=1.9):raise ValueError('Octagon retains its fixed diameter')

def planting_line(a,b):
    a,b=Vector(a),Vector(b);n=max(2,math.ceil((b-a).length/.38)+1)
    return [tuple(a.lerp(b,i/(n-1))) for i in range(n)]

all_models=[];stats={}
for idx,(name,w,d,h,flowers) in enumerate(specs):
    p=parameters.get(name,{})
    w=float(p.get('length_m',w));d=float(p.get('depth_m',d));arm=float(p.get('arm_width_m',.87))
    is_corner=idx in (2,5,6)
    is_brick=idx in (4,5)
    before=set(bpy.context.scene.objects)
    if idx<2 or idx==4:poly=[(-w/2,-d/2),(w/2,-d/2),(w/2,d/2),(-w/2,d/2)]
    elif is_corner:poly=[(-w/2,-d/2),(w/2,-d/2),(w/2,-d/2+arm),(-w/2+arm,-d/2+arm),(-w/2+arm,d/2),(-w/2,d/2)]
    else:poly=[(.90*math.cos(i*math.tau/8+math.pi/8),.90*math.sin(i*math.tau/8+math.pi/8)) for i in range(8)]
    masonry_ring(poly,h,is_brick)
    # Soil sits below coping. L-shaped surface triangulated to avoid concave fan artefacts.
    soil=mesh('Recessed soil',[(x,y,h-.07) for x,y in poly],[(0,1,2,3),(0,3,4,5)] if is_corner else [tuple(range(len(poly)))],[4]*2)
    if idx<2 or idx==4:centres=[(-w/2+.33+i*(w-.66)/(max(2,round(w/.38))-1),0) for i in range(max(2,round(w/.38)))]
    elif is_corner:
        joint=(-w/2+arm/2,-d/2+arm/2)
        centres=planting_line(joint,(w/2-.34,joint[1]))+planting_line(joint,(joint[0],d/2-.34))[1:]
    else:centres=[(0,0)]+[(.40*math.cos(i*math.tau/6),.40*math.sin(i*math.tau/6)) for i in range(6)]
    plants(centres,h-.07,.95 if idx in (0,6) else (.48 if idx==2 else .25),flowers,is_brick)
    objects=[o for o in bpy.context.scene.objects if o not in before]
    masonry=[o for o in objects if o.name not in [soil.name] and not o.name.startswith('Planting')]
    bpy.ops.object.select_all(action='DESELECT')
    for o in masonry:o.select_set(True)
    bpy.context.view_layer.objects.active=masonry[0];bpy.ops.object.join();bpy.context.object.name='Stonework'
    objects=[o for o in bpy.context.scene.objects if o not in before]
    bpy.context.scene.cursor.location=(0,0,0)
    for o in objects:
        bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o;bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
        # Remove unused palette slots so exports retain only required surfaces.
        bpy.ops.object.material_slot_remove_unused()
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects:o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(EXPORT/(name+'.glb')),export_format='GLB',use_selection=True,export_yup=True)
    tris=0
    for o in objects:o.data.calc_loop_triangles();tris+=len(o.data.loop_triangles)
    stats[name]={'stone_height_m':h+.09,'triangles':tris,'mesh_objects':len(objects),'purpose':['wall-side hedge','low window flowers','L-shaped corner','small junction','reference brick foliage border','warm brick L-shaped low foliage','pale stone L-shaped tall hedge'][idx]}
    stats[name].update(length_m=w,depth_m=d,arm_width_m=arm if is_corner else None)
    col=bpy.data.collections.new(name);bpy.context.scene.collection.children.link(col)
    col['length_m']=w;col['depth_m']=d
    col['recipe']=str(Path(args.config).resolve())
    if is_corner:col['arm_width_m']=arm
    offset=[(-2.4,3,0),(2.1,3,0),(-2.4,-.6,0),(2.1,-.6,0),(0,-3.5,0),(-2.4,-7,0),(2.1,-7,0)][idx]
    for o in objects:
        for old in list(o.users_collection):old.objects.unlink(o)
        col.objects.link(o);o.location=offset
    all_models.extend(objects)

# Review stage and camera are a separate collection in the editable source.
stage=bpy.data.collections.new('REVIEW_STAGE');bpy.context.scene.collection.children.link(stage)
old=set(bpy.context.scene.objects)
floor=box('Neutral stone presentation ground',(0,0,-.09),(200,200,.15),3)
world=bpy.context.scene.world;world.use_nodes=True;world.node_tree.nodes['Background'].inputs[0].default_value=(.55,.62,.72,1);world.node_tree.nodes['Background'].inputs[1].default_value=.4
for pos,power,size in [((-3,-4,9),1700,7),((4,4,7),1100,5)]:
    bpy.ops.object.light_add(type='AREA',location=pos);o=bpy.context.object;o.data.energy=power;o.data.shape='DISK';o.data.size=size;o.rotation_euler=(-o.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(location=(6,-16,14));cam=bpy.context.object;cam.rotation_euler=(Vector((0,-1.6,.45))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=16.0
sc=bpy.context.scene;sc.camera=cam;sc.unit_settings.system='METRIC';sc.render.engine='CYCLES';sc.cycles.device='CPU';sc.cycles.samples=24
sc.render.resolution_x=1500;sc.render.resolution_y=1200;sc.render.resolution_percentage=100;sc.view_settings.view_transform='AgX'
for o in set(bpy.context.scene.objects)-old:
    for col in list(o.users_collection):col.objects.unlink(o)
    stage.objects.link(o)
sc.render.filepath=str(OUT/'town_planters_review.png')
bpy.ops.object.select_all(action='DESELECT')
for o in all_models:o.select_set(True)
bpy.context.view_layer.objects.active=all_models[0]
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type=='VIEW_3D':area.spaces.active.region_3d.view_perspective='CAMERA'
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'town_planters.blend'))
(OUT/'mesh_stats.json').write_text(json.dumps(stats,indent=2),encoding='utf8')
if not args.no_render:bpy.ops.render.render(write_still=True)
# Dedicated comparison of the two newly requested L-shaped variants.
for col in bpy.data.collections:
    if col.name[:2].isdigit():col.hide_render=not col.name.startswith(('06_','07_'))
cam.location=(4,-16,9);cam.rotation_euler=(Vector((-.15,-7,.6))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=8.8
sc.render.resolution_x=1500;sc.render.resolution_y=1000
sc.render.filepath=str(OUT/'town_planters_L_variants_review.png')
if not args.no_render:bpy.ops.render.render(write_still=True)
print('TOWN_PLANTERS_COMPLETE',json.dumps(stats))
