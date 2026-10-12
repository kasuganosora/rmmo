extends "res://tools/test_transfer_loading_gpu.gd"
## Root runs this with run_godot_background.py; only temporary maps are written.
const WorldScript=preload("res://scripts/world3d/world_3d.gd")
const Blueprint=preload("res://scripts/world3d/building_blueprint.gd")
var indoor:=Vector3.ZERO
var member_count:=0

func make_building_map(path:String,broken:bool=false)->bool:
	var plan:Dictionary=Blueprint.generate({"template":"house","floors":2,"rooms_per_floor":1})
	if not plan.ok:return false
	var doc:=Doc.new()
	var instance:Dictionary={"version":Blueprint.VERSION,"parameters":plan.parameters,"position":[31.0,0.0,0.0],"yaw":0.0,"parts":{},"signatures":{}}
	for source:Dictionary in plan.records:
		var r:Dictionary=source.duplicate(true);r.uuid="house_part_%d"%doc.records.size();r.position[0]+=31.0;r.building.id="home"
		instance.parts[r.building.part]=r.uuid;instance.signatures[r.building.part]=Blueprint.geometry_signature(r);doc.records.append(r)
	member_count=doc.records.size()
	# Genuine recipe room centre avoids a partition, door sweep or staircase.
	var centre:Array=plan.rooms[0].center
	indoor=Vector3(float(centre[0])+31,.9,float(centre[2]))
	if broken:doc.records.pop_back()
	doc.add_box("ground",Vector3(30,-.2,0),Vector3(160,.2,100))
	doc.add_box("ground",Vector3(320,-.1,0),Vector3(32,.2,32))
	doc.add_box("block",Vector3(328,1,4),Vector3(2,2,2))
	doc.map_meta={"spawn":[indoor.x,indoor.y,indoor.z],"map_ref":"building_entry_"+path.get_file(),"building_instances":{"home":instance}}
	if doc.save(path)!=OK:return false
	var source:RefCounted=Snapshot.read_file(path)
	var native:int=Cursor.native_root(source._data)
	var hydrated:Dictionary=Cursor.hydrate_references(source._data.nodes[native].extras,path,Paths.external_root())
	return hydrated.get("ok",false) and Index.build(path,Paths.external_root(),hydrated.extras.rmmo_records,source._signature).get("ok",false)

func move_to(path:String,point:Vector3,condition:Callable=Callable())->bool:
	var result:Dictionary={"done":false,"ok":false}
	execute(path,point,result,condition)
	var frozen:=true
	while not result.done:
		if world._transfer_pending:frozen=frozen and world._player.input_locked and not world._player.is_physics_processing()
		await process_frame
	check(frozen,"input and gravity remain frozen throughout covered transfer")
	if result.ok:
		check(world._building_entry.report().state=="active","real destination first frame receives authority activation")
		check(world._player.global_position.distance_to(point)<.15,"authority activates the requested physical destination")
		check(world._building_transfer==null and world.get_node_or_null("TransferLoading")==null,"completed transfer releases ticket and cover")
	return result.ok

