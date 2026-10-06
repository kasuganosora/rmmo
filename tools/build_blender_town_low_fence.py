"""Reference-led low timber barrier. Review only; no game registration."""
import bpy, math, random, json, argparse, sys
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser();parser.add_argument('--config',default=str(ROOT/'tools/town_low_fence_parameters.json'))
args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
config=json.loads(Path(args.config).read_text(encoding='utf-8-sig'))
OUT=ROOT.parent/'rmmo_runtime/art_sources/town_low_fence';OUT.mkdir(parents=True,exist_ok=True)
(OUT/'review_exports').mkdir(exist_ok=True)
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
random.seed(10528)
wood=bpy.data.materials.new('Fab solid timber - longitudinal grain');wood.use_nodes=True
nt=wood.node_tree;p=nt.nodes.get('Principled BSDF')
path=ROOT.parent/'rmmo_runtime/packs/default/assets/materials/wood/solid_timber'
for filename,socket in [('texture.png','Base Color'),('roughness.png','Roughness'),('normal.png',None)]:
    image=bpy.data.images.load(str(path/filename));image.pack()
    if filename!='texture.png':image.colorspace_settings.name='Non-Color'
    tex=nt.nodes.new('ShaderNodeTexImage');tex.image=image
    if socket=='Base Color':
        tone=nt.nodes.new('ShaderNodeHueSaturation');tone.inputs['Value'].default_value=.72
        nt.links.new(tex.outputs['Color'],tone.inputs['Color']);nt.links.new(tone.outputs[0],p.inputs[socket])
    elif socket:nt.links.new(tex.outputs['Color'],p.inputs[socket])
    else:
        normal=nt.nodes.new('ShaderNodeNormalMap');normal.inputs['Strength'].default_value=.45;nt.links.new(tex.outputs['Color'],normal.inputs['Color']);nt.links.new(normal.outputs[0],p.inputs['Normal'])
iron=bpy.data.materials.new('Dark forged pin');iron.diffuse_color=(.065,.05,.035,1);iron.use_nodes=True
ip=iron.node_tree.nodes.get('Principled BSDF');ip.inputs['Base Color'].default_value=iron.diffuse_color;ip.inputs['Metallic'].default_value=.7;ip.inputs['Roughness'].default_value=.63

def timber(name,verts,faces,vertical=False):
    data=bpy.data.meshes.new(name);data.from_pydata(verts,[],faces);data.update()
    o=bpy.data.objects.new(name,data);bpy.context.collection.objects.link(o);data.materials.append(wood)
    uv=data.uv_layers.new(name='Grain metres');off=random.random()*.8
    for poly in data.polygons:
        for li in poly.loop_indices:
            v=data.vertices[data.loops[li].vertex_index].co
            if vertical:across=v.x if abs(poly.normal.y)>.5 else v.y;along=v.z
            else:across=v.z if abs(poly.normal.y)>.5 else v.y;along=v.x
            uv.data[li].uv=(across/.8+off,along/2.4+.13)
    bpy.context.view_layer.objects.active=o
    bevel=o.modifiers.new('Worn arris','BEVEL');bevel.width=.0035;bevel.segments=1
    bpy.ops.object.modifier_apply(modifier=bevel.name)
    return o

def post(x,y,h):
    r=random.uniform(.040,.047);lean=random.uniform(-.085,.085)
    vs=[(a*r+(z-.40)*lean,b*r,z) for z in [-.12,h] for a,b in [(-1,-1),(1,-1),(1,1),(-1,1)]]
    # Narrow irregular stakes, leaning about the rail joint rather than drifting off it.
    vs=[(a,b,z+(a*.3+random.uniform(-.007,.007) if i>=4 else 0)) for i,(a,b,z) in enumerate(vs)]
    o=timber('Squared rough post',vs,[(3,2,1,0),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],True);o.location=(x,y,0);return o

def rail(a,b,height,end_a=.13,end_b=.13):
    a,b=Vector(a),Vector(b);delta=b-a;length=delta.length
    # Local X along the board, Y across thickness. Rail back touches post front.
    xs=[-end_a]+[length*i/4 for i in range(1,4)]+[length+end_b]
    slope=random.uniform(-.022,.022);board_width=float(config.get('rail_width_m',.33))+random.uniform(-.012,.014)
    lower=[height-board_width+slope*x+random.uniform(-.007,.007) for x in xs]
    upper=[height+slope*x+random.uniform(-.006,.006) for x in xs]
    # The user's 50 cm requirement is the exposed support below the lowest board edge.
    lift=max(0,float(config.get('min_clearance_m',0))-min(lower))
    lower=[z+lift for z in lower];upper=[z+lift for z in upper]
    verts=[]
    for y in [-.102,-.040]:
        verts.extend([(x+(random.uniform(-.012,.012) if i in (0,4) else 0),y,lower[i]) for i,x in enumerate(xs)])
        verts.extend([(x+(random.uniform(-.012,.012) if i in (0,4) else 0),y,upper[i]) for i,x in enumerate(xs)])
    faces=[]
    for i in range(4):faces.extend([(i,i+1,i+6,i+5),(10+i,15+i,16+i,11+i),(i,10+i,11+i,i+1),(5+i,6+i,16+i,15+i)])
    faces.extend([(0,5,15,10),(4,14,19,9)])
    o=timber('Single broad rail',verts,faces);o.location=(*a,0);o.rotation_euler.z=math.atan2(delta.y,delta.x)
    return o

