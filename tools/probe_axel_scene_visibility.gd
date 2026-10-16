extends "res://tools/probe_axel_guard_approach.gd"
## Observe normal residency before freezing only camera-follow for the image.
const VisibilityStream=preload("res://scripts/world3d/world_stream.gd")
func runtime_batch_stats()->Dictionary:
	var batcher:Node=world._map_root.get_node_or_null("GroundRenderBatches")
	return batcher.stats() if batcher!=null else {}
func visibility_snapshot(view:Dictionary)->Dictionary:
	var map:Node=world._map_root;var meshes:Dictionary=map.get_meta("stream_meshes",{});var specs:Dictionary=map.get_meta("stream_by_id",{})
	var ids:Dictionary={};var target:=vector(view.target)
	for record:Dictionary in document.records:
		if record.get("kind")=="asset" and Vector2(record.position[0],record.position[2]).distance_to(Vector2(target.x,target.z))<50:ids[record.uuid]=true
	var rows:Array=[];var water_count:=0;var water_visible:=0
	for id:String in specs:
		var spec:Dictionary=specs[id]
		if spec.get("extras",{}).get("rmmo_landscape_kind","")=="channel":
			water_count+=1
			if meshes.has(id):water_visible+=1
		if not ids.has(id.get_slice("__",0)):continue
		var node:MeshInstance3D=meshes.get(id);var row:={"id":id,"resident":is_instance_valid(node),"range":spec.get("extras",{}).get("rmmo_visibility_range",{}),"bounds":[xyz((spec.transform*spec.mesh.get_aabb()).position),xyz((spec.transform*spec.mesh.get_aabb()).size)]}
		if is_instance_valid(node):
			row.visible=node.is_visible_in_tree();row.begin=node.visibility_range_begin;row.end=node.visibility_range_end
			row.camera_distance=vector(view.eye).distance_to(node.global_transform*node.get_aabb().get_center())
		rows.append(row)
	var queue:Node=map.get_node_or_null("DeferredAssets")
	return {"at_ms":Time.get_ticks_msec(),"feet":xyz(feet()),"stream_chunk":str(map.get_meta("stream_chunk","unsettled")),"stream_target":str(map.get_meta("stream_target","unplanned")),"cursor":map.get_meta("stream_cursor",0),"jobs":map.get_meta("stream_jobs",[]).size(),"water_indexed":water_count,"water_resident":water_visible,"subjects":rows,"queue_pending":queue.pending.size() if queue!=null else -1,"batches":runtime_batch_stats()}
func run()->void:
	started_ms=Time.get_ticks_msec();map_path="D:/code/rmmo_runtime/cache/world3d/axel_town_layout_20261016/map.gltf";output=FB_OUT+"/scene_visibility_fixed"
	expected_map_sha="cbfa6d3b0d5315d934bb679c741976e15d9e3170808dccac8bf74cb857248475"
	var recipe_path:=FB_OUT+"/functional_extra_cameras.json"
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):output=arg.trim_prefix("--out=")
		elif arg.begins_with("--cameras="):recipe_path=arg.trim_prefix("--cameras=")
	report={"phase":"metadata","checks":[],"screenshots":[],"views":[],"map_path":map_path,"scope":"Passive normal streaming until local demanded assets and residency plans settle (bounded 120 seconds), then unchanged camera images. No new residency sources or readiness bypass."}
	if not Paths.allowed(output) or DirAccess.make_dir_recursive_absolute(output)!=OK:quit(1);return
	capture_directory=output.path_join("images_"+str(Time.get_unix_time_from_system()).replace(".","_"));DirAccess.make_dir_recursive_absolute(capture_directory)
	create_timer(900).timeout.connect(func():
		if not finished:check(false,"visibility diagnostic timeout");finish(2))
	if not check(DisplayServer.get_name()!="headless","private GPU runtime") or not check(FileAccess.get_sha256(map_path)==expected_map_sha,"exact saved candidate"):finish();return
	report.map_sha256=expected_map_sha;report.executed_source_sha256={}
	for path:String in ["res://scripts/world3d/world_document.gd","res://scripts/world3d/world_stream.gd","res://scripts/world3d/stream_landscape.gd","res://scripts/world3d/gltf_map_io.gd","res://tools/probe_axel_scene_visibility.gd"]:report.executed_source_sha256[path]=FileAccess.get_sha256(path)
	document=Document.open_file(map_path)
	if not check(document!=null,"candidate opens read only"):finish();return
	for record:Dictionary in document.records:records[record.uuid]=record
	terrain_records=document.records.filter(func(r):return r.has("terrain_mesh"))
	var views:Array=JSON.parse_string(FileAccess.get_file_as_string(recipe_path)).cameras.filter(func(c):return c.id in ["market","farm","south_grove"] or c.has("shot_id"))
	report.camera_recipe={"path":recipe_path,"sha256":FileAccess.get_sha256(recipe_path)}
	Engine.max_fps=60;root.size=Vector2i(1600,1000);root.content_scale_size=root.size
	preload("res://tools/world3d_test_character.gd").ensure(self);var session=root.get_node("GameSession")
	session.spawn_data={"character":session.selected_character.duplicate(true),"equipment":[],"world_mode":"world3d"};session.world3d_requested=true;session.loading_mode="world3d_preview";session.world3d_map_path=map_path;session.world3d_spawn=Vector3(0,.9,4);session.prepared_world3d=null
	report.phase="native_loading";save_report()
	if not check(change_scene_to_file("res://scenes/loading.tscn")==OK,"production LoadingScene"):finish();return
	while not finished:
		await process_frame;world=current_scene
		if world==null:continue
		if world.has_meta("entry_loading_error"):check(false,"runtime loading failed");finish();return
		if world.has_method("is_world_ready") and world.is_world_ready() and not session._world_transition_active:break
	if finished:return
	for view:Dictionary in views:
		report.phase=view.id;save_report()
		var at:=vector(view.anchor) if view.anchor.size()==3 else ground_point(Vector3(view.anchor[0],0,view.anchor[1]))
		if not await relocate(at+Vector3.UP*.04,"visibility "+view.id):break
		var row:={"id":view.id,"initial":visibility_snapshot(view)}
		var began:=Time.get_ticks_msec();var stable:=0
		while Time.get_ticks_msec()-began<120000:
			await process_frame
			var map:Node=world._map_root;var queue:Node=map.get_node_or_null("DeferredAssets")
			var unfinished:bool=queue!=null and queue.pending.any(func(item):return queue._demanded_by_id.has(item.record.uuid))
			var ready:bool=map.has_meta("stream_chunk") and map.get_meta("stream_jobs",[]).is_empty() and map.get_meta("stream_append_pending",[]).is_empty() and not unfinished
			stable=stable+1 if ready else 0
			if stable>=30:break
		row.wait_ms=Time.get_ticks_msec()-began;row.ready=stable>=30
		check(row.ready,"normal requested region settles "+view.id,{"wait_ms":row.wait_ms})
		row.settled=visibility_snapshot(view);report.views.append(row)
		capture_fov=view.fov;await capture(view.get("shot_id","area_"+view.id),vector(view.eye),vector(view.target));save_report()
	check(FileAccess.get_sha256(map_path)==expected_map_sha,"source map unchanged")
	report.phase="complete";finish()
