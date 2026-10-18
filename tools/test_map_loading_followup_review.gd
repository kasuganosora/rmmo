extends SceneTree
## Native map entry and residency observer handoff, using external temporary maps.
const Loader=preload("res://scripts/world3d/map_loader.gd")
const Doc=preload("res://scripts/world3d/world_document.gd")
const Directory=preload("res://scripts/world3d/map_dependency_index.gd")
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Queue=preload("res://scripts/world3d/deferred_asset_loader.gd")
const Residency=preload("res://scripts/world3d/asset_residency.gd")
const DEFAULT=Vector3(0,.9,4)
const MAP_SPAWN=Vector3(512,.9,4)
var failures:=0
var checks:=0
var receipt:Dictionary={"entries":[]}
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func load_at(path:String,origin:Variant,near:bool)->Dictionary:
	var loader:=Loader.new();loader.near_first=near;root.add_child(loader)
	loader.start(path,origin)
	var result:Array=await loader.finished
	var at:Vector3=loader._entry_origin
	var scene:Node=result[0]
	var success:bool=scene!=null
	var loaded_ids:Array=[];var plan:Dictionary={};var index_hit:=false
	if scene!=null:
		for spec:Dictionary in scene.get_meta("stream_library",[]):loaded_ids.append(str(spec.uuid))
		plan=scene.get_meta("entry_plan",{})
		index_hit=bool(scene.get_meta("load_profile",{}).get("reference_index_hit",false))
		scene.free()
	while is_instance_valid(loader):await process_frame
	var observation:={"origin":str(at),"near_first":near,"ids":loaded_ids,"plan_cell":str(plan.get("cell")),"index_hit":index_hit,"error":str(result[2])}
	receipt.entries.append(observation)
	return {"at":at,"ids":loaded_ids,"plan":plan,"ok":success,"index_hit":index_hit,"error":str(result[2])}
