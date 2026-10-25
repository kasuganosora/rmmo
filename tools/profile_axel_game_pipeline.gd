extends SceneTree
## Read-only production game entry, passive queue observations, then gameplay.
## Never edits maps/assets or forces whole-map residency. GPU runs use the
## private-desktop runner. Timed work includes the ordinary avatar and HUD.
const MAP="D:/code/rmmo_runtime/packs/default/maps/axel_town/map.gltf"
const MOCK_SERVER_BACKGROUND:=true
const Trace=preload("res://scripts/world3d/load_trace.gd")
const CpuMesh=preload("res://scripts/world3d/ground_cpu_mesh.gd")
var output:=""
var report:Dictionary={"queues":[],"stages":[],"failures":[]}
var began:=0
var last:=0
var next_sample:=0
var phase:="loading"
var frames:Array=[]
var monitor:RefCounted
var sampling:=false
var runtime_seconds:=20.
var mesh_only:=false
var mesh_map:Node
var cold_index:=false
var cancel_stream_frames:=0
var uncapped_runtime:=false
var cancel_during_capture:=false
var white_material:=false
var early_white_camera:=false
var loading_disable_3d:=false
var initial_cover:CanvasLayer
var sources_task:=-1
var measured_sources:Dictionary={}
var measured_sources_us:=0
var queue_observer_calls:=0
var queue_observer_elapsed_us:=0
var queue_observer_max_us:=0
func _initialize()->void:
	report.startup={"initialize_us":Time.get_ticks_usec()}
	report.frame_metric_contract={"ms":"Wall time between consecutive observer callbacks; phase is sampled at the ending callback.","process_ms":"Performance.TIME_PROCESS: engine process wall-time maximum published about once per second, not this frame's OS thread CPU time.","physics_ms":"Performance.TIME_PHYSICS_PROCESS: engine physics wall-time maximum published about once per second, not this frame's OS thread CPU time.","deferred_stages":"Last observed stage counters; use the timestamped stage ring to associate work with a frame. Zero alone does not prove OS or GPU idle."}
	run.call_deferred()
func source_snapshot(folder:String="res://scripts")->Dictionary:
	var result:Dictionary={}
	if folder=="res://scripts":result["res://tools/load_monitor.gd"]=FileAccess.get_sha256("res://tools/load_monitor.gd")
	for entry:String in DirAccess.get_files_at(folder):
		if entry.ends_with(".gd"):result[folder.path_join(entry)]=FileAccess.get_sha256(folder.path_join(entry))
	for entry:String in DirAccess.get_directories_at(folder):result.merge(source_snapshot(folder.path_join(entry)))
	return result
func save()->void:
	report.queue_observer={"calls":queue_observer_calls,"elapsed_us":queue_observer_elapsed_us,"max_us":queue_observer_max_us,"scope":"500ms queue/profile/batch snapshot, excluding frame append and trace emission"}
	var dqueue:Node=mesh_map.get_node_or_null("DeferredAssets") if is_instance_valid(mesh_map) else null
	if dqueue!=null and dqueue.get("profile") is Dictionary:
		report.stage_ring=dqueue.profile.get("stage_ring",[])
	var server:Node=root.get_node_or_null("MockServer")
	var server_disabled:=server!=null and server.has_meta(&"mock_server_disabled")
	report.mock_server={"disabled":server_disabled,"installed":server!=null and not server_disabled and not server.has_meta(&"mock_server_preparation"),"preparation":preload("res://scripts/net/mock_server_host.gd").profile_of(server)}
	var file:=FileAccess.open(output,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(report,"\t"));file.close()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:report.failures.append(label)
func runtime_frame_policy()->void:
	if uncapped_runtime:
		Engine.max_fps=0
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED,root.get_window_id())
	report.runtime_frame_policy={"max_fps":Engine.max_fps,"vsync":DisplayServer.window_get_vsync_mode(root.get_window_id()),"screen_refresh_hz":DisplayServer.screen_get_refresh_rate(root.current_screen),"physics_ticks_per_second":Engine.physics_ticks_per_second}
