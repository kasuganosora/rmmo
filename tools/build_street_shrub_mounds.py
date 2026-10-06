"""Offline freestanding realistic shrub mounds using owned Boxwood scan atlas."""
import bpy,math,random,json,hashlib,struct,ast
from pathlib import Path
from mathutils import Vector
OUT=Path('D:/code/rmmo_runtime/art_sources/street_shrub_mounds');OUT.mkdir(exist_ok=True)
TEX=Path('D:/code/rmmo_runtime/art_sources/town_planters/sources/boxwood_rjepadp2')
source=(Path(__file__).parent/'render_town_planters_boxwood.py').read_text(encoding='utf8')
rects=ast.literal_eval(source.split('rects=')[1].split('\n')[0])
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
sc=bpy.context.scene;sc.unit_settings.system='METRIC'
leaf=bpy.data.materials.new('Scanned boxwood foliage');leaf.use_nodes=True;leaf.use_backface_culling=False;leaf.surface_render_method='DITHERED'
nt=leaf.node_tree;bs=next(n for n in nt.nodes if n.type=='BSDF_PRINCIPLED');bs.inputs['Roughness'].default_value=.75
for path,socket in [(OUT/'boxwood_rgba.png','Base Color'),(TEX/'Boxwood_rjepadp2_4K_Normal.jpg','Normal'),(TEX/'Boxwood_rjepadp2_4K_Roughness.jpg','Roughness')]:
    im=bpy.data.images.load(str(path),check_existing=True);im.pack();t=nt.nodes.new('ShaderNodeTexImage');t.image=im
    if socket=='Base Color':nt.links.new(t.outputs['Color'],bs.inputs[socket]);nt.links.new(t.outputs['Alpha'],bs.inputs['Alpha'])
    else:
        im.colorspace_settings.name='Non-Color'
        if socket=='Normal':
            n=nt.nodes.new('ShaderNodeNormalMap');n.inputs['Strength'].default_value=.55;nt.links.new(t.outputs['Color'],n.inputs['Color']);nt.links.new(n.outputs[0],bs.inputs[socket])
        else:nt.links.new(t.outputs['Color'],bs.inputs[socket])
wood=bpy.data.materials.new('Hidden woody branches');wood.use_nodes=True
wb=next(n for n in wood.node_tree.nodes if n.type=='BSDF_PRINCIPLED');wb.inputs['Base Color'].default_value=(.085,.052,.018,1);wb.inputs['Roughness'].default_value=.94
specs=[dict(id='shrub_round',radius=(.92,.78,.62),cards=2000,seed=707,preview=(-2.7,0,0)),dict(id='shrub_spreading',radius=(1.35,.76,.49),cards=2400,seed=708,preview=(.3,0,0)),dict(id='shrub_tall',radius=(.85,.78,.83),cards=2200,seed=709,preview=(3.1,0,0))]
def meshobj(name,vertices,faces,material):
    me=bpy.data.meshes.new(name);me.from_pydata(vertices,[],faces);me.update();o=bpy.data.objects.new(name,me);sc.collection.objects.link(o);me.materials.append(material);return o
def foliage(spec,rows):
    rng=random.Random(spec['seed']);verts=[];faces=[];uv=[];rx,ry,rz=spec['radius']
    for card in range(spec['cards']):
        az=rng.random()*math.tau;z=rng.uniform(-.85,1);rad=math.sqrt(1-z*z);shell=rng.uniform(.08,.90)**.333
        unit=Vector((math.cos(az)*rad,math.sin(az)*rad,z))
        foot=Vector((unit.x*rx*shell,unit.y*ry*shell,rz+.08+unit.z*rz*shell))
        # Several overlapping lobes, with low leaves hiding the woody root fan.
        foot.z+=.065*math.sin(az*3+spec['seed'])
        if card%3==0:
            foot=Vector((rng.uniform(-.7,.7)*rx,rng.uniform(-.7,.7)*ry,rng.uniform(.025,.40)))
        direction=az+rng.uniform(-2.2,2.2);tilt=rng.uniform(.40,1.45)
        axis=Vector((math.cos(direction)*math.sin(tilt),math.sin(direction)*math.sin(tilt),math.cos(tilt)))
        side=axis.cross(Vector((0,0,1))).normalized();normal=side.cross(axis).normalized()
        roll=rng.uniform(-1.2,1.2);side=side*math.cos(roll)+normal*math.sin(roll);normal=side.cross(axis).normalized()
        length=rng.uniform(.32,.50);x0,y0,x1,y1=rng.choice(rects);width=length*(x1-x0)/(y1-y0);start=len(verts)
        for row in range(rows+1):
            t=row/rows
            for col in range(3):
                s=col/2;co=foot+axis*(t*length)+side*((s-.5)*width)+normal*(math.sin(t*math.pi)*length*.035+abs(s-.5)*width*.10)
                verts.append(co);uv.append((x0+(x1-x0)*s,1-y1+(y1-y0)*t))
        for row in range(rows):
            for col in range(2):
                q=start+row*3+col;faces.append((q,q+1,q+4,q+3))
    o=meshobj(spec['id']+'_foliage',verts,faces,leaf);layer=o.data.uv_layers.new(name='BoxwoodAtlas')
    for loop in o.data.loops:layer.data[loop.index].uv=uv[loop.vertex_index]
    for p in o.data.polygons:p.use_smooth=True
    o['rmmo_collision']='none';o['rmmo_wind']={'profile':'foliage','mesh':'*','amplitude':.035,'stiffness':.72,'anchor':'bottom','shelter':True};o['rmmo_leaf_backlight']=[.18]
    o.location=spec['preview'];return o
