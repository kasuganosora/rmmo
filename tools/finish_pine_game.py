"""Author three portable game LODs from V6 branch sprays; preserve original master."""
import bpy,json,sys
from pathlib import Path
from mathutils import Vector
ROOT=Path('D:/code/rmmo_runtime');OUT=ROOT/'assets/baltic_pine_dense_v3_game'
sys.path.insert(0,str(Path(__file__).parent))
from export_pine_runtime import mesh_subset

def tris(mesh):return sum(len(p.vertices)-2 for p in mesh.polygons)

def main():
 manifest=json.loads((OUT/'manifest.json').read_text(encoding='utf-8'))
 for row in manifest:
  bpy.ops.wm.read_factory_settings(use_empty=True)
  bpy.ops.import_scene.gltf(filepath=row['file'])
  foliage=bpy.data.objects['Foliage'];trunk=bpy.data.objects['Trunk'];sc=foliage.users_scene[0];bpy.context.window.scene=sc
  for o in list(sc.objects):
   if o.name.startswith('Foliage_LOD'):bpy.data.objects.remove(o,do_unlink=True)
  bpy.ops.object.select_all(action='DESELECT');trunk.select_set(True);bpy.context.view_layer.objects.active=trunk
  if tris(trunk.data)>3000:
   dec=trunk.modifiers.new('Game trunk silhouette','DECIMATE');dec.ratio=.18;bpy.ops.object.modifier_apply(modifier=dec.name)
  vertices=[v.co for v in foliage.data.vertices];lo=Vector(tuple(min(v[i] for v in vertices) for i in range(3)));hi=Vector(tuple(max(v[i] for v in vertices) for i in range(3)))
  # Explicit common Y-up AABB keeps all LOD range tests at the same center.
  bounds=[lo.x,lo.z,-hi.y,hi.x-lo.x,hi.z-lo.z,hi.y-lo.y]
  foliage['rmmo_visibility_range']={'begin':0.,'end':35.,'bounds':bounds}
  leaf=[p for p in foliage.data.polygons if 'needle_volume' in foliage.data.materials[p.material_index].name]
  # Find complete disconnected cards, never drop one of a quad's triangles.
  parent=list(range(len(foliage.data.vertices)))
  def find(i):
   while parent[i]!=i:parent[i]=parent[parent[i]];i=parent[i]
   return i
  for p in leaf:
   ids=list(p.vertices);root=find(ids[0])
   for v in ids[1:]:parent[find(v)]=root
  groups={}
  for p in leaf:groups.setdefault(find(p.vertices[0]),[]).append(p)
  cards=list(groups.values());counts=[tris(foliage.data)+tris(trunk.data)]
  for level,stride,scale,begin,end in [(1,3,1.65,35.,85.),(2,9,2.85,85.,0.)]:
   chosen=[]
   for i,card in enumerate(cards):
    if (i*37+11)%stride==0:chosen.extend(card)
   mesh=mesh_subset(foliage.data,chosen,'Pine_LOD'+str(level));obj=bpy.data.objects.new('Foliage_LOD'+str(level),mesh);sc.collection.objects.link(obj);obj.matrix_world=foliage.matrix_world.copy()
   # Each selected card remains independent; enlarge modestly for distant coverage.
   seen=set()
   for p in mesh.polygons:
    if p.index in seen:continue
    indices=set(p.vertices);neighbors=[q for q in mesh.polygons[max(0,p.index-1):p.index+2] if indices.intersection(q.vertices)]
    ids=set(v for q in neighbors for v in q.vertices);center=sum((mesh.vertices[i].co for i in ids),Vector())/len(ids)
    for i in ids:mesh.vertices[i].co=center+(mesh.vertices[i].co-center)*scale
    seen.update(q.index for q in neighbors)
   # Strip unused bark slots and use a single leaf draw for each distant level.
   material=mesh.materials[chosen[0].material_index].copy();material.name='Pine game needle_volume LOD'+str(level)
   if level==2:
    p=next(n for n in material.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    for link in list(p.inputs['Normal'].links):material.node_tree.links.remove(link)
   mesh.materials.clear();mesh.materials.append(material)
   for p in mesh.polygons:p.material_index=0
   obj['rmmo_collision']='none';obj['rmmo_visibility_range']={'begin':begin,'end':end,'bounds':bounds}
   if level==1:obj['rmmo_wind']={'profile':'foliage','mesh':'*','amplitude':.04,'stiffness':.9,'anchor':'bottom','shelter':True}
   counts.append(tris(mesh)+tris(trunk.data))
  for obj in bpy.context.view_layer.objects:obj.select_set(obj.type=='MESH')
  bpy.ops.export_scene.gltf(filepath=row['file'],export_format='GLB',use_selection=True,export_extras=True,export_yup=True,export_animations=False,export_cameras=False,export_lights=False,use_active_scene=True)
  row['lod_triangles']=counts;row['triangles']=sum(tris(o.data) for o in bpy.context.view_layer.objects if o.type=='MESH');row['lod_ranges_m']=[0,35,85];row['near_triangles']=counts[0]
  print('GAME_LODS',row['id'],counts,'stored',row['triangles'],flush=True)
 (OUT/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf-8')
if __name__=='__main__':main()
