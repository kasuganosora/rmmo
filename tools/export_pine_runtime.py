"""Bake owned high-detail pine modules into layered geometry, then export presets.

Never expands the ~244M triangle authoring tree. Source blend remains unchanged.
"""
import bpy,sys,math,json
import numpy as np
from pathlib import Path
from mathutils import Vector,Matrix
sys.path.insert(0,str(Path(__file__).parent))
from build_blender_parametric_pine import setval
BASE=Path('D:/code/rmmo_runtime')
ART=BASE/'art_sources/bridge_street_kit/baltic_pine_procedural'
OUT=BASE/'assets/baltic_pine_dense_v3';OUT.mkdir(parents=True,exist_ok=True)
BAKE=OUT/'bake_8_layers';BAKE.mkdir(exist_ok=True)
TILE=512;GRID=5;SLICES=8

def log(*x):print(*x,flush=True)
def image_node(nt,img):
 n=nt.nodes.new('ShaderNodeTexImage');n.image=img;return n
def principled(m):return next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
def mesh_subset(src,selected,name):
 # Bulk extraction, retaining original UVs and normals on cut boundaries.
 pts=np.empty(len(src.vertices)*3,dtype=np.float32);src.vertices.foreach_get('co',pts);pts=pts.reshape(-1,3)
 loops=np.empty(len(src.loops),dtype=np.int32);src.loops.foreach_get('vertex_index',loops)
 starts=np.array([p.loop_start for p in selected]);counts=np.array([p.loop_total for p in selected])
 idx=np.concatenate([np.arange(a,a+c) for a,c in zip(starts,counts)])
 old=loops[idx];used,remap=np.unique(old,return_inverse=True)
 m=bpy.data.meshes.new(name);m.vertices.add(len(used));m.vertices.foreach_set('co',pts[used].ravel())
 m.loops.add(len(idx));m.loops.foreach_set('vertex_index',remap)
 m.polygons.add(len(counts));m.polygons.foreach_set('loop_start',np.r_[0,np.cumsum(counts[:-1])]);m.polygons.foreach_set('loop_total',counts)
 m.polygons.foreach_set('material_index',np.array([p.material_index for p in selected],dtype=np.int32))
 m.polygons.foreach_set('use_smooth',np.ones(len(counts),dtype=bool))
 for mat in src.materials:m.materials.append(mat)
 if src.uv_layers:
  uv=np.empty(len(src.loops)*2,dtype=np.float32);src.uv_layers[0].data.foreach_get('uv',uv)
  m.uv_layers.new(name='UVMap').data.foreach_set('uv',uv.reshape(-1,2)[idx].ravel())
 m.update();return m

