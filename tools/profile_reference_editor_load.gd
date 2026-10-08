extends "res://tools/test_world3d_mcp.gd"
## GPU/scene run only via run_godot_background.py. Preparation writes a unique
## temporary reference map; --map reuses it without touching any formal map.
const Art=preload("res://scripts/asset/art_paths.gd")
const Pose=preload("res://scripts/world3d/pose_save.gd")
const SOURCE="D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf"
const TOP_FRAMES:=24
var output_path:=""
var map_path:=""
var report:Dictionary={}
var sampling:=false
var sample_started:=0
var last_frame:=0
var previous_phase:="request"
var previous_completed:=0
var frame_count:=0
var frame_max:=0.
var slow_frames:Array=[]
var phase_frames:Dictionary={}
var last_document:RefCounted
var replacements:=0
var monitor:RefCounted

func persist()->void:
	if output_path.is_empty():return
	report.failures=failed
	var file:=FileAccess.open(output_path,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(report,"\t"));file.close()

func observe_frame()->void:
	if not sampling or not is_instance_valid(editor):return
	var now:=Time.get_ticks_usec();var elapsed:=(now-last_frame)/1000.
	var job=editor._load_job
	if monitor!=null:
		var details:={"completed":job.completed,"total":job.total,"asset_worker_alive":job._asset_thread!=null and job._asset_thread.is_alive()}
		if is_instance_valid(editor._ground_batches):
			var batches=editor._ground_batches
			details.batch_pending=batches.pending.size();details.batch_workers=batches._workers.size()
			details.batch_ready=batches._workers.filter(func(work):return not work.thread.is_alive()).size()
			details.batch_budget_us=batches.work_budget_usec;details.batch_rebuild_count=batches.rebuild_count
			details.batch_preparation_phase=batches._preparation.get("phase","")
			details.batch_preparation_cursor=batches._preparation.get("cursor",0)
			details.batch_preparation_items=batches._preparation.get("items",[]).size()
		monitor.frame(job.phase,details)
	frame_count+=1;frame_max=maxf(frame_max,elapsed)
	if not phase_frames.has(previous_phase):phase_frames[previous_phase]={"frames":0,"observed_ms":0.,"max_frame_ms":0.}
	var phase:Dictionary=phase_frames[previous_phase]
	phase.frames+=1;phase.observed_ms+=elapsed;phase.max_frame_ms=maxf(phase.max_frame_ms,elapsed)
	var item:={"ms":elapsed,"frame":frame_count,"elapsed_ms":(now-sample_started)/1000.,
		"before":{"phase":previous_phase,"completed":previous_completed},
		"after":{"phase":job.phase,"completed":job.completed}}
	if slow_frames.size()<TOP_FRAMES or elapsed>float(slow_frames.back().ms):
		var index:=0
		while index<slow_frames.size() and float(slow_frames[index].ms)>=elapsed:index+=1
		slow_frames.insert(index,item)
		if slow_frames.size()>TOP_FRAMES:slow_frames.pop_back()
	if editor._doc!=last_document:replacements+=1;last_document=editor._doc
	last_frame=now;previous_phase=job.phase;previous_completed=job.completed

func unit_summary(timings:Dictionary)->Dictionary:
	var result:={"validation":timings.get("validation",{}),"build_max_slice_ms":timings.get("build",{}).get("max_slice_ms",0),"geometry":{},"collision":{}}
	for key:String in timings.get("build",{}).get("units",{}):
		var group:String="collision" if key.begins_with("picking") or key=="add_bodies" else "geometry"
		result[group][key]=timings.build.units[key]
	return result

