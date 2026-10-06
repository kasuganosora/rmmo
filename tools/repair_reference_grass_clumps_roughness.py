"""Repair Quixel R-only roughness links in existing Blender masters, preserving geometry."""
import bpy,json,struct,hashlib,shutil
from pathlib import Path
ROOT=Path('D:/code/rmmo_runtime')
def export(objects,path,colored):
 bpy.ops.object.select_all(action='DESELECT');states=[]
 for o in objects:
  states.append((o,o.location.copy(),o.hide_get(),o.hide_render));o.hide_set(False);o.hide_render=False;o.location=(0,0,0);o.select_set(True)
 opts={'export_vertex_color':'NAME','export_vertex_color_name':'BladeTint','export_all_vertex_colors':False} if colored else {}
 bpy.ops.export_scene.gltf(filepath=str(path),export_format='GLB',use_selection=True,export_extras=True,export_yup=True,export_animations=False,export_cameras=False,export_lights=False,**opts)
 raw=path.read_bytes();size=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+size]);binary=raw[28+size:]
 for m in doc.get('materials',[]):m['alphaMode']='MASK';m['alphaCutoff']=.45;m['doubleSided']=True
 for n in doc.get('nodes',[]):
  if 'mesh' in n:n.setdefault('extras',{})['rmmo_leaf_backlight']=[.18]*len(doc['meshes'][n['mesh']]['primitives'])
 encoded=json.dumps(doc,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4)
 path.write_bytes(struct.pack('<III',0x46546c67,2,28+len(encoded)+len(binary))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+struct.pack('<II',len(binary),0x004e4942)+binary)
 for o,loc,hidden,render in states:o.location=loc;o.hide_set(hidden);o.hide_render=render

def signature():
 h=hashlib.sha256()
 for o in sorted(bpy.data.objects,key=lambda o:o.name):
  if o.type!='MESH':continue
  h.update(o.name.encode())
  for v in o.data.vertices:h.update(struct.pack('<3f',*v.co))
  for p in o.data.polygons:h.update(struct.pack('<'+'I'*len(p.vertices),*p.vertices))
 return h.hexdigest()
report=[]
for family,blend in [('reference_grass_clumps',ROOT/'art_sources/reference_grass_clumps/reference_grass_clumps.blend'),('town_grass',ROOT/'art_sources/bridge_street_kit/town_grass/town_grass_masters.blend')]:
 backup=blend.with_name(blend.stem+'_before_roughness_fix.blend')
 if not backup.exists():shutil.copy2(blend,backup)
 bpy.ops.wm.open_mainfile(filepath=str(blend));before=signature();fixed=0
 for mat in bpy.data.materials:
  if not mat.use_nodes:continue
  for p in mat.node_tree.nodes:
   if p.type!='BSDF_PRINCIPLED' or not p.inputs['Roughness'].is_linked:continue
   source=p.inputs['Roughness'].links[0].from_node
   if source.type!='TEX_IMAGE':continue
   sep=mat.node_tree.nodes.new('ShaderNodeSeparateColor');sep.mode='RGB';mat.node_tree.links.new(source.outputs['Color'],sep.inputs['Color']);mat.node_tree.links.new(sep.outputs['Red'],p.inputs['Roughness']);fixed+=1
 after=signature();assert before==after
 manifest=json.loads((ROOT/'assets'/family/'manifest.json').read_text(encoding='utf8'))
 for row in manifest:
  for level in range(3):
   obj=bpy.data.objects[row['id']+'_LOD'+str(level)]
   for material in obj.data.materials:
    for node in material.node_tree.nodes:
     if node.type=='TEX_IMAGE' and max(node.image.size)>2048:
      im=node.image.copy();im.scale(2048,2048);folder=blend.parent/'runtime_2k';folder.mkdir(exist_ok=True);im.filepath_raw=str(folder/(im.name.replace('/','_')+'.png'));im.file_format='PNG';im.save();im.pack();node.image=im
  export([bpy.data.objects[row['id']+'_master']],Path(row['baseline']),family=='reference_grass_clumps')
  export([bpy.data.objects[row['id']+'_LOD'+str(i)] for i in range(3)],Path(row['file']),family=='reference_grass_clumps')
 bpy.ops.wm.save_as_mainfile(filepath=str(blend))
 report.append({'family':family,'materials_fixed':fixed,'geometry_before':before,'geometry_after':after,'count':len(manifest),'blend':str(blend),'prior_blend':str(backup)})
(ROOT/'review_artifacts/reference_grass_clumps/roughness_repair_run.json').write_text(json.dumps(report,indent=2),encoding='utf8')
print('ROUGHNESS_FIX',json.dumps(report))

