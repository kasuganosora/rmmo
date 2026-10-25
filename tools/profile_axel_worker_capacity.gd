extends "res://tools/profile_axel_predictive_streaming.gd"
## Controlled capacity experiment. Never changes the byte admission envelope.
var capacity_applied:=false
var settled_batch_budget:=0
var next_collision_state:=0
var collision_state_probe:=false
var capacity_timeline_enabled:=false
var capacity_timeline:Array=[]
var texture_job_timeline:Array=[]
var frame_split_probe:=false
var frame_split:Array=[]
var frame_split_previous:Dictionary={}
var completed_job_audit_enabled:=false
var completed_job_audit:RefCounted
var completed_job_audit_samples:Array=[]
var draw_marks:=PackedInt64Array([0,0,0,0])
func sample_frame_split(tick_us:int)->void:
	# Previous frame's engine timings plus this frame's geometry tick. Cheap,
	# read-only counters; no per-item iteration.
	var viewport:=root.get_viewport_rid()
	if frame_split.is_empty():
		RenderingServer.viewport_set_measure_render_time(viewport,true)
		RenderingServer.frame_pre_draw.connect(func():draw_marks[0]=Time.get_ticks_usec();draw_marks[3]=draw_marks[0]-draw_marks[1] if draw_marks[1]>0 else -1)
		RenderingServer.frame_post_draw.connect(func():draw_marks[1]=Time.get_ticks_usec();draw_marks[2]=draw_marks[1]-draw_marks[0])
	var queue:Node=mesh_map.get_node("DeferredAssets")
	var budgets:Dictionary=queue.profile.get("main_thread_budgets",{}).get("interactive",{})
	var batcher:Node=mesh_map.get_node_or_null("GroundRenderBatches")
	var current:={"svc_us":int(budgets.get("elapsed_us",0)),"pub_us":int(budgets.get("publication_us",0)),"pub_units":int(budgets.get("publication_units",0))}
	var row:Array=[Time.get_ticks_usec()-began,phase,tick_us,
		current.svc_us-int(frame_split_previous.get("svc_us",current.svc_us)),
		current.pub_us-int(frame_split_previous.get("pub_us",current.pub_us)),
		current.pub_units-int(frame_split_previous.get("pub_units",current.pub_units)),
		int(Performance.get_monitor(Performance.TIME_PROCESS)*1000000.),
		int(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000000.),
		int(RenderingServer.viewport_get_measured_render_time_cpu(viewport)*1000.),
		int(RenderingServer.get_frame_setup_time_cpu()*1000.),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)),
		mesh_map.get_meta("stream_jobs",[]).size(),mesh_map.get_meta("stream_cursor",0),
		batcher.pending.size() if batcher!=null else -1,
		draw_marks[2],draw_marks[3]]
	frame_split_previous=current
	frame_split.append(row)
	report.frame_split={"columns":["at_us","phase","geometry_tick_us","deferred_service_us","publication_us","publication_units","engine_process_us","engine_physics_us","render_cpu_us","frame_setup_cpu_us","draw_calls","primitives","stream_jobs","stream_cursor","batches_pending","previous_draw_wall_us","previous_process_wall_us"],"rows":frame_split}