func observe()->void:
	if not sampling:return
	var now:=Time.get_ticks_usec()
	var dqueue:Node=mesh_map.get_node_or_null("DeferredAssets") if is_instance_valid(mesh_map) else null
	var dprof:Dictionary=dqueue.profile if dqueue!=null and dqueue.get("profile") is Dictionary else {}
	frames.append({"at_ms":(now-began)/1000.,"ms":(now-last)/1000.,"phase":phase,
		"process_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000.0,
		"physics_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0,
		"deferred_poll_us":int(dprof.get("last_poll_us",0)),
		"deferred_join_us":int(dprof.get("last_poll_join_us",0)),
		"deferred_sync_us":int(dprof.get("last_poll_sync_us",0)),
		"deferred_dispatch_us":int(dprof.get("last_dispatch_us",0)),
		"deferred_bookkeeping_us":int(dprof.get("frame_bookkeeping_us",0)),
		"deferred_accept_us":int(dprof.get("last_accept_us",0))});last=now
	if monitor!=null:monitor.frame(phase)
	if now<next_sample:return
	next_sample=now+500000
	var observation_started:=Time.get_ticks_usec()
	var row:Dictionary={"at_ms":(now-began)/1000.,"phase":phase}
	var scene:=current_scene
	if scene!=null:
		var stage:=""
		if scene.has_method("loading_progress"):stage=str(scene.loading_progress().stage)
		elif scene.get("status_label")!=null:stage=str(scene.status_label.text)
		if not stage.is_empty() and (report.stages.is_empty() or report.stages.back().stage!=stage):
			report.stages.append({"at_ms":row.at_ms,"stage":stage});print("AXEL_STAGE ",stage)
		var map:Node=scene.get("_map_root") if scene.has_method("is_world_ready") else mesh_map
		if map!=null:
			var collision:Node=map.get_node_or_null("StreamCollisionPreparer")
			if collision!=null:row.collision={"bvh_worker_shapes":collision.bvh_worker_shapes,"bvh_main_shapes":collision.bvh_main_shapes,"bvh_worker_face_vertices":collision.bvh_worker_face_vertices,"bvh_main_face_vertices":collision.bvh_main_face_vertices,"bvh_worker_slices":collision._terrain.bvh_worker_slices,"bvh_main_slices":collision._terrain.bvh_main_slices,"bvh_worker_installed_slices":collision._terrain.bvh_worker_installed_slices,"bvh_main_installed_slices":collision._terrain.bvh_main_installed_slices,"bvh_worker_slice_face_vertices":collision._terrain.bvh_worker_face_vertices,"bvh_main_slice_face_vertices":collision._terrain.bvh_main_face_vertices,"serial_face_workers":collision.face_worker_starts,"prepared_face_hits":collision.prepared_face_hits,"lookahead":collision._face_prefetch.profile.duplicate(true),"lookahead_work":collision._face_prefetch.work_snapshot()}
			var jobs:Array=map.get_meta("stream_jobs",[])
			row.stream={"batch_checkpoints":map.get_meta("stream_batch_checkpoints",0),"jobs":jobs.size(),"cursor":map.get_meta("stream_cursor",0),"append":map.get_meta("stream_append_pending",[]).size(),"specs":map.get_meta("stream_library",[]).size(),"meshes":map.get_meta("stream_meshes",{}).size(),"bodies":map.get_meta("stream_bodies",{}).size(),"settled":map.has_meta("stream_chunk")}
			row.stream.priority_classified_rows=map.get_meta("stream_priority_classified_rows",0);row.stream.priority_reused_rows=map.get_meta("stream_priority_reused_rows",0)
			row.stream.priority_bulk_reused_rows=map.get_meta("stream_priority_bulk_reused_rows",0)
			row.stream.job_catalog_scan_rows=map.get_meta("stream_job_catalog_scan_rows",0)
			row.stream.ready_bypass_applied=map.get_meta("stream_ready_bypass_applied",0)
			row.stream.ready_bypass_scanned=map.get_meta("stream_ready_bypass_scanned",0)
			row.stream.ready_bypass_scan_us=map.get_meta("stream_ready_bypass_scan_us",0)
			row.stream.ready_bypass_max_scan_us=map.get_meta("stream_ready_bypass_max_scan_us",0)
			var queue:Node=map.get_node_or_null("DeferredAssets")
			if queue!=null:
				row.deferred={"pending":queue.pending.size(),"demanded":queue._demanded_by_id.size(),"unpublished":queue.pending.filter(func(item):return queue._demanded_by_id.has(item.record.uuid)).size(),"admission":queue._admission.snapshot(),"profile":queue.profile.duplicate(true),"jobs":[]}
				for path:String in queue._jobs:
					var job:Dictionary=queue._jobs[path];var worker:Thread=job.get("worker")
					row.deferred.jobs.append({"path":path,"stage":job.get("stage",""),"alive":worker!=null and worker.is_alive(),"age_ms":(now-int(job.get("dispatch_us",now)))/1000.,"ready":job.has("result")})
			var batches:Node=map.get_node_or_null("GroundRenderBatches")
			if batches!=null:
				row.batches=batches.stats();row.batches.max_prepare_slice_ms=batches.max_prepare_slice_ms
	report.queues.append(row)
	var observation_us:=Time.get_ticks_usec()-observation_started
	queue_observer_calls+=1;queue_observer_elapsed_us+=observation_us;queue_observer_max_us=maxi(queue_observer_max_us,observation_us)
	row.observer_us=observation_us;row.observer_total_us=queue_observer_elapsed_us;row.observer_calls=queue_observer_calls;row.observer_max_us=queue_observer_max_us
	Trace.elapsed("probe.queue_observation",observation_started,{"phase":phase})
	# Keep disk serialization outside timed gameplay. Queue observations stay
	# in memory; loading checkpoints remain available through stage prints.