func identity_and_picking()->Dictionary:
	var ids:Dictionary={};var absent:Array=[];var body_errors:Array=[];var body_count:=0
	for record:Dictionary in editor._doc.records:
		var id:String=record.uuid
		if ids.has(id):absent.append("duplicate:"+id)
		ids[id]=true
		var node:Node=editor._view.get_node_or_null(NodePath(id))
		if node==null or str(node.name)!=id:absent.append(id)
	for id:String in editor._bodies_by_uuid:
		if not ids.has(id):body_errors.append("unknown owner:"+id)
		for body:StaticBody3D in editor._bodies_by_uuid[id]:
			body_count+=1
			if not is_instance_valid(body) or str(body.get_meta("uuid",""))!=id:body_errors.append(id)
	check(absent.is_empty(),"every authored UUID has an independent editor visual")
	check(body_errors.is_empty() and body_count>0,"all picking bodies retain a valid author UUID")
	for frame in 3:await physics_frame
	var rays:Array=[];var attempts:=0;var diagnostics:Array=[]
	# Spread probes across the author list: the first records are adjacent terrain
	# patches, whose first face can coincide with another patch or an overlay.
	var owners:Array=editor._bodies_by_uuid.keys();var sample_ids:Array=[]
	for slot in mini(40,owners.size()):
		sample_ids.append(owners[slot*owners.size()/mini(40,owners.size())])
	for id:String in sample_ids:
		if rays.size()>=5 or attempts>=120:break
		if not editor._record_editable(editor._doc._find(id)):continue
		for body:StaticBody3D in editor._bodies_by_uuid[id]:
			if rays.size()>=5 or attempts>=120:break
			for child:Node in body.get_children():
				if not child is CollisionShape3D or child.disabled or child.shape==null:continue
				var surfaces:Array=[]
				if child.shape is BoxShape3D:
					surfaces.append([child.global_transform*Vector3(0,child.shape.size.y*.5,0),(child.global_basis*Vector3.UP).normalized()])
				elif child.shape is ConcavePolygonShape3D:
					var faces:PackedVector3Array=child.shape.get_faces()
					var triangles:=faces.size()/3
					for sample in mini(3,triangles):
						var triangle:int=sample*triangles/mini(3,triangles)
						var a:Vector3=child.global_transform*faces[triangle*3]
						var b:Vector3=child.global_transform*faces[triangle*3+1]
						var c:Vector3=child.global_transform*faces[triangle*3+2]
						var normal:Vector3=(b-a).cross(c-a)
						if normal.length_squared()>0.000001:surfaces.append([(a+b+c)/3.,normal.normalized()])
				for surface:Array in surfaces:
					if attempts>=120:break
					var center:Vector3=surface[0];var normal:Vector3=surface[1]
					var world:World3D=body.get_world_3d()
					for direction in [1.,-1.]:
						attempts+=1
						var query:=PhysicsRayQueryParameters3D.create(center+normal*.5*direction,center-normal*.5*direction,1)
						query.hit_back_faces=true
						var hit:Dictionary=world.direct_space_state.intersect_ray(query)
						var hit_id:String=str(hit.collider.get_meta("uuid","")) if not hit.is_empty() else ""
						var server_transform:Transform3D=PhysicsServer3D.body_get_state(body.get_rid(),PhysicsServer3D.BODY_STATE_TRANSFORM)
						diagnostics.append({"expected_uuid":id,"hit_uuid":hit_id,"shape":child.shape.get_class(),"center":str(center),
							"direction":direction,"body_layer":body.collision_layer,"world_matches_editor":world==editor.get_world_3d(),
							"space_matches_world":PhysicsServer3D.body_get_space(body.get_rid())==world.space,
							"physics_transform_matches_node":server_transform.is_equal_approx(body.global_transform)})
						if hit_id==id:
							rays.append({"uuid":id,"body_id":body.get_instance_id(),"position":[hit.position.x,hit.position.y,hit.position.z]});break
					if not rays.is_empty() and str(rays.back().uuid)==id:break
				if not rays.is_empty() and str(rays.back().uuid)==id:break
			if not rays.is_empty() and str(rays.back().uuid)==id:break
	check(rays.size()>=3,"real physics rays resolve at least three distinct selectable UUIDs")
	if not rays.is_empty():
		await call_tool("select_objects",{"ids":[rays[0].uuid]})
		check(editor._selection_tools.ids.has(rays[0].uuid),"HTTP selection accepts an actually ray-hit object identity")
	return {"author_ids":ids.size(),"view_children":editor._view.get_child_count(),"body_owner_count":editor._bodies_by_uuid.size(),
		"bodies":body_count,"missing_visuals":absent,"invalid_body_owners":body_errors,"ray_attempts":attempts,"ray_hits":rays,"ray_diagnostics":diagnostics}

