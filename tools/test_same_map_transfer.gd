extends SceneTree
## CPU/headless checks for ownership, signal routing and physical landing probes.
const Stream=preload("res://scripts/world3d/world_stream.gd")
class QuietWorld extends "res://scripts/world3d/world_3d.gd":
	func _ready()->void:pass
	func _process(_delta:float)->void:pass
	func _physics_process(_delta:float)->void:pass
	func _exit_tree()->void:pass
class PendingAssets extends Node:
	signal published(specs:Array)
	signal completed
	signal failed(reason:String)
	var error:=""
	var _reference_index:Dictionary={}
	var source_signatures:Dictionary={"model":"digest"}
	var demands:Dictionary={}
	var demand_scope:Array=[]
	var released:Array=[]
	var failure_clip:=AABB(Vector3(300,-10,0),Vector3(8,20,8))
	var path_error:=""
	func is_complete()->bool:return false
	func ensure_geometry(clip:AABB,id:String="navigation")->bool:demands[id]=clip;return true
	func release_demand(id:String)->void:released.append(id);demands.erase(id)
	func get_demand_scope()->Array:return demand_scope.duplicate()
	func set_demand_scope(ids:Array)->bool:demand_scope=ids.duplicate();return true
	func allow_demand_in_scope(id:String)->bool:
		if not demand_scope.is_empty() and not demand_scope.has(id):demand_scope.append(id)
		return true
	func error_for_clip(clip:AABB)->String:return path_error if clip.intersects(failure_clip) else ""
	func retry_failed(clip:AABB)->void:
		if clip.intersects(failure_clip):path_error=""
class FakeNavigation extends Node:
	var geometry_pending:=false
	var runtime_geometry_key:=""
	var provider:Callable
	var appended:=0
	var error:=""
	func set_geometry_pending(value:bool)->bool:geometry_pending=value;return true
	func configure_geometry_provider(value:Callable)->void:provider=value
	func append_specs(specs:Array)->Dictionary:appended+=specs.size();return {"ok":true}
	func set_geometry_error(value:String)->void:error=value
	func near_surface(_point:Vector3,_horizontal:float,_vertical:float)->bool:return true
class MapData extends RefCounted:
	var appended:=0
	func append_specs(specs:Array)->void:appended+=specs.size()
	func append_resident_specs(specs:Array)->void:append_specs(specs)
var failures:=0
var passed:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label_:String)->void:
	print("PASS: " if ok else "FAIL: ",label_)
	if ok:passed+=1
	else:failures+=1
func body_shape(body:CollisionObject3D,shape:Shape3D,offset:Vector3=Vector3.ZERO)->CollisionShape3D:
	var node:=CollisionShape3D.new();node.name="CollisionShape3D";node.shape=shape;node.position=offset;body.add_child(node);return node
func settle()->void:
	await physics_frame;await process_frame