func finish(code:int)->void:
	sampling=false
	if process_frame.is_connected(observe):process_frame.disconnect(observe)
	report.frames=frames
	report.prefab_material_identity={"reuses":preload("res://scripts/world3d/house_prefab.gd").material_identity_reuses,"scans":preload("res://scripts/world3d/house_prefab.gd").material_identity_scans}
	if monitor!=null:report.monitor=monitor.finish();monitor=null
	if current_scene!=null:
		for key:String in ["initial_loading_cover_started","initial_loading_cover_released","initial_loading_cover_aborted"]:
			if current_scene.has_meta(key):report[key]=current_scene.get_meta(key)
		if current_scene.has_method("is_world_ready"):report.is_world_ready=current_scene.is_world_ready()
	var map:Node=mesh_map if mesh_map!=null else (current_scene.get("_map_root") if current_scene!=null and current_scene.has_method("is_world_ready") else null)
	if map!=null:
		if mesh_only and white_material:
			report.white_render_audit={"gpu_surfaces":0,"shader_surfaces":0,"nonwhite_surfaces":0,"examples":[]}
			for visual:MeshInstance3D in preload("res://scripts/world3d/surface_materials.gd").meshes(map):
				if not visual.is_visible_in_tree() or visual.mesh==null or visual.mesh is CpuMesh or visual.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY:continue
				for slot:int in visual.mesh.get_surface_count():
					var material:Material=visual.get_active_material(slot)
					report.white_render_audit.gpu_surfaces+=1
					if material is ShaderMaterial:report.white_render_audit.shader_surfaces+=1
					if not material is StandardMaterial3D or material.shading_mode!=BaseMaterial3D.SHADING_MODE_UNSHADED or material.albedo_color!=Color.WHITE:
						report.white_render_audit.nonwhite_surfaces+=1
						if report.white_render_audit.examples.size()<8:report.white_render_audit.examples.append({"node":str(visual.name),"material":material.resource_path if material!=null else "null"})
			check(report.white_render_audit.nonwhite_surfaces==0,"actual visible GPU surfaces remain white after all streaming registrations")
		report.stream_adopt=map.get_meta("stream_adopt_ms",{}).duplicate(true)
		report.stream_load=map.get_meta("stream_load_profile_us",{}).duplicate(true)
		report.render_sources={"meshes":0,"visible":0,"batch_tag":0,"batch_sources":0,"scaled_batch_sources":0,"native":0,"by_namespace":{}}
		for node:MeshInstance3D in preload("res://scripts/world3d/surface_materials.gd").meshes(map):
			report.render_sources.meshes+=1
			if node.is_visible_in_tree():report.render_sources.visible+=1
			if node.has_meta("ground_render_batch"):report.render_sources.batch_tag+=1
			if node.has_meta("native_visual"):report.render_sources.native+=1
			if node.has_meta("ground_batch_record"):
				report.render_sources.batch_sources+=1
				if not node.global_basis.get_scale().is_equal_approx(Vector3.ONE):report.render_sources.scaled_batch_sources+=1
			var id:String=str(node.get_meta("extras",{}).get("uuid",node.name)).get_slice("__",0)
			report.render_sources.by_namespace[id]=int(report.render_sources.by_namespace.get(id,0))+1
		var queue:Node=map.get_node_or_null("DeferredAssets")
		if queue!=null:
			# Scalar-only cardinalities, collected after sampling stops.
			report.support_set_snapshot=queue.support_set_snapshot()
			report.index_classifications={}
			var unknown:Array=[]
			for row:Dictionary in queue._reference_index.get("rows",[]):
				var key:String=row.classification+":"+row.reason
				report.index_classifications[key]=int(report.index_classifications.get(key,0))+1
				if row.reason=="unknown_geometry":unknown.append(queue._reference_index.extras.rmmo_records[row.order])
			if not unknown.is_empty():
				# Post-measurement, read-only diagnostic: never part of timed load
				# or runtime samples, and never reused to prime another process.
				var restored:Dictionary=preload("res://scripts/world3d/map_resource_store.gd").read_records(unknown,MAP,"D:/code/rmmo_runtime")
				report.unknown_records={"read_ok":restored.ok,"kinds":{},"road_extra_fields":{}}
				if restored.ok:
					for record:Dictionary in restored.records:
						var kind:="road" if record.has("road_mesh") else ("terrain" if record.has("terrain_mesh") else str(record.get("kind","other")))
						report.unknown_records.kinds[kind]=int(report.unknown_records.kinds.get(kind,0))+1
						if kind!="road":continue
						for field:String in record:
							if field not in preload("res://scripts/world3d/map_dependency_index.gd").COMMON_FIELDS+preload("res://scripts/world3d/map_dependency_index.gd").ROAD_FIELDS:report.unknown_records.road_extra_fields[field]=int(report.unknown_records.road_extra_fields.get(field,0))+1
	report.map_sha_after=FileAccess.get_sha256(MAP)
	check(report.map_sha_after==report.map_sha,"formal map unchanged")
	if is_instance_valid(mesh_map):
		report.stream_append_timing=mesh_map.get_meta("stream_append_timing",{})
		report.stream_append_slow=mesh_map.get_meta("stream_append_slow",[])
		var native_node:Node=mesh_map.get_node_or_null("NativeResidency")
		if native_node!=null and native_node.get("profile") is Dictionary:report.native_profile=native_node.profile
	var final_queue:Node=mesh_map.get_node_or_null("DeferredAssets") if is_instance_valid(mesh_map) else null
	if final_queue!=null and final_queue.get("profile") is Dictionary:
		report.stage_ring=final_queue.profile.get("stage_ring",[])
		report.stage_slow=final_queue.profile.get("stage_slow",[])
		report.publish_slow=final_queue.profile.get("publish_slow",[])
	if mesh_only and is_instance_valid(mesh_map):await retire_white_map()
	preload("res://scripts/world3d/map_resource_store.gd").wait_bundle_writes()
	report.resource_bundle=preload("res://scripts/world3d/map_resource_store.gd").bundle_profile.duplicate()
	if sources_task>=0:
		WorkerThreadPool.wait_for_task_completion(sources_task);sources_task=-1
		report.sources=measured_sources;report.startup.sources_hashed_us=measured_sources_us
	report.sources_after=source_snapshot()
	report.sources_after["res://tools/profile_axel_game_pipeline.gd"]=FileAccess.get_sha256("res://tools/profile_axel_game_pipeline.gd")
	check(report.sources_after==report.sources,"production and profiler sources unchanged throughout measurement")
	report.shadow_faces=preload("res://scripts/world3d/building_shadow_proxy.gd").stats()
	report.viewport_size=[root.size.x,root.size.y]
	save();print("AXEL_PIPELINE_FINISHED ",output," failures=",report.failures.size());quit(code if report.failures.is_empty() else 1)
func retire_white_map()->void:
	# Destruction is outside every measured interval. Exercise ordinary map exit,
	# including an unfinished collision/batch worker, rather than clear caches.
	var weak_map:WeakRef=weakref(mesh_map)
	var queue:Node=mesh_map.get_node_or_null("DeferredAssets")
	var admission:RefCounted=queue._admission if queue!=null else null
	var collision:Node=mesh_map.get_node_or_null("StreamCollisionPreparer")
	var lookahead:RefCounted=collision._face_prefetch if collision!=null else null
	var paths:Array=[]
	if mesh_map.has_meta("runtime_asset_cache_scope"):paths=mesh_map.get_meta("runtime_asset_cache_scope")._templates.keys()
	# Match permanent game-map replacement, including batch callback teardown.
	preload("res://scripts/world3d/world_stream.gd").prepare_map_disposal(mesh_map,self)
	var host:Node=current_scene;current_scene=null;mesh_map=null;host.free()
	var deadline:=Time.get_ticks_msec()+15000
	while Time.get_ticks_msec()<deadline:
		if lookahead!=null:lookahead.poll()
		var drainer:Node=root.get_node_or_null("AssetWorkerDrainer")
		var resources:Node=root.get_node_or_null("ResourceRetirement")
		if (drainer==null or drainer.jobs.is_empty()) and (resources==null or resources.pending.is_empty()) and (admission==null or admission.reserved_bytes==0) and (lookahead==null or lookahead.profile.reserved_bytes==0):break
		await process_frame
	RenderingServer.force_sync()
	var drainer:Node=root.get_node_or_null("AssetWorkerDrainer")
	var resources:Node=root.get_node_or_null("ResourceRetirement")
	report.retirement={"map_freed":weak_map.get_ref()==null,"worker_jobs":drainer.jobs.size() if drainer!=null else 0,"admission_bytes":admission.reserved_bytes if admission!=null else 0,"lookahead_bytes":lookahead.profile.reserved_bytes if lookahead!=null else 0,"retained_templates":0,"loading_render_contexts":root.find_children("LoadingRenderContext","SubViewport",true,false).size()}
	report.retirement.resource_retirements=resources.pending.size() if resources!=null else 0
	if resources!=null:report.retirement.resource_retirement_profile=resources.profile.duplicate()
	var geometry_sizes:RefCounted=preload("res://scripts/world3d/resource_retirement.gd")._geometry_sizes
	report.retirement.geometry_size_work={"hits":geometry_sizes.hits,"scans":geometry_sizes.scans,"channels":geometry_sizes.channels,"entries":geometry_sizes.sizes.size()}
	for path:String in paths:
		if preload("res://scripts/world_editor/asset_library.gd")._scenes.has(path):report.retirement.retained_templates+=1
	check(report.retirement.map_freed and report.retirement.worker_jobs==0 and report.retirement.resource_retirements==0 and report.retirement.admission_bytes==0 and report.retirement.lookahead_bytes==0 and report.retirement.retained_templates==0 and report.retirement.loading_render_contexts==0,"real white map exit releases map, template owners, workers and admission leases")
