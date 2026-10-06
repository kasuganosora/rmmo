"""Portable PBR atlas and three distance meshes; source remains editable."""
import bpy,sys,json,struct,math
import numpy as np
from pathlib import Path
from mathutils import Vector,Matrix
sys.path.insert(0,str(Path(__file__).parent))
from build_oak_game import ART,OUT,REVIEW,setval,triangles
from export_pine_runtime import mesh_subset,principled

def atlas_material(modules):
 size=3072;tile=1024;arrays={k:np.zeros((size,size,4),np.float32) for k in ['color','normal']}
 mapping={}
 for i,m in enumerate(modules):
  mapping[m.name]=i
  for kind in arrays:
   img=bpy.data.images.load(str(OUT/(m.name.replace('_small_clusters','')+'_cluster_'+kind+'.png')),check_existing=False)
   if kind=='normal':img.colorspace_settings.name='Non-Color'
   img.scale(tile,tile);a=np.empty(tile*tile*4,np.float32);img.pixels.foreach_get(a)
   arrays[kind][(i//3)*tile:(i//3+1)*tile,(i%3)*tile:(i%3+1)*tile]=a.reshape(tile,tile,4)
   bpy.data.images.remove(img)
 mat=bpy.data.materials.new('Oak game leaf PBR');mat.use_nodes=True;mat.use_backface_culling=False;mat.surface_render_method='DITHERED';p=principled(mat);p.inputs['Roughness'].default_value=.57;p.inputs['Specular IOR Level'].default_value=.27
 for kind,a in arrays.items():
  img=bpy.data.images.new('Oak atlas '+kind,width=size,height=size,alpha=True)
  if kind=='normal':img.colorspace_settings.name='Non-Color'
  img.pixels.foreach_set(a.ravel());img.filepath_raw=str(OUT/('atlas_'+kind+'.png'));img.file_format='PNG';img.save();img.pack()
  n=mat.node_tree.nodes.new('ShaderNodeTexImage');n.image=img
  if kind=='color':mat.node_tree.links.new(n.outputs['Color'],p.inputs['Base Color']);mat.node_tree.links.new(n.outputs['Alpha'],p.inputs['Alpha'])
  else:
   normal=mat.node_tree.nodes.new('ShaderNodeNormalMap');normal.inputs['Strength'].default_value=.25;mat.node_tree.links.new(n.outputs['Color'],normal.inputs['Color']);mat.node_tree.links.new(normal.outputs[0],p.inputs['Normal'])
 return mat,mapping

def decimate(o,ratio):
 bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o
 d=o.modifiers.new('Distance wood simplification','DECIMATE');d.ratio=ratio;bpy.ops.object.modifier_apply(modifier=d.name)

def main():
 source_blend=ART/('street_oak_thick_trunk.blend' if '--thick-trunk' in sys.argv else 'street_oak_game_reviewed.blend')
 if '--reduced-wood' in sys.argv:source_blend=ART/'street_oak_thick_reduced.blend'
 bpy.ops.wm.open_mainfile(filepath=str(source_blend))
 source=bpy.data.scenes['Scene'];bpy.context.window.scene=source;tree=bpy.data.objects['STREET OAK | editable parameters'];setval(tree,'Optimized',True);setval(tree,'Wind (m)',0.)
 bpy.context.view_layer.update();dg=bpy.context.evaluated_depsgraph_get()
 instances=[(i.object.original.data,i.matrix_world.copy()) for i in dg.object_instances if i.is_instance]
 trunkmesh=bpy.data.meshes.new_from_object(tree.evaluated_get(dg),depsgraph=dg)
 modules=list({m.name:m for m,_ in instances}.values());leaf,slots=atlas_material(modules)
 scene=bpy.data.scenes.new('RUNTIME | wide crown oak');bpy.context.window.scene=scene
 bark=next(m for m in trunkmesh.materials if 'bark' in m.name.lower())
 bark=bark.copy();bark.name='Oak_Bark_PBR'
 trunkmesh.materials.clear();trunkmesh.materials.append(bark)
 trunk=bpy.data.objects.new('Oak_Trunk',trunkmesh);scene.collection.objects.link(trunk);trunk['rmmo_collision']='block'
 decimate(trunk,.22)
 objects=[trunk];counts=[]
 for level,stride,enlarge in [(0,1,1.),(1,2,1.27),(2,6,2.05)]:
  verts=[];faces=[];uv=[];mi=[];serial=0
  for mesh,tf in instances:
   slot=slots[mesh.name];leafslot=next(i for i,m in enumerate(mesh.materials) if 'needle_volume' in m.name)
   offset=len(verts);verts.extend([tuple(tf@v.co) for v in mesh.vertices])
   for p in mesh.polygons:
    isleaf=p.material_index==leafslot
    if not isleaf and level>0:continue
    if isleaf:
     serial+=1
     if (serial*37+11)%stride:continue
    if isleaf and enlarge!=1.:
     center=sum((Vector(verts[offset+i]) for i in p.vertices),Vector())/len(p.vertices)
     for i in p.vertices:verts[offset+i]=tuple(center+(Vector(verts[offset+i])-center)*enlarge)
    faces.append(tuple(offset+i for i in p.vertices));mi.append(1 if isleaf else 0)
    for loop in p.loop_indices:
     u,v=mesh.uv_layers[0].data[loop].uv
     uv.append(((slot%3+u)/3,(slot//3+v)/3) if isleaf else (u,v))
  m=bpy.data.meshes.new('Oak canopy LOD'+str(level));m.from_pydata(verts,[],faces);m.uv_layers.new(name='UVMap').data.foreach_set('uv',np.asarray(uv).ravel());m.materials.append(bark);m.materials.append(leaf);m.polygons.foreach_set('material_index',mi);m.polygons.foreach_set('use_smooth',np.ones(len(mi),bool));m.update()
  o=bpy.data.objects.new('Oak_Canopy_LOD'+str(level),m);scene.collection.objects.link(o);o['rmmo_collision']='none';objects.append(o);counts.append(triangles(m)+triangles(trunk.data))
  if level<2:o['rmmo_wind']={'profile':'foliage','mesh':'*','amplitude':.045,'stiffness':.9,'anchor':'bottom','shelter':True}
 points=[v.co for v in objects[1].data.vertices];lo=Vector(tuple(min(v[i] for v in points) for i in range(3)));hi=Vector(tuple(max(v[i] for v in points) for i in range(3)))
 bounds=[lo.x-.2,0.,-hi.y-.2,hi.x-lo.x+.4,hi.z+.3,hi.y-lo.y+.4]
 for level,o in enumerate(objects[1:]):o['rmmo_visibility_range']={'begin':[0.,25.,65.][level],'end':[25.,65.,180.][level],'bounds':bounds}
 bpy.ops.object.select_all(action='DESELECT')
 for o in objects:o.select_set(True)
 file=OUT/'oak_riverside.glb';bpy.ops.export_scene.gltf(filepath=str(file),export_format='GLB',use_selection=True,export_extras=True,export_yup=True,export_animations=False,export_cameras=False,export_lights=False)
 raw=file.read_bytes();size=struct.unpack_from('<I',raw,12)[0];doc=json.loads(raw[20:20+size]);binary=raw[28+size:]
 leafids=[]
 for i,mat in enumerate(doc.get('materials',[])):
  if mat.get('name')==leaf.name:mat['alphaMode']='MASK';mat['alphaCutoff']=.4;mat['doubleSided']=True;leafids.append(i)
 for n in doc['nodes']:
  if 'mesh' in n:n.setdefault('extras',{})['rmmo_leaf_backlight']=[.14 if p.get('material') in leafids else 0. for p in doc['meshes'][n['mesh']]['primitives']]
 encoded=json.dumps(doc,separators=(',',':')).encode();encoded+=b' '*((-len(encoded))%4)
 file.write_bytes(struct.pack('<III',0x46546c67,2,28+len(encoded)+len(binary))+struct.pack('<II',len(encoded),0x4e4f534a)+encoded+struct.pack('<II',len(binary),0x004e4942)+binary)
 report={'id':'oak_riverside','label':'写实阔叶橡树·宽冠河岸','file':str(file),'lod_triangles':counts,'lod_ranges':[0,25,65,180],'trunk_triangles':triangles(trunk.data),'stored_triangles':sum(triangles(o.data) for o in objects),'height':hi.z,'materials':2,'source_blend':str(ART/'street_oak_game_reviewed.blend'),'status':'pending review'}
 report['source_blend']=str(source_blend)
 (OUT/'manifest.json').write_text(json.dumps([report],ensure_ascii=False,indent=2),encoding='utf-8')
 for o in objects[2:]:o.hide_render=True;o.hide_set(True)
 bpy.ops.wm.save_as_mainfile(filepath=str(ART/'street_oak_runtime_lods.blend'),compress=True)
 print('OAK_RUNTIME_EXPORTED',report,flush=True)
if __name__=='__main__':main()
