extends SceneTree
const Queue=preload("res://scripts/world3d/resource_retirement.gd")
const Budget=preload("res://scripts/world3d/frame_work_budget.gd")
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
const Navigation=preload("res://scripts/world3d/world_navigation.gd")
const Batch=preload("res://scripts/world3d/ground_batcher.gd")
const Proxy=preload("res://scripts/world3d/distant_building_proxy.gd")
var checks:=0
var failures:Array[String]=[]
var cases:Array=[]
var output:=""
class World extends "res://scripts/world3d/world_3d.gd":
	func _ready()->void:set_process(false);set_physics_process(false)
	func drive_prepared_disposal(context:Dictionary)->bool:
		# Same await/failure branch as transfer_map, on the actual World instance.
		# In particular failure runs while owner/stage/cover exit is still on-stack.
		if not await _detach_outgoing_bodies(context):return _outgoing_disposal_failed(context)
		return true
class Player extends CharacterBody3D:
	var input_locked:=true
	var geometry_blocked:=true
class Combat extends Node:
	var actors:Dictionary={}
class Cover extends CanvasLayer:
	var failed:=false
	func is_opaque_drawn()->bool:return true
	func show_failure(_reason:String,_action:Callable)->void:failed=true
class Cutaway extends RefCounted:
	var map:Node
	func bind(value:Node)->void:map=value
class Camera extends Node3D:
	var cutaway:=Cutaway.new()
class Candles extends Node3D:
	var map:Node
	func bind_map(value:Node)->void:map=value
class Body extends StaticBody3D:
	var journal:Dictionary
	func _exit_tree()->void:
		journal.exits+=1;journal.frames[Engine.get_process_frames()]=true
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures.append(label)
func fixture(count:int=32)->Dictionary:
	var world:=World.new();root.add_child(world)
	var map:=Node3D.new();world.add_child(map);world._map_root=map
	map.set_meta("stream_meshes",{});map.set_meta("stream_bodies",{});map.set_meta("stream_library",[])
	var records:Array=[{"uuid":"record","values":PackedInt32Array([2,4,8])}]
	map.set_meta("extras",{"rmmo_records":records});map.set_meta("runtime_record_metadata_cpu_only",true)
	var deferred:=Deferred.new();deferred.name="DeferredAssets";deferred._reference_index={"rows":[]};map.add_child(deferred);deferred.set_process(false)
	var batch:=Batch.new();map.add_child(batch);batch.set_process(false)
	var proxy:=Proxy.new();proxy.name="DistantBuildingProxy";map.add_child(proxy);proxy.set_process(false)
	# A real prefab-source path, independent of batcher.groups.
	var material:=StandardMaterial3D.new();var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,BoxMesh.new().get_mesh_arrays());mesh.surface_set_material(0,material)
	for i:int in 2:
		var source:=MeshInstance3D.new();source.mesh=mesh;source.position=Vector3(300+i*2,0,0)
		source.set_meta("ground_batch_record",{"building":{"id":"far"},"house_prefab":{}})
		map.add_child(source);map.get_meta("stream_meshes")[str(i)]=source
	var navigation:=Navigation.new();world.add_child(navigation);navigation.set_process(false);navigation.set_physics_process(false);world._navigation=navigation
	world._bind_deferred_geometry(map,navigation);world._bind_navigation_lifetime(navigation,map)
	world._player=Player.new();world.add_child(world._player);world._player.set_physics_process(false)
	world._camera=Camera.new();world.add_child(world._camera);world._camera.cutaway.bind(map)
	world._house_candles=Candles.new();world.add_child(world._house_candles);world._house_candles.bind_map(map)
	world._combat=Combat.new();world.add_child(world._combat);world._combat.set_physics_process(false)
	world._weather=preload("res://scripts/world3d/weather_controller.gd").new();world.add_child(world._weather)
	world._outline=preload("res://scripts/world3d/occlusion_outline.gd").new();world.add_child(world._outline)
	world._outline.mask=SubViewport.new();world._outline.add_child(world._outline.mask);world._outline.mask.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	world._outline.overlay=ColorRect.new();world._outline.add_child(world._outline.overlay);world._outline.overlay.show()
	world._status=Label.new();world.add_child(world._status)
	world._ready_for_play=true;world._transfer_pending=true
	var journal:Dictionary={"exits":0,"frames":{},"map_borrow":false}
	var bodies:Array[Node]=[];var ids:Array[int]=[]
	for i:int in count:
		var body:=Body.new();body.journal=journal;body.position=Vector3(i*2,0,0);world.add_child(body)
		var shape:=CollisionShape3D.new();shape.shape=BoxShape3D.new();body.add_child(shape)
		bodies.append(body);ids.append(body.get_instance_id());ids.append(shape.get_instance_id());map.get_meta("stream_bodies")[str(i)]=body
	var first:WeakRef=weakref(bodies[0]);map.tree_exiting.connect(func():journal.map_borrow=first.get_ref()!=null and map.get_meta("extras").rmmo_records[0].values==PackedInt32Array([2,4,8]))
	var cover:=Cover.new();world.add_child(cover)
	var viewport:=SubViewport.new();viewport.own_world_3d=true;viewport.disable_3d=true;world.add_child(viewport)
	var stage:=Node3D.new();viewport.add_child(stage)
	var target:=Node3D.new();stage.add_child(target);viewport.set_meta("transfer_prepared_map",weakref(target))
	var target_deferred:=Deferred.new();target_deferred.name="DeferredAssets";target.add_child(target_deferred);target_deferred.begin_scene_handoff()
	var target_navigation:=Navigation.new();world.add_child(target_navigation);target_navigation.set_process(false);target_navigation.set_physics_process(false)
	return {"world":world,"map":map,"deferred":deferred,"batch":batch,"proxy":proxy,"navigation":navigation,"bodies":bodies,"ids":ids,"journal":journal,"records":records,"cover":cover,"viewport":viewport,"target":target,"target_deferred":target_deferred,"target_navigation":target_navigation}
