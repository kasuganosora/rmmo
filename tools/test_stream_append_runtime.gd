extends SceneTree
## Parent runs this scene/physics regression through run_godot_background.py.
const Stream=preload("res://scripts/world3d/world_stream.gd")
const Index=preload("res://scripts/world3d/stream_index.gd")
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
const Player=preload("res://scripts/world3d/world_player.gd")
const Net=preload("res://scripts/net/net.gd")
class GuardWorld extends "res://scripts/world3d/world_3d.gd":
	# Exercise the production guard without booting a character, map or renderer.
	func _ready()->void:pass
	func _process(_delta:float)->void:pass
	func _physics_process(_delta:float)->void:pass
	func _exit_tree()->void:pass
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func box(id:String,position:Vector3,size:Vector3,ground:bool=false)->Dictionary:
	var node:=MeshInstance3D.new();node.name=id;node.position=position
	var mesh:=BoxMesh.new();mesh.size=size;node.mesh=mesh
	var spec:Dictionary=Stream._spec(node);node.free()
	if ground:spec.ground_batch_record={"kind":"box","surface_id":"ground","size":[size.x,size.y,size.z]}
	return spec
func scene(specs:Array)->Dictionary:
	var host:=Node3D.new();root.add_child(host)
	var map:=Node3D.new();host.add_child(map);map.set_meta("stream_library",specs)
	var index:=Index.build(specs)
	for key:String in index:map.set_meta(key,index[key])
	map.set_meta("stream_children",0)
	return {"host":host,"map":map}
func settle(world:Dictionary,at:Vector3)->void:
	for i in 1500:
		Stream.sync(world.map,world.host,at,1)
		if world.map.get_meta("stream_chunk",Vector2i(2147483647,0))==Stream.chunk_key(at) and world.map.get_meta("stream_append_pending",[]).is_empty():return
		await process_frame
	check(false,"bounded residency settles")
func equal_residency(world:Dictionary,at:Vector3,label:String)->void:
	var expected:=scene(world.map.get_meta("stream_library").duplicate(true))
	Stream.sync(expected.map,expected.host,at)
	for key:String in ["stream_meshes","stream_bodies"]:
		var actual:Array=world.map.get_meta(key).keys();actual.sort()
		var wanted:Array=expected.map.get_meta(key).keys();wanted.sort()
		check(actual==wanted,label+" "+key+" matches fresh load")
	expected.host.free()
func ray(world:Dictionary,at:Vector3,id:String)->void:
	await physics_frame;await physics_frame;await process_frame
	var query:=PhysicsRayQueryParameters3D.create(at+Vector3.UP*6,at-Vector3.UP*6,1)
	var hit:Dictionary=world.host.get_world_3d().direct_space_state.intersect_ray(query)
	check(not hit.is_empty() and str(hit.collider.get_meta("uuid",""))==id,"new collider answers real ray: "+id)
