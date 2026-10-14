extends SceneTree
const Components=preload('res://scripts/world3d/model_components.gd')
func _initialize()->void:call_deferred('run')
func run()->void:
 var path:='D:/code/rmmo/review_artifacts/guild_reference_recheck_20261013/accepted_building/asset.scn'
 var packed:PackedScene=load(path);var model:Node3D=packed.instantiate();root.add_child(model)
 var before:Dictionary={};var sockets:Array=[]
 for mesh:MeshInstance3D in model.find_children('*','MeshInstance3D',true,false):before[mesh.get_instance_id()]=mesh.cast_shadow
 for node in model.find_children('*','',true,false):
  var socket:Variant=node.get_meta('extras',{}).get('rmmo_light_socket')
  if Components.valid_socket(socket):sockets.append({'name':str(node.name),'flame':socket.flame,'indoor':socket.indoor})
 Components.apply(model,{'kind':'asset','uuid':'socket_whole_building'})
 var changed:Array=[]
 for mesh:MeshInstance3D in model.find_children('*','MeshInstance3D',true,false):
  if mesh.cast_shadow!=before[mesh.get_instance_id()]:
   var names:Array=[]
   for slot in mesh.mesh.get_surface_count():names.append(mesh.get_active_material(slot).resource_name)
   changed.append({'mesh':str(mesh.name),'materials':names,'cast_shadow':mesh.cast_shadow})
 var result:={'source_native_sha256':FileAccess.get_sha256(path),'sockets':sockets,'changed_meshes':changed}
 var f:=FileAccess.open('D:/code/rmmo/review_artifacts/guild_reference_recheck_20261013/whole_building_socket_shadows.json',FileAccess.WRITE)
 f.store_string(JSON.stringify(result,'  '));print('BUILDING_SOCKET_SHADOWS ',JSON.stringify(result));model.free();quit()
