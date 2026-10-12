"""Blender material-first authoring for continuous automatic road edges.
Owned scanned stone + baked mortar relief. No per-stone game objects.
"""
import bpy,bmesh,math,json,hashlib
from pathlib import Path
from mathutils import Vector
root=Path('D:/code/rmmo_runtime');out=root/'art_sources/automatic_kerb';out.mkdir(parents=True,exist_ok=True)
dest=out/'material';dest.mkdir(exist_ok=True)
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
sc=bpy.context.scene;sc.unit_settings.system='METRIC';sc.render.engine='CYCLES';sc.cycles.samples=16
src=(Path(__file__).parent/'build_street_edge_stones.py').read_text(encoding='utf8')
exec(src[src.index('def surface('):src.index('stone=surface(')])
mat=surface('Scanned limestone with continuous joint strip','terrain/beach_cliff');nt=mat.node_tree;bs=next(n for n in nt.nodes if n.type=='BSDF_PRINCIPLED');output=next(n for n in nt.nodes if n.type=='OUTPUT_MATERIAL')
original_color=bs.inputs['Base Color'].links[0].from_socket
original_normal=bs.inputs['Normal'].links[0].from_socket
uv=nt.nodes.new('ShaderNodeTexCoord');sep=nt.nodes.new('ShaderNodeSeparateXYZ');nt.links.new(uv.outputs['UV'],sep.inputs[0])
def mathnode(op,a,b):
 n=nt.nodes.new('ShaderNodeMath');n.operation=op
 for value,socket in [(a,n.inputs[0]),(b,n.inputs[1])]:
  if isinstance(value,(int,float)):socket.default_value=value
  else:nt.links.new(value,socket)
 return n.outputs[0]
noise=nt.nodes.new('ShaderNodeTexNoise');noise.inputs['Scale'].default_value=45;nt.links.new(uv.outputs['UV'],noise.inputs['Vector'])
u=mathnode('ADD',mathnode('MULTIPLY',sep.outputs['X'],4),mathnode('MULTIPLY',noise.outputs['Fac'],.02))
fract=mathnode('FRACT',u,0);mask=mathnode('LESS_THAN',fract,.018)
mix=nt.nodes.new('ShaderNodeMixRGB');mix.inputs[2].default_value=(.22,.20,.165,1);nt.links.new(mask,mix.inputs[0]);nt.links.new(original_color,mix.inputs[1]);nt.links.new(mix.outputs[0],bs.inputs['Base Color'])
bump=nt.nodes.new('ShaderNodeBump');bump.inputs['Distance'].default_value=.004;bump.inputs['Strength'].default_value=.65
nt.links.new(mathnode('SUBTRACT',1,mask),bump.inputs['Height']);nt.links.new(original_normal,bump.inputs['Normal']);nt.links.new(bump.outputs[0],bs.inputs['Normal'])
bpy.ops.mesh.primitive_plane_add(size=1.76);plane=bpy.context.object;plane.data.materials.append(mat)
em=nt.nodes.new('ShaderNodeEmission');target=nt.nodes.new('ShaderNodeTexImage');nt.nodes.active=target
sc.render.bake.margin=0
for name,kind,source in [('texture','EMIT',mix.outputs[0]),('roughness','EMIT',None),('normal','NORMAL',None)]:
 image=bpy.data.images.new('Baked '+name,1024,1024,alpha=False);target.image=image
 if name!='texture':image.colorspace_settings.name='Non-Color'
 if kind=='EMIT':
  if source:nt.links.new(source,em.inputs['Color'])
  else:
   for link in list(em.inputs['Color'].links):nt.links.remove(link)
   em.inputs['Color'].default_value=(.86,.86,.86,1)
  nt.links.new(em.outputs[0],output.inputs['Surface'])
 else:nt.links.new(bs.outputs[0],output.inputs['Surface'])
 bpy.ops.object.bake(type=kind);image.filepath_raw=str(dest/(name+'.png'));image.file_format='PNG';image.save()
bpy.data.objects.remove(plane,do_unlink=True)
# Review and exports use exactly the same baked PBR as the game.
runtime=bpy.data.materials.new('Automatic limestone kerb PBR');runtime.use_nodes=True;n=runtime.node_tree;b=next(x for x in n.nodes if x.type=='BSDF_PRINCIPLED')
for file,socket in [('texture.png','Base Color'),('normal.png','Normal'),('roughness.png','Roughness')]:
 t=n.nodes.new('ShaderNodeTexImage');t.image=bpy.data.images.load(str(dest/file));t.image.pack()
 if socket!='Base Color':t.image.colorspace_settings.name='Non-Color'
 if socket=='Normal':
  normal=n.nodes.new('ShaderNodeNormalMap');n.links.new(t.outputs[0],normal.inputs['Color']);n.links.new(normal.outputs[0],b.inputs[socket])
 else:n.links.new(t.outputs[0],b.inputs[socket])