func run()->void:
	var world:=QuietWorld.new();root.add_child(world)
	world._map_path="D:/maps/town/map.gltf"
	check(world._same_map_target("D:/maps/town/sub/../map.gltf") and not world._same_map_target("D:/maps/other/map.gltf"),"same-map routing normalizes paths without accepting another map")
	var map_root:=Node3D.new();world.add_child(map_root);world._map_root=map_root;map_root.set_meta("runtime_geometry_key","base")
	var assets:=PendingAssets.new();assets.name="DeferredAssets";map_root.add_child(assets)
	var original:=FakeNavigation.new();var staged:=FakeNavigation.new();world.add_child(original);world.add_child(staged)
	world._navigation=original;world._hud=Control.new();world.add_child(world._hud)
	var map_data:=MapData.new();world._map_data=map_data
	assets.set_demand_scope(["transfer:7"])
	world._transfer_request_serial=7
	world._local_transfer={"request":7,"map":map_root,"deferred":assets,"navigation":staged,"scope_applied":true,"cancelled":false}
	world._bind_deferred_geometry(map_root,original)
	check(assets.get_demand_scope()==["transfer:7"],"binding the old navigation cannot extend the destination scope")
	world._bind_deferred_geometry(map_root,staged)
	check(assets.get_demand_scope()==["transfer:7","navigation:%d"%staged.get_instance_id()],"only the current staged navigation receives an allowed destination ticket")
	var stale:=FakeNavigation.new();world.add_child(stale)
	world._local_transfer.navigation=stale;world._local_transfer.request=6
	world._bind_deferred_geometry(map_root,stale)
	check(not assets.get_demand_scope().has("navigation:%d"%stale.get_instance_id()),"superseded request cannot authorize a new navigation ticket")
	stale.free()
	world._local_transfer={};assets.set_demand_scope([])
	original.provider.call(AABB(Vector3.ZERO,Vector3.ONE));staged.provider.call(AABB(Vector3.ONE,Vector3.ONE))
	check(assets.demands.size()==2,"staged and live navigation hold independent geometry demands")
	assets.published.emit([{"uuid":"first"}])
	check(original.appended==1 and staged.appended==1 and map_data.appended==1,"both navigation snapshots receive geometry while minimap appends once")
	assets.completed.emit()
	check(original.runtime_geometry_key==staged.runtime_geometry_key and map_root.get_meta("runtime_geometry_key")==original.runtime_geometry_key,"completion does not append source identity twice")
	world._navigation=staged;original.free()
	check(assets.published.get_connections().size()==1 and assets.demands.size()==1,"retiring navigation disconnects callbacks and releases only its demand")
	assets.published.emit([{"uuid":"second"}])
	check(staged.appended==2 and map_data.appended==2,"new navigation becomes the sole minimap publisher after commit")
	world._transfer_request_serial=7
	var context:Dictionary={"request":7,"map":map_root,"deferred":assets,"cancelled":false,"origin_id":"origin","target_id":"target","demand_id":"transfer","clip":AABB(Vector3.ZERO,Vector3(10,10,10))}
	check(world._local_transfer_error(context).is_empty(),"active same-map transaction is valid")
	world._transfer_request_serial=8
	check(not world._local_transfer_error(context).is_empty(),"new request invalidates the old transaction before commit")
	world._transfer_request_serial=7;assets.error="broken"
	check(world._local_transfer_error(context).contains("broken"),"asset preparation failures are surfaced before movement")
	assets.error=""
	assets.path_error="bad distant model"
	check(world._local_transfer_error(context).is_empty() and staged.error.is_empty(),"distant failed source does not poison original region or navigation")
	context.clip=assets.failure_clip
	check(world._local_transfer_error(context).contains("bad distant model") and staged.error.is_empty(),"failed target reports only its own source error without mutating live navigation")
	assets.retry_failed(AABB(Vector3(600,0,0),Vector3(10,10,10)))
	check(not assets.error_for_clip(context.clip).is_empty(),"retrying another region does not erase the target failure")
	assets.retry_failed(context.clip)
	check(world._local_transfer_error(context).is_empty(),"retry of the repaired target clears only its scoped failure")
	Stream.pin_source(map_root,"origin",Vector3.ZERO);Stream.pin_source(map_root,"target",Vector3(300,0,0));Stream.pin_source(map_root,"other",Vector3(500,0,0))
	assets.demands.transfer=AABB();world._release_local_transfer_sources(context)
	check(map_root.get_meta("stream_sources").keys()==["other"] and not assets.demands.has("transfer"),"transaction cleanup preserves unrelated residency and demand owners")
	assets.set_demand_scope(["before:cover"]);world._release_local_transfer_sources(context)
	check(assets.get_demand_scope()==["before:cover"],"failure before a transaction installs its scope leaves a pre-existing scope intact")
	context.original={"deferred_scope":["existing:scope"]};context.scope_applied=true
	assets.set_demand_scope(["transfer","navigation:temporary"]);assets.demands.transfer=AABB()
	world._release_local_transfer_sources(context)
	check(assets.get_demand_scope()==["existing:scope"] and not context.scope_applied,"success, failure and cancellation cleanup restore the exact saved scope once")
	assets.set_demand_scope(["newer:scope"]);world._release_local_transfer_sources(context)
	check(assets.get_demand_scope()==["newer:scope"],"repeated old cleanup cannot overwrite a subsequent scope")
	var old_clip:=AABB(Vector3(-10,-10,-10),Vector3(20,20,20))
	var target_clip:=AABB(Vector3(290,-10,-10),Vector3(32,20,32))
	context.original.entry_stream_clip=old_clip;context.stream_scope_applied=true
	Stream.set_entry_scope(map_root,target_clip);world._release_local_transfer_sources(context)
	check(map_root.get_meta("entry_stream_clip")==old_clip and not context.stream_scope_applied,"stream scope restores original exactly once")
	Stream.set_entry_scope(map_root,target_clip);world._release_local_transfer_sources(context)
	check(map_root.get_meta("entry_stream_clip")==target_clip,"old cleanup cannot clear a newer stream scope")
	Stream.clear_entry_scope(map_root)
	assets.set_demand_scope([])
	var player:=CharacterBody3D.new();world.add_child(player);world._player=player;player.position=Vector3(0,.9,0)
	var capsule:=CapsuleShape3D.new();capsule.radius=.3;capsule.height=2.1
	body_shape(player,capsule,Vector3(0,.15,0))
	await settle()
	check(world._same_map_destination_fits(player.position,staged),"landing at current position excludes the player's own old body")
	var obstacle:=CharacterBody3D.new();world.add_child(obstacle);obstacle.position=Vector3(4,.9,0)
	var other_shape:=CapsuleShape3D.new();other_shape.radius=.3;other_shape.height=1.8;body_shape(obstacle,other_shape)
	await settle()
	check(not world._same_map_destination_fits(Vector3(4,.9,0),staged),"live actor capsule blocks its current destination pose")
	obstacle.position=Vector3(8,.9,0);await settle()
	check(world._same_map_destination_fits(Vector3(4,.9,0),staged),"moved actor does not keep blocking its old authored position")
	var ceiling:=StaticBody3D.new();world.add_child(ceiling);ceiling.position=Vector3(4,2.02,0)
	var box:=BoxShape3D.new();box.size=Vector3(2,.1,2);body_shape(ceiling,box);await settle()
	check(not world._same_map_destination_fits(Vector3(4,.9,0),staged),"actual 2.1 metre player capsule rejects a low ceiling")
	ceiling.free();await settle()
	var peer:=Node3D.new();world.add_child(peer);peer.position=Vector3(4,0,0);world.remote_players.models.peer=peer
	check(not world._same_map_destination_fits(Vector3(4,.9,0),staged),"remote visual peers without physics bodies still reserve occupied space")
	world.remote_players.models.clear();peer.free()
	staged.free()
	check(assets.published.get_connections().is_empty() and assets.demands.is_empty(),"last navigation retirement leaves no stale signal or geometry demand")
	world.free()
	print("SAME_MAP_TRANSFER_LOGIC passed=",passed," failures=",failures)
	quit(0 if failures==0 else 1)