def bake_modules(source_meshes):
 sc=bpy.data.scenes.new('BAKE | unlit sliced modules');bpy.context.window.scene=sc
 sc.render.engine='CYCLES';sc.cycles.samples=8;sc.cycles.use_denoising=False
 try:
  prefs=bpy.context.preferences.addons['cycles'].preferences;prefs.compute_device_type='OPTIX';prefs.get_devices()
  for d in prefs.devices:d.use=d.type!='CPU'
  sc.cycles.device='GPU'
 except Exception:pass
 sc.render.resolution_x=sc.render.resolution_y=TILE;sc.render.resolution_percentage=100
 sc.render.film_transparent=True;sc.view_settings.view_transform='Standard';sc.view_settings.look='None'
 sc.view_settings.exposure=0;sc.view_settings.gamma=1
 sc.world=bpy.data.worlds.new('Bake black');sc.world.use_nodes=True
 bg=next(n for n in sc.world.node_tree.nodes if n.type=='BACKGROUND');bg.inputs[1].default_value=0
 cam=bpy.data.objects.new('BakeCamera',bpy.data.cameras.new('BakeCamera'));sc.collection.objects.link(cam);sc.camera=cam;cam.data.type='ORTHO'
 # Emission-only base color avoids baking light/shadow into the runtime texture.
 originals=[]
 for mat in source_meshes[0].materials:
  originals.append(mat);m=mat.copy();nt=m.node_tree;p=principled(m);out=next(n for n in nt.nodes if n.type=='OUTPUT_MATERIAL')
  emit=nt.nodes.new('ShaderNodeEmission')
  if p.inputs['Base Color'].is_linked:nt.links.new(p.inputs['Base Color'].links[0].from_socket,emit.inputs['Color'])
  else:emit.inputs['Color'].default_value=p.inputs['Base Color'].default_value
  nt.links.new(emit.outputs[0],out.inputs['Surface']);originals[-1]=(mat,m)
 # A second view layer material override writes signed surface normals in world XYZ.
 normalmat=bpy.data.materials.new('Bake surface normals');normalmat.use_nodes=True;nt=normalmat.node_tree;nt.nodes.clear()
 geo=nt.nodes.new('ShaderNodeNewGeometry');scale=nt.nodes.new('ShaderNodeVectorMath');scale.operation='SCALE';scale.inputs['Scale'].default_value=.5
 nt.links.new(geo.outputs['Normal'],scale.inputs[0]);add=nt.nodes.new('ShaderNodeVectorMath');add.operation='ADD';add.inputs[1].default_value=(.5,.5,.5);nt.links.new(scale.outputs[0],add.inputs[0])
 emit=nt.nodes.new('ShaderNodeEmission');nt.links.new(add.outputs[0],emit.inputs[0]);out=nt.nodes.new('ShaderNodeOutputMaterial');nt.links.new(emit.outputs[0],out.inputs['Surface'])
 # Render combined and normal override separately; cached tiles permit resuming.
 modules={}
 for src in source_meshes:
  key=src.name;pts=np.array([v.co[:] for v in src.vertices]);lo=pts.min(0);hi=pts.max(0);center=(lo+hi)*.5
  centroids=np.array([p.center[:] for p in src.polygons]);polys=list(src.polygons)
  atlas=np.zeros((GRID*TILE,GRID*TILE,4),np.float32);normalatlas=np.zeros_like(atlas);normalatlas[:,:,:3]=(.5,.5,1)
  verts=[];faces=[];uvs=[]
  # Camera right, up, outward normal: right cross up = outward.
  bases=[((1,0,0),(0,1,0),(0,0,1)),((0,1,0),(0,0,1),(1,0,0)),((1,0,0),(0,0,-1),(0,1,0))]
  for axis,(right,up,normal) in enumerate(bases):
   r=np.array(right,float);u=np.array(up,float);n=np.array(normal,float)
   depth=pts@n;cuts=np.linspace(depth.min()-1e-6,depth.max()+1e-6,SLICES+1)
   span=max(np.ptp(pts@r),np.ptp(pts@u))*1.06;cam.data.ortho_scale=float(span)
   for layer in range(SLICES):
    slot=axis*SLICES+layer;col=slot%GRID;row=slot//GRID
    c=center.copy();c+=n*((cuts[layer]+cuts[layer+1])/2-center@n)
    selected=[polys[i] for i in np.flatnonzero(((centroids@n)>=cuts[layer])&((centroids@n)<cuts[layer+1]))]
    if not selected:continue
    mesh=mesh_subset(src,selected,'slice');obj=bpy.data.objects.new('slice',mesh);sc.collection.objects.link(obj)
    for i,(_,m) in enumerate(originals):mesh.materials[i]=m
    cam.location=Vector(center+n*(span*2+10));cam.rotation_euler=(Vector(-n)).to_track_quat('-Z','Y').to_euler()
    # Explicit basis handles the +Y camera whose up direction is -Z.
    cam.matrix_world=Matrix(((r[0],u[0],n[0],cam.location.x),(r[1],u[1],n[1],cam.location.y),(r[2],u[2],n[2],cam.location.z),(0,0,0,1)))
    cam.data.clip_end=100
    for kind in ['color','normal']:
     path=BAKE/f'{key}_{slot:02d}_{kind}.png'
     if not path.exists():
      sc.view_layers[0].material_override=normalmat if kind=='normal' else None
      sc.view_settings.view_transform='Raw' if kind=='normal' else 'Standard'
      sc.render.image_settings.file_format='PNG';sc.render.image_settings.color_mode='RGBA';sc.render.filepath=str(path)
      bpy.ops.render.render(write_still=True)
     img=bpy.data.images.load(str(path),check_existing=False)
     if kind=='normal':img.colorspace_settings.name='Non-Color'
     data=np.empty(TILE*TILE*4,np.float32);img.pixels.foreach_get(data);data=data.reshape(TILE,TILE,4)
     if kind=='normal':
      normaldata=data[:,:,:3]*2-1
      data[:,:,:3]=np.stack([normaldata@r,normaldata@u,normaldata@n],axis=-1)*.5+.5
      normalatlas[row*TILE:(row+1)*TILE,col*TILE:(col+1)*TILE]=data
     else:atlas[row*TILE:(row+1)*TILE,col*TILE:(col+1)*TILE]=data
     bpy.data.images.remove(img)
    bpy.data.objects.remove(obj,do_unlink=True);bpy.data.meshes.remove(mesh)
    start=len(verts);half=span*.5
    for xx,yy in [(-1,-1),(1,-1),(1,1),(-1,1)]:verts.append(tuple(c+r*xx*half+u*yy*half))
    faces.append(tuple(range(start,start+4)))
    uvs.extend([((col+x)/GRID,(row+y)/GRID) for x,y in [(0,0),(1,0),(1,1),(0,1)]])
   log('BAKED_AXIS',key,axis)
  textures=[]
  for kind,data in [('color',atlas),('normal',normalatlas)]:
   img=bpy.data.images.new(key+'_'+kind,width=GRID*TILE,height=GRID*TILE,alpha=True)
   if kind=='normal':img.colorspace_settings.name='Non-Color'
   img.pixels.foreach_set(data.ravel());img.filepath_raw=str(OUT/(key+'_'+kind+'.png'));img.file_format='PNG';img.save();img.pack();textures.append(img)
  m=bpy.data.materials.new(key+'_needle_volume');m.use_nodes=True;m.surface_render_method='DITHERED';m.use_backface_culling=False
  p=principled(m);p.inputs['Roughness'].default_value=.75;p.inputs['Specular IOR Level'].default_value=.22
  t=image_node(m.node_tree,textures[0]);m.node_tree.links.new(t.outputs['Color'],p.inputs['Base Color']);m.node_tree.links.new(t.outputs['Alpha'],p.inputs['Alpha'])
  t=image_node(m.node_tree,textures[1]);norm=m.node_tree.nodes.new('ShaderNodeNormalMap');norm.inputs['Strength'].default_value=.45;m.node_tree.links.new(t.outputs['Color'],norm.inputs['Color']);m.node_tree.links.new(norm.outputs[0],p.inputs['Normal'])
  mesh=bpy.data.meshes.new(key+'_slices');mesh.from_pydata(verts,[],faces);mesh.uv_layers.new().data.foreach_set('uv',np.asarray(uvs).ravel());mesh.materials.append(m);mesh.update()
  modules[key]=mesh;log('MODULE_READY',key,len(faces)*2)
 bpy.data.scenes.remove(sc)
 return modules