def pin(x,y,z,angle):
    # Dark nail heads attach at actual post/rail crossings; subtle at normal distance.
    bpy.ops.mesh.primitive_cylinder_add(vertices=7,radius=random.uniform(.006,.008),depth=.004,location=(x,y,z))
    o=bpy.context.object;o.name='Forged fixing head';o.data.materials.append(iron)
    o.rotation_euler=(math.pi/2,0,angle);return o

stats={}
for index,spec in enumerate(config['samples']):
    before=set(bpy.context.scene.objects)
    length=float(spec['length_m']);depth=float(spec.get('return_m',0));spacing=float(config['max_post_spacing_m'])
    if not (1<=length<=10 and 0<=depth<=10 and .7<=spacing<=2):raise ValueError('Invalid fence dimensions')
    segments=[((0,0),(length,0))]
    if depth:segments.append(((0,depth),(0,0)))
    placed=set()
    for si,(a,b) in enumerate(segments):
        a,b=Vector(a),Vector(b);delta=b-a;n=max(1,math.ceil(delta.length/spacing));normal=Vector((delta.y,-delta.x)).normalized();angle=math.atan2(delta.y,delta.x)
        rail_top=float(config['rail_top_m'])
        for j in range(n+1):
            point=a.lerp(b,j/n);key=(round(point.x,4),round(point.y,4))
            if key not in placed:post(*point,float(config['post_height_m'])+random.uniform(-.045,.045));placed.add(key)
            for along in ([-.027,.027] if 0<j<n else [random.uniform(-.007,.007)]):
                for z in [rail_top-.065+random.uniform(-.017,.017),rail_top-.235+random.uniform(-.019,.019)]:
                    p2=point+normal*.104+delta.normalized()*(along+random.uniform(-.004,.004));pin(*p2,z,angle)
        for j in range(n):
            # Butt joins are located on posts. Corner boards end against two different post faces.
            ea=(.023 if depth and si==0 else random.uniform(.11,.19)) if j==0 else -.009
            eb=(.023 if depth and si==1 else random.uniform(.11,.19)) if j==n-1 else -.009
            rail(a.lerp(b,j/n),a.lerp(b,(j+1)/n),rail_top+random.uniform(-.022,.022),ea,eb)
    objects=[o for o in bpy.context.scene.objects if o not in before]
    col=bpy.data.collections.new(spec['name']);bpy.context.scene.collection.children.link(col)
    for o in objects:
        for old in list(o.users_collection):old.objects.unlink(o)
        col.objects.link(o)
    # Two runtime-ready groups, wood and pins, while preserving each sample separately.
    joined=[]
    groups=[('Timber',[o for o in objects if o.data.materials[0]==wood]),('Fixings',[o for o in objects if o.data.materials[0]==iron])]
    for label,group in groups:
        bpy.ops.object.select_all(action='DESELECT')
        for o in group:o.select_set(True)
        bpy.context.view_layer.objects.active=group[0];bpy.ops.object.join();o=bpy.context.object;o.name=spec['name']+'_'+label
        bpy.context.scene.cursor.location=(0,0,0);bpy.ops.object.origin_set(type='ORIGIN_CURSOR');joined.append(o)
    bpy.ops.object.select_all(action='DESELECT')
    for o in joined:o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(OUT/'review_exports'/(spec['name']+'.glb')),export_format='GLB',use_selection=True,export_yup=True)
    tris=0
    for o in joined:o.data.calc_loop_triangles();tris+=len(o.data.loop_triangles)
    stats[spec['name']]={'triangles':tris,'posts':len(placed),'length_m':length,'return_m':depth}
    offset=[(-1.8,3,0),(-1.8,.3,0),(-1.8,-2.8,0)][index]
    for o in joined:o.location+=Vector(offset)
    col['length_m']=length;col['return_m']=depth

# Neutral stage lets the rail/post proportions and grain stay easy to inspect.
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.006));floor=bpy.context.object;floor.name='REVIEW ground'
m=bpy.data.materials.new('Warm neutral ground');m.diffuse_color=(.25,.275,.22,1);floor.data.materials.append(m)
scene=bpy.context.scene;scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.6,.68,.8,1);scene.world.node_tree.nodes['Background'].inputs[1].default_value=.5
for pos,power,size in [((-3,-4,7),1300,5),((4,2,5),900,4)]:
    bpy.ops.object.light_add(type='AREA',location=pos);o=bpy.context.object;o.data.energy=power;o.data.size=size;o.rotation_euler=(-o.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(location=(5,-9,7));cam=bpy.context.object;cam.rotation_euler=(Vector((.1,.3,.35))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=7.8;scene.camera=cam
scene.unit_settings.system='METRIC';scene.render.engine='CYCLES';scene.cycles.samples=32;scene.cycles.use_denoising=True
scene.render.resolution_x=1500;scene.render.resolution_y=1100;scene.render.resolution_percentage=100;scene.view_settings.view_transform='AgX'
scene.render.filepath=str(OUT/'town_low_fence_review.png')
bpy.ops.file.pack_all();bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'town_low_fence.blend'))
(OUT/'mesh_stats.json').write_text(json.dumps(stats,indent=2),encoding='utf8')
bpy.ops.render.render(write_still=True)
# Reference-like low eye view on the long straight run.
for col in bpy.data.collections:
    if col.name.startswith(('01_','03_')):col.hide_render=True
cam.location=(3,-5,2.2);cam.rotation_euler=(Vector((0,.3,.4))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=4.7
scene.render.resolution_x=1500;scene.render.resolution_y=800;scene.render.filepath=str(OUT/'town_low_fence_detail.png')
bpy.ops.render.render(write_still=True)
print('LOW_FENCE_COMPLETE',json.dumps(stats))