var publication_block_probe:=false
var publication_blocks:Array=[]
var job_lifecycle:Dictionary={}
var publication_job_samples:Array=[]
func sample_publication_blocks()->void:
	# Read-only observation of accepted-but-unconsumed jobs. Calls only
	# side-effect-free predicates; never publishes, dispatches or reorders.
	var queue:Node=mesh_map.get_node("DeferredAssets")
	var now:=Time.get_ticks_usec()-began
	var counts:Dictionary={}
	var supports_waiting:Dictionary={}
	var job_rows:Array=[]
	var unstarted:=0
	for path:String in queue._demanded_by_path:
		if not queue._jobs.has(path) and not queue.path_errors.has(path):unstarted+=1
	counts.unstarted_paths=unstarted
	for path:String in queue._jobs:
		var job:Dictionary=queue._jobs[path]
		var life:Dictionary=job_lifecycle.get(path,{})
		var generation:int=job.token.get_instance_id()
		if life.is_empty() or life.get("generation")!=generation:
			life={"generation":generation,"seen_us":now,"items":job.get("publication_ids",[]).size(),"phase":phase};job_lifecycle[path+"#"+str(now)]=life;job_lifecycle[path]=life
		if job.has("worker") and not life.has("worker_seen_us"):life.worker_seen_us=now
		if not job.has("worker") and job.has("result") and not life.has("joined_us"):life.joined_us=now
		if job.get("accepted",false) and not life.has("accepted_us"):life.accepted_us=now
		life.last_us=now
		if not job.get("accepted",false):
			var state:="live" if job.has("worker") and job.worker.is_alive() else ("joinable" if job.has("worker") else ("ready" if job.has("result") else "other"))
			counts["job_"+state]=int(counts.get("job_"+state,0))+1
			continue
		counts.job_accepted=int(counts.get("job_accepted",0))+1
		if job.has("instance_preparation"):counts.job_instance_cursor=int(counts.get("job_instance_cursor",0))+1
		var staged:Dictionary=job.get("staged",{})
		var reasons:Dictionary={}
		for uuid:String in job.get("publication_ids",[]):
			var item:Dictionary=queue._demanded_by_id.get(uuid,{})
			var reason:="eligible"
			if item.is_empty():reason="undemanded"
			elif item.get("published",false):reason="published"
			elif queue.instance_errors.has(uuid) or queue.path_errors.has(path):reason="failed"
			elif staged.has(uuid):reason="staged_group"
			elif item.has("reference_entry") and not item.get("reference_prepared",false):reason="reference_unprepared"
			elif not item.get("native_reference",false) and not item.get("model_verified",false):reason="unverified"
			else:
				var supports:Dictionary=queue._runtime_building_supports.get(uuid,{})
				var waiting:=false
				for id:String in supports:
					var support:Dictionary=queue._pending_by_record_id.get(id,{})
					if not support.is_empty() and not support.get("published",false):waiting=true;supports_waiting[id]=support.path
				if waiting:reason="support"
				else:
					var collision:Dictionary=queue._collision_publication_status(uuid)
					if collision.get("owned",false) and collision.get("pending",false):reason="collision"
			counts[reason]=int(counts.get(reason,0))+1
			reasons[reason]=int(reasons.get(reason,0))+1
		var instance:Dictionary=job.get("instance_preparation",{})
		var cursor_work:int=int(instance.cursor.profile.get("elapsed_us",0)) if instance.has("cursor") else 0
		var retained_bytes:=0;var index_work:=0
		for packet:Dictionary in job.get("publication_packets",{}).values():
			retained_bytes+=int(packet.get("workspace_charge",0))
			if packet.has("index_preparation"):index_work+=int(packet.index_preparation.profile.get("elapsed_us",0))
		job_rows.append([path,generation,queue._job_consumed(job),reasons,staged.size(),instance.get("uuid",""),instance.get("phase",""),cursor_work,queue._publication_queues.get(path,{}).get("cursor",0),queue._path_priority(path),queue._path_rank(path),job.get("dispatch_us",0),job.get("publication_packets",{}).size(),retained_bytes,index_work])
	counts.support_targets=supports_waiting.size()
	var budgets:Dictionary=queue.profile.get("main_thread_budgets",{}).get("interactive",{})
	counts.pub_units=int(budgets.get("publication_units",0));counts.pub_us=int(budgets.get("publication_us",0))
	counts.svc_us=int(budgets.get("elapsed_us",0));counts.svc_frames=int(budgets.get("frames",0))
	counts.demand_revision=queue._demand_revision;counts.candidates_revision=queue._candidates_revision
	counts.frame=Engine.get_process_frames()
	var support_jobs:Dictionary={}
	for id:String in supports_waiting:
		var path:String=supports_waiting[id]
		var job:Dictionary=queue._jobs.get(path,{})
		var state:="no_job" if job.is_empty() else ("accepted" if job.get("accepted",false) else ("live" if job.has("worker") else "ready"))
		support_jobs[state]=int(support_jobs.get(state,0))+1
	if not support_jobs.is_empty():counts.support_job_states=support_jobs
	publication_blocks.append([now,phase,counts])
	publication_job_samples.append([now,phase,job_rows])
	report.publication_jobs={"columns":["path","generation","consumed","reasons","staged","instance_uuid","instance_phase","instance_work_us","queue_cursor","priority","rank","dispatch_us","retained_packets","replacement_workspace_bytes","index_work_us"],"samples":publication_job_samples,"contract":"Diagnostic only: accepted result owners and progress after each geometry tick. Reasons describe commit dependencies; private instance work may progress despite those dependencies. No eligibility mutation; integer IDs never retain task tokens or results. unstarted_paths is separate from unpublished instances."}
	report.publication_blocks={"samples":publication_blocks,"contract":"Per geometry tick, read-only classification of unpublished items in accepted jobs, first failing gate only."}
	if publication_blocks.size()%30!=1 and not queue._jobs.is_empty():return
	var lifecycles:Array=[]
	for key:String in job_lifecycle:
		if "#" in key:lifecycles.append([key]+[job_lifecycle[key].get("seen_us",0),job_lifecycle[key].get("joined_us",-1),job_lifecycle[key].get("accepted_us",-1),job_lifecycle[key].get("last_us",-1),job_lifecycle[key].get("items",0),job_lifecycle[key].get("phase","")])
	report.job_lifecycle={"columns":["path#seen","seen_us","joined_us","accepted_us","last_us","items","phase"],"rows":lifecycles}