def export_presets(modules,records,trunks):
 sc=bpy.data.scenes.new('RUNTIME | dense pine');bpy.context.window.scene=sc
 # Convert procedural bark to explicit glTF-compatible texture inputs.
 bark=bpy.data.materials.new('Pine bark PBR');bark.use_nodes=True;p=principled(bark);p.inputs['Roughness'].default_value=.88
 for filename,socket in [('texture.jpg','Base Color'),('normal.png','Normal')]:
  img=bpy.data.images.load(str(BASE/'packs/default/assets/materials/wood/outdoor_bark'/filename));img.pack();t=image_node(bark.node_tree,img)
  if socket=='Normal':
   img.colorspace_settings.name='Non-Color';n=bark.node_tree.nodes.new('ShaderNodeNormalMap');n.inputs['Strength'].default_value=.55;bark.node_tree.links.new(t.outputs[0],n.inputs['Color']);bark.node_tree.links.new(n.outputs[0],p.inputs[socket])
  else:bark.node_tree.links.new(t.outputs[0],p.inputs[socket])
 manifest=[]
 for key,label,instances in records:
  for o in list(sc.objects):bpy.data.objects.remove(o,do_unlink=True)
  trunk=bpy.data.objects.new('Trunk',trunks[key]);sc.collection.objects.link(trunk);trunk.data.materials.clear();trunk.data.materials.append(bark);trunk['rmmo_collision']='block'
  # Keep five materials and merge card geometry for predictable draw calls.
  verts=[];faces=[];uvs=[];mi=[];mats=[]
  material_maps={}
  for name,module in modules.items():
   mapping=[]
   for m in module.materials:
    resolved=bark if 'bark' in m.name.lower() else m
    if resolved not in mats:mats.append(resolved)
    mapping.append(mats.index(resolved))
   material_maps[name]=mapping
  keys=list(modules)
  for name,matrix in instances:
   mesh=modules[name];offset=len(verts);verts.extend([tuple(matrix@v.co) for v in mesh.vertices]);faces.extend([tuple(offset+i for i in p.vertices) for p in mesh.polygons]);uvs.extend([tuple(d.uv) for d in mesh.uv_layers[0].data]);mi.extend([material_maps[name][p.material_index] for p in mesh.polygons])
  mesh=bpy.data.meshes.new('NeedleVolume');mesh.from_pydata(verts,[],faces);mesh.uv_layers.new().data.foreach_set('uv',np.asarray(uvs).ravel())
  for m in mats:mesh.materials.append(m)
  mesh.polygons.foreach_set('material_index',mi);mesh.polygons.foreach_set('use_smooth',np.ones(len(mesh.polygons),dtype=bool));mesh.update()
  o=bpy.data.objects.new('Foliage',mesh);sc.collection.objects.link(o);o['rmmo_collision']='none';o['rmmo_wind']={'profile':'foliage','mesh':'*','amplitude':.06,'stiffness':.85,'anchor':'bottom','shelter':True}
  for obj in sc.objects:obj.select_set(True)
  file=OUT/(key+'.glb')
  bpy.ops.export_scene.gltf(filepath=str(file),export_format='GLB',use_selection=True,export_extras=True,export_yup=True,export_animations=False,export_cameras=False,export_lights=False)
  triangles=sum(len(p.vertices)-2 for p in mesh.polygons)+sum(len(p.vertices)-2 for p in trunk.data.polygons)
  manifest.append({'id':key,'label':label,'file':str(file),'triangles':triangles,'instances_baked':len(instances),'source_blend':str(ART/'baltic_pine_dense_v3.blend')})
  log('EXPORTED',manifest[-1])
 (OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')

def main():
 bpy.ops.wm.open_mainfile(filepath=str(ART/'baltic_pine_dense_v3.blend'))
 sc=bpy.data.scenes['Scene'];bpy.context.window.scene=sc;tree=bpy.data.objects['BALTIC PINE | editable parameters']
 presets=bpy.data.scenes['PRESETS | compact - mature - windswept']
 records=[];trunks={}
 for index,o in enumerate(sorted([o for o in presets.objects if o.asset_data],key=lambda o:o.name)):
  for s in tree.modifiers[0].node_group.interface.items_tree:
   if s.item_type=='SOCKET' and s.in_out=='INPUT':setval(tree,s.name,o.modifiers[0].get(s.identifier,s.default_value))
  setval(tree,'Wind (m)',0.);bpy.context.view_layer.update();dg=bpy.context.evaluated_depsgraph_get()
  inst=[(i.object.original.data.name,i.matrix_world.copy()) for i in dg.object_instances if i.is_instance]
  key=['pine_dense_compact','pine_dense_mature','pine_dense_windswept'][index];label=['写实密冠松树·小型','写实密冠松树·成熟','写实密冠松树·倾斜'][index]
  trunks[key]=bpy.data.meshes.new_from_object(tree.evaluated_get(dg),depsgraph=dg);records.append((key,label,inst));assert len(inst)==583
 meshes=[bpy.data.meshes[k] for k in sorted(set(n for _,_,ins in records for n,_ in ins))]
 modules=bake_modules(meshes);export_presets(modules,records,trunks)
 log('PINE_RUNTIME_EXPORT_COMPLETE')
if __name__=='__main__':
 raise SystemExit('Whole-branch volume sheets failed visual review. Run tools/export_pine_small_clusters.py instead; this module now supplies shared export helpers only.')
