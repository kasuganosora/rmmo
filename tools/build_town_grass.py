"""Preserve scanned grass masters; build rooted, textured game grass with true 3D LODs."""
import bpy,bmesh,json,math,struct
from pathlib import Path
from mathutils import Matrix,Vector
import numpy as np
ROOT=Path('D:/code/rmmo_runtime')
SRC=ROOT/'art_sources/bridge_street_kit/sources/grass'
OUT=ROOT/'assets/town_grass'; OUT.mkdir(parents=True,exist_ok=True)
AUTHOR=ROOT/'art_sources/bridge_street_kit/town_grass';AUTHOR.mkdir(parents=True,exist_ok=True)
REVIEW=ROOT/'review_artifacts/town_grass';REVIEW.mkdir(parents=True,exist_ok=True)

def texture(path):
 im=bpy.data.images.load(str(path),check_existing=True);im.colorspace_settings.name='Non-Color';return im

def material(folder,kind):
 base=texture(next(folder.glob('*4K_BaseColor.jpg')));alpha=texture(next(folder.glob('*4K_Opacity.jpg')))
 a=np.empty(len(base.pixels),dtype=np.float32);base.pixels.foreach_get(a);a=a.reshape(-1,4)
 mask=np.empty(len(alpha.pixels),dtype=np.float32);alpha.pixels.foreach_get(mask)
 # Offline material-channel packing, retaining scanned luminance/veins and opacity.
 a[:,:3]*=np.array([.77,1.04,.65]);a[:,:3]=np.clip(a[:,:3],0,1);a[:,3]=mask.reshape(-1,4)[:,0]
 im=bpy.data.images.new(kind+'_summer_RGBA',width=base.size[0],height=base.size[1],alpha=True)
 im.pixels.foreach_set(a.ravel());im.filepath_raw=str(AUTHOR/(kind+'_summer_RGBA.png'));im.file_format='PNG';im.save();im.pack()
 mat=bpy.data.materials.new(kind+'_scanned_summer');mat.use_nodes=True;mat.surface_render_method='DITHERED';mat.use_backface_culling=False
 nt=mat.node_tree;p=next(n for n in nt.nodes if n.type=='BSDF_PRINCIPLED');p.inputs['Roughness'].default_value=.8;p.inputs['Specular IOR Level'].default_value=.25
 t=nt.nodes.new('ShaderNodeTexImage');t.image=im;nt.links.new(t.outputs['Color'],p.inputs['Base Color']);nt.links.new(t.outputs['Alpha'],p.inputs['Alpha'])
 t=nt.nodes.new('ShaderNodeTexImage');t.image=texture(next(folder.glob('*4K_Normal.jpg')));n=nt.nodes.new('ShaderNodeNormalMap');n.inputs['Strength'].default_value=.65;nt.links.new(t.outputs['Color'],n.inputs['Color']);nt.links.new(n.outputs['Normal'],p.inputs['Normal'])
 t=nt.nodes.new('ShaderNodeTexImage');t.image=texture(next(folder.glob('*4K_Roughness.jpg')))
 # Quixel scalar maps are stored in R; direct Color linking exports empty G.
 separate=nt.nodes.new('ShaderNodeSeparateColor');separate.mode='RGB';nt.links.new(t.outputs['Color'],separate.inputs['Color']);nt.links.new(separate.outputs['Red'],p.inputs['Roughness'])
 return mat

def load(path,mat):
 bpy.ops.object.select_all(action='DESELECT');bpy.ops.import_scene.fbx(filepath=str(path));objects=[o for o in bpy.context.selected_objects if o.type=='MESH']
 for o in objects:o.select_set(True)
 bpy.context.view_layer.objects.active=objects[0];bpy.ops.object.join();o=objects[0]
 o.data.transform(o.matrix_world);o.matrix_world=Matrix.Identity(4)
 bottom=min(v.co.z for v in o.data.vertices)
 for v in o.data.vertices:v.co.z-=bottom
 o.data.materials.clear();o.data.materials.append(mat)
 for p in o.data.polygons:p.material_index=0;p.use_smooth=True
 return o

def count(o):o.data.calc_loop_triangles();return len(o.data.loop_triangles)
def simplify(o,angle):
 bm=bmesh.new();bm.from_mesh(o.data)
 bmesh.ops.dissolve_limit(bm,angle_limit=angle,verts=list(bm.verts),edges=list(bm.edges),delimit={'UV','MATERIAL','NORMAL'},use_dissolve_boundaries=False)
 bm.to_mesh(o.data);bm.free();o.data.update()