func start_detach(f:Dictionary,state:Dictionary)->void:
	state.ok=await f.world.drive_prepared_disposal(f.context);state.done=true
func drain()->void:
	var service:=Queue._service();service.set_process(false)
	var turns:=0
	while not service.pending.is_empty() and turns<1000:
		if service._advance(service.pending[0],0):service._finish_front()
		turns+=1
	check(service.pending.is_empty(),"held node and donor FIFO drains after terminal decision")
func complete_case()->void:
	var f:=fixture();var world:Node=f.world;var old_combat:WeakRef=weakref(world._combat)
	f.proxy.clear();var ordinary_ticks:int=f.proxy.profile.fallback_ticks;f.proxy.tick(Vector3.ZERO)
	check(not f.proxy._closed and f.proxy.profile.fallback_ticks==ordinary_ticks+1,"ordinary proxy clear remains reusable with real prefab-source scanning")
	check(not f.proxy._job.is_empty(),"eligible far-source fixture really starts a background proxy job before permanent close")
	var before:int=f.deferred.published.get_connections().size()
	f.context=world._prepare_outgoing_disposal(f.cover,f.viewport,f.target_navigation)
	check(f.context.hold!=null,"real World entry reserves held FIFO on supported engine")
	check(not world._ready_for_play and not world._outgoing_disposal.is_empty() and world._player.input_locked and not world._player.is_physics_processing(),"permanent point locks readiness and preserves paused player")
	check(f.map.process_mode==Node.PROCESS_MODE_DISABLED and f.deferred._cancelled and not f.deferred._active,"old map automatic processing and Deferred producer are sealed")
	check(f.navigation._terminal_state=="cancelled" and f.deferred.published.get_connections().size()<before,"navigation callbacks are terminal and old publication subscription disconnects")
	check(world._weather._map_observation_suspended and world._outline._map_observation_suspended and world._outline.mask.render_target_update_mode==SubViewport.UPDATE_DISABLED and not world._outline.overlay.visible,"actual World commit suspends Weather direct callbacks and independent Outline mask")
	check(world._camera.cutaway.map==null and world._house_candles.map==null,"cutaway and candles release old map before any body exit")
	var old_profile:Dictionary=f.proxy.profile.duplicate();f.proxy.tick(Vector3.ZERO);f.proxy._poll();f.proxy._process(1.)
	check(f.proxy._job.is_empty() and f.proxy.profile==old_profile,"permanent proxy cannot restart from prefab sources or explicit poll/tick")
	var ledger:RefCounted=Budget.shared();ledger.covered_limits=Budget.COVERED.duplicate();ledger.covered_limits.retire=1
	ledger.record(Engine.get_process_frames(),"retire",1000)
	Queue._service().set_process(false) # Keep the held FIFO inert; the driver still uses the real shared lane.
	var state:Dictionary={"done":false,"ok":false};start_detach(f,state)
	check(not state.done and f.journal.exits==0,"pre-consumed retire lane yields with zero body detach work")
	var frames:=0
	while not state.done and frames<256:
		world._process(.25);world._apply_residency(1);world._guard_deferred_geometry();f.deferred._process(1.)
		if is_instance_valid(f.navigation):f.navigation._baked()
		check(old_combat.get_ref()!=null and world._combat.actors.is_empty(),"radar Combat borrow stays valid throughout sliced detach")
		check(f.target.get_parent()!=world and f.target.get_world_3d()!=world.get_world_3d(),"target stays isolated while old topology is partial")
		Queue._service().set_process(false)
		await process_frame;frames+=1
	check(state.done and state.ok and f.journal.exits==f.bodies.size() and f.journal.frames.size()>1,"real World driver detaches every body exactly once over multiple frames")
	check(f.bodies.all(func(n:Node)->bool:return is_instance_valid(n) and n.get_parent()==null and not n.is_inside_tree()),"completed cursor leaves all bodies individually detached and retained")
	check(world._detach_outgoing_map(f.context),"actual World map phase detaches its unchanged owned MapRoot synchronously")
	check(f.journal.map_borrow,"final MapRoot exit still borrows retained body prefix and CPU records")
	check(f.context.hold.commit(),"checked commit accepts the actual final independent root state")
	world._map_root=f.target
	check(world._adopt_transfer_target(f.target,f.target_deferred,f.cover),"actual World adoption succeeds only after all old roots leave")
	world._navigation=f.target_navigation
	world._combat.free();world._combat=Combat.new();world.add_child(world._combat)
	world._finish_outgoing_disposal(f.context)
	check(not world._weather._map_observation_suspended and not world._outline._map_observation_suspended and world._outline.mask.render_target_update_mode==SubViewport.UPDATE_ALWAYS,"actual target tail resumes observer state after new Combat exists")
	check(world._outgoing_disposal.is_empty() and world._ready_for_play and world._player.input_locked,"target setup restores world tick state while reveal still owns player unlock")
	cases.append({"case":"complete","profile":world.get_meta("body_detach_profile",{}),"held":f.context.hold.status()})
	drain();check(f.ids.all(func(id:int)->bool:return instance_from_id(id)==null),"all old body identities finally retire")
	world._ready_for_play=false;world.free();await process_frame;drain()