func guards()->void:
	var server:=Net.server();var session:=Net.session()
	var old_stats:Dictionary=server.combat_stats.player.duplicate(true)
	var old_respawn:bool=server.awaiting_respawn;var old_transition:bool=session._world_transition_active
	server.combat_stats.player={"hp":100};server.awaiting_respawn=false;session._world_transition_active=false
	var world:=GuardWorld.new();root.add_child(world)
	var map:=Node3D.new();world.add_child(map);world._map_root=map
	map.set_meta("stream_chunk",Vector2i.ZERO)
	var deferred:=Deferred.new();map.add_child(deferred)
	# PROCESS_MODE_DISABLED removes a CollisionObject3D from its physics space
	# with the default disable mode. Only disable automatic callbacks here:
	# the production motion method below still needs a real registered body.
	var player:=Player.new()
	var model:=Node3D.new();model.name="CharacterModel3D";player.add_child(model)
	var capsule:=CollisionShape3D.new();capsule.shape=CapsuleShape3D.new();player.add_child(capsule)
	world.add_child(player);world._player=player;player.position=Vector3(4,20,4)
	player.set_process(false);player.set_physics_process(false)
	await physics_frame;await physics_frame;await process_frame
	check(PhysicsServer3D.body_get_space(player.get_rid())==player.get_world_3d().space,"guard fixture player is attached to the real physics space")
	var status:=Label.new();world.add_child(status);world._status=status
	var nearby:Dictionary={"record":{"uuid":"guard_near"},"bounds":AABB(Vector3(3,0,3),Vector3(2,2,2))}
	var far:Dictionary={"record":{"uuid":"guard_far"},"bounds":AABB(Vector3(24,0,24),Vector3(2,2,2))}
	deferred.pending=[nearby,far];player.input_locked=false;player.velocity=Vector3(3,-7,2)
	world._guard_deferred_geometry()
	check(player.geometry_blocked and player.input_locked and world._geometry_wait_locked,"missing nearby asset acquires geometry and input locks")
	var before:=player.position
	for i in 10:player._physics_process(.1)
	check(player.position==before and player.velocity==Vector3.ZERO,"geometry wait suspends gravity and existing vertical velocity")
	nearby.published=true;deferred.pending.erase(nearby)
	server.combat_stats.player.hp=0
	world._guard_deferred_geometry()
	check(player.input_locked and not world._geometry_wait_locked and not player.geometry_blocked,"completed geometry never unlocks dead player")
	server.combat_stats.player.hp=100;server.awaiting_respawn=true;world._geometry_wait_locked=true
	world._guard_deferred_geometry()
	check(player.input_locked and not world._geometry_wait_locked,"completed geometry never unlocks player awaiting respawn")
	server.awaiting_respawn=false;world._geometry_wait_locked=true;map.set_meta("stream_chunk",Vector2i(7,7))
	world._guard_deferred_geometry()
	check(player.input_locked and world._geometry_wait_locked,"mismatched settled chunk cannot release existing geometry wait")
	map.set_meta("stream_chunk",Stream.chunk_key(player.position));world._guard_deferred_geometry()
	check(not player.input_locked and not player.geometry_blocked and not world._geometry_wait_locked,"matching chunk releases healthy player while far asset remains pending")
	# A published spec is known before its body is attached. This is distinct
	# from the service's pending-assets gate and must suspend gravity too.
	var missing:=box("guard_published",player.position-Vector3.UP,Vector3(3,1,3))
	var catalog:=Index.build([missing])
	for key:String in catalog:map.set_meta(key,catalog[key])
	map.set_meta("stream_bodies",{});player.input_locked=false
	world._guard_deferred_geometry()
	check(player.geometry_blocked and player.input_locked,"published nearby geometry without actual body blocks movement")
	var body:=StaticBody3D.new();world.add_child(body);map.set_meta("stream_bodies",{missing.uuid:body})
	world._guard_deferred_geometry()
	check(not player.geometry_blocked and not player.input_locked,"attached body releases healthy player's geometry lock")
	player.input_locked=true;world._geometry_wait_locked=true
	map.set_meta("stream_chunk",Vector2i(7,7));map.set_meta("stream_target",Stream.chunk_key(player.position))
	map.set_meta("stream_jobs",[far]);map.set_meta("stream_append_pending",[far])
	world._guard_deferred_geometry()
	check(not player.input_locked and not player.geometry_blocked and not world._geometry_wait_locked,"local ready body releases input while current target has unfinished distant jobs and appended work")
	player.input_locked=true;player.geometry_blocked=false;player.velocity=Vector3.ZERO
	player._physics_process(.1)
	check(player.velocity.y<0,"ordinary UI input lock retains established gravity behavior")
	server.combat_stats.player=old_stats;server.awaiting_respawn=old_respawn;session._world_transition_active=old_transition
	world.free()