func run()->void:
	create_timer(300).timeout.connect(func():print("BUILDING_ENTRY_TIMEOUT");quit(2))
	WorldScript.building_readiness_enabled=true
	WorldScript.navigation_background_enabled=true;WorldScript.wind_background_enabled=true
	preload("res://tools/world3d_test_character.gd").ensure(self)
	directory=Paths.cache_directory("building_entry_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(directory)
	var a:=directory.path_join("a.gltf");var b:=directory.path_join("b.gltf");var unknown:=directory.path_join("unresolved.gltf")
	check(make_building_map(a),"write first complete cross-chunk building fixture")
	check(make_building_map(b),"write second map for isolated-physics transfer")
	check(make_building_map(unknown,true),"write allowed hand-edited building with missing semantic member")
	if failures:quit(1);return
	var session:=root.get_node("GameSession")
	session.world3d_map_path=a;session.world3d_spawn=indoor
	session.spawn_data={"character":session.selected_character.duplicate(true),"equipment":[],"world_mode":"world3d"}
	session.go_world_3d()
	while true:
		await process_frame
		if is_instance_valid(current_scene) and current_scene.has_meta("entry_loading_error"):
			check(false,"entry: "+str(current_scene.get_meta("entry_loading_error")));quit(1);return
		if is_instance_valid(current_scene) and current_scene.has_node("FailActions"):
			check(false,"loader: "+str(current_scene.status_label.text));quit(1);return
		if is_instance_valid(current_scene) and current_scene.has_method("is_world_ready") and current_scene.is_world_ready() and not session._world_transition_active:break
	world=current_scene
	var first:Dictionary=world._building_entry.report()
	check(first.state=="active" and first.membership=="indoor" and first.building_members.size()==member_count,"initial production entry verifies every cross-chunk building member")
	check(not world._building_entry.residency_pins.is_empty(),"indoor activation retains complete-building collision residency")
	check(first.token.map_revision==FileAccess.get_sha256(a),"authority revision is full source SHA, independent of selected cook identity")
	check(not world._player.input_locked and world._player.is_physics_processing(),"initial authority activation releases movement and physics only after rendered frame")
	var fixture:Dictionary=world.list_building_components("home")[0]
	var fixture_id:String=fixture.id
	var changed:Dictionary=world.set_building_component_state("home",fixture_id,1.0-float(fixture.open),0)
	check(changed.ok and changed.authority_state.building.state_watermark==1,"existing World API publishes ordered authoritative fixture state")
	var outside:=Vector3(0,.8,4)
	check(await move_to(a,outside),"same-map indoor-to-outdoor transaction")
	check(await move_to(a,indoor),"same-map re-entry waits for full building and state")
	check(world._building_entry.report().applied_state_sequence==1,"re-entry applies persisted runtime door state")
	var before:Vector3=world._player.global_position
	check(not await move_to(a,Vector3(0,40,4)),"unsupported target is denied")
	check(world._player.global_position.is_equal_approx(before) and not world._player.input_locked and world._building_entry.report().state=="active","failed target revalidates original support and fresh recovery ticket")
	check(not await move_to(unknown,indoor),"unknown building membership never defaults outdoors")
	check(world._map_path==a and not world._player.input_locked,"unknown cross-map target safely recovers original map")
	check(await move_to(b,indoor),"cross-map production transfer applies membership before preparing geometry")
	var stale:Dictionary=world._building_entry.issued.ticket.duplicate(true)
	check(await move_to(b,outside),"next movement transaction creates independent ticket")
	check(not world._building_authority().validate(stale).ok,"old completion cannot activate after successful transfer")
	var cancelled:Dictionary={"done":false,"ok":false};var latest:Dictionary={"done":false,"ok":false}
	execute(b,indoor,cancelled,Callable());execute(b,Vector3(4,.8,4),latest,Callable())
	while not latest.done:await process_frame
	check(cancelled.done and not cancelled.ok and latest.ok,"latest same-map request cancels previous attempt and revalidates recovery")
	var queue:Node=world._map_root.get_node_or_null("DeferredAssets")
	var clean:=true
	for id:String in queue._demands:
		if id.begins_with("building_entry:") or id=="transfer_landing":clean=false
	check(clean,"outdoor completion releases building and temporary landing demands")
	await respawn_cases(b)
	await cleanup_world()
	print("BUILDING_ENTRY_GPU_FINISHED failures=",failures," fixture=",directory)
	quit(1 if failures else 0)

func run_respawn(result:Dictionary)->void:
	result.ok=await world._combat.request_respawn();result.done=true

func respawn_cases(path:String)->void:
	var server:=root.get_node("MockServer")
	var queue:Node=world._map_root.get_node_or_null("DeferredAssets")
	var destination:=Vector3(320,.9,4)
	check(not queue.ensure_geometry(EntryPlan.create(destination).core_clip,"test_respawn_pending"),"respawn target begins outside loaded dependency cells")
	queue.release_demand("test_respawn_pending")
	var actions:Array=[];server.combat_engine._damage_player(9999,actions,"",false);world._combat._apply({"actions":actions})
	world._combat.respawn_point=destination
	check(not server.combat_stats.player_alive() and not await world.transfer_map(path,destination),"ordinary transfer cannot grant dead-player teleport permission")
	check(not world._combat.respawn(),"legacy synchronous bool cannot pretend the async respawn completed")
	var blocker:=StaticBody3D.new();var shape:=CollisionShape3D.new();shape.shape=BoxShape3D.new();shape.shape.size=Vector3(1,2,1);blocker.add_child(shape);world.add_child(blocker);blocker.global_position=destination
	await physics_frame;await process_frame
	check(not await world._combat.request_respawn() and not server.combat_stats.player_alive() and world._revive.visible,"occupied respawn fails without restoring HP or hiding death UI")
	blocker.free();await physics_frame;await process_frame
	var cancelled:Dictionary={"done":false,"ok":false};run_respawn(cancelled)
	check(not await world._combat.request_respawn(),"duplicate respawn request is rejected while preparation owns the ticket")
	check(world.cancel_respawn_preparation(),"pending respawn can be cancelled before logical commit")
	while not cancelled.done:await process_frame
	check(not cancelled.ok and not server.combat_stats.player_alive() and world._revive.visible,"cancelled respawn preserves death and retry UI")
	var result:Dictionary={"done":false,"ok":false};run_respawn(result)
	var alive_early:=false
	while not result.done:
		alive_early=alive_early or server.combat_stats.player_alive()
		await process_frame
	check(result.ok and not alive_early and server.combat_stats.player_alive() and not world._player.input_locked,"HP and movement commit only after ready destination first-frame authorization")
	check(world._player.global_position.distance_to(destination)<.1,"async respawn enters the prepared target cell")
