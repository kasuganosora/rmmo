"""Original wheat clumps: metre-scale culms, leaf blades, paired spikelets/awns.
No purchased geometry. Shared small procedural fibre texture, no alpha cards.
"""
import argparse, bpy, hashlib, json, math, random, sys
from pathlib import Path
from mathutils import Vector
import numpy as np

p=argparse.ArgumentParser();p.add_argument('--output',required=True)
out=Path(p.parse_args(sys.argv[sys.argv.index('--')+1:]).output).resolve()
out.mkdir(parents=True,exist_ok=True)
assert not (out/'wheat_ripe.glb').exists(), 'Use a new candidate directory'
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
rng=random.Random(12102026)
noise=np.random.default_rng(19).random((256,256))
x=np.arange(256)[None,:];y=np.arange(256)[:,None]
fibre=np.clip(.84+.055*np.sin(x*.72+np.sin(y*.017))+.06*noise,.0,1.)
pixels=np.ones((256,256,4),dtype=np.float32);pixels[:,:,:3]=fibre[:,:,None]
image=bpy.data.images.new('Wheat fibre 256',width=256,height=256)
image.pixels.foreach_set(pixels.ravel());image.pack()
vertices=[];faces=[];uvs=[];roles=[]
def face(points,uv,role):
    start=len(vertices);vertices.extend(points);uvs.extend(uv);faces.append(tuple(range(start,start+len(points))));roles.append(role)
def tube(a,b,r1,r2,role,sides=6):
    a,b=Vector(a),Vector(b);d=(b-a).normalized();u=d.cross(Vector((0,1,0))).normalized();v=d.cross(u)
    for i in range(sides):
        u0=u*math.cos(i*math.tau/sides)+v*math.sin(i*math.tau/sides)
        u1=u*math.cos((i+1)*math.tau/sides)+v*math.sin((i+1)*math.tau/sides)
        face([a+u0*r1,a+u1*r1,b+u1*r2,b+u0*r2],[(i/sides,0),((i+1)/sides,0),((i+1)/sides,1),(i/sides,1)],role)
    face([b+(u*math.cos(i*math.tau/sides)+v*math.sin(i*math.tau/sides))*r2 for i in range(sides)],[(.5,.5)]*sides,role)
def kernel(center,angle):
    c=Vector(center);d=Vector((math.cos(angle),math.sin(angle),.55));d.normalize()
    a=c-d*.012;b=c+d*.02
    tube(a,c,.001,.008,1,6);tube(c,b,.008,.001,1,6)
    tube(b,b+d*.045+Vector((0,0,.025)),.0007,.00015,1,3)
for stem in range(5):
    phi=stem*2.399;rad=.06*math.sqrt(stem);base=Vector((math.cos(phi)*rad,math.sin(phi)*rad,0))
    height=rng.uniform(.85,1.18);lean=Vector((rng.uniform(-.065,.065),rng.uniform(-.065,.065),0))
    top=base+lean+Vector((0,0,height))
    tube(base,top,.0032,.0018,0,7)
    for leaf in range(3):
        az=phi+leaf*2.4;origin=base+lean*(.25+leaf*.19)+Vector((0,0,height*(.25+leaf*.19)))
        along=Vector((math.cos(az),math.sin(az),0));side=Vector((-along.y,along.x,0))
        length=.22+leaf*.025
        def pt(t,s):
            return origin+along*length*t+Vector((0,0,.13*math.sin(t*math.pi*.85)-.06*t))+side*s*.015*math.sin(math.pi*t)**.65+Vector((0,0,-abs(s)*.004))
        for j in range(8):
            for s in [-1,0]:face([pt(j/8,s),pt((j+1)/8,s),pt((j+1)/8,s+1),pt(j/8,s+1)],[(s*.5+.5,j/8),(s*.5+.5,(j+1)/8),((s+1)*.5+.5,(j+1)/8),((s+1)*.5+.5,j/8)],0)
    tube(top,top+Vector((0,0,.12)),.0018,.0007,1,6)
    for j in range(9):
        for side in [-1,1]:kernel(top+Vector((0,0,j*.012)),phi+(0 if side==1 else math.pi)+(j%2)*.23)
mesh=bpy.data.meshes.new('Wheat clump master');mesh.from_pydata(vertices,[],faces);mesh.update()
layer=mesh.uv_layers.new(name='FibreUV')
for poly in mesh.polygons:
    poly.material_index=roles[poly.index];poly.use_smooth=True
    for li in poly.loop_indices:layer.data[li].uv=uvs[mesh.loops[li].vertex_index]
ob=bpy.data.objects.new('Wheat five culms',mesh);bpy.context.collection.objects.link(ob)
ob['rmmo_auto_lod']=True
mats=[]
for name in ['Culms and leaf blades','Glumes and awns']:
    m=bpy.data.materials.new(name);m.use_nodes=True;m.diffuse_color=(.4,.3,.12,1)
    bs=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED');bs.inputs['Roughness'].default_value=.83
    tex=m.node_tree.nodes.new('ShaderNodeTexImage');tex.image=image
    tint=m.node_tree.nodes.new('ShaderNodeMixRGB');tint.blend_type='MULTIPLY';tint.inputs[0].default_value=1
    # glTF exporter supports image * factor through Principled's default color,
    # so set the factor directly on the socket and use the baked colored image.
    m.node_tree.nodes.remove(tint);m.node_tree.links.new(tex.outputs['Color'],bs.inputs['Base Color'])
    m.use_backface_culling=False;ob.data.materials.append(m);mats.append(m)
manifest=[]
for variant,colors in [('ripe',[(.55,.40,.17),(.64,.46,.21)]),('green',[(.20,.34,.08),(.33,.43,.12)])]:
    for index,m in enumerate(mats):
        colored=bpy.data.images.new('Wheat '+variant+str(index),width=256,height=256)
        texels=pixels.copy();texels[:,:,:3]*=np.array(colors[index]);colored.pixels.foreach_set(texels.ravel());colored.pack()
        next(n for n in m.node_tree.nodes if n.type=='TEX_IMAGE').image=colored
    bpy.ops.object.select_all(action='DESELECT');ob.select_set(True);bpy.context.view_layer.objects.active=ob
    path=out/f'wheat_{variant}.glb'
    bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_yup=True,export_materials='EXPORT',export_extras=True)
    manifest.append({'name':variant,'path':str(path),'sha256':hashlib.sha256(path.read_bytes()).hexdigest(),'bytes':path.stat().st_size})
bpy.ops.wm.save_as_mainfile(filepath=str(out/'wheat_master.blend'))
(out/'source.json').write_text(json.dumps({'units':'metres','source':'original procedural botanical model; project supplementary design','exports':manifest},indent=2),encoding='utf-8')
print(json.dumps(manifest))