func continuous_appends()->void:
	var focus:=box("waiting_near",Vector3(100,1,4),Vector3(2,2,2))
	# Use a genuine CPU triangle mesh so the production collision worker is
	# exercised, rather than only the immediate primitive-box shortcut.
	var triangles:=ArrayMesh.new()
	triangles.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,focus.mesh.get_mesh_arrays())
	focus.collision_mesh=preload("res://scripts/world3d/ground_cpu_mesh.gd").capture(triangles)
	var initial:Array=[box("flood_anchor",Vector3(4,1,4),Vector3.ONE),focus]
	for i in 24:initial.append(box("old_waiting_%d"%i,Vector3(100+i%6*3,1,12+int(i/6)*3),Vector3.ONE))
	var world:=scene(initial);Stream.sync(world.map,world.host,Vector3.ZERO)
	var destination:=Vector3(100,2,4)
	Stream.sync(world.map,world.host,destination,1)
	var ready_frame:=-1;var all_ok:=true
	for frame in 80:
		var position:=Vector3(115,1,28+frame*.01) if frame%5==0 else Vector3(1000+frame*3,1,4)
		all_ok=Stream.append_specs(world.map,[box("flood_%d"%frame,position,Vector3.ONE)]).ok and all_ok
		Stream.sync(world.map,world.host,destination,1)
		if ready_frame<0 and Stream.nearby_collision_ready(world.map,destination):ready_frame=frame
		await process_frame
	check(all_ok,"every frame publishes another complete spec during existing residency work")
	check(ready_frame>=0 and ready_frame<40,"original nearby triangle collision finishes before continuous arrivals stop (frame %d)"%ready_frame)
	check(focus.has("shape") and focus.shape is ConcavePolygonShape3D,"nearby readiness includes completed exact triangle collision worker")
	await settle(world,destination)
	var registered:Dictionary=world.map.get_meta("stream_by_id")
	# The library is intentionally shared with initial; check each incoming UUID
	# and final residency rather than deriving an expected count from that alias.
	var complete:bool=registered.size()==106 and world.map.get_meta("stream_library").size()==106
	for i in 80:complete=complete and registered.has("flood_%d"%i)
	check(complete and world.map.get_meta("stream_append_pending",[]).is_empty(),"all 80 accumulated appends are eventually absorbed exactly once")
	equal_residency(world,destination,"continuous append completion")
	await ray(world,Vector3(100,1,4),"waiting_near")
	world.host.free()
func scheduling_item(id:String,path:String,x:float)->Dictionary:
	return {"record":{"uuid":id,"kind":"asset","asset_path":path,"position":[x,0,0],"rotation":[0,0,0],"size":[1,1,1]},"path":path,"digest":FileAccess.get_sha256(path),"bounds":AABB(Vector3(x-.5,-.5,-.5),Vector3.ONE)}