func run()->void:
	report.startup.run_us=Time.get_ticks_usec()
	var monitored:=false
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		elif arg=="--monitor":monitored=true
		elif arg=="--method-profile":Trace.methods_enabled=true
		elif arg=="--cold-read-diagnostics":
			preload("res://scripts/world3d/map_resource_store.gd").read_timing_enabled=true
			preload("res://scripts/world3d/map_loader.gd").cold_read_diagnostics_enabled=true
		elif arg.begins_with("--trace-minimum-us="):Trace.minimum_event_us=arg.trim_prefix("--trace-minimum-us=").to_int()
		elif arg=="--without-hud":preload("res://scripts/world3d/runtime_probe_controls.gd").hud_enabled=false
		elif arg=="--without-map-textures":preload("res://scripts/world3d/runtime_probe_controls.gd").discard_map_textures=true
		elif arg=="--without-compiled":preload("res://scripts/world3d/compiled_asset_cache.gd").enabled=false
		elif arg=="--mesh-only":mesh_only=true
		elif arg=="--early-white-camera":early_white_camera=true
		elif arg=="--loading-disable-3d":loading_disable_3d=true
		elif arg=="--force-covered-loading-budget":preload("res://scripts/world3d/deferred_asset_loader.gd").force_covered_loading_budget=true
		elif arg.begins_with("--covered-loading-budget-us="):preload("res://scripts/world3d/deferred_asset_loader.gd").covered_loading_budget_usec=clampi(arg.trim_prefix("--covered-loading-budget-us=").to_int(),8000,24000)
		elif arg=="--late-render-context":preload("res://scripts/world3d/map_loader.gd").startup_render_context_enabled=false
		elif arg=="--continuous-render-context":preload("res://scripts/world3d/map_loader.gd").startup_render_context_frames=0
		elif arg=="--legacy-shadow-materials":preload("res://scripts/world3d/building_shadow_proxy.gd").unshaded_materials_enabled=false
		elif arg=="--single-road-reference-jobs":preload("res://scripts/world3d/deferred_asset_loader.gd").native_reference_batching_enabled=false
		elif arg=="--repeat-gltf-state-getters":preload("res://scripts/world3d/gltf_map_io.gd").legacy_state_array_getters_enabled=true
		elif arg=="--legacy-candle-uploads":preload("res://scripts/world3d/candle_sconce_mesh.gd").cpu_index_enabled=false
		elif arg=="--legacy-mesh-placeholder":preload("res://scripts/world3d/world_document.gd").legacy_mesh_placeholder_enabled=true
		elif arg=="--copied-index-projection":preload("res://scripts/world3d/deferred_asset_loader.gd").owned_index_projection_enabled=false
		elif arg=="--regather-retirement-plan":preload("res://scripts/world3d/stream_index.gd").reuse_owned_retirement_plan_enabled=false
		elif arg=="--renderer-lod-readback":CpuMesh.importer_lod_hints_enabled=false
		elif arg=="--serial-retirement-schema":preload("res://scripts/world3d/stream_index.gd").retirement_schema_workers=0
		elif arg=="--allocated-index-signatures":preload("res://scripts/world3d/stream_index_preparation.gd").shared_signature_defaults_enabled=false
		elif arg=="--untyped-demand-scan":preload("res://scripts/world3d/deferred_asset_loader.gd").typed_demand_scan_enabled=false
		elif arg=="--eager-retirement-pending-scan":preload("res://scripts/world3d/native_residency.gd").lazy_pending_scan_enabled=false
		elif arg=="--single-asset-retirement":preload("res://scripts/world3d/asset_residency.gd").retirement_batching_enabled=false
		elif arg=="--sync-loading-batches":preload("res://scripts/world3d/world_stream.gd").sliced_loading_batches_enabled=false
		elif arg=="--legacy-progressive-batches":preload("res://scripts/world3d/world_stream.gd").progressive_white_batches_enabled=false
		elif arg=="--legacy-priority-arrivals":preload("res://scripts/world3d/world_stream.gd").incremental_collision_priority_enabled=false
		elif arg=="--join-loading-workers":preload("res://scripts/world3d/ground_batcher.gd").legacy_loading_worker_wait_enabled=true
		elif arg=="--legacy-retirement-validation":preload("res://scripts/world3d/world_stream.gd").legacy_retirement_validation_enabled=true
		elif arg=="--rebuild-owned-retirement":preload("res://scripts/world3d/stream_index.gd").legacy_owned_rebuild_enabled=true
		elif arg=="--single-native-retirement":preload("res://scripts/world3d/native_residency.gd").retirement_batching_enabled=false
		elif arg=="--legacy-residency-scans":
			preload("res://scripts/world3d/asset_residency.gd").legacy_retirement_source_scan_enabled=true
			preload("res://scripts/world3d/world_navigation.gd").legacy_retirement_geometry_scan_enabled=true
		elif arg=="--without-taa":root.use_taa=false
		elif arg=="--white-material":white_material=true;preload("res://scripts/world3d/runtime_probe_controls.gd").enable_white_materials()
		elif arg=="--late-white-gltf":preload("res://scripts/world3d/runtime_probe_controls.gd").early_white_gltf_enabled=false
		elif arg=="--serial-index-definitions":preload("res://scripts/world3d/map_dependency_index.gd").parallel_definition_checks=false
		elif arg=="--native-index-snapshot":preload("res://scripts/world3d/stream_index_preparation.gd").native_snapshot_validation_enabled=true
		elif arg=="--ordinary-index-validation":preload("res://scripts/world3d/stream_index_preparation.gd").native_snapshot_validation_enabled=false
		elif arg=="--serial-spec-snapshots":preload("res://scripts/world3d/spec_snapshot_validation.gd").workers=0
		elif arg=="--without-sliced-retirement-schema":preload("res://scripts/world3d/world_stream.gd").sliced_retirement_schema_enabled=false
		elif arg=="--uncapped-runtime":uncapped_runtime=true
		elif arg=="--mesh-cancel-during-capture":cancel_during_capture=true
		elif arg=="--without-collision-prefetch":preload("res://scripts/world3d/stream_collision_preparer.gd").prefetch_enabled=false
		elif arg=="--cold-index":cold_index=true
		elif arg=="--cold-index-disk-roundtrip":preload("res://scripts/world3d/map_loader.gd").cold_index_handoff_enabled=false
		elif arg=="--legacy-road-schema":preload("res://scripts/world3d/road_surface.gd").boolean_schema_enabled=false
		elif arg=="--unbatched-index-paths":preload("res://scripts/world3d/map_dependency_index.gd").classification_path_batching=false
		elif arg=="--recursive-resource-scalars":preload("res://scripts/world3d/map_resource_store.gd").inline_numeric_safety_enabled=false
		elif arg=="--serial-native-classification":preload("res://scripts/world3d/map_dependency_index.gd").parallel_native_classification=false
		elif arg=="--duplicate-prefab-decodes":preload("res://scripts/world3d/house_prefab.gd").coalesce_decodes=false
		elif arg=="--serial-imported-sources":preload("res://scripts/world3d/map_dependency_index.gd").parallel_imported_sources=false
		elif arg=="--recursive-numeric-rows":preload("res://scripts/world3d/document_schema.gd").numeric_rows_enabled=false
		elif arg=="--late-stale-rejection":preload("res://scripts/world3d/map_dependency_index.gd").early_stale_rejection=false
		elif arg=="--verify-resource-packages":preload("res://scripts/world3d/runtime_package_policy.gd").verify_packages=true
		elif arg.begins_with("--mesh-cancel-after-stream-frames="):cancel_stream_frames=arg.trim_prefix("--mesh-cancel-after-stream-frames=").to_int()
		elif arg=="--main-thread-model-scenes":preload("res://scripts/world3d/model_parse_preparation.gd").initial_scene_preparation_enabled=false
		elif arg=="--main-thread-initial-capture":preload("res://scripts/world3d/map_loader.gd").initial_cpu_capture_enabled=false
		elif arg=="--tree-adoption":preload("res://scripts/world3d/map_loader.gd").initial_static_specs_enabled=false
		elif arg=="--main-thread-prefab-textures":
			preload("res://scripts/world3d/deferred_asset_loader.gd").prefab_texture_preparation_enabled=false
			preload("res://scripts/world3d/deferred_asset_loader.gd").shared_prefab_texture_preparation_enabled=false
		elif arg=="--background-prefab-textures":
			preload("res://scripts/world3d/deferred_asset_loader.gd").prefab_texture_preparation_enabled=true
			preload("res://scripts/world3d/deferred_asset_loader.gd").shared_prefab_texture_preparation_enabled=true
		elif arg=="--texture-stage-profile":
			preload("res://scripts/world3d/runtime_texture_cache.gd").profile_enabled=true
			preload("res://scripts/world3d/surface_materials.gd").texture_profile_enabled=true
			preload("res://scripts/world3d/runtime_texture_cache.gd").reset_profile()
		elif arg.begins_with("--runtime-seconds="):runtime_seconds=arg.trim_prefix("--runtime-seconds=").to_float()
	if output.is_empty() or not preload("res://scripts/world3d/map_paths.gd").allowed(output,"D:/code/rmmo_runtime/review_artifacts"):quit(2);return
	if preload("res://scripts/world3d/runtime_probe_controls.gd").discard_map_textures and not preload("res://scripts/world3d/runtime_probe_controls.gd").white_materials:
		# Native products embed texture resources; they cannot enter a no-texture
		# control or its separately keyed procedural cache.
		preload("res://scripts/world3d/compiled_asset_cache.gd").enabled=false
	if cold_index:
		var cache:String=preload("res://scripts/world3d/map_dependency_index.gd").cache_path(MAP,"D:/code/rmmo_runtime")
		var backup:String=output+".previous_dependency_index.bin"
		if not preload("res://scripts/world3d/map_paths.gd").allowed(cache,"D:/code/rmmo_runtime/cache/world3d/dependency_indexes") or FileAccess.file_exists(backup):quit(2);return
		if FileAccess.file_exists(cache) and DirAccess.rename_absolute(cache,backup)!=OK:quit(2);return
		report.cache_control="Only this map's derived dependency index moved aside, bytes preserved beside this report. Other derived caches and OS caches retained."
	report.map=MAP;report.map_sha=FileAccess.get_sha256(MAP);report.engine=Engine.get_version_info();report.pid=OS.get_process_id()
	report.controls={"hud":preload("res://scripts/world3d/runtime_probe_controls.gd").hud_enabled,"map_textures":not preload("res://scripts/world3d/runtime_probe_controls.gd").discard_map_textures,"compiled":preload("res://scripts/world3d/compiled_asset_cache.gd").enabled}
	report.controls.white_native=report.controls.compiled and preload("res://scripts/world3d/white_native_asset_cache.gd").active() and preload("res://scripts/world3d/white_native_asset_cache.gd").enabled
	report.controls.worker_model_scenes=preload("res://scripts/world3d/model_parse_preparation.gd").initial_scene_preparation_enabled
	report.controls.cold_index_handoff=preload("res://scripts/world3d/map_loader.gd").cold_index_handoff_enabled
	report.controls.cold_read_diagnostics=preload("res://scripts/world3d/map_loader.gd").cold_read_diagnostics_enabled
	report.controls.boolean_road_schema=preload("res://scripts/world3d/road_surface.gd").boolean_schema_enabled
	report.controls.classification_path_batching=preload("res://scripts/world3d/map_dependency_index.gd").classification_path_batching
	report.controls.parallel_native_classification=preload("res://scripts/world3d/map_dependency_index.gd").parallel_native_classification
	report.controls.parallel_imported_sources=preload("res://scripts/world3d/map_dependency_index.gd").parallel_imported_sources
	report.controls.numeric_rows=preload("res://scripts/world3d/document_schema.gd").numeric_rows_enabled
	report.controls.early_stale_rejection=preload("res://scripts/world3d/map_dependency_index.gd").early_stale_rejection
	report.controls.trusted_resource_packages=preload("res://scripts/world3d/runtime_package_policy.gd").trusted()
	report.controls.coalesce_prefab_decodes=preload("res://scripts/world3d/house_prefab.gd").coalesce_decodes
	report.controls.inline_numeric_safety=preload("res://scripts/world3d/map_resource_store.gd").inline_numeric_safety_enabled
	report.controls.sliced_initial_capture=preload("res://scripts/world3d/map_loader.gd").initial_cpu_capture_enabled
	report.controls.private_static_specs=preload("res://scripts/world3d/map_loader.gd").initial_static_specs_enabled
	report.controls.white_material=white_material
	report.controls.unshaded_shadow_materials=preload("res://scripts/world3d/building_shadow_proxy.gd").unshaded_materials_enabled
	report.controls.candle_cpu_index=preload("res://scripts/world3d/candle_sconce_mesh.gd").cpu_index_enabled
	report.controls.legacy_mesh_placeholder=preload("res://scripts/world3d/world_document.gd").legacy_mesh_placeholder_enabled
	report.controls.owned_index_projection=preload("res://scripts/world3d/deferred_asset_loader.gd").owned_index_projection_enabled
	report.controls.reuse_owned_retirement_plan=preload("res://scripts/world3d/stream_index.gd").reuse_owned_retirement_plan_enabled
	report.controls.importer_lod_hints=CpuMesh.importer_lod_hints_enabled
	report.controls.retirement_schema_workers=preload("res://scripts/world3d/stream_index.gd").retirement_schema_workers
	report.controls.sliced_retirement_schema=preload("res://scripts/world3d/world_stream.gd").sliced_retirement_schema_enabled
	report.controls.native_index_snapshot=preload("res://scripts/world3d/stream_index_preparation.gd").native_snapshot_validation_enabled
	report.controls.spec_snapshot_workers=preload("res://scripts/world3d/spec_snapshot_validation.gd").workers
	report.controls.typed_demand_scan=preload("res://scripts/world3d/deferred_asset_loader.gd").typed_demand_scan_enabled
	report.controls.lazy_retirement_pending_scan=preload("res://scripts/world3d/native_residency.gd").lazy_pending_scan_enabled
	report.controls.asset_retirement_batching=preload("res://scripts/world3d/asset_residency.gd").retirement_batching_enabled
	report.controls.shared_signature_defaults=preload("res://scripts/world3d/stream_index_preparation.gd").shared_signature_defaults_enabled
	report.controls.batched_road_reference_jobs=preload("res://scripts/world3d/deferred_asset_loader.gd").native_reference_batching_enabled
	report.controls.repeated_gltf_state_getters=preload("res://scripts/world3d/gltf_map_io.gd").legacy_state_array_getters_enabled
	report.controls.early_white_gltf=preload("res://scripts/world3d/runtime_probe_controls.gd").early_white_gltf_enabled
	report.controls.early_white_camera=early_white_camera
	report.controls.white_debug_draw="--white-debug-draw" in OS.get_cmdline_user_args()
	report.controls.startup_render_context=preload("res://scripts/world3d/map_loader.gd").startup_render_context_enabled
	report.controls.startup_render_context_frames=preload("res://scripts/world3d/map_loader.gd").startup_render_context_frames
	report.controls.progressive_white_batches=preload("res://scripts/world3d/world_stream.gd").progressive_white_batches_enabled
	report.controls.incremental_collision_priority=preload("res://scripts/world3d/world_stream.gd").incremental_collision_priority_enabled
	report.controls.sliced_loading_batches=preload("res://scripts/world3d/world_stream.gd").sliced_loading_batches_enabled
	report.controls.join_loading_workers=preload("res://scripts/world3d/ground_batcher.gd").legacy_loading_worker_wait_enabled
	report.controls.legacy_retirement_validation=preload("res://scripts/world3d/world_stream.gd").legacy_retirement_validation_enabled
	report.controls.batched_native_retirement=preload("res://scripts/world3d/native_residency.gd").retirement_batching_enabled
	report.controls.legacy_residency_source_scan=preload("res://scripts/world3d/asset_residency.gd").legacy_retirement_source_scan_enabled
	report.controls.legacy_residency_geometry_scan=preload("res://scripts/world3d/world_navigation.gd").legacy_retirement_geometry_scan_enabled
	report.controls.parallel_definition_checks=preload("res://scripts/world3d/map_dependency_index.gd").parallel_definition_checks
	report.controls.background_prefab_textures=preload("res://scripts/world3d/deferred_asset_loader.gd").prefab_texture_preparation_enabled
	report.controls.shared_prefab_textures=preload("res://scripts/world3d/deferred_asset_loader.gd").shared_prefab_texture_preparation_enabled
	report.controls.collision_prefetch=preload("res://scripts/world3d/stream_collision_preparer.gd").prefetch_enabled
	preload("res://scripts/world3d/imported_building.gd").single_read_sources_enabled=not "--legacy-imported-source-checks" in OS.get_cmdline_user_args()
	report.controls.single_read_imported_sources=preload("res://scripts/world3d/imported_building.gd").single_read_sources_enabled
	# The all-cold experiment must also exclude the derived resource read layout.
	# Native authored model products remain inputs, not runtime cache hits.
	preload("res://scripts/world3d/map_resource_store.gd").resource_bundles_enabled=not ("--without-resource-bundle" in OS.get_cmdline_user_args() or "--without-derived-geometry-cache" in OS.get_cmdline_user_args())
	report.controls.resource_bundles=preload("res://scripts/world3d/map_resource_store.gd").resource_bundles_enabled
	# Hashing every source only identifies the measured code; it is not game work,
	# so it runs beside the measurement and is joined before the final comparison.
	report.startup.sources_begin_us=Time.get_ticks_usec()
	sources_task=WorkerThreadPool.add_task(func():
		measured_sources=source_snapshot()
		measured_sources["res://tools/profile_axel_game_pipeline.gd"]=FileAccess.get_sha256("res://tools/profile_axel_game_pipeline.gd")
		measured_sources_us=Time.get_ticks_usec())
	report.startup.sources_end_us=Time.get_ticks_usec()
	report.limits="Fresh process, existing OS/derived caches, unchanged normal production demand and readiness. Frame monitor overhead measured separately; nested trace spans are not additive CPU time. Renderer memory is global, admission estimates are not RSS/VRAM."
	Engine.max_fps=60;root.size=Vector2i(1440,900);root.content_scale_size=root.size
	if "--uncapped-loading" in OS.get_cmdline_user_args():
		Engine.max_fps=0
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED,root.get_window_id())
	report.loading_frame_policy={"max_fps":Engine.max_fps,"vsync":DisplayServer.window_get_vsync_mode(root.get_window_id())}
	check(DisplayServer.get_name()!="headless","private desktop GPU game mode")
	report.startup.session_begin_us=Time.get_ticks_usec()
	var session=root.get_node("GameSession")
	preload("res://tools/world3d_test_character.gd").ensure(self)
	session.spawn_data={"character":session.selected_character.duplicate(true),"equipment":[],"world_mode":"world3d"}
	session.world3d_map_path=MAP
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(MAP))
	for node:Dictionary in data.nodes:
		if node.get("extras",{}).has("spawn"):
			var spawn:Array=node.extras.spawn;session.world3d_spawn=Vector3(spawn[0],spawn[1],spawn[2]);report.requested_spawn=spawn;break
	data.clear()
	report.startup.spawn_parsed_us=Time.get_ticks_usec()
	began=Time.get_ticks_usec();last=began;sampling=true;process_frame.connect(observe)
	report.begin_ticks_us=began
	report.cpu_time_anchor={"ticks_us":Time.get_ticks_usec(),"unix_us":int(Time.get_unix_time_from_system()*1000000)}
	if monitored:monitor=preload("res://tools/load_monitor.gd").new();monitor.start(self)
	create_timer(600 if "--settle-demands" in OS.get_cmdline_user_args() else 420).timeout.connect(func():report.failures.append("game entry timeout");finish(2))
	print("AXEL_PIPELINE_BEGIN ",report.map_sha);save()
	if mesh_only:
		await run_mesh_only(session.world3d_spawn);return
	session.go_world_3d()
	while true:
		await process_frame
		if current_scene==null:continue
		if current_scene.has_meta("entry_loading_error") or current_scene.has_node("FailActions"):
			report.failures.append("production loading rejected map");finish(1);return
		if current_scene.has_method("is_world_ready") and current_scene.is_world_ready() and not session._world_transition_active:break
	report.entry_ms=(Time.get_ticks_usec()-began)/1000.;phase="playable";runtime_frame_policy()
	var world=current_scene
	check(world._player!=null and not world._player.input_locked and (world._hud!=null or not report.controls.hud),"ordinary entry hands off avatar and requested HUD")
	report.session_profile=session.last_loading_profile.duplicate(true);report.world_profile=world.loading_profile.duplicate(true)
	report.map_profile=world._map_root.get_meta("load_profile",{}).duplicate(true)
	report.cartography={"shapes":world._map_data.shapes.size(),"markers":world._map_data.markers.size()}
	report.spawn=[world._player.position.x,world._player.position.y,world._player.position.z]
	print("AXEL_ENTRY_READY ms=",report.entry_ms);save()
	var until:=Time.get_ticks_usec()+int(runtime_seconds*1000000.)
	for node:Node in [world,world._camera,world._player,world._weather,world._outline,world._hud,world._player._model,world._weather.wind_objects]:
		if is_instance_valid(node):node.set_meta("profile_frame",true)
	report.runtime=[]
	while Time.get_ticks_usec()<until:
		await process_frame
		var row:Dictionary={"at_ms":(Time.get_ticks_usec()-began)/1000.}
		for key:String in ["frame_timings","traversal_timing"]:
			if world.has_meta(key):row[key]=world.get_meta(key).duplicate(true)
		if world._player.has_meta("physics_timing"):row.player=world._player.get_meta("physics_timing").duplicate(true)
		for key:String in ["_weather","_hud","_outline"]:
			var node:Node=world.get(key)
			if is_instance_valid(node) and node.has_meta("frame_timing"):row[key]=node.get_meta("frame_timing").duplicate(true)
		report.runtime.append(row)
	report.frame_work_budget=preload("res://scripts/world3d/frame_work_budget.gd").report()
	report.navigation=world._navigation.capability_status()
	report.final_player={"position":[world._player.position.x,world._player.position.y,world._player.position.z],"on_floor":world._player.is_on_floor(),"input_locked":world._player.input_locked}
	var queue:Node=world._map_root.get_node_or_null("DeferredAssets")
	if queue!=null:
		report.deferred_error=queue.error;report.instance_errors=queue.instance_errors.duplicate()
		check(queue.error.is_empty() and queue.instance_errors.is_empty(),"runtime deferred publications succeed")
	if preload("res://scripts/world3d/runtime_texture_cache.gd").profile_enabled:
		report.texture_stages=preload("res://scripts/world3d/runtime_texture_cache.gd").profile_snapshot()
		report.paint_texture_stages=preload("res://scripts/world3d/surface_materials.gd").profile_snapshot()
	finish(0 if report.failures.is_empty() else 1)