func run()->void:
	create_timer(120).timeout.connect(func():quit(2))
	var session:Node=root.get_node("GameSession");var old_spawn:Vector3=session.world3d_spawn
	session.world3d_spawn=DEFAULT
	var folder:=Paths.cache_directory("blind_followup_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	var path:=folder.path_join("map.gltf")
	var doc:=Doc.new();doc.map_meta.spawn=[MAP_SPAWN.x,MAP_SPAWN.y,MAP_SPAWN.z]
	var near_id:=doc.add_box_silent("ground",Vector3(0,-.1,4),Vector3(16,.2,16))
	var far_id:=doc.add_box_silent("ground",Vector3(512,-.1,4),Vector3(16,.2,16))
	check(doc.save(path)==OK,"write isolated native map with a different authored spawn")
	var source_sha:=FileAccess.get_sha256(path)
	var cold:=await load_at(path,DEFAULT,true)
	check(cold.ok and not cold.index_hit,"first entry exercises missing dependency index and its rebuild")
	check(cold.at==DEFAULT and cold.plan.get("origin")==DEFAULT,"cold entry preserves an explicit default-coordinate destination")
	check(near_id in cold.ids and not far_id in cold.ids,"cold rebuild prepares the requested district")
	check(Directory.build(path,Paths.external_root(),doc.records,source_sha).ok,"build native dependency index for exact entry selection")
	var explicit_default:=await load_at(path,DEFAULT,true)
	check(explicit_default.ok,"explicit default-coordinate entry loads")
	check(explicit_default.at==DEFAULT,"explicit (0,0.9,4) must not become the map spawn")
	check(explicit_default.plan.get("origin")==DEFAULT and explicit_default.plan.get("cell")==Vector2i.ZERO,"entry plan belongs to the explicitly requested destination")
	check(near_id in explicit_default.ids and not far_id in explicit_default.ids,"initial loaded closure contains the requested district instead of the authored spawn district")
	var implicit:=await load_at(path,null,true)
	check(implicit.ok and implicit.at==MAP_SPAWN,"omitted destination keeps authored-spawn fallback")
	check(far_id in implicit.ids and not near_id in implicit.ids,"implicit fallback selects the authored spawn closure")
	var other:=Vector3(-32,.9,4)
	var explicit_other:=await load_at(path,other,true)
	check(explicit_other.ok and explicit_other.at==other and explicit_other.plan.get("cell")==Vector2i(-1,0),"other explicit destinations retain exact negative-cell selection")
	var complete:=await load_at(path,DEFAULT,false)
	check(complete.ok and complete.at==DEFAULT,"full loading path also retains an explicit default-coordinate destination")
	check(near_id in complete.ids and far_id in complete.ids,"full loading still returns the complete map")
	check(FileAccess.get_sha256(path)==source_sha,"entry choices never rewrite map author bytes")
	session.world3d_spawn=old_spawn
	await test_records()
	for i in 8:await process_frame
	receipt.checks=checks;receipt.failures=failures
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			var file:=FileAccess.open(arg.trim_prefix("--out="),FileAccess.WRITE)
			if file!=null:file.store_string(JSON.stringify(receipt,"\t"))
	print("MAP_LOADING_FOLLOWUP checks=",checks," failures=",failures)
	quit(1 if failures else 0)
func test_records()->void:
	var scene:=Node3D.new();root.add_child(scene)
	var existing:={"uuid":"initial","kind":"asset","asset_path":"initial.glb"}
	scene.set_meta("extras",{"rmmo_records":[existing]})
	scene.set_meta("stream_library",[])
	var queue:=Queue.new();scene.add_child(queue);queue.activate(scene);queue.set_process(false)
	var record:={"uuid":"later","kind":"asset","asset_path":"later.glb","material_overrides":{}}
	var compact:={"uuid":"later","rmmo_ref":{"uri":"res/later.rmres","sha256":"a".repeat(64)}}
	var entry:={"record_index":0,"compact_record":compact,"bounds":AABB(Vector3(500,0,0),Vector3.ONE),"classification":"spatial","reason":"asset","asset_path":"later.glb","group_id":"","memory_bytes":1}
	queue._reference_index={"extras":{"rmmo_records":[compact]},"rows":[{"uuid":"later","order":0,"classification":"spatial","reason":"asset","group_id":"","asset_path":"later.glb","bounds":entry.bounds,"memory_bytes":1}],"models":{}}
	queue._note_runtime_record({"record":record,"reference_entry":entry})
	check(queue.has_method("runtime_record"),"publication exposes the already verified record without another author scan")
	if queue.has_method("runtime_record"):
		check(is_same(queue.runtime_record("initial"),existing),"activation indexes exact existing record identity")
		check(is_same(queue.runtime_record("later"),record),"publication lookup owns the same verified record as runtime metadata")
		check(queue.runtime_record("missing").is_empty(),"unpublished UUID cannot acquire another record")
	var residency:=Residency.new();scene.add_child(residency);residency.configure(scene,scene,queue);residency.set_process(false)
	residency._record_pins.erase("later")
	residency.observe([{"uuid":"later__mesh","mesh":BoxMesh.new(),"transform":Transform3D.IDENTITY,"chunk":Vector2i.ZERO,"chunk_min":Vector2i.ZERO,"chunk_max":Vector2i.ZERO,"extras":{}}])
	receipt.resident_record={"pin":residency._resident.later.pinned,"records":scene.get_meta("extras").rmmo_records.duplicate(true),"pins":residency._record_pins.duplicate()}
	check(residency._resident.later.pinned=="material_overrides","record lookup retains paint retirement protection")
	check(residency._record_paths.later=="later.glb","record lookup preserves original asset path")
	var legacy:={"uuid":"legacy","kind":"asset","asset_path":"legacy.glb","event":{}}
	scene.get_meta("extras").rmmo_records.append(legacy)
	queue._runtime_record_ids.legacy=true
	residency._catalog.legacy=entry
	residency.observe([{"uuid":"legacy__mesh","mesh":BoxMesh.new(),"transform":Transform3D.IDENTITY,"chunk_min":Vector2i.ZERO,"chunk_max":Vector2i.ZERO,"extras":{}}])
	check(residency._resident.legacy.pinned=="event" and residency._record_paths.legacy=="legacy.glb","legacy membership values use conservative author fallback with the same protections")
	residency._catalog.missing=entry
	residency.observe([{"uuid":"missing__mesh","mesh":BoxMesh.new(),"transform":Transform3D.IDENTITY,"chunk_min":Vector2i.ZERO,"chunk_max":Vector2i.ZERO,"extras":{}}])
	check(residency._resident.missing.pinned=="missing_authored_record","missing records remain pinned instead of being admitted for retirement")
	var index_size:int=queue._runtime_record_ids.size()
	queue._note_runtime_record({"record":record,"reference_entry":entry})
	check(queue._runtime_record_ids.size()==index_size and scene.get_meta("extras").rmmo_records.size()==3,"repeated publication does not duplicate records")
	check(queue.requeue_reference(entry),"retirement restores the compact queue request")
	if queue.has_method("runtime_record"):check(queue.runtime_record("later").is_empty(),"retirement releases hydrated record lookup ownership")
	check(not scene.get_meta("extras").rmmo_records.any(func(r):return r.uuid=="later"),"retirement drops hydrated author record")
	queue.shutdown()
	check(queue._runtime_record_ids.is_empty(),"shutdown releases all borrowed runtime record aliases")
	var moving:=Queue.new();scene.add_child(moving);moving.activate(scene);moving.set_process(false)
	await moving.quiesce()
	if moving.has_method("runtime_record"):check(is_same(moving.runtime_record("initial"),existing),"quiescence retains the original record for rollback")
	check(moving.begin_scene_handoff(),"quiesced queue starts staged scene handoff")
	scene.remove_child(moving)
	if moving.has_method("runtime_record"):check(is_same(moving.runtime_record("initial"),existing),"scene handoff does not cancel verified record ownership")
	scene.add_child(moving);moving.end_scene_handoff(scene)
	scene.remove_child(moving)
	check(moving._runtime_record_ids.is_empty(),"ordinary tree exit releases borrowed record aliases")
	moving.free()
	scene.free()
