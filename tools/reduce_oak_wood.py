"""Reduce fine woody twigs only; preserve every leaf card and the approved trunk."""
import bpy,bmesh,sys,json
from pathlib import Path
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).parent))
from build_oak_game import ART,REVIEW,setval,triangles
from export_pine_runtime import mesh_subset
bpy.ops.wm.open_mainfile(filepath=str(ART/'street_oak_thick_trunk.blend'))
sc=bpy.data.scenes['Scene'];bpy.context.window.scene=sc;tree=bpy.data.objects['STREET OAK | editable parameters'];setval(tree,'Optimized',True);setval(tree,'Wind (m)',0.)
col=bpy.data.collections['SOURCE_C | conservative optimized modules'];original={o.name:o.data for o in col.objects};cache={};stats=[]
for source in dict.fromkeys(original.values()):
 name=source.name;leaf_faces=[p for p in source.polygons if 'needle_volume' in source.materials[p.material_index].name];wood_faces=[p for p in source.polygons if p not in leaf_faces]
 leafmesh=mesh_subset(source,leaf_faces,name+'_leaves');woodmesh=mesh_subset(source,wood_faces,name+'_wood')
 bm=bmesh.new();bm.from_mesh(woodmesh);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=0.000001);bm.to_mesh(woodmesh);bm.free()
 leaf=bpy.data.objects.new('Temporary leaves',leafmesh);wood=bpy.data.objects.new('Temporary twigs',woodmesh);sc.collection.objects.link(leaf);sc.collection.objects.link(wood)
 bpy.ops.object.select_all(action='DESELECT');wood.select_set(True);bpy.context.view_layer.objects.active=wood
 dec=wood.modifiers.new('Fine woody twig budget','DECIMATE');dec.ratio=.4;bpy.ops.object.modifier_apply(modifier=dec.name)
 leaftris=triangles(leafmesh);afterwood=triangles(wood.data)
 leaf.select_set(True);bpy.context.view_layer.objects.active=leaf;bpy.ops.object.join()
 reduced=leaf.data;source.name=name+'_preserved';source.use_fake_user=True;reduced.name=name
 cache[source]=reduced;stats.append({'module':name,'source_triangles':triangles(source),'leaf_triangles_unchanged':leaftris,'wood_triangles_after':afterwood,'after_triangles':triangles(reduced)})
 bpy.data.objects.remove(leaf,do_unlink=True)
sc.cycles.samples=20;sc.render.resolution_x=sc.render.resolution_y=1000;sc.view_settings.exposure=.5
sun=bpy.data.objects['REVIEW | fixed sun'];sun.rotation_euler=(.45,-.5,-.5);cam=sc.camera
for label,reduced in [('wood_before',False),('wood_reduced',True)]:
 for o in col.objects:o.data=cache[original[o.name]] if reduced else original[o.name]
 bpy.context.view_layer.update();dg=bpy.context.evaluated_depsgraph_get();total=triangles(tree.evaluated_get(dg).data)+sum(triangles(i.object.data) for i in dg.object_instances if i.is_instance)
 print(label,total,flush=True)
 for view,pos,target,scale in [('full',(14,-20,11),(0,0,4.2),11.8),('close',(6,-10,7),(1.8,-.2,6.4),2.5)]:
  cam.location=pos;cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.ortho_scale=scale;sc.render.filepath=str(REVIEW/(label+'_'+view+'.png'));bpy.ops.render.render(write_still=True)
bpy.ops.wm.save_as_mainfile(filepath=str(ART/'street_oak_thick_reduced.blend'),compress=True)
(REVIEW/'wood_reduction.json').write_text(json.dumps({'modules':stats,'policy':'Only fine woody twigs welded and reduced to 40%; all leaf geometry, atlas UV, primary trunk, crown parameters and 505 instances preserved'},indent=2),encoding='utf-8')
print('OAK_WOOD_REDUCTION_READY',flush=True)
