"""Small local needle clusters; reject whole-branch volume sheets.

Each card groups only nearby similarly facing surfaces in a 4.5 cm source cell.
Alpha and tangent normals are ray-baked from the owned original geometry.
"""
import bpy,json,sys,math
import numpy as np
from pathlib import Path
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).parent))
import export_pine_runtime as shared
from build_blender_parametric_pine import setval
ART,OUT=shared.ART,shared.OUT
CELL=.045;TILE=128
FINE='--fine-clusters' in sys.argv
if FINE:
 CELL=.025;OUT=OUT.with_name(OUT.name+'_fine');OUT.mkdir(parents=True,exist_ok=True);shared.OUT=OUT

def bake_modules(meshes):
 sc=bpy.data.scenes.new('Small cluster baker');bpy.context.window.scene=sc
 sc.render.engine='CYCLES';sc.cycles.samples=4;sc.cycles.use_denoising=False
 prefs=bpy.context.preferences.addons['cycles'].preferences
 try:
  prefs.compute_device_type='OPTIX';prefs.get_devices()
  for d in prefs.devices:d.use=d.type!='CPU'
  sc.cycles.device='GPU'
 except Exception:pass
 sc.render.bake.use_selected_to_active=True;sc.render.bake.cage_extrusion=CELL*4;sc.render.bake.max_ray_distance=CELL*8
 # Ray-miss pixels between needles must stay transparent. Bake padding dilates
 # the thin needles into broad leaves; no padding is allowed in coverage passes.
 sc.render.bake.margin=0;sc.render.bake.use_clear=True
 modules={};stats=[]
 for src in meshes:
  src.update();pts=np.array([v.co[:] for v in src.vertices])
  # Connected needles are indivisible. Triangle-level grouping cuts each curved
  # needle into different cards and produces disconnected flecks at close range.
  parent=list(range(len(src.vertices)))
  def find(i):
   while parent[i]!=i:parent[i]=parent[parent[i]];i=parent[i]
   return i
  leaf_faces=[p for p in src.polygons if p.material_index==1]
  for poly in leaf_faces:
   ids=list(poly.vertices);root=find(ids[0])
   for v in ids[1:]:parent[find(v)]=root
  islands={}
  for poly in leaf_faces:islands.setdefault(find(poly.vertices[0]),[]).append(poly.index)
  groups={}
  for indices in islands.values():
   ids=np.unique(np.concatenate([np.asarray(src.polygons[i].vertices) for i in indices]));points=pts[ids];center=points.mean(0);cloud=points-center
   _,axes=np.linalg.eigh(cloud.T@cloud);axis=int(np.argmax(np.abs(axes[:,0])))
   cell=tuple(np.floor(center/CELL).astype(int));groups.setdefault(cell+(axis,),[]).extend(indices)
  shared.log('WHOLE_NEEDLES_GROUPED',src.name,len(islands),len(groups))
  verts=[];faces=[];uvs=[];face_groups=np.zeros(len(src.polygons),np.float32)
  grid=math.ceil(math.sqrt(len(groups)));size=grid*TILE
  bases=[(np.array((0,1,0.)),np.array((0,0,1.)),np.array((1,0,0.))),(np.array((1,0,0.)),np.array((0,0,-1.)),np.array((0,1,0.))),(np.array((1,0,0.)),np.array((0,1,0.)),np.array((0,0,1.)))]
  for slot,(key,indices) in enumerate(groups.items()):
   face_groups[indices]=slot+1
   r,u,n=bases[key[-1]]
   ids=np.unique(np.concatenate([np.asarray(src.polygons[i].vertices) for i in indices]));points=pts[ids]
   if FINE:
    cloud=points-points.mean(0);_,axes=np.linalg.eigh(cloud.T@cloud)
    fitted=axes[:,0]
    if fitted@n<0:fitted=-fitted
    n=fitted;r=axes[:,2];u=np.cross(n,r)
   rx=points@r;uy=points@u;nz=points@n
   cx=(rx.min()+rx.max())*.5;cy=(uy.min()+uy.max())*.5;cz=np.median(nz)
   w=max(.001,np.ptp(rx))*.53;h=max(.001,np.ptp(uy))*.53;c=r*cx+u*cy+n*cz
   start=len(verts)
   for x,y in [(-1,-1),(1,-1),(1,1),(-1,1)]:verts.append(tuple(c+r*x*w+u*y*h))
   faces.append(tuple(range(start,start+4)));col=slot%grid;row=slot//grid;pad=4/TILE
   uvs.extend([((col+x)/grid,(row+y)/grid) for x,y in [(pad,pad),(1-pad,pad),(1-pad,1-pad),(pad,1-pad)]])
  mesh=bpy.data.meshes.new(src.name+'_small_clusters');mesh.from_pydata(verts,[],faces);mesh.uv_layers.new(name='UVMap').data.foreach_set('uv',np.asarray(uvs).ravel());mesh.update()
  source=bpy.data.objects.new('Source needles',shared.mesh_subset(src,leaf_faces,src.name+'_isolated_bake'));sc.collection.objects.link(source)
  source_material_ids=np.ones(len(source.data.polygons),dtype=np.int32)
  local_groups=face_groups[np.array([p.index for p in leaf_faces],dtype=np.int32)]
  vertex_groups=np.zeros(len(source.data.vertices),dtype=np.int32)
  for poly,gid in zip(source.data.polygons,local_groups):vertex_groups[list(poly.vertices)]=int(gid)
  original_co=np.array([v.co[:] for v in source.data.vertices],dtype=np.float32)
  positions=source.data.attributes.new('OriginalNeedlePosition','FLOAT_VECTOR','POINT');positions.data.foreach_set('vector',original_co.ravel())
  # Explode clusters into isolated baking cells. Each ray sees only its own
  # complete needles, so masking never cuts a needle around an unrelated hit.
  offsets=np.zeros((len(groups)+1,3),dtype=np.float32)
  for slot in range(len(groups)):offsets[slot+1]=((slot%64)*2.,(slot//64)*2.,0.)
  source.data.vertices.foreach_set('co',(original_co+offsets[vertex_groups]).ravel())
  mesh.vertices.foreach_set('co',(np.asarray(verts)+np.repeat(offsets[1:],4,axis=0)).ravel());mesh.update()
  source.data.materials.clear()
  for mat in src.materials:
   m=mat.copy();nt=m.node_tree;p=shared.principled(m);out=next(n for n in nt.nodes if n.type=='OUTPUT_MATERIAL');emit=nt.nodes.new('ShaderNodeEmission');emit.name='BAKE_EMISSION'
   if p.inputs['Base Color'].is_linked:nt.links.new(p.inputs['Base Color'].links[0].from_socket,emit.inputs['Color'])
   else:emit.inputs['Color'].default_value=p.inputs['Base Color'].default_value
   position=nt.nodes.new('ShaderNodeAttribute');position.attribute_name='OriginalNeedlePosition'
   for coord in [n for n in nt.nodes if n.type=='TEX_COORD']:
    for link in list(coord.outputs['Object'].links):nt.links.new(position.outputs['Vector'],link.to_socket)
   nt.links.new(emit.outputs[0],out.inputs['Surface']);source.data.materials.append(m)
  source.data.polygons.foreach_set('material_index',source_material_ids)
  group_attr=source.data.attributes.new('NeedleClusterID','FLOAT','FACE');group_attr.data.foreach_set('value',local_groups)
  source.data.update()
  target=bpy.data.objects.new('Target clustered cards',mesh);sc.collection.objects.link(target)
  mat=bpy.data.materials.new(src.name+'_needle_volume');mat.use_nodes=True;mesh.materials.append(mat)
  nt=mat.node_tree;p=shared.principled(mat);targetnode=nt.nodes.new('ShaderNodeTexImage')
  imgs={}
  if '--reuse-baked' in sys.argv:
   for kind in ['color','normal']:
    img=bpy.data.images.load(str(OUT/(src.name+'_cluster_'+kind+'.png')),check_existing=False)
    if kind=='normal':img.colorspace_settings.name='Non-Color'
    assert tuple(img.size)==(size,size),(src.name,tuple(img.size),size)
    imgs[kind]=img
  else:
   for kind in ['color','mask','group','normal']:
    img=bpy.data.images.new(src.name+'_cluster_'+kind,width=size,height=size,alpha=True,float_buffer=kind=='group')
    if kind in ['mask','group','normal']:img.colorspace_settings.name='Non-Color'
    targetnode.image=img;nt.nodes.active=targetnode
    if kind=='mask':
     for m in source.data.materials:
      e=m.node_tree.nodes['BAKE_EMISSION']
      for link in list(e.inputs['Color'].links):m.node_tree.links.remove(link)
      e.inputs['Color'].default_value=(1,1,1,1)
    if kind=='group':
     for m in source.data.materials:
      attr=m.node_tree.nodes.new('ShaderNodeAttribute');attr.attribute_name='NeedleClusterID'
      div=m.node_tree.nodes.new('ShaderNodeMath');div.operation='DIVIDE';div.inputs[1].default_value=8192.
      m.node_tree.links.new(attr.outputs['Fac'],div.inputs[0]);m.node_tree.links.new(div.outputs[0],m.node_tree.nodes['BAKE_EMISSION'].inputs['Color'])
    if kind=='normal':
     for m in source.data.materials:
      out=next(n for n in m.node_tree.nodes if n.type=='OUTPUT_MATERIAL');m.node_tree.links.new(shared.principled(m).outputs[0],out.inputs['Surface'])
    bpy.ops.object.select_all(action='DESELECT');source.select_set(True);target.select_set(True);bpy.context.view_layer.objects.active=target
    bpy.ops.object.bake(type='NORMAL' if kind=='normal' else 'EMIT')
    imgs[kind]=img;shared.log('CLUSTER_BAKED',src.name,kind,len(groups),size)
   color=np.empty(size*size*4,np.float32);imgs['color'].pixels.foreach_get(color);color=color.reshape(-1,4)
   mask=np.empty(size*size*4,np.float32);imgs['mask'].pixels.foreach_get(mask);color[:,3]=mask.reshape(-1,4)[:,0]
   # Reject ray hits from other clusters. Without this ownership mask each card
   # captures nearby layers again, filling the air gaps and creating blobs.
   labels=np.empty(size*size*4,np.float32);imgs['group'].pixels.foreach_get(labels)
   yy,xx=np.indices((size,size));expected=(yy//TILE)*grid+(xx//TILE)+1
   owned=np.abs(labels.reshape(size,size,4)[:,:,0]*8192.-expected)<.1
   color[:,3]*=owned.ravel()
   imgs['color'].pixels.foreach_set(color.ravel())
  for kind in ['color','normal']:
   img=imgs[kind];img.filepath_raw=str(OUT/(src.name+'_cluster_'+kind+'.png'));img.file_format='PNG';img.save();img.pack()
  mesh.vertices.foreach_set('co',np.asarray(verts).ravel());mesh.update()
  nt.nodes.remove(targetnode);t=shared.image_node(nt,imgs['color']);nt.links.new(t.outputs['Color'],p.inputs['Base Color']);nt.links.new(t.outputs['Alpha'],p.inputs['Alpha'])
  t=shared.image_node(nt,imgs['normal']);normal=nt.nodes.new('ShaderNodeNormalMap');normal.inputs['Strength'].default_value=1.;nt.links.new(t.outputs['Color'],normal.inputs['Color']);nt.links.new(normal.outputs[0],p.inputs['Normal'])
  p.inputs['Roughness'].default_value=.57;p.inputs['Specular IOR Level'].default_value=.27;mat.surface_render_method='DITHERED';mat.use_backface_culling=False
  # Keep the connecting woody twigs in 3D. Baking them away removes the visible
  # skeleton between needle tufts even when the leaf mask is otherwise correct.
  woody=shared.mesh_subset(src,[p for p in src.polygons if p.material_index==0],src.name+'_woody')
  wood=bpy.data.objects.new('Woody twigs',woody);sc.collection.objects.link(wood)
  bpy.ops.object.select_all(action='DESELECT');wood.select_set(True);bpy.context.view_layer.objects.active=wood
  dec=wood.modifiers.new('Small woody twig simplification','DECIMATE');dec.ratio=.03
  bpy.ops.object.modifier_apply(modifier=dec.name)
  while len(wood.data.materials)>1:wood.data.materials.pop(index=len(wood.data.materials)-1)
  woody_triangles=sum(len(p.vertices)-2 for p in wood.data.polygons)
  target.select_set(True);bpy.context.view_layer.objects.active=target;bpy.ops.object.join();mesh=target.data
  modules[src.name]=mesh;stats.append({'module':src.name,'cards':len(groups),'triangles':len(groups)*2+woody_triangles,'woody_triangles':woody_triangles,'atlas':size,'source_cell_m':CELL})
  bpy.data.objects.remove(source,do_unlink=True);bpy.data.objects.remove(target,do_unlink=True)
 (OUT/'cluster_bake.json').write_text(json.dumps(stats,indent=2),encoding='utf-8')
 bpy.data.scenes.remove(sc);return modules

def main():
 bpy.ops.wm.open_mainfile(filepath=str(ART/'baltic_pine_dense_v3.blend'))
 sc=bpy.data.scenes['Scene'];bpy.context.window.scene=sc;tree=bpy.data.objects['BALTIC PINE | editable parameters'];presets=bpy.data.scenes['PRESETS | compact - mature - windswept']
 records=[];trunks={}
 for index,o in enumerate(sorted([o for o in presets.objects if o.asset_data],key=lambda o:o.name)):
  for s in tree.modifiers[0].node_group.interface.items_tree:
   if s.item_type=='SOCKET' and s.in_out=='INPUT':setval(tree,s.name,o.modifiers[0].get(s.identifier,s.default_value))
  setval(tree,'Wind (m)',0.);bpy.context.view_layer.update();dg=bpy.context.evaluated_depsgraph_get()
  inst=[(i.object.original.data.name,i.matrix_world.copy()) for i in dg.object_instances if i.is_instance]
  key=['pine_dense_compact','pine_dense_mature','pine_dense_windswept'][index];label=['写实密冠松树·小型','写实密冠松树·成熟','写实密冠松树·倾斜'][index]
  trunks[key]=bpy.data.meshes.new_from_object(tree.evaluated_get(dg),depsgraph=dg);records.append((key,label,inst))
 meshes=[bpy.data.meshes[k] for k in sorted(set(n for _,_,ins in records for n,_ in ins))]
 modules=bake_modules(meshes);shared.export_presets(modules,records,trunks)
 # Editable low-geometry counterpart, keeping the approved high-detail master
 # untouched and using exactly the same native parameter controller.
 for obj in bpy.data.collections['SOURCE_D | conservative optimized modules'].objects:
  obj.data=modules[obj.data.name]
 bpy.context.window.scene=sc
 for s in tree.modifiers[0].node_group.interface.items_tree:
  if s.item_type=='SOCKET' and s.in_out=='INPUT':
   mature=bpy.data.objects['02 Pine | mature'];setval(tree,s.name,mature.modifiers[0].get(s.identifier,s.default_value))
 bpy.ops.wm.save_as_mainfile(filepath=str(ART/('baltic_pine_fine_clusters_runtime.blend' if FINE else 'baltic_pine_small_clusters_runtime.blend')),compress=True)
 shared.log('SMALL_CLUSTER_EXPORT_COMPLETE')
if __name__=='__main__':main()