func scheduler()->void:
	var paths=preload("res://scripts/world3d/map_paths.gd")
	var assets=preload("res://scripts/world_editor/asset_library.gd")
	var directory:String=paths.cache_directory("stream_order_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(directory)
	var path_a:=directory.path_join("a.glb");var path_b:=directory.path_join("b.glb")
	for path:String in [path_a,path_b]:
		var source:=MeshInstance3D.new();source.name="Box";source.mesh=BoxMesh.new()
		var writer:=GLTFDocument.new();var state:=GLTFState.new()
		var code:=writer.append_from_scene(source,state)
		if code==OK:code=writer.write_to_filesystem(state,path)
		source.free();check(code==OK,"create isolated ordinary scheduling model "+path.get_file())
	var preload_a:Node=preload("res://scripts/world3d/gltf_map_io.gd").load_scene(path_a)
	check(assets.cache_scene(path_a,preload_a),"model A is already prepared in shared cache")
	var world:=scene([]);var service:=Deferred.new();world.map.add_child(service)
	service.pending=[scheduling_item("a_far",path_a,100),scheduling_item("b_near",path_b,10),scheduling_item("b_next",path_b,20)]
	service._prepared_paths[path_a]=true;service.prioritize(Vector3.ZERO)
	check(service.pending[service._nearest_index()].record.uuid=="b_near","unprepared nearby model B precedes prepared distant model A")
	service.prioritize(Vector3(99,0,0))
	check(service.pending[service._nearest_index()].record.uuid=="a_far","player movement reorders globally across model paths")
	service.prioritize(Vector3.ZERO)
	var published:Array=[]
	service.published.connect(func(specs:Array):
		var id:String=str(specs[0].uuid).get_slice("__",0);published.append(id)
		# Move after the first actual publication: the prepared A instance must
		# precede B's second instance, without preparing B a second time later.
		service.prioritize(Vector3(99,0,0) if id=="b_near" else Vector3.ZERO)
	)
	service.activate(world.host)
	for i in 1800:
		await process_frame
		if service.is_complete() or not service.error.is_empty():break
	check(service.error.is_empty() and service.is_complete(),"real deferred scheduler completes both model paths")
	check(published==["b_near","a_far","b_next"],"actual publication honors global distance and moved player priority")
	check(int(service.profile.models)==1 and int(service.profile.instances)==3 and service._prepared_paths.size()==2,"model B is prepared once for both instances; prepared model A is reused")
	check(service.source_signatures.has(path_b),"single B preparation retains verified source signature")
	world.host.free();assets._scenes.erase(path_a);assets._scenes.erase(path_b)
func shared_near_far_model()->void:
	var paths=preload("res://scripts/world3d/map_paths.gd")
	var assets=preload("res://scripts/world_editor/asset_library.gd")
	var directory:String=paths.cache_directory("stream_shared_model_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(directory)
	var asset:=directory.path_join("crate.glb");var map_path:=directory.path_join("map.gltf")
	check(preload("res://tools/test_transfer_loading_gpu.gd").ordinary_fixture(asset)==OK,"create standard self-contained shared near/far GLB")
	check(preload("res://scripts/world3d/asset_bounds_manifest.gd").read(asset).known,"shared fixture is actually eligible for deferred manifest")
	var doc=preload("res://scripts/world3d/world_document.gd").new()
	var near_id:String=doc.add_asset({"asset_path":asset,"label":"Shared near"},Vector3(4,.5,4))
	var far_id:String=doc.add_asset({"asset_path":asset,"label":"Shared far"},Vector3(304,.5,4))
	var authored:Array=doc.records.duplicate(true)
	var saved:int=doc.save(map_path)
	check(saved==OK,"save temporary reference map with one model at near and far positions")
	if saved!=OK:return
	var loader=preload("res://scripts/world3d/map_loader.gd").new();loader.near_first=true;root.add_child(loader)
	loader.start(map_path,Vector3(4,.9,4))
	var loaded:Array=await loader.finished
	check(loaded[0] is Node and str(loaded[2]).is_empty(),"real near-first MapLoader finishes shared-model map")
	if not loaded[0] is Node:return
	var host:=Node3D.new();root.add_child(host)
	var map:Node=loaded[0];host.add_child(map)
	var profile:Dictionary=map.get_meta("load_profile",{})
	check(profile.get("asset_parses",[]).size()==1 and int(profile.get("initial_asset_paths",-1))==1,"near model has exactly one initial parse")
	var service:Node=map.get_node_or_null("DeferredAssets")
	check(service!=null and service.pending.size()==1 and service.pending[0].record.uuid==far_id,"same-path far author instance stays pending at entry")
	if service==null:host.free();return
	check(service._prepared_paths.has(asset),"initial successful preparation is inherited by deferred queue")
	var prepared_id:int=assets._scenes[asset].get_instance_id()
	Stream.sync(map,host,Vector3(4,.9,4))
	var near_specs:Array=map.get_meta("stream_library").filter(func(spec):return str(spec.uuid).begins_with(near_id+"__"))
	check(near_specs.size()==1 and map.get_meta("stream_meshes",{}).has(near_specs[0].uuid),"near imported instance is a real resident mesh")
	if near_specs.size()==1:await ray({"host":host},Vector3(4,.5,4),near_specs[0].uuid)
	service.activate(host)
	for i in 600:
		await process_frame
		if service.is_complete() or not service.error.is_empty():break
	check(service.error.is_empty() and service.is_complete() and int(service.profile.models)==0 and int(service.profile.instances)==1,"far instance completes with zero repeated model preparations")
	check(assets._scenes[asset].get_instance_id()==prepared_id,"near and far instances retain the same immutable prepared scene")
	Stream.sync(map,host,Vector3(304,.9,4))
	var far_specs:Array=map.get_meta("stream_library").filter(func(spec):return str(spec.uuid).begins_with(far_id+"__"))
	var far_meshes:Dictionary=map.get_meta("stream_meshes",{})
	var real_visual:bool=far_specs.size()==1 and far_meshes.has(far_specs[0].uuid)
	if real_visual:
		var mesh:MeshInstance3D=far_meshes[far_specs[0].uuid]
		real_visual=mesh.visible and mesh.mesh.get_faces().size()==36 and mesh.get_active_material(0)!=null
	check(real_visual,"far instance restores full standard cube geometry and authored material")
	if far_specs.size()==1:await ray({"host":host},Vector3(304,.5,4),far_specs[0].uuid)
	check(map.get_meta("extras").rmmo_records==authored and doc.records==authored,"both near/far author records remain complete and unchanged")
	for i in 600:
		if not is_instance_valid(loader):break
		await process_frame
	check(not is_instance_valid(loader),"shared-model loader retires all initial background work")
	host.free();assets._scenes.erase(asset)
func run()->void:
	create_timer(90).timeout.connect(func():push_error("append runtime timeout");quit(2))
	var initial:Array=[box("anchor",Vector3(4,1,4),Vector3(2,2,2))]
	for i in 18:initial.append(box("initial_%d"%i,Vector3(36+i*8,1,12),Vector3(2,2,2)))
	var world:=scene(initial);Stream.sync(world.map,world.host,Vector3.ZERO)
	var anchor:Node=world.map.get_meta("stream_meshes").anchor
	var anchor_body:Node=world.map.get_meta("stream_bodies").anchor
	var added:=box("added",Vector3(12,1,4),Vector3(2,2,2))
	check(Stream.append_specs(world.map,[added]).ok,"same chunk append accepted")
	check(not Stream.nearby_collision_ready(world.map,Vector3(12,2,4)),"published near spec without attached body is not collision-ready")
	check(Stream.nearby_collision_ready(world.map,Vector3(4,2,4)),"pending spec outside capsule neighborhood does not block local player")
	await settle(world,Vector3.ZERO)
	check(Stream.nearby_collision_ready(world.map,Vector3(12,2,4)),"settled new body is collision-ready")
	check(world.map.get_meta("stream_meshes").has("added"),"same chunk append becomes visible")
	check(world.map.get_meta("stream_meshes").anchor==anchor and world.map.get_meta("stream_bodies").anchor==anchor_body,"same chunk append preserves existing node identities")
	await ray(world,Vector3(12,1,4),"added")
	# Exercise the detached imported-node transform collection used by the service.
	var holder:=Node3D.new();holder.position=Vector3(20,1,4);holder.rotation.y=.31
	var nested:=Node3D.new();nested.position=Vector3(1,0,0);holder.add_child(nested)
	var imported:=MeshInstance3D.new();imported.name="source";imported.mesh=BoxMesh.new();nested.add_child(imported)
	imported.set_meta("extras",{"uuid":"ordinary__nested__source"})
	var ordinary:Array=[];Deferred._collect(holder,Transform3D.IDENTITY,ordinary)
	var expected_pose:Transform3D=holder.transform*nested.transform*imported.transform
	check(ordinary.size()==1 and ordinary[0].uuid=="ordinary__nested__source" and ordinary[0].transform.is_equal_approx(expected_pose),"detached ordinary hierarchy keeps namespace and composed transform")
	var fixture:Dictionary={"id":"source_door","kind":"door","pivot":[-.5,0,0],"angle":90.,"open":.5}
	imported.set_meta("extras",{"uuid":"fixture__source","fixture":fixture})
	var fixture_specs:Array=[];Deferred._collect(holder,Transform3D.IDENTITY,fixture_specs)
	var composed:Transform3D=preload("res://scripts/world3d/building_fixtures.gd").pose(fixture_specs[0].closed_transform,fixture,.5)
	check(composed.is_equal_approx(expected_pose),"nested fixture closed transform is prepared from composed world pose")
	holder.free();check(Stream.append_specs(world.map,ordinary).ok,"ordinary complete instance appended")
	await settle(world,Vector3.ZERO);await ray(world,expected_pose.origin,ordinary[0].uuid)
	# Interrupt selection and job application, append while a target is unsettled,
	# then reverse direction. No old pending work may disappear.
	for step in 6:
		var target:=Vector3(65 if step%2==0 else 97,0,0)
		Stream.sync(world.map,world.host,target,1)
		var item:=box("during_%d"%step,Vector3(67+step*3,1,20),Vector3(2,2,2))
		check(Stream.append_specs(world.map,[item]).ok,"append during interrupted target %d"%step)
		Stream.sync(world.map,world.host,target,1)
	await settle(world,Vector3(65,0,0));equal_residency(world,Vector3(65,0,0),"interrupted append")
	await settle(world,Vector3.ZERO);equal_residency(world,Vector3.ZERO,"return after interrupted append")
	var count:int=world.map.get_meta("stream_library").size()
	check(not Stream.append_specs(world.map,[added]).ok and world.map.get_meta("stream_library").size()==count,"duplicate rejection leaves library unchanged")
	world.host.free()
	# Ground at chunk 34 is beyond the building radius of a viewer in chunk 0.
	# A new whole imported structure spanning 31..34 makes this OLD support visible.
	var support:=box("support",Vector3(1104,-.5,16),Vector3(30,1,30),true)
	var support_world:=scene([support]);Stream.sync(support_world.map,support_world.host,Vector3.ZERO)
	check(not support_world.map.get_meta("stream_meshes",{}).has("support"),"distant support starts nonresident")
	var structure:=box("long_building__mesh",Vector3(1050,8,16),Vector3(120,16,8))
	check(Stream.append_specs(support_world.map,[structure]).ok,"whole imported structure registers supports")
	await settle(support_world,Vector3.ZERO)
	check(support.render_dependents.size()==1,"support dependency occurs exactly once")
	check(support_world.map.get_meta("stream_meshes",{}).has("support"),"existing support newly required by appended building becomes visible")
	equal_residency(support_world,Vector3.ZERO,"new building supporting old ground")
	support_world.host.free()
	# Conversely a newly appended broad support can expand an OLD building's
	# drawing bounds into the viewer's radius without moving the viewer.
	var old_structure:=box("old_building__mesh",Vector3(1104,8,16),Vector3(8,16,8))
	var reverse:=scene([old_structure]);Stream.sync(reverse.map,reverse.host,Vector3.ZERO)
	check(not reverse.map.get_meta("stream_meshes",{}).has(old_structure.uuid),"distant building starts nonresident")
	var broad:=box("broad_support",Vector3(1060,-.5,16),Vector3(120,1,30),true)
	check(Stream.append_specs(reverse.map,[broad]).ok,"new support can expand existing building bounds")
	await settle(reverse,Vector3.ZERO)
	check(reverse.map.get_meta("stream_meshes",{}).has(old_structure.uuid),"existing building affected by new support becomes visible")
	equal_residency(reverse,Vector3.ZERO,"new ground supporting old building")
	reverse.host.free()
	await guards()
	await continuous_appends()
	await scheduler()
	await shared_near_far_model()
	print("STREAM_APPEND_RUNTIME_FINISHED failures=",failures);quit(1 if failures else 0)