func _initialize()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg=="--serial-chunk-textures":preload("res://scripts/world3d/deferred_asset_loader.gd").parallel_texture_preparation_enabled=false
		if arg=="--without-texture-plan-reuse":preload("res://scripts/world3d/deferred_asset_loader.gd").texture_plan_reuse_enabled=false
		if arg=="--sync-texture-headers":preload("res://scripts/world3d/deferred_asset_loader.gd").async_texture_headers_enabled=false
		if arg=="--full-cache-trims":preload("res://scripts/world3d/surface_materials.gd").incremental_cache_budget_enabled=false
		if arg=="--full-stream-adoption":preload("res://scripts/world3d/world_stream.gd").incremental_adoption_enabled=false
		if arg=="--without-completed-owner-drain":preload("res://scripts/world3d/publication_order.gd").completed_owner_drain_enabled=false
		if arg=="--without-native-prefab-direct-specs":preload("res://scripts/world3d/deferred_asset_loader.gd").native_prefab_direct_specs_enabled=false
		if arg=="--completed-job-audit":
			completed_job_audit_enabled=true
			completed_job_audit=preload("res://tools/completed_job_audit_probe.gd").new()
			preload("res://scripts/world3d/completed_job_trace.gd").start()
		if arg=="--without-white-priority-turns":preload("res://scripts/world3d/publication_order.gd").white_priority_turns_enabled=false
		if arg=="--without-independent-instance-preparation":preload("res://scripts/world3d/deferred_asset_loader.gd").independent_instance_preparation_enabled=false
		if arg=="--without-white-building-turns":preload("res://scripts/world3d/publication_order.gd").white_building_turns_enabled=false
		if arg=="--without-support-set-ids":preload("res://scripts/world3d/deferred_asset_loader.gd").support_set_ids_enabled=false
		if arg=="--without-retirement-delta-reuse":preload("res://scripts/world3d/stream_index.gd").retirement_delta_reuse_enabled=false
		if arg=="--without-retirement-prefix-reuse":preload("res://scripts/world3d/stream_index.gd").retirement_bucket_prefix_reuse_enabled=false
		if arg=="--without-retirement-frame-retry":
			preload("res://scripts/world3d/native_residency.gd").frame_retry_enabled=false
			preload("res://scripts/world3d/asset_residency.gd").frame_retry_enabled=false
		if arg=="--without-shadow-face-preparation":preload("res://scripts/world3d/house_prefab.gd").shadow_face_preparation_enabled=false
		if arg=="--without-lazy-demand-snapshot":preload("res://scripts/world3d/deferred_asset_loader.gd").lazy_demand_snapshot_enabled=false
		if arg=="--without-terrain-shape-retirement":preload("res://scripts/world3d/ground_cpu_mesh.gd").terrain_shape_retirement_enabled=false
		if arg=="--without-source-collision-faces":preload("res://scripts/world3d/house_prefab.gd").source_collision_faces_enabled=false
		if arg=="--without-prepared-prefab-face-handoff":preload("res://scripts/world3d/house_prefab.gd").prepared_face_handoff_enabled=false
		if arg=="--profile-procedural-uploads":preload("res://scripts/world3d/prepared_cpu_upload.gd").profile_enabled=true
		if arg=="--without-procedural-upload-preparation":preload("res://scripts/world3d/prepared_cpu_upload.gd").enabled=false
		if arg=="--without-lazy-navigation-snapshot":preload("res://scripts/world3d/world_navigation.gd").lazy_retirement_snapshot_enabled=false
		if arg=="--without-membership-row-reuse":preload("res://scripts/world3d/deferred_asset_loader.gd").reuse_demand_membership_rows_enabled=false
		if arg=="--without-publication-row-borrow":preload("res://scripts/world3d/deferred_asset_loader.gd").borrow_publication_rows_enabled=false
		if arg=="--without-raw-face-reuse":preload("res://scripts/world3d/house_prefab.gd").raw_face_reuse_enabled=false
		if arg=="--without-bounds-only-decode":preload("res://scripts/world3d/house_prefab.gd").bounds_only_decode_enabled=false
		if arg=="--without-prefab-bounds-cache":preload("res://scripts/world3d/prefab_bounds_metadata.gd").disk_cache_enabled=false
		if arg=="--without-model-metadata-cache":preload("res://scripts/world3d/asset_source_metadata.gd").disk_cache_enabled=false
		if arg=="--without-white-worker-capacity":preload("res://scripts/world3d/deferred_asset_loader.gd").white_worker_capacity_enabled=false
		if arg=="--without-native-source-metadata":preload("res://scripts/world3d/white_native_asset_metadata.gd").enabled=false
		if arg=="--without-bulk-road-arrays":preload("res://scripts/world3d/road_surface.gd").bulk_arrays_enabled=false
		if arg=="--without-indexed-terrain-top":preload("res://scripts/world3d/terrain_surface_arrays.gd").indexed_top_enabled=false
		if arg=="--without-bulk-terrain-arrays":preload("res://scripts/world3d/terrain_surface.gd").bulk_arrays_enabled=false
		if arg=="--without-bulk-kerb-arrays":preload("res://scripts/world3d/road_kerb.gd").bulk_arrays_enabled=false
		if arg=="--without-append-bounds-reuse":Stream.append_bounds_reuse_enabled=false
		if arg=="--without-cooked-cache":preload("res://scripts/world3d/runtime_mesh_cache.gd").read_enabled=false
		if arg=="--without-pack-iteration":preload("res://scripts/world3d/runtime_mesh_cache.gd").pack_iteration_enabled=false
		if arg=="--without-white-entry-material-reuse":preload("res://scripts/world3d/world_document.gd").white_entry_material_reuse_enabled=false
		if arg=="--without-batched-geometry-release":preload("res://scripts/world3d/resource_retirement.gd").batched_geometry_release_enabled=false
		if arg=="--without-small-worker-bvh":preload("res://scripts/world3d/stream_collision_preparer.gd").small_worker_bvh_enabled=false
		if arg=="--without-selected-terrain-context":preload("res://scripts/world3d/selected_terrain_context.gd").enabled=false
		if arg=="--without-requeue-record-retirement":preload("res://scripts/world3d/deferred_asset_loader.gd").background_requeue_records_enabled=false
		if arg=="--without-parallel-retirement-selection":preload("res://scripts/world3d/resident_retirement_selection.gd").enabled=false
		if arg=="--without-spatial-membership-handoff":preload("res://scripts/world3d/deferred_asset_loader.gd").reuse_spatial_membership_catalogue_enabled=false
		if arg=="--without-asset-spec-template":preload("res://scripts/world3d/asset_spec_template.gd").enabled=false
		if arg=="--without-worker-instance-specs":preload("res://scripts/world3d/asset_spec_template.gd").worker_enabled=false
		if arg=="--without-derived-geometry-cache":
			preload("res://scripts/world3d/runtime_mesh_cache.gd").read_enabled=false
			preload("res://scripts/world3d/road_array_cache.gd").enabled=false
			preload("res://scripts/world3d/prefab_binary_cache.gd").enabled=false
			preload("res://scripts/world3d/collision_product_cache.gd").enabled=false
		if arg=="--without-phase-budget-guard":preload("res://scripts/world3d/deferred_asset_loader.gd").phase_budget_guard_enabled=false
		if arg=="--without-append-dependency-delta":preload("res://scripts/world3d/stream_index.gd").append_dependency_delta_enabled=false
		if arg=="--without-ready-collision-bypass":Stream.ready_collision_bypass_enabled=false
		if arg=="--without-resumable-bin-ledger":preload("res://scripts/world3d/ground_batcher.gd").resumable_bin_ledger_enabled=false
		if arg=="--without-parallel-collision-batch":preload("res://scripts/world3d/collision_face_prefetch.gd").parallel_batches_enabled=false
		if arg=="--without-live-node-retirement":preload("res://scripts/world3d/world_stream.gd").live_node_retirement_enabled=false
		if arg=="--without-entry-surface-reuse":preload("res://scripts/world3d/entry_surface_preparation.gd").enabled=false
		if arg=="--without-geometry-size-reuse":preload("res://scripts/world3d/resource_retirement.gd").geometry_size_reuse_enabled=false
		if arg=="--without-cached-road-bounds":preload("res://scripts/world3d/road_array_cache.gd").prepared_bounds_enabled=false
		if arg=="--without-retirement-metadata-reuse":preload("res://scripts/world3d/stream_index.gd").retirement_metadata_enabled=false
		if arg=="--without-streamed-road-bounds":preload("res://scripts/world3d/road_record_bounds.gd").enabled=false
		if arg=="--without-worker-pending-catalogue":preload("res://scripts/world3d/pending_catalogue_preparation.gd").enabled=false
		if arg=="--without-typed-filter-reuse":preload("res://scripts/world3d/deferred_asset_loader.gd").reuse_typed_demand_filter_enabled=false
		if arg=="--without-worker-bvh":preload("res://scripts/world3d/collision_bvh_preparation.gd").enabled=false
		if arg=="--without-decoded-background-release":preload("res://scripts/world3d/resource_retirement.gd").background_decoded_release_enabled=false
		if arg=="--without-worker-surface-bounds":preload("res://scripts/world3d/procedural_surface_bounds.gd").enabled=false
		if arg=="--capacity-timeline":capacity_timeline_enabled=true
		if arg=="--publication-block-probe":publication_block_probe=true
		if arg=="--frame-split-probe":frame_split_probe=true
		if arg=="--collision-state-probe":collision_state_probe=true
		if arg=="--serial-white-collisions":Stream.white_collision_prefetch_enabled=false
		if arg=="--progressive-batches-probe":Stream.progressive_white_batches_enabled=true
		if arg=="--legacy-stream-object-limit":Stream.white_time_slice_enabled=false
		if arg=="--without-settled-batch-budget":preload("res://scripts/world3d/ground_batcher.gd").settled_white_budget_enabled=false
		if arg=="--without-covered-batch-borrow":preload("res://scripts/world3d/ground_batcher.gd").covered_idle_budget_enabled=false
		if arg=="--without-uv-projection-elision":preload("res://scripts/world3d/surface_materials.gd").uv_projection_elision_enabled=false
		if arg=="--profile-batch-preparation":preload("res://scripts/world3d/ground_batcher.gd").profile_preparation_units_enabled=true
		if arg=="--batch-timeline":
			preload("res://scripts/world3d/ground_batch_timeline.gd").enabled=true
			report.batch_timeline=preload("res://scripts/world3d/ground_batch_timeline.gd").report()
		if arg=="--without-prepared-surfaces":preload("res://scripts/world3d/ground_batch_geometry.gd").prepared_surfaces_enabled=false
		if arg=="--without-inflight-batch-sharing":preload("res://scripts/world3d/ground_batcher.gd").inflight_building_sharing_enabled=false
		if arg.begins_with("--publication-budget-probe="):
			preload("res://scripts/world3d/deferred_asset_loader.gd").interactive_budget_override_usec=arg.trim_prefix("--publication-budget-probe=").to_int()
		elif arg.begins_with("--settled-batch-budget-probe="):
			settled_batch_budget=clampi(arg.trim_prefix("--settled-batch-budget-probe=").to_int(),2000,8000)
	super._initialize()