profile=[[0,-.04],[0,.037],[.018,.055],[.262,.055],[.28,.037],[.28,-.04]]
def sweep(name,path,height=.055):
 vertices=[];uvs=[];faces=[];s=0
 for i,p in enumerate(path):
  tangent=Vector(path[min(i+1,len(path)-1)])-Vector(path[max(0,i-1)])
  tangent.normalize();normal=Vector((-tangent.y,tangent.x));p=Vector(p)
  if i:s+=(p-Vector(path[i-1])).length
  v=0
  for j,(x,z) in enumerate(profile):
   z=z if z<0 else z+height-.055
   if j:v+=math.dist(profile[j],profile[j-1])
   q=p+normal*x;vertices.append((q.x,q.y,z));uvs.append((s/1.76,v/1.76))
  if i:
   for j in range(6):a=(i-1)*6+j;c=(i-1)*6+(j+1)%6;faces.append((a,c,c+6,a+6))
 faces.extend([tuple(reversed(range(6))),tuple(range((len(path)-1)*6,len(path)*6))])
 me=bpy.data.meshes.new(name);me.from_pydata(vertices,[],faces);me.update()
 bm=bmesh.new();bm.from_mesh(me);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(me);bm.free();me.update()
 obj=bpy.data.objects.new(name,me);sc.collection.objects.link(obj);me.materials.append(runtime)
 layer=me.uv_layers.new()
 for loop in me.loops:layer.data[loop.index].uv=uvs[loop.vertex_index]
 for poly in me.polygons:
  if len(poly.vertices)!=6:continue
  axis=max(range(3),key=lambda k:abs(poly.normal[k]))
  for li in poly.loop_indices:
   c=me.vertices[me.loops[li].vertex_index].co;layer.data[li].uv=((c.y,c.z) if axis==0 else (c.x,c.z))
 return obj
def samples(res):
 return [sweep('Low straight',[(i*3/res,0) for i in range(res+1)]),sweep('Raised straight',[(i*3/res,1) for i in range(res+1)],.14),sweep('Outside corner',[(4+math.sin(i*math.pi/2/res),1-math.cos(i*math.pi/2/res)) for i in range(res+1)]),sweep('Inside corner',[(7.4-math.sin(i*math.pi/2/res),1-math.cos(i*math.pi/2/res)) for i in range(res+1)])]
objects=samples(64)
ground=surface('Review ground','terrain/mossy_grass_vcjmej0s');bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.035));bpy.context.object.data.materials.append(ground)
sc.world.color=(.3,.3,.3);bpy.ops.object.light_add(type='AREA',location=(2,-4,6));bpy.context.object.data.energy=1200;bpy.context.object.data.size=4
bpy.ops.object.camera_add(location=(6,-5,5));cam=bpy.context.object;cam.rotation_euler=(Vector((3.6,.5,0))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=9.4;sc.camera=cam
sc.render.resolution_x=1400;sc.render.resolution_y=650;sc.render.resolution_percentage=100;sc.view_settings.view_transform='AgX';sc.cycles.samples=32;sc.cycles.use_denoising=True
bpy.ops.wm.save_as_mainfile(filepath=str(out/'master.blend'));sc.render.filepath=str(out/'master.png');bpy.ops.render.render(write_still=True)
for obj in objects:bpy.data.objects.remove(obj,do_unlink=True)
objects=samples(16)
bpy.ops.wm.save_as_mainfile(filepath=str(out/'optimized.blend'));sc.render.filepath=str(out/'optimized.png');bpy.ops.render.render(write_still=True)
bpy.ops.object.select_all(action='DESELECT')
for obj in objects:obj.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(out/'cross_section_samples.glb'),use_selection=True,export_format='GLB')
source=json.loads((root/'packs/default/assets/materials/terrain/beach_cliff/material.json').read_text(encoding='utf8'))['source']
data={'category':'铺装／道路边缘','usage':'自动道路边界连续截面专用；沿长度方向每1.76米重复，四条灰浆接缝。','source':{'derived_from':source,'process':'Blender Cycles baked mortar relief over owned limestone; not individual stone meshes'},'material':{'name':'自动路缘·浅石灰岩','color':[1,1,1,1],'texture_path':'texture.png','normal_path':'normal.png','roughness_path':'roughness.png','roughness':.86,'metallic':0,'normal_format':'opengl','normal_strength':1,'tile_size':[1.76,1.76]}}
(dest/'material.json').write_text(json.dumps(data,ensure_ascii=False,indent=2),encoding='utf8')
(out/'profile.json').write_text(json.dumps({'width':.28,'height':.055,'buried':.04,'bevel':.018,'profile':profile,'master_samples':64,'game_samples':16,'texture_hashes':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in dest.glob('*.png')}},indent=2),encoding='utf8')
print('AUTOMATIC_KERB_MATERIAL_COMPLETE')