func cancel_case(kind:String)->void:
	var f:=fixture(8);var world:Node=f.world
	f.context=world._prepare_outgoing_disposal(f.cover,f.viewport,f.target_navigation)
	var ledger:RefCounted=Budget.shared();ledger.record(Engine.get_process_frames(),"retire",1000)
	Queue._service().set_process(false) # Keep the held FIFO inert; the driver still uses the real shared lane.
	var state:Dictionary={"done":false,"ok":false};start_detach(f,state)
	check(not state.done,"interruption fixture really pauses on a denied shared lane")
	match kind:
		"remove":root.remove_child(world)
		"free":world.free()
		"cover":f.cover.free()
		"stage":f.viewport.free()
	check(state.done and not state.ok,"real owner/cover exit resolves the awaiting World helper before its script can disappear: "+kind)
	if is_instance_valid(world):world._outgoing_disposal_failed(f.context)
	await process_frame;await process_frame
	drain()
	check(f.ids.all(func(id:int)->bool:return instance_from_id(id)==null),"interrupted irreversible disposal drains all old bodies: "+kind)
	if is_instance_valid(world):
		check(world._player.input_locked and not world._ready_for_play and not world._outgoing_disposal.is_empty(),"cancel never restores old gameplay or unlocks the player: "+kind)
		world.free()
	await process_frame;drain()