def stems(spec):
    rng=random.Random(spec['seed']);v=[];f=[]
    for i in range(18):
        a=Vector((rng.uniform(-.13,.13),rng.uniform(-.13,.13),0));az=i*math.tau/18;b=Vector((math.cos(az)*spec['radius'][0]*.65,math.sin(az)*spec['radius'][1]*.65,spec['radius'][2]*rng.uniform(.65,1.3)))
        axis=(b-a).normalized();u=axis.cross(Vector((0,1,0))).normalized();n=u.cross(axis);base=len(v)
        for center,radius in [(a,.012),(b,.003)]:
            for k in range(5):v.append(center+radius*(u*math.cos(k*math.tau/5)+n*math.sin(k*math.tau/5)))
        for k in range(5):f.append((base+k,base+(k+1)%5,base+5+(k+1)%5,base+5+k))
    o=meshobj(spec['id']+'_stems',v,f,wood);o.location=spec['preview'];o['rmmo_collision']='none';return o
assets=[dict(spec=s,leaf=foliage(s,4),stem=stems(s)) for s in specs]
ground=bpy.data.materials.new('Review soil');ground.diffuse_color=(.23,.245,.20,1)
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.015));bpy.context.object.data.materials.append(ground)
sc.world.use_nodes=True;bg=next(n for n in sc.world.node_tree.nodes if n.type=='BACKGROUND');bg.inputs[0].default_value=(.7,.8,1,1);bg.inputs[1].default_value=.5
bpy.ops.object.light_add(type='AREA',location=(-3,-4,7));light=bpy.context.object;light.data.energy=1700;light.data.size=4;light.rotation_euler=(Vector((0,0,.7))-light.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add();cam=bpy.context.object;cam.data.type='ORTHO';sc.camera=cam
sc.render.engine='CYCLES';sc.cycles.samples=24;sc.cycles.use_denoising=True;sc.cycles.transparent_max_bounces=48
sc.render.resolution_x=1500;sc.render.resolution_y=900;sc.render.resolution_percentage=100;sc.view_settings.view_transform='AgX'
def view(loc,target,scale):cam.location=loc;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=scale
def render(name):sc.render.filepath=str(OUT/(name+'.png'));bpy.ops.render.render(write_still=True)
view((5,-12,6),(0,0,.8),9.2);bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'shrub_master.blend'),compress=True);render('master_overview')
view((-1.3,-3,2),(-2.7,0,.8),1.9);render('master_close')
for a in assets:bpy.data.objects.remove(a['leaf'],do_unlink=True);a['leaf']=foliage(a['spec'],2)
render('optimized_close');view((5,-12,6),(0,0,.8),9.2);render('optimized_overview')
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'shrub_optimized.blend'),compress=True)
report=[]
for a in assets:
    s=a['spec'];bpy.ops.object.select_all(action='DESELECT')
    for o in [a['leaf'],a['stem']]:o.location=(0,0,0);o.select_set(True)
    path=OUT/(s['id']+'.glb');bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_extras=True)
    raw=path.read_bytes();length=struct.unpack_from('<I',raw,12)[0];g=json.loads(raw[20:20+length]);tail=raw[20+length:]
    for m in g['materials']:
        if 'boxwood' in m.get('name','').lower():m['alphaMode']='MASK';m['alphaCutoff']=.45;m['doubleSided']=True
    encoded=json.dumps(g,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4);path.write_bytes(struct.pack('<III',0x46546c67,2,20+len(encoded)+len(tail))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+tail)
    report.append(dict(**s,master_triangles=s['cards']*16+180,game_triangles=s['cards']*8+180,sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
    for o in [a['leaf'],a['stem']]:o.location=s['preview']
(OUT/'manifest.json').write_text(json.dumps(dict(status='offline review',assets=report,source='owned Quixel Boxwood rjepadp2',scope='freestanding shrubs, no planters or walls'),indent=2))
print('SHRUB_MOUNDS_COMPLETE',flush=True)