func run()->void:
	Engine.max_fps=60;root.size=Vector2i(1440,960);root.content_scale_size=root.size;rpc_timeout_ms=60000
	output_path=Art.review_path("reference_editor_load_20261008.json")
	var prepare_only:=false
	var monitor_enabled:=false
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):map_path=arg.trim_prefix("--map=")
		elif arg=="--prepare-only":prepare_only=true
		elif arg=="--monitor":monitor_enabled=true
		elif arg.begins_with("--output="):output_path=arg.trim_prefix("--output=")
	# Reports may only be written to the normal runtime review artifacts folder.
	if not Paths.allowed(output_path,Art.review_path("")) or output_path.get_extension().to_lower()!="json":
		push_error("Profile output must stay within runtime review_artifacts");quit(1);return
	create_timer(1800).timeout.connect(func():sampling=false;report.timeout=true;persist();quit(2))
	report={"version":1,"date":"2026-10-08","http_samples":[],"poll_interval_ms":5000,
		"note":"phase observed_ms includes waits/rendering/HTTP polling; internal unit total_ms is nested and must not be added to overall elapsed"}
	var cache_root:=Paths.external_root().path_join("cache/world3d")
	var source_hash:=""
	if map_path.is_empty():
		source_hash=FileAccess.get_sha256(SOURCE)
		var prepare_started:=Time.get_ticks_usec()
		var source_doc=Doc.open_file(SOURCE)
		check(source_doc!=null,"read already-migrated formal town as immutable preparation input")
		if source_doc==null:persist();quit(1);return
		var directory:=Paths.cache_directory("reference_load_checkpoint_%d"%Time.get_ticks_usec())
		map_path=directory.path_join("map.gltf")
		check(source_doc.save(map_path)==OK,"create temporary reference map through native save without directory copy")
		report.preparation={"source":SOURCE,"source_sha256":source_hash,"elapsed_ms":(Time.get_ticks_usec()-prepare_started)/1000.,"records":source_doc.records.size(),"save_metrics":source_doc.last_save_metrics.duplicate(true)}
		report.preparation_in_same_process=true
		source_doc=null
	else:
		report.preparation_in_same_process=false
	if not Paths.allowed(map_path,cache_root) or map_path.get_extension().to_lower()!="gltf" or not FileAccess.file_exists(map_path):
		check(false,"--map must be an existing glTF under runtime cache/world3d");persist();quit(1);return
	map_path=map_path.replace("\\","/").simplify_path()
	var map_hash:=FileAccess.get_sha256(map_path)
	report.checkpoint={"path":map_path,"sha256":map_hash,"reuse_argument":"--map="+map_path}
	var file:=FileAccess.open(map_path,FileAccess.READ);report.checkpoint.bytes=file.get_length();file=null
	report.output=output_path;persist()
	print("REFERENCE_LOAD_CHECKPOINT ",JSON.stringify(report.checkpoint))
	if prepare_only:
		if not source_hash.is_empty():check(FileAccess.get_sha256(SOURCE)==source_hash,"formal source unchanged after preparation")
		report.prepare_only=true;persist();quit(0 if failed==0 else 1);return
	# A tiny initial document avoids ever constructing the town view ahead of
	# the HTTP load. --map additionally avoids source parsing/save cache warming.
	var initial:=Doc.new();initial.add_box("block",Vector3.ZERO,Vector3.ONE)
	var session=preload("res://scripts/net/net.gd").session()
	session.world3d_editor_doc=initial;session.world3d_editor_path=map_path.get_base_dir().path_join("initial_unsaved.gltf")
	editor=preload("res://scripts/world_editor/world_editor.gd").new();editor._mcp_autostart=false
	editor._draft_directory=Paths.cache_directory("reference_load_drafts_%d"%Time.get_ticks_usec())
	root.add_child(editor);editor._safety.enabled=false;await settle()
	check(editor._doc==initial and editor._doc.records.size()==1,"fresh editor begins with only one simple object")
	var probe:=TCPServer.new()
	while probe.listen(port,"127.0.0.1")!=OK:port+=1
	probe.stop();check(editor.start_mcp(port).ok,"real loopback 3D MCP load profiling server")
	var discovery:=await rpc("tools/list")
	check(discovery.get("result",{}).get("tools",[]).any(func(tool):return tool.name=="open_world"),"real HTTP discovery exposes open_world")
	last_document=initial;sample_started=Time.get_ticks_usec();last_frame=sample_started
	if monitor_enabled:monitor=preload("res://tools/load_monitor.gd").new();monitor.start(self)
	sampling=true;process_frame.connect(observe_frame)
	var pending:=await call_tool("open_world",{"path":map_path,"background":true})
	check(pending.get("pending",false),"actual HTTP open_world returns asynchronous load job")
	report.open_response=pending
	var next_poll:=Time.get_ticks_msec()
	while editor._load_job.active:
		if Time.get_ticks_msec()>=next_poll:
			var request_started:=Time.get_ticks_usec()
			var state:=await call_tool("editor_state")
			report.http_samples.append({"elapsed_ms":(Time.get_ticks_usec()-sample_started)/1000.,"request_ms":(Time.get_ticks_usec()-request_started)/1000.,"load":state.get("load",{})})
			next_poll=Time.get_ticks_msec()+5000
			print("REFERENCE_LOAD_PROGRESS ",editor._load_job.phase," ",editor._load_job.completed,"/",editor._load_job.total)
		await process_frame
	observe_frame();sampling=false;process_frame.disconnect(observe_frame)
	report.endpoint_to_completion_ms=(Time.get_ticks_usec()-sample_started)/1000.
	report.frames=frame_count;report.max_frame_ms=frame_max;report.slow_frames=slow_frames;report.phase_frames=phase_frames
	report.document_replacements=replacements
	report.load=editor._load_job.state();report.result=editor._load_job.result.duplicate(true)
	report.timings=editor._load_job._timings.duplicate(true);report.units=unit_summary(report.timings)
	report.load_start_offset_ms=(editor._load_job._started-sample_started)/1000.
	check(report.result.get("ok",false) and replacements==1,"load succeeds and publishes one document identity")
	if monitor!=null:
		editor._camera.projection=Camera3D.PROJECTION_PERSPECTIVE
		editor._orbit_center=Vector3(261,4,126);editor._camera.position=Vector3(310,60,205)
		editor._camera.look_at(editor._orbit_center);editor._city.update_grid()
		var post_started:=Time.get_ticks_usec()
		while Time.get_ticks_usec()-post_started<10000000:
			await process_frame;monitor.frame("loaded_bridge")
		report.monitor=monitor.finish();monitor=null
	persist()
	var final_state:=await call_tool("editor_state");report.final_http_load=final_state.get("load",{})
	if not report.result.get("ok",false):
		editor._mcp.stop();editor.queue_free();await settle();persist();quit(1);return
	# Every correctness probe and screenshot is outside the measured load span.
	var expected=Doc.open_file(map_path)
	check(expected!=null and Pose.same(expected.records,editor._doc.records) and Pose.same(expected.map_meta,editor._doc.map_meta),"HTTP-loaded complete records and metadata equal independent native reopen")
	report.records=editor._doc.records.size();report.identity=await identity_and_picking()
	report.ground_batches=editor._ground_batches.stats()
	check(FileAccess.get_sha256(map_path)==map_hash,"checkpoint stays byte-identical during load and inspection")
	if not source_hash.is_empty():check(FileAccess.get_sha256(SOURCE)==source_hash,"formal source remains byte-identical")
	editor._camera.projection=Camera3D.PROJECTION_PERSPECTIVE
	editor._orbit_center=Vector3(261,4,126);editor._camera.position=Vector3(310,60,205)
	editor._camera.look_at(editor._orbit_center);editor._city.update_grid()
	await settle();await RenderingServer.frame_post_draw
	var screenshot:=output_path.get_basename()+"_complete.png"
	check(root.get_texture().get_image().save_png(screenshot)==OK,"post-measurement bridge-town screenshot captured")
	report.screenshot=screenshot;persist()
	print("REFERENCE_EDITOR_LOAD_FINISHED failures=",failed," report=",output_path," checkpoint=",map_path)
	editor._mcp.stop();editor.queue_free();await settle()
	session.world3d_editor_doc=null;session.world3d_editor_path=""
	quit(0 if failed==0 else 1)