func adopted_body_case()->void:
	var f:=fixture(3);var world:Node=f.world
	f.context=world._prepare_outgoing_disposal(f.cover,f.viewport,f.target_navigation)
	Budget.shared().record(Engine.get_process_frames(),"retire",1000);Queue._service().set_process(false)
	var state:Dictionary={"done":false,"ok":false};start_detach(f,state)
	var foreign:=Node3D.new();var borrowed:Node=f.bodies[0];world.remove_child(borrowed);foreign.add_child(borrowed)
	for i:int in 6:
		if state.done:break
		await process_frame
	check(state.done and not state.ok and f.context.reason=="body_adopted","driver rejects a borrowed body under a live off-tree foreign parent")
	world._outgoing_disposal_failed(f.context);await process_frame;await process_frame;drain()
	check(is_instance_valid(borrowed) and borrowed.get_parent()==foreign,"held abort never destroys the foreign borrow during actual World cleanup")
	check(not world._ready_for_play and world._player.input_locked,"foreign ownership refusal cannot activate target or resume old gameplay")
	world.free();foreign.free();await process_frame;drain()
func adopted_map_case()->void:
	var f:=fixture(3);var world:Node=f.world
	f.context=world._prepare_outgoing_disposal(f.cover,f.viewport,f.target_navigation)
	Budget.shared().record(Engine.get_process_frames(),"retire",1000);Queue._service().set_process(false)
	var state:Dictionary={"done":false,"ok":false};start_detach(f,state)
	for i:int in 8:
		if state.done:break
		Queue._service().set_process(false);await process_frame
	check(state.done and state.ok,"map ownership fixture completes the real body phase before final map step")
	var foreign:=Node3D.new();world.remove_child(f.map);foreign.add_child(f.map)
	check(not world._detach_outgoing_map(f.context) and f.context.reason=="map_adopted" and f.map.get_parent()==foreign,"post-yield map phase refuses to steal an off-tree foreign MapRoot")
	world._outgoing_disposal_failed(f.context);await process_frame;await process_frame;drain()
	check(is_instance_valid(f.map) and f.map.get_parent()==foreign,"irreversible World cleanup preserves adopted MapRoot through held abort")
	check(world._player.input_locked and not world._ready_for_play,"map ownership refusal cannot reveal or activate target")
	world._map_root=null;world.free();foreign.free();await process_frame;drain()
func unsupported_case()->void:
	var f:=fixture(3);var world:Node=f.world
	f.context=world._prepare_outgoing_disposal(f.cover,f.viewport,f.target_navigation)
	check(f.context.hold==null and not f.context.sliced_nodes,"default old engine declines reservation and native detached cursor")
	var state:Dictionary={"done":false,"ok":false};start_detach(f,state)
	check(state.done and state.ok and f.journal.exits==3,"unsupported engine preserves immediate synchronous fallback without a frame yield")
	check(f.ids.all(func(id:int)->bool:return instance_from_id(id)==null),"unsupported fallback frees old bodies using original semantics")
	check(world._detach_outgoing_map(f.context),"unsupported engine retains synchronous map free at the same transaction boundary")
	world._map_root=f.target;world._navigation=f.target_navigation
	check(world._adopt_transfer_target(f.target,f.target_deferred,f.cover),"fallback target still adopts through the normal World transaction")
	world._combat.free();world._combat=Combat.new();world.add_child(world._combat);world._finish_outgoing_disposal(f.context)
	world._ready_for_play=false;world.free();await process_frame;drain()
func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	Budget.enabled=true
	create_timer(90.).timeout.connect(func():push_error("body detach integration timeout");quit(2))
	if "--map-only" in OS.get_cmdline_user_args():await adopted_map_case()
	elif "--unsupported" in OS.get_cmdline_user_args():await unsupported_case()
	else:
		await complete_case()
		if not "--red" in OS.get_cmdline_user_args():
			for kind:String in ["remove","free","cover","stage"]:await cancel_case(kind)
			await adopted_body_case()
			await adopted_map_case()
	var report:Dictionary={"checks":checks,"failures":failures,"cases":cases,"scope":"real World disposal helpers; no real-map performance claim; MapRoot detach remains synchronous"}
	if not output.is_empty():FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("WORLD_BODY_DETACH58 ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)
