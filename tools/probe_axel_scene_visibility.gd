extends "res://tools/probe_axel_guard_approach.gd"
## Observe normal residency before freezing only camera-follow for the image.
const VisibilityStream=preload("res://scripts/world3d/world_stream.gd")
func foot_support()->Dictionary:
	var point:=feet();var center:=support(point,.6,.3)
	if center.ok:return center
	# A real capsule can stand astride a masonry joint. Require the production
	# body to be grounded as well as two nearby rays; do not invent support.
	if not world._player.is_on_floor():return center
	var supported:=0
	for offset:Vector3 in [Vector3(.08,0,0),Vector3(-.08,0,0),Vector3(0,0,.08),Vector3(0,0,-.08)]:
		if support(point+offset,.6,.3).ok:supported+=1
	return {"ok":supported>=2,"footprint_samples":supported,"center_missed":true}
func foot_target(point:Vector3)->Dictionary:
	var best:Dictionary={"ok":false}
	# Sample inside the character's foot area so a 4mm mortar seam does not
	# turn a stair destination into the riverbed below it. Keep requested X/Z.
	for offset:Vector3 in [Vector3.ZERO,Vector3(.08,0,0),Vector3(-.08,0,0),Vector3(0,0,.08),Vector3(0,0,-.08)]:
		var hit:=ray_surface(point+offset,.8,2.)
		if hit.ok and (not best.ok or hit.position[1]>best.position[1]):best=hit
	if best.ok:best.position=[point.x,best.position[1],point.z]
	return best
func manual_walk(target:Vector3,label:String)->Dictionary:
	stop_route();var start:=feet();var yaw_before:float=world._camera.yaw;var began:=Time.get_ticks_msec();var unsupported:=0;var maximum:=0;var seen:Dictionary={};var joint_support_ticks:=0
	var event:=InputEventKey.new();event.keycode=KEY_W;event.pressed=true;Input.parse_input_event(event)
	while Time.get_ticks_msec()-began<20000:
		var delta:Vector3=target-feet();delta.y=0
		if delta.length()<.10:break
		world._camera.yaw=atan2(-delta.x,-delta.z)
		await physics_frame
		var hit:=foot_support();unsupported=0 if hit.ok else unsupported+1;maximum=maxi(maximum,unsupported)
		if hit.ok and hit.get("center_missed",false):joint_support_ticks+=1
		for i in world._player.get_slide_collision_count():
			var contact:KinematicCollision3D=world._player.get_slide_collision(i)
			seen[object_id(contact.get_collider())]=true
		if maximum>20:break
	event=InputEventKey.new();event.keycode=KEY_W;event.pressed=false;Input.parse_input_event(event)
	world._camera.yaw=yaw_before
	await physics_frame
	var remaining:=feet().distance_to(target)
	var row:={"id":label,"method":"normal W key, camera steering, unchanged production player and streaming guards; joint fallback requires grounded body plus two foot-area support rays","start":xyz(start),"target":xyz(target),"end":xyz(feet()),"remaining_m":remaining,"unsupported_ticks":maximum,"joint_support_ticks":joint_support_ticks,"contacts":seen.keys(),"passed":remaining<.25 and maximum<=20}
	check(row.passed,"actual keyboard exterior walk "+label,row);return row
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
	return {"at_ms":Time.get_ticks_msec(),"feet":xyz(feet()),"stream_chunk":str(map.get_meta("stream_chunk","unsettled")),"stream_target":str(map.get_meta("stream_target","unplanned")),"cursor":map.get_meta("stream_cursor",0),"jobs":map.get_meta("stream_jobs",[]).size(),"water_indexed":water_count,"water_resident":water_visible,"subjects":rows,"queue_pending":queue.pending_count() if queue!=null else -1,"batches":runtime_batch_stats()}
func run()->void:
	started_ms=Time.get_ticks_msec();map_path="D:/code/rmmo_runtime/cache/world3d/axel_town_layout_20261016/map.gltf";output=FB_OUT+"/scene_visibility_fixed"
	expected_map_sha="cbfa6d3b0d5315d934bb679c741976e15d9e3170808dccac8bf74cb857248475"
	var recipe_path:=FB_OUT+"/functional_extra_cameras.json"
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):output=arg.trim_prefix("--out=")
		elif arg.begins_with("--cameras="):recipe_path=arg.trim_prefix("--cameras=")
		elif arg.begins_with("--map="):map_path=arg.trim_prefix("--map=")
		elif arg.begins_with("--expected-map-sha="):expected_map_sha=arg.trim_prefix("--expected-map-sha=")
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
	var recipe:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(recipe_path))
	var views:Array=recipe.cameras.filter(func(c):return c.id in ["market","farm","south_grove"] or c.has("shot_id"))
	report.camera_recipe={"path":recipe_path,"sha256":FileAccess.get_sha256(recipe_path)}
	var resolution:Array=recipe.get("resolution",[1600,1000])
	Engine.max_fps=60;root.size=Vector2i(resolution[0],resolution[1]);root.content_scale_size=root.size
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
			var unfinished:bool=queue!=null and queue._materialize_pending_snapshot().any(func(item):return queue._demanded_by_id.has(item.record.uuid))
			var ready:bool=map.has_meta("stream_chunk") and map.get_meta("stream_jobs",[]).is_empty() and map.get_meta("stream_append_pending",[]).is_empty() and not unfinished
			stable=stable+1 if ready else 0
			if stable>=30:break
		row.wait_ms=Time.get_ticks_msec()-began;row.ready=stable>=30
		check(row.ready,"normal requested region settles "+view.id,{"wait_ms":row.wait_ms})
		row.settled=visibility_snapshot(view);report.views.append(row)
		capture_fov=view.fov;await capture(view.get("shot_id","area_"+view.id),vector(view.eye),vector(view.target));save_report()
		for probe:Dictionary in view.get("support_probes",[]):
			var hit:=ray_surface(vector(probe.point),1.,2.)
			if not report.has("support_probes"):report.support_probes=[]
			var accepted:bool=hit.ok and hit.get("id","")==probe.expected_id
			report.support_probes.append({"id":probe.id,"hit":hit,"passed":accepted})
			check(accepted,"actual native bank cap support "+str(probe.id),hit)
	# Optional scoped exterior routes use the ordinary controller and real
	# collision. They never visit component-house interiors or change the map.
	report.outdoor_routes=[]
	for route:Dictionary in recipe.get("outdoor_routes",[]):
		var start:=ground_point(vector(route.start))
		if not await relocate(start+Vector3.UP*.04,route.id):break
		for index in route.points.size():
			var sample:=foot_target(vector(route.points[index])) if route.get("mode","")=="keyboard" else ray_surface(vector(route.points[index]),.8,2.)
			if not check(sample.ok,"actual walkable target "+str(route.id)+"/"+str(index),sample):break
			if route.get("mode","")=="keyboard":report.outdoor_routes.append(await manual_walk(vector(sample.position),str(route.id)+"/"+str(index)))
			else:report.outdoor_routes.append(await walk_route(vector(sample.position),str(route.id)+"/"+str(index)))
			save_report()
	check(FileAccess.get_sha256(map_path)==expected_map_sha,"source map unchanged")
	report.phase="complete";finish()
