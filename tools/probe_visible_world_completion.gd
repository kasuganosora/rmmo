extends SceneTree
## Functional coverage audit. Enumerations occur only at explicit checkpoints.
## Does not alter the map, camera, budgets, residency or entry readiness.
const Stream=preload("res://scripts/world3d/world_stream.gd")
const CpuMesh=preload("res://scripts/world3d/ground_cpu_mesh.gd")
var game:Node
var output:String
var report:Dictionary={"snapshots":[],"runtime_blackout_frames":0}
var active:=false
var deadline_us:int

func _initialize()->void:run.call_deferred()

func _process(_delta:float)->bool:
	if active and is_instance_valid(game):
		if game.get_viewport().disable_3d:report.runtime_blackout_frames+=1
	return false

func save()->void:
	var file:=FileAccess.open(output,FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"));file.close()

func run()->void:
	var path:=OS.get_environment("RMMO_VISIBLE_PROBE_MAP")
	output=OS.get_environment("RMMO_VISIBLE_PROBE_OUTPUT")
	var paths=preload("res://scripts/world3d/map_paths.gd")
	if not paths.allowed(path,paths.external_root().path_join("cache/world3d")) or not FileAccess.file_exists(path):push_error("Requires a temporary map");quit(2);return
	if not paths.allowed(output,paths.external_root().path_join("review_artifacts")):push_error("Requires external evidence output");quit(2);return
	report.map_sha256=FileAccess.get_sha256(path)
	preload("res://tools/world3d_test_character.gd").ensure(self)
	var session:=root.get_node("GameSession")
	session.spawn_data={"character":session.selected_character.duplicate(true),"equipment":[],"world_mode":"world3d"}
	session.world3d_map_path=path
	report.entry_started_us=Time.get_ticks_usec()
	session.go_world_3d()
	deadline_us=Time.get_ticks_usec()+240000000
	while Time.get_ticks_usec()<deadline_us:
		await process_frame
		if is_instance_valid(current_scene) and (current_scene.has_node("FailActions") or current_scene.has_meta("entry_loading_error")):
			report.status="entry_failed";save();quit(2);return
		if is_instance_valid(current_scene) and current_scene.has_method("is_world_ready") and current_scene.is_world_ready() and not session._world_transition_active:break
	if Time.get_ticks_usec()>=deadline_us:report.status="entry_timeout";save();quit(2);return
	game=current_scene;active=true
	report.playable_us=Time.get_ticks_usec()
	capture("playable")
	var stable:=0
	while Time.get_ticks_usec()<deadline_us:
		await process_frame
		var map_root:Node=game._map_root
		var queue:Node=map_root.get_node_or_null("DeferredAssets")
		var batches:Node=map_root.get_node_or_null("GroundRenderBatches")
		var jobs:Array=map_root.get_meta("stream_jobs",[])
		var planning:bool=map_root.has_meta("stream_candidates") or map_root.has_meta("stream_candidate_work") or map_root.has_meta("stream_collision_priority_work")
		var complete:bool=not planning and (queue==null or queue.is_idle()) and int(map_root.get_meta("stream_cursor",0))>=jobs.size() and map_root.get_meta("stream_append_pending",[]).is_empty() and (batches==null or (batches.pending.is_empty() and batches._workers.is_empty() and batches._preparation.is_empty() and batches._next_residency.is_empty()))
		stable=stable+1 if complete else 0
		if stable>=30:break
	report.status="settled" if stable>=30 else "completion_timeout"
	capture(report.status)
	report.finished_us=Time.get_ticks_usec();save()
	if stable>=30 and DisplayServer.get_name()!="headless":await photograph()
	print("VISIBLE_WORLD_COMPLETION ",JSON.stringify({"status":report.status,"blackout_frames":report.runtime_blackout_frames,"last":report.snapshots[-1].summary}))
	quit(0 if stable>=30 else 2)

func capture(label:String)->void:
	var map_root:Node=game._map_root
	var queue:Node=map_root.get_node("DeferredAssets")
	var center:Vector2i=Stream.chunk_key(game._player.global_position)
	# Independent contract: the actual camera's far plane, plus its orbit margin.
	# Derive the camera envelope independently from its asymmetric frustum planes.
	var projection:Projection=game._camera.camera.get_camera_projection()
	var far_plane:Plane=projection.get_projection_plane(Projection.PLANE_FAR)
	var radius_m:=0.0
	for x:int in [Projection.PLANE_LEFT,Projection.PLANE_RIGHT]:
		for y:int in [Projection.PLANE_TOP,Projection.PLANE_BOTTOM]:
			var corner:Variant=far_plane.intersect_3(projection.get_projection_plane(x),projection.get_projection_plane(y))
			if corner is Vector3:radius_m=maxf(radius_m,corner.length())
	var desired:=Stream._ring_at(center,int(ceil((radius_m+32.)/Stream.CHUNK_M)))
	var missing:Array=[];var unknown:Array=[];var expected:=0;var published:=0;var pending_in_view:=0
	for row:Dictionary in queue._reference_index.get("rows",[]):
		if not row.bounds_known:
			unknown.append({"uuid":row.uuid,"reason":row.reason,"pending":queue._pending_by_record_id.has(row.uuid)})
			# Unknown envelopes are conservative global work, never silently excluded.
		else:
			var low:Vector2i=Stream.chunk_key(row.bounds.position);var high:Vector2i=Stream.chunk_key(row.bounds.end)
			if low.x>desired.high.x or high.x<desired.low.x or low.y>desired.high.y or high.y<desired.low.y:continue
		expected+=1
		var uuid:String=row.uuid
		if queue._pending_by_record_id.has(uuid):
			pending_in_view+=1
			missing.append({"uuid":uuid,"reason":row.reason,"asset_path":row.asset_path,"bounds":str(row.bounds),"demanded":queue._demanded_by_id.has(uuid)})
		else:published+=1
	var hidden_specs:Array=[];var unbacked_cpu:Array=[];var visible_expected:=0;var resident:=0;var native:=0
	var meshes:Dictionary=map_root.get_meta("stream_meshes",{})
	var batches:Node=map_root.get_node_or_null("GroundRenderBatches")
	for spec:Dictionary in map_root.get_meta("stream_library",[]):
		if not Stream._overlaps(spec,desired):continue
		visible_expected+=1
		if spec.get("native_visual",false):native+=1;continue
		var node:Variant=meshes.get(spec.uuid)
		if is_instance_valid(node):
			resident+=1
			if node.mesh is CpuMesh:
				var group:String=str(batches._member_groups.get(str(node.name),"")) if batches!=null else ""
				if group.is_empty() or not batches.groups.has(group) or not is_instance_valid(batches.groups[group].get("visual")):unbacked_cpu.append(spec.uuid)
		else:hidden_specs.append({"uuid":spec.uuid,"bounds":str(spec.get("chunk_min",spec.get("chunk"))),"building":spec.get("render_building",""),"type":spec.get("ground_batch_record",{}).get("kind","")})
	var summary:={"expected_records":expected,"published_records":published,"pending_in_view":pending_in_view,"expected_specs":visible_expected,"resident_specs":resident,"native_specs":native,"missing_visual_specs":hidden_specs.size(),"unbacked_cpu_specs":unbacked_cpu.size(),"pending_total":queue.pending_count(),"demanded":queue._demanded_by_id.size(),"jobs":queue._jobs.size(),"scope":queue._demand_scope.keys(),"entry_scope":map_root.has_meta("entry_stream_clip"),"position":str(game._player.global_position),"camera_far":game._camera.camera.far,"visual_radius":Stream.render_radius(map_root)}
	report.snapshots.append({"label":label,"ticks_us":Time.get_ticks_usec(),"summary":summary,"unknown_bounds":unknown,"missing_records":missing,"missing_visual_specs":hidden_specs,"unbacked_cpu_specs":unbacked_cpu,"demands":str(queue._demands),"error":queue.error,"path_errors":queue.path_errors.duplicate(),"instance_errors":queue.instance_errors.duplicate(),"profile":queue.profile.duplicate()})
	save()

func photograph()->void:
	var model:Node3D=game._player._model
	var was_visible:=model.visible
	var old_yaw:float=game._camera.yaw
	model.visible=false
	report.images=[]
	for i:int in 4:
		game._camera.yaw=old_yaw+i*PI*.5
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var photo:=root.get_texture().get_image()
		var path:=output.get_base_dir().path_join("view_%d_q90.webp"%i)
		var saved:=photo.save_webp(path,false,.9)
		report.images.append({"path":path,"quality":90,"lossy":true,"width":photo.get_width(),"height":photo.get_height(),"save_error":saved,"sha256":FileAccess.get_sha256(path) if saved==OK else ""})
	game._camera.yaw=old_yaw;model.visible=was_visible
	save()