func run_mesh_only(spawn:Vector3)->void:
	report.scope="MapLoader plus core streaming only; no World3D gameplay, avatar, HUD, radar, navigation, weather or events. This isolates geometry cost and is not a full game entry."
	var host:=Node3D.new();root.add_child(host);current_scene=host
	if loading_disable_3d:
		root.get_viewport().disable_3d=true
		report.loading_disable_3d=true
	if not "--without-white-load-cover" in OS.get_cmdline_user_args():
		# Cover the loader itself, not only the post-loader demand settle. This
		# mirrors the production loading screen and keeps the first heavy frame
		# off the visible desktop.
		initial_cover=preload("res://scripts/world3d/initial_loading_cover.gd").new()
		root.add_child(initial_cover)
		await process_frame
		root.get_viewport().disable_3d=true
	if early_white_camera:create_white_camera(host,spawn)
	var loader:=preload("res://scripts/world3d/map_loader.gd").new();loader.near_first=true
	if cancel_during_capture:
		loader.progress.connect(func(stage:String,_done:int,_total:int):
			if stage=="准备模型 CPU 几何":report.cancelled_during_capture=true;loader.cancel())
	root.add_child(loader);loader.start(MAP,spawn)
	if cancel_during_capture:
		while is_instance_valid(loader):await process_frame
		var drainer:Node=root.get_node_or_null("AssetWorkerDrainer")
		check(report.get("cancelled_during_capture",false) and preload("res://scripts/world3d/runtime_asset_cache_scope.gd")._scopes.is_empty() and preload("res://scripts/world_editor/asset_library.gd")._scenes.is_empty() and (drainer==null or drainer.jobs.is_empty()),"real white loading cancellation during CPU slices releases templates, map scopes and worker jobs")
		finish(0);return
	var result:Array=await loader.finished
	report.loader_error=str(result[2])
	check(result[0]!=null and str(result[2]).is_empty(),"pure geometry loader succeeds")
	if result[0]==null:finish(1);return
	mesh_map=result[0]
	if Trace.methods_enabled:mesh_map.set_meta("profile_frame",true)
	if white_material:
		# Unshaded debug draw still runs custom spatial shaders. This separate
		# control removes material/shader rendering while preserving every mesh,
		# transform and collision resource. It changes batch material grouping.
		var count:=0;var shaders:=0
		for spec:Dictionary in mesh_map.get_meta("stream_library",[]):
			var mesh:Mesh=spec.mesh
			if spec.get("material_override") is ShaderMaterial:shaders+=1
			for slot:int in mesh.get_surface_count():
				if mesh.surface_get_material(slot) is ShaderMaterial:shaders+=1
			for override:Variant in spec.get("surface_overrides",[]):
				if override is ShaderMaterial:shaders+=1
			whiten_spec(spec);count+=1
		report.white_material_control={"specs":count,"original_shader_material_slots":shaders,"geometry_and_collision_resources_replaced":false,"batch_material_grouping_changed":true}
	host.add_child(mesh_map)
	if initial_cover!=null:
		var deferred:=mesh_map.get_node_or_null("DeferredAssets")
		if deferred!=null and deferred.begin_loading_cover(host,initial_cover):
			report.white_load_cover=true
		else:
			root.get_viewport().disable_3d=false
			initial_cover.retire();initial_cover=null
	report.loader_ms=(Time.get_ticks_usec()-began)/1000.;report.map_profile=mesh_map.get_meta("load_profile",{}).duplicate(true)
	if not early_white_camera:create_white_camera(host,spawn)
	var stream=preload("res://scripts/world3d/world_stream.gd")
	var stream_frames:=0
	report.white_sync_spikes=[]
	# Production World3D defers standalone uploads of batch candidates during
	# this covered entry loop (world_3d.gd). Mirror it unless measuring the
	# pre-round-156 harness behaviour for comparison with older evidence.
	var entry_defer:=not "--legacy-entry-upload" in OS.get_cmdline_user_args()
	report.entry_defer_upload=entry_defer
	if entry_defer:mesh_map.set_meta("defer_source_upload",true)
	while not mesh_map.has_meta("stream_chunk"):
		if Trace.methods_enabled:
			var preparer:Node=mesh_map.get_node_or_null("StreamCollisionPreparer")
			if preparer!=null:preparer.profile_enabled=true
		var sync_started:=Time.get_ticks_usec()
		stream.sync(mesh_map,host,spawn,stream.LOAD_BUDGET)
		if Time.get_ticks_usec()-sync_started>50000 and report.white_sync_spikes.size()<32:
			report.white_sync_spikes.append({"ms":(Time.get_ticks_usec()-sync_started)/1000.,"at_ms":(Time.get_ticks_usec()-began)/1000.,"cursor":mesh_map.get_meta("stream_cursor",0),"jobs":mesh_map.get_meta("stream_jobs",[]).size(),"adopt":mesh_map.get_meta("stream_adopt_ms",{}).duplicate(true),"load":mesh_map.get_meta("stream_load_profile_us",{}).duplicate(true)})
		stream_frames+=1
		if cancel_stream_frames>0 and stream_frames>=cancel_stream_frames:
			report.cancelled_during_white_stream=true;finish(0);return
		await process_frame
	if entry_defer:mesh_map.remove_meta("defer_source_upload")
	report.stream_settled_ms=(Time.get_ticks_usec()-began)/1000.
	var batches:Node=mesh_map.get_node_or_null("GroundRenderBatches")
	while batches!=null and (not batches._preparation.is_empty() or not batches.pending.is_empty() or not batches._workers.is_empty()):await process_frame
	report.batches_ready_ms=(Time.get_ticks_usec()-began)/1000.
	await RenderingServer.frame_post_draw
	report.entry_ms=(Time.get_ticks_usec()-began)/1000.;phase="playable";runtime_frame_policy()
	print("AXEL_MESH_READY ms=",report.entry_ms);save()
	await create_timer(runtime_seconds).timeout
	finish(0 if report.failures.is_empty() else 1)
func create_white_camera(host:Node3D,spawn:Vector3)->void:
	var camera:=Camera3D.new();host.add_child(camera);camera.position=spawn+Vector3(0,4,7);camera.look_at(spawn+Vector3(0,1,0));camera.current=true;camera.fov=55.
	# White unshaded materials already provide the isolation. Keep the normal
	# renderer path; a separate control can reproduce the earlier debug mode.
	if "--white-debug-draw" in OS.get_cmdline_user_args():root.debug_draw=Viewport.DEBUG_DRAW_UNSHADED

func whiten_spec(spec:Dictionary)->void:
	preload("res://scripts/world3d/runtime_probe_controls.gd").whiten_spec(spec)
