"""Curved individual blades, scanned Quixel leaf channels, preserved masters."""
import bpy,sys,math,random,json
from pathlib import Path
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).parent))
import build_town_grass as common
ROOT=Path('D:/code/rmmo_runtime');OUT=ROOT/'assets/reference_grass_clumps';AUTHOR=ROOT/'art_sources/reference_grass_clumps'
OUT.mkdir(parents=True,exist_ok=True);AUTHOR.mkdir(parents=True,exist_ok=True)
common.AUTHOR=AUTHOR
bpy.ops.wm.read_factory_settings(use_empty=True)
mat=common.material(common.SRC/'wild_grass_vlkhcbxia_high','reference_blade')
nt=mat.node_tree;principled=next(n for n in nt.nodes if n.type=='BSDF_PRINCIPLED')
principled.inputs['Specular IOR Level'].default_value=.1
next(n for n in nt.nodes if n.type=='NORMAL_MAP').inputs['Strength'].default_value=.25
source=principled.inputs['Base Color'].links[0].from_socket
attr=nt.nodes.new('ShaderNodeVertexColor');attr.layer_name='BladeTint'
mix=nt.nodes.new('ShaderNodeMixRGB');mix.blend_type='MULTIPLY';mix.inputs[0].default_value=1
nt.links.new(source,mix.inputs[1]);nt.links.new(attr.outputs['Color'],mix.inputs[2]);nt.links.new(mix.outputs[0],principled.inputs['Base Color'])
# Shared 2K scanned PBR. The UV strip follows the clean long leaf, not a plant card.
for n in mat.node_tree.nodes:
 if n.type=='TEX_IMAGE':
  n.image=n.image.copy();n.image.scale(2048,2048);n.image.pack()
def export(objects,path):
 import struct
 bpy.ops.object.select_all(action='DESELECT')
 for o in objects:o.select_set(True)
 bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_extras=True,export_yup=True,export_animations=False,export_cameras=False,export_lights=False,export_vertex_color='NAME',export_vertex_color_name='BladeTint',export_all_vertex_colors=False)
 raw=path.read_bytes();size=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+size]);binary=raw[28+size:]
 for m in doc.get('materials',[]):m['alphaMode']='MASK';m['alphaCutoff']=.45;m['doubleSided']=True
 for n in doc.get('nodes',[]):
  if 'mesh' in n:n.setdefault('extras',{})['rmmo_leaf_backlight']=[.18]*len(doc['meshes'][n['mesh']]['primitives'])
 encoded=json.dumps(doc,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4)
 path.write_bytes(struct.pack('<III',0x46546c67,2,28+len(encoded)+len(binary))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+struct.pack('<II',len(binary),0x004e4942)+binary)

def create(name,blades,segments):
 verts=[];faces=[];uvs=[];tints=[]
 for root,angle,height,bend,width,twist,phase in blades:
  start=len(verts)
  for j in range(segments+1):
   t=j/segments;direction=angle+twist*t;side=Vector((-math.sin(direction),math.cos(direction),0))
   # Upright root, bowed upper leaf, gently drooping tips; no crossed cards.
   p=root+Vector((math.cos(angle)*bend*t**1.15,math.sin(angle)*bend*t**1.15,height*math.sin(t*2.05)))
   w=width*(.42+.85*math.sin(math.pi*t*.85))*(1-t)**.62
   if j==segments:w=.00015
   # Interior UV strip of scanned long leaf; avoid the pale stem section.
   v=.54+t*.41
   for k in range(3):
    q=p+side*((k-1)*w*.5);q.z+=(1-abs(k-1))*w*.16
    verts.append(q);uvs.append((.390+(k-1)*.0015,v))
    shade=(.26+.74*min(1,t/.34))*(.82+.18*phase);tints.append((shade,shade,shade*.94,1))
  for j in range(segments):
   for k in range(2):
    a=start+j*3+k;b=a+3;faces.append((a,a+1,b+1,b))
 mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],faces);mesh.materials.append(mat);mesh.update()
 uv=mesh.uv_layers.new();color=mesh.color_attributes.new(name="BladeTint",type="FLOAT_COLOR",domain="POINT")
 for i,c in enumerate(tints):color.data[i].color=c
 for p in mesh.polygons:
  p.use_smooth=True
  for li in p.loop_indices:uv.data[li].uv=uvs[mesh.loops[li].vertex_index]
 o=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(o)
 if name.endswith('_master'):
  for i in range(len(blades)):
   group=o.vertex_groups.new(name='Leaf_%03d'%i);group.add(list(range(i*(segments+1)*3,(i+1)*(segments+1)*3)),1.0,'REPLACE')
 return o
manifest=[]
for idx,(name,height,count,spread) in enumerate([('arch_A',.48,210,.30),('arch_B',.57,245,.34),('arch_C',.38,180,.32)]):
 rng=random.Random(917+idx);blades=[]
 roots=[Vector((math.cos(a)*r,math.sin(a)*r,0)) for a,r in [(rng.random()*math.tau,rng.random()*spread) for _ in range(11)]]
 for i in range(count):
  ra=rng.random()*math.tau;rr=math.sqrt(rng.random())*spread
  root=Vector((math.cos(ra)*rr,math.sin(ra)*rr,0))
  a=rng.random()*math.tau;h=height*rng.uniform(.32,1);bend=rng.uniform(.20,.42)*(h/height)**.3;w=rng.uniform(.012,.028)
  if i%4==0:h*=.45;bend*=.8
  blades.append((root,a,h,bend,w,rng.uniform(-.5,.5),rng.random()))
 master=create(name+'_master',blades,24);master['rmmo_grass']=True;master['rmmo_collision']='none';export([master],AUTHOR/(name+'_baseline.glb'))
 lods=[create(name+'_LOD'+str(level),blades,segments) for level,segments in enumerate([14,8,4])]
 pts=[v.co for v in lods[0].data.vertices];lo=Vector(tuple(min(v[i] for v in pts) for i in range(3)));hi=Vector(tuple(max(v[i] for v in pts) for i in range(3)))
 bounds=[lo.x-.1,lo.z-.02,-hi.y-.1,hi.x-lo.x+.2,hi.z-lo.z+.15,hi.y-lo.y+.2]
 for level,o in enumerate(lods):
  o['rmmo_grass']=True;o['rmmo_collision']='none';o['rmmo_visibility_range']={'begin':[0.,12.,25.][level],'end':[12.,25.,55.][level],'bounds':bounds}
  if level<2:o['rmmo_wind']={'profile':'foliage','mesh':'*','amplitude':.055,'stiffness':.72,'anchor':'bottom','shelter':True}
 export(lods,OUT/(name+'.glb'))
 manifest.append({'id':name,'kind':'reference_blade','file':str(OUT/(name+'.glb')),'baseline':str(AUTHOR/(name+'_baseline.glb')),'source':'Quixel Wild Grass vlkhcbxia leaf PBR with authored curved geometry','source_triangles':common.count(master),'lod_triangles':[common.count(o) for o in lods],'height_m':hi.z,'width_m':hi.x-lo.x,'lod_ranges':[0,12,25,55]})
 for o in [master]+lods:o.hide_set(True);o.hide_render=True
for idx,row in enumerate(manifest):
 o=bpy.data.objects[row['id']+'_LOD0'];o.hide_set(False);o.hide_render=False;o.location.x=idx*1.4
bpy.ops.wm.save_as_mainfile(filepath=str(AUTHOR/'reference_grass_clumps.blend'))
(OUT/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf8')
print('REFERENCE_GRASS_BUILT',json.dumps(manifest))