def export(objects,path):
 bpy.ops.object.select_all(action='DESELECT')
 for o in objects:o.select_set(True)
 bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_extras=True,export_yup=True,export_animations=False,export_cameras=False,export_lights=False)
 raw=path.read_bytes();size=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+size]);binary=raw[28+size:]
 for mat in doc.get('materials',[]):mat['alphaMode']='MASK';mat['alphaCutoff']=.45;mat['doubleSided']=True
 for n in doc.get('nodes',[]):
  if 'mesh' in n:n.setdefault('extras',{})['rmmo_leaf_backlight']=[.18]*len(doc['meshes'][n['mesh']]['primitives'])
 encoded=json.dumps(doc,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4)
 path.write_bytes(struct.pack('<III',0x46546c67,2,28+len(encoded)+len(binary))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+struct.pack('<II',len(binary),0x004e4942)+binary)

def main():
 bpy.ops.wm.read_factory_settings(use_empty=True);manifest=[]
 for kind,folder in [('short',SRC/'grass_clumps_rbojr_raw'),('wild',SRC/'wild_grass_vlkhcbxia_high')]:
  mat=material(folder,kind)
  for source in sorted(folder.glob('*LOD0.fbx')):
   variant=source.stem.split('_Var')[1][0];name=kind+'_'+variant
   original=load(source,mat);original.name=name+'_master';original['source_fab']='70b6ac17-a842-48d9-81e4-41f80fe160d9' if kind=='short' else '50d9a417-73ed-4132-9421-6be3d4f7432e'
   original_count=count(original)
   export([original],AUTHOR/(name+'_baseline.glb'))
   near=original.copy();near.data=original.data.copy();bpy.context.collection.objects.link(near);near.name=name+'_LOD0';simplify(near,.004)
   if kind=='short':
    bpy.context.view_layer.objects.active=near
    mod=near.modifiers.new('Preserve curved blade silhouette','DECIMATE');mod.ratio=.25;bpy.ops.object.modifier_apply(modifier=mod.name)
   # Runtime textures share one 2K set per family; 4K baseline/master retained.
   game_mat=mat.copy();game_mat.name=kind+'_game_2K'
   for node in game_mat.node_tree.nodes:
    if node.type=='TEX_IMAGE':
     im=node.image.copy();im.scale(2048,2048);im.filepath_raw=str(AUTHOR/(name+'_'+im.name.replace('/','_')+'_2k.png'));im.file_format='PNG';im.save();im.pack();node.image=im
   near.data.materials.clear();near.data.materials.append(game_mat)
   lods=[near]
   for level in [1,2]:
    if kind=='wild':
     obj=load(Path(str(source).replace('LOD0','LOD'+str(level))),game_mat);simplify(obj,.004)
    else:
     obj=near.copy();obj.data=near.data.copy();bpy.context.collection.objects.link(obj)
     bpy.context.view_layer.objects.active=obj
     mod=obj.modifiers.new('Distance mesh simplification','DECIMATE');mod.ratio=.45 if level==1 else .2;bpy.ops.object.modifier_apply(modifier=mod.name)
    obj.name=name+'_LOD'+str(level);lods.append(obj)
   pts=[v.co for v in near.data.vertices];lo=Vector(tuple(min(v[i] for v in pts) for i in range(3)));hi=Vector(tuple(max(v[i] for v in pts) for i in range(3)))
   bounds=[lo.x-.1,lo.z-.02,-hi.y-.1,hi.x-lo.x+.2,hi.z-lo.z+.15,hi.y-lo.y+.2]
   for level,obj in enumerate(lods):
    obj['rmmo_grass']=True;obj['rmmo_collision']='none';obj['rmmo_visibility_range']={'begin':[0.,12.,25.][level],'end':[12.,25.,55.][level],'bounds':bounds}
    if level<2:obj['rmmo_wind']={'profile':'foliage','mesh':'*','amplitude':.045 if kind=='short' else .075,'stiffness':.65,'anchor':'bottom','shelter':True}
   export(lods,OUT/(name+'.glb'))
   manifest.append({'id':name,'kind':kind,'variant':variant,'file':str(OUT/(name+'.glb')),'source':str(source),'baseline':str(AUTHOR/(name+'_baseline.glb')),'source_triangles':original_count,'lod_triangles':[count(o) for o in lods],'height_m':hi.z-lo.z,'lod_ranges':[0,12,25,55]})
   for o in [original]+lods:o.hide_render=True;o.hide_set(True)
 for im in bpy.data.images:
  if im.source=='FILE':im.pack()
 # Opening the authoring file shows the eleven near meshes in a usable gallery.
 for i,row in enumerate(manifest):
  for suffix in ['master','LOD0','LOD1','LOD2']:
   o=bpy.data.objects.get(row['id']+'_'+suffix)
   if o is not None:
    o.location=((i%4)*1.15,(i//4)*1.1,0);o.hide_render=suffix!='LOD0';o.hide_set(suffix!='LOD0')
 bpy.ops.wm.save_as_mainfile(filepath=str(AUTHOR/'town_grass_masters.blend'))
 (OUT/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf8')
 print('GRASS_BUILD',json.dumps(manifest),flush=True)
if __name__=='__main__':main()