func source_snapshot(folder:String="res://scripts")->Dictionary:
	var result:=super.source_snapshot(folder)
	if folder=="res://scripts":result["res://tools/profile_axel_worker_capacity.gd"]=FileAccess.get_sha256("res://tools/profile_axel_worker_capacity.gd")
	if folder=="res://scripts":result["res://tools/completed_job_audit_probe.gd"]=FileAccess.get_sha256("res://tools/completed_job_audit_probe.gd")
	return result
func save()->void:
	if preload("res://scripts/world3d/ground_batch_timeline.gd").enabled:report.batch_timeline=preload("res://scripts/world3d/ground_batch_timeline.gd").report()
	report.texture_invalidation_material_scans=preload("res://scripts/world3d/house_prefab.gd").texture_invalidation_material_scans
	if completed_job_audit_enabled:
		var trace:Dictionary=preload("res://scripts/world3d/completed_job_trace.gd").snapshot(began)
		report.publication_audit_v178={"samples":completed_job_audit_samples,"trace":trace,"trace_complete":report.get("retirement",{}).get("map_freed",false) and trace.dropped==0}
	super.save()
func tick_geometry()->void:
	if not capacity_applied:
		capacity_applied=true
		report.white_priority_turns=preload("res://scripts/world3d/publication_order.gd").white_priority_turns_enabled
		report.append_dependency_delta=preload("res://scripts/world3d/stream_index.gd").append_dependency_delta_enabled
		report.ready_collision_bypass=Stream.ready_collision_bypass_enabled
		report.resumable_bin_ledger=preload("res://scripts/world3d/ground_batcher.gd").resumable_bin_ledger_enabled
		report.independent_instance_preparation=preload("res://scripts/world3d/deferred_asset_loader.gd").independent_instance_preparation_enabled
		report.native_prefab_direct_specs=preload("res://scripts/world3d/deferred_asset_loader.gd").native_prefab_direct_specs_enabled
		report.completed_owner_drain=preload("res://scripts/world3d/publication_order.gd").completed_owner_drain_enabled
		report.white_stream_time_slice=Stream.white_time_slice_enabled
		report.white_building_turns=preload("res://scripts/world3d/publication_order.gd").white_building_turns_enabled
		report.terrain_shape_retirement=preload("res://scripts/world3d/ground_cpu_mesh.gd").terrain_shape_retirement_enabled
		report.native_products_required=mesh_map.get_node("DeferredAssets").require_native_products
		report.ordered_retirement_tail=preload("res://scripts/world3d/resource_retirement.gd").ordered_retirement_tail_enabled
		report.support_set_ids=preload("res://scripts/world3d/deferred_asset_loader.gd").support_set_ids_enabled
		report.retirement_delta_reuse=preload("res://scripts/world3d/stream_index.gd").retirement_delta_reuse_enabled
		report.retirement_bucket_prefix_reuse=preload("res://scripts/world3d/stream_index.gd").retirement_bucket_prefix_reuse_enabled
		report.retirement_frame_retry={"native":preload("res://scripts/world3d/native_residency.gd").frame_retry_enabled,"ordinary":preload("res://scripts/world3d/asset_residency.gd").frame_retry_enabled}
		for arg:String in OS.get_cmdline_user_args():
			if arg.begins_with("--ready-jobs-probe="):
				var queue:Node=mesh_map.get_node("DeferredAssets")
				queue.ready_job_limit=clampi(arg.trim_prefix("--ready-jobs-probe=").to_int(),4,32)
				report.ready_jobs_probe=queue.ready_job_limit
			if arg.begins_with("--interactive-workers-probe="):
				var queue:Node=mesh_map.get_node("DeferredAssets")
				queue._admission.worker_limit=clampi(arg.trim_prefix("--interactive-workers-probe=").to_int(),1,12)
				report.worker_capacity_probe={"limit":queue._admission.worker_limit,"byte_limit":queue._admission.byte_limit}
	var tick_began:=Time.get_ticks_usec()
	super.tick_geometry()
	if frame_split_probe:sample_frame_split(Time.get_ticks_usec()-tick_began)
	report.indexed_terrain_top=preload("res://scripts/world3d/terrain_surface_arrays.gd").indexed_top_enabled
	report.prepared_procedural_surfaces=preload("res://scripts/world3d/prepared_cpu_upload.gd").installed_surfaces
	if preload("res://scripts/world3d/prepared_cpu_upload.gd").profile_enabled:report.procedural_uploads=preload("res://scripts/world3d/prepared_cpu_upload.gd").profile_rows
	if capacity_timeline_enabled:
		var queue:Node=mesh_map.get_node("DeferredAssets")
		var live:=0;var finished:=0;var accepted:=0;var ready:=0
		var waiting_pixels:=0;var pixel_consumers:=0;var material_owners:=0
		for job:Dictionary in queue._jobs.values():
			if job.has("worker"):
				if job.worker.is_alive():live+=1
				else:finished+=1
			elif job.get("accepted",false):accepted+=1
			else:ready+=1
			if map_texture_stage:
				if job.get("result",{}).get("waiting_pixels",false):waiting_pixels+=1
				if job.has("pixel_consumer"):pixel_consumers+=1
				if job.has("material_textures"):material_owners+=1
		capacity_timeline.append([Time.get_ticks_usec()-began,queue._demanded_by_id.size(),live,finished,ready,accepted,queue._jobs.size(),queue._job_limit(),queue._admission.active_workers(),queue._admission.worker_limit,queue._admission.reserved_bytes,not queue._dispatch_fence.is_empty(),mesh_map.get_meta("stream_jobs",[]).size(),mesh_map.get_meta("stream_cursor",0)])
		report.capacity_timeline={"columns":["at_us","demanded","live_workers","finished_unjoined","ready_unaccepted","accepted","jobs","job_limit","charged_workers","worker_limit","reserved_bytes","admission_fence","stream_jobs","stream_cursor"],"samples":capacity_timeline,"contract":"Once per geometry tick, after focus update. Interval occupancy is sampled, not exact task CPU or lock waiting time."}
		if map_texture_stage:
			texture_job_timeline.append([Time.get_ticks_usec()-began,waiting_pixels,pixel_consumers,material_owners])
			report.texture_job_timeline={"columns":["at_us","waiting_pixels","pixel_consumers","material_texture_owners"],"samples":texture_job_timeline,"contract":"Counts existing deferred jobs during the capacity observer; shared pixel pool is separately checked at full-ready. No texture enumeration or GPU readback per tick."}
	if publication_block_probe:sample_publication_blocks()
	if completed_job_audit_enabled:
		completed_job_audit_samples.append(completed_job_audit.sample(mesh_map.get_node("DeferredAssets"),Time.get_ticks_usec()-began,phase,preload("res://scripts/world3d/completed_job_trace.gd").events))
	if collision_state_probe and Time.get_ticks_msec()>=next_collision_state:
		next_collision_state=Time.get_ticks_msec()+1000
		var p:Node=mesh_map.get_node_or_null("StreamCollisionPreparer")
		if p!=null:
			var jobs:Array=mesh_map.get_meta("stream_jobs",[]);var cursor:int=mesh_map.get_meta("stream_cursor",0)
			print("COLLISION_STATE ",JSON.stringify({"at_ms":(Time.get_ticks_usec()-began)/1000.,"cursor":cursor,"jobs":jobs.size(),"head":jobs[cursor].uuid if cursor<jobs.size() else "","serial_alive":p._thread!=null and p._thread.is_alive(),"terrain_alive":p._terrain._thread!=null and p._terrain._thread.is_alive(),"terrain_uuid":p._terrain._spec.get("uuid",""),"terrain_cursor":p._terrain._cursor,"terrain_faces":p._terrain._faces.size(),"terrain_shapes":p._terrain._shapes.size(),"prefetch_alive":p._face_prefetch._thread!=null and p._face_prefetch._thread.is_alive(),"prefetch_thread":p._face_prefetch._thread!=null,"prefetch_ready":p._face_prefetch._ready.size(),"prefetch_draining":p._face_prefetch._draining!=null,"lease":p._face_prefetch.profile,"retiring":p._retiring_workers,"retired_leases":p._retired_leases.size()}))
	if settled_batch_budget>0:
		var queue:Node=mesh_map.get_node("DeferredAssets")
		var batcher:Node=mesh_map.get_node_or_null("GroundRenderBatches")
		if batcher!=null and queue._jobs.is_empty() and queue._demanded_by_id.is_empty() and mesh_map.get_meta("stream_jobs",[]).is_empty() and mesh_map.has_meta("stream_chunk"):
			batcher.work_budget_usec=settled_batch_budget
			report.settled_batch_budget_probe=settled_batch_budget
