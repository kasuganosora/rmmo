extends SceneTree
const Components=preload('res://scripts/world3d/model_components.gd')
func _initialize()->void:
 var rows:Array=[]
 for aid:String in ['guild_hall_lantern','guild_facade_wall_lantern']:
  var path:='D:/code/rmmo/review_artifacts/guild_reference_recheck_20261013/accepted_library/'+aid+'/asset.scn'
  var packed:PackedScene=load(path)
  var model:Node3D=packed.instantiate()
  var nodes:Array[Node]=[model];nodes.append_array(model.find_children('*','',true,false))
  for node in nodes:
   var socket:Variant=node.get_meta('extras',{}).get('rmmo_light_socket')
   if not Components.valid_socket(socket) or not node is Node3D:continue
   var p:Array=socket.position
   var point:Vector3=Components.relative_pose(node,model)*Vector3(p[0],p[1],p[2])
   for m:MeshInstance3D in node.find_children('*','MeshInstance3D',true,false):
    var local:=Components.relative_pose(m,model).affine_inverse()*point
    var materials:Array=[]
    for i in m.mesh.get_surface_count():
     var material:Material=m.get_active_material(i)
     materials.append({'name':material.resource_name,'class':material.get_class(),
       'emission':material.emission_enabled if material is BaseMaterial3D else false,
       'energy':material.emission_energy_multiplier if material is BaseMaterial3D else -1,
       'color':str(material.emission) if material is BaseMaterial3D else ''})
    if m.get_aabb().has_point(local):
     rows.append({'asset':aid,'socket':str(node.name),'mesh':str(m.name),'point':str(local),
       'aabb':str(m.get_aabb()),'cast_shadow':m.cast_shadow,'materials':materials})
  model.free()
 var file:=FileAccess.open('D:/code/rmmo/review_artifacts/guild_reference_recheck_20261013/socket_shadow_diagnosis.json',FileAccess.WRITE)
 file.store_string(JSON.stringify(rows,'  '))
 print('SOCKET_DIAG ',JSON.stringify(rows))
 quit()
