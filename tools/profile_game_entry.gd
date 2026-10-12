extends SceneTree
## Actual loading screen -> world transition -> first playable frame, on a
## private desktop. Only a pre-existing temporary reference map is accepted.
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Cache=preload("res://scripts/world3d/runtime_mesh_cache.gd")
const Doc=preload("res://scripts/world3d/world_document.gd")
const Pose=preload("res://scripts/world3d/pose_save.gd")
const CpuMesh=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const SOURCE="D:/code/rmmo_runtime/maps/medieval_river_town/map.gltf"
var map_path:="D:/code/rmmo_runtime/cache/world3d/reference_load_checkpoint_26004507/map.gltf"
var output:="D:/code/rmmo_runtime/review_artifacts/game_entry_before_20261008.json"
var report:Dictionary={"stages":[],"failures":0}
var started:=0
var previous:=0
var frame_max:=0.
var sampling:=false
var phase:="startup"
var slow:Array=[]
var monitor:RefCounted
var town_route:=false
var town_route_return_only:=false
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if not value:report.failures+=1
func persist()->void:
	var file:=FileAccess.open(output,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(report,"\t"));file.close()
func finish_failed_measurement()->void:
	# Preserve the same bounded trace on failures, not only successful entries.
	# These are failure spans, never a playable-ready performance sample.
	report.failure_epoch_s=Time.get_unix_time_from_system()
	if started>0:report.failed_elapsed_ms=(Time.get_ticks_usec()-started)/1000.
	report.max_frame_ms=frame_max;report.slow_frames=slow
	sampling=false
	if process_frame.is_connected(observe):process_frame.disconnect(observe)
	if monitor!=null and monitor.active:report.monitor=monitor.finish()
func cooked_files(path:String)->Array:
	# Enumerate only the two cooked namespaces of this already-authorized
	# temporary map. No source reads, recursive delete, or cache warming.
	var result:Array=[Cache.cache_path(path)]
	var selected_dir:=Cache.cache_path(path,"0".repeat(64)).get_base_dir()
	var directory:=DirAccess.open(selected_dir)
	if directory==null:return result
	for file:String in directory.get_files():
		if file.get_extension()!="bin" or not Cache._valid_selection(file.get_basename()) or directory.is_link(file):continue
		result.append(selected_dir.path_join(file))
	return result
func model_texture_observation(scene:Node)->Dictionary:
	# Same descriptor-only observation as the editor acceptance fixture. Called
	# after timed loading/runtime/physics work, never while measuring or warming.
	var cache=preload("res://scripts/world3d/model_texture_cache.gd")
	var textures:Dictionary={};var keyed:Dictionary={};var shared_keys:=0;var duplicate_objects:=0
	for material:StandardMaterial3D in cache._materials(scene):
		for info:Dictionary in material.get_property_list():
			if not (int(info.usage)&PROPERTY_USAGE_STORAGE):continue
			var texture:Variant=material.get(info.name)
			if not texture is Texture2D or textures.has(texture.get_instance_id()):continue
			textures[texture.get_instance_id()]=true
			var key:Variant=texture.get_meta(cache.PIXEL_KEY,"")
			if cache._valid_key(key):keyed[key]=int(keyed.get(key,0))+1
	for count:int in keyed.values():
		if count>1:shared_keys+=1;duplicate_objects+=count-1
	var live_pool:=0
	for weak:WeakRef in cache._textures.values():
		if weak.get_ref()!=null:live_pool+=1
	return {"scope":"post-measurement map-root descriptor observation of reachable StandardMaterial3D textures; no pixel readback; renderer memory is process-global, not per-asset VRAM",
		"texture_objects":textures.size(),"stamped_pixel_keys":keyed.size(),"pixel_keys_with_multiple_objects":shared_keys,
		"duplicate_stamped_objects":duplicate_objects,"live_pool_keys":live_pool,
		"renderer_texture_memory_bytes":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)}
func memory_pages_observation()->Dictionary:
	# Optional diagnostic only, after every load/runtime/physics measurement.
	# A separate read-only process enumerates resident pages without touching
	# scene state or changing the target working set. Never run in a timed span.
	var result:Dictionary={"ok":false,"scope":"post-measurement Windows working-set classification; no target memory reads, trimming, or world mutation",
		"started_epoch_s":Time.get_unix_time_from_system(),"pid":OS.get_process_id(),
		"static_memory_before":Performance.get_monitor(Performance.MEMORY_STATIC),
		"object_count_before":Performance.get_monitor(Performance.OBJECT_COUNT),
		"renderer_buffer_bytes_before":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED),
		"renderer_texture_bytes_before":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)}
	var output_path:=ProjectSettings.globalize_path(output.get_basename()+".memory-pages.json").replace("\\","/")
	result.report=output_path
	if OS.get_name()!="Windows" or not Paths.allowed(output_path,Paths.external_root().path_join("review_artifacts")):
		result.error="Working-set probe requires Windows and a confined runtime review report";return result
	if FileAccess.file_exists(output_path):result.error="Working-set evidence already exists; use a fresh output name";return result
	var helper:=ProjectSettings.globalize_path("res://tools/probe_windows_working_set.py")
	var python:=OS.get_environment("LOCALAPPDATA").path_join("Programs/Python/Python312/python.exe")
	if not FileAccess.file_exists(helper) or not FileAccess.file_exists(python):
		result.error="Working-set helper or local Python312 is unavailable";return result
	var stdout:Array=[]
	result.exit_code=OS.execute(python,PackedStringArray([helper,"--pid",str(OS.get_process_id()),"--output",output_path]),stdout,true,false)
	result.finished_epoch_s=Time.get_unix_time_from_system()
	result.static_memory_after=Performance.get_monitor(Performance.MEMORY_STATIC)
	result.object_count_after=Performance.get_monitor(Performance.OBJECT_COUNT)
	result.renderer_buffer_bytes_after=RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_BUFFER_MEM_USED)
	result.renderer_texture_bytes_after=RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TEXTURE_MEM_USED)
	result.process_output="\n".join(PackedStringArray(stdout)).left(4096)
	var file:=FileAccess.open(output_path,FileAccess.READ)
	if file==null or file.get_length()>4*1024*1024:
		result.error="Working-set probe did not return a bounded report";return result
	var parsed:Variant=JSON.parse_string(file.get_as_text());file.close()
	if not parsed is Dictionary:
		result.error="Working-set probe report is invalid";return result
	result.probe=parsed
	result.ok=result.exit_code==0 and parsed.get("ok",false)==true and parsed.get("complete",false)==true and parsed.get("pid",-1)==OS.get_process_id()
	return result
func observe()->void:
	if not sampling:return
	if monitor!=null:monitor.frame(phase)
	var now:=Time.get_ticks_usec();var elapsed:=(now-previous)/1000.;previous=now
	frame_max=maxf(frame_max,elapsed)
	if slow.size()<20 or elapsed>float(slow.back().ms):
		slow.append({"ms":elapsed,"phase":phase,"at_ms":(now-started)/1000.});slow.sort_custom(func(a,b):return a.ms>b.ms)
		if slow.size()>20:slow.pop_back()
	var next:=phase
	if is_instance_valid(current_scene):
		if current_scene.has_method("loading_progress"):next=str(current_scene.loading_progress().stage)
		elif current_scene.get("status_label")!=null:next=str(current_scene.status_label.text)
	if next!=phase:
		phase=next;report.stages.append({"stage":phase,"at_ms":(now-started)/1000.})
		print("GAME_ENTRY_STAGE ",phase)
func run()->void:
	report.engine_build={"executable":OS.get_executable_path(),"version":Engine.get_version_info(),"debug":OS.is_debug_build(),"editor":OS.has_feature("editor"),"template":OS.has_feature("template"),"release":OS.has_feature("release"),"renderer":ProjectSettings.get_setting_with_override("rendering/renderer/rendering_method")}
	var reset_cache:=false
	var reset_index:=false
	var wait_deferred:=false
	var teleport_probe:=false
	var monitor_enabled:=false
	var physics_probe:=false
	var collision_query_pair:=false
	var memory_pages:=false
	var spawn_override:Variant=null
	for arg:String in OS.get_cmdline_user_args():
		if arg=="--town-route":town_route=true
		if arg=="--town-route-return":town_route=true;town_route_return_only=true
		if arg.begins_with("--map="):map_path=arg.trim_prefix("--map=")
		elif arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		elif arg=="--reset-derived-cache":reset_cache=true
		elif arg=="--reset-dependency-index":reset_index=true
		elif arg=="--wait-deferred":wait_deferred=true
		elif arg=="--definition-cache":
			preload("res://scripts/world3d/definition_cache_policy.gd").enabled=true
			report.definition_cache_enabled=true
		elif arg=="--teleport-probe":teleport_probe=true
		elif arg=="--monitor":monitor_enabled=true
		elif arg=="--collision-query-pair":collision_query_pair=true
		elif arg=="--no-entry-pipeline":
			preload("res://scripts/world3d/map_loader.gd").entry_pipeline_enabled=false
			report.entry_pipeline_enabled=false
		elif arg=="--probe-physics":physics_probe=true
		elif arg=="--memory-pages":memory_pages=true
		elif arg.begins_with("--spawn="):
			var coordinates:=arg.trim_prefix("--spawn=").split(",")
			if coordinates.size()!=3 or not Array(coordinates).all(func(value):return value.is_valid_float() and is_finite(value.to_float())):
				push_error("--spawn requires finite x,y,z coordinates");quit(1);return
			spawn_override=Vector3(coordinates[0].to_float(),coordinates[1].to_float(),coordinates[2].to_float())
		elif arg=="--without-compiled":preload("res://scripts/world3d/compiled_asset_cache.gd").enabled=false
		elif arg=="--without-upload-preparation":
			preload("res://scripts/world3d/runtime_texture_cache.gd").upload_preparation_enabled=false
			report.upload_preparation_enabled=false
		elif arg=="--without-native-footprints":
			preload("res://scripts/world3d/model_parse_preparation.gd").native_footprints_enabled=false
			report.native_footprints_enabled=false
		elif arg=="--native-source-precheck":
			preload("res://scripts/world3d/compiled_asset_preparation.gd").source_precheck_enabled=true
			report.native_source_precheck=true
		elif arg=="--collision-geometry" or arg.begins_with("--collision-geometry="):
			var mode:=arg.trim_prefix("--collision-geometry=")
			if mode not in ["off","on"]:push_error("Expected --collision-geometry=off or on");quit(2);return
			preload("res://scripts/world3d/model_collision_requirements.gd").enabled=mode=="on"
		elif arg=="--model-texture-sharing" or arg.begins_with("--model-texture-sharing="):
			var mode:=arg.trim_prefix("--model-texture-sharing=")
			if mode not in ["off","on"]:push_error("Expected --model-texture-sharing=off or on");quit(2);return
			preload("res://scripts/world3d/model_texture_cache.gd").enabled=mode=="on"
		elif arg=="--without-index-path-batching":
			preload("res://scripts/world3d/map_dependency_index.gd").batch_path_validation=false
			report.index_path_batching=false
		elif arg=="--without-cpu-river-overrides":
			preload("res://scripts/world3d/river_materials.gd").cpu_index_overrides_enabled=false
			report.cpu_river_overrides=false
		elif arg=="--without-water-cpu-normals":
			preload("res://scripts/world3d/river_materials.gd").water_cpu_normals_enabled=false
			report.water_cpu_normals=false
		elif arg=="--without-water-cpu-index":
			preload("res://scripts/world3d/river_materials.gd").water_cpu_index_enabled=false
			report.water_cpu_index=false
		elif arg=="--without-cold-index-rebuild":
			preload("res://scripts/world3d/map_loader.gd").cold_index_rebuild_enabled=false
			report.cold_index_rebuild=false
		elif arg=="--without-deferred-native":
			preload("res://scripts/world3d/deferred_asset_loader.gd").native_preparation_enabled=false
			report.deferred_native_preparation=false
		elif arg=="--without-deferred-native-budget":preload("res://scripts/world3d/deferred_asset_loader.gd").native_budget_enabled=false
		elif arg=="--deferred-native-budget":preload("res://scripts/world3d/deferred_asset_loader.gd").native_budget_enabled=true
		elif arg=="--without-prefab-texture-preparation":preload("res://scripts/world3d/deferred_asset_loader.gd").prefab_texture_preparation_enabled=false
		elif arg=="--with-prefab-texture-preparation":preload("res://scripts/world3d/deferred_asset_loader.gd").prefab_texture_preparation_enabled=true
		elif arg=="--without-native-entry-prefetch":preload("res://scripts/world3d/deferred_asset_loader.gd").native_entry_prefetch_enabled=false
		elif arg=="--with-native-entry-prefetch":preload("res://scripts/world3d/deferred_asset_loader.gd").native_entry_prefetch_enabled=true
		elif arg=="--with-shared-prefab-textures":preload("res://scripts/world3d/deferred_asset_loader.gd").shared_prefab_texture_preparation_enabled=true
		elif arg=="--bridge-texture-preparation":preload("res://scripts/world3d/deferred_asset_loader.gd").bridge_texture_preparation_enabled=true
		elif arg=="--without-bridge-texture-preparation":preload("res://scripts/world3d/deferred_asset_loader.gd").bridge_texture_preparation_enabled=false
		elif arg=="--with-frame-budget":preload("res://scripts/world3d/frame_work_budget.gd").enabled=true
		elif arg=="--without-frame-budget":preload("res://scripts/world3d/frame_work_budget.gd").enabled=false
		elif arg=="--with-background-navigation":preload("res://scripts/world3d/world_3d.gd").navigation_background_enabled=true
		elif arg=="--without-background-navigation":preload("res://scripts/world3d/world_3d.gd").navigation_background_enabled=false
		elif arg=="--with-background-wind":preload("res://scripts/world3d/world_3d.gd").wind_background_enabled=true
		elif arg=="--without-background-wind":preload("res://scripts/world3d/world_3d.gd").wind_background_enabled=false
		elif arg=="--with-building-readiness":preload("res://scripts/world3d/world_3d.gd").building_readiness_enabled=true
		elif arg=="--with-collision-first":preload("res://scripts/world3d/deferred_asset_loader.gd").collision_first_enabled=true
		elif arg=="--with-no-collision-proof":preload("res://scripts/world3d/collision_dependency_loader.gd").no_collision_proof_enabled=true
		elif arg=="--without-no-collision-proof":preload("res://scripts/world3d/collision_dependency_loader.gd").no_collision_proof_enabled=false
		elif arg=="--dispatch-before-collision-installation":preload("res://scripts/world3d/collision_dependency_loader.gd").dispatch_before_installation=true
		elif arg=="--dispatch-after-collision-installation":preload("res://scripts/world3d/collision_dependency_loader.gd").dispatch_before_installation=false
		elif arg=="--collision-scheduler-profile":preload("res://scripts/world3d/collision_dependency_loader.gd").dispatch_profile_enabled=true
		elif arg=="--texture-stage-profile":
			preload("res://scripts/world3d/surface_materials.gd").texture_profile_enabled=true
			preload("res://scripts/world3d/runtime_texture_cache.gd").profile_enabled=true
			preload("res://scripts/world3d/runtime_texture_cache.gd").reset_profile()
		elif arg=="--with-collision-query-caches":
			preload("res://scripts/world3d/deferred_asset_loader.gd").collision_query_cache_enabled=true
			preload("res://scripts/world3d/world_stream.gd").collision_candidate_cache_enabled=true
		elif arg=="--without-collision-query-caches":
			preload("res://scripts/world3d/deferred_asset_loader.gd").collision_query_cache_enabled=false
			preload("res://scripts/world3d/world_stream.gd").collision_candidate_cache_enabled=false
		elif arg=="--collision-query-profile":
			preload("res://scripts/world3d/deferred_asset_loader.gd").collision_query_profile_enabled=true
			preload("res://scripts/world3d/world_stream.gd").collision_readiness_profile_enabled=true
		elif arg=="--without-deferred-worker-yield":
			preload("res://scripts/world3d/deferred_asset_loader.gd").ready_worker_yield_enabled=false
			report.deferred_ready_worker_yield=false
		elif arg=="--without-prepared-collision-faces":
			preload("res://scripts/world3d/stream_collision_preparer.gd").prepared_faces_enabled=false
			preload("res://scripts/world3d/terrain_collision_preparer.gd").prepared_faces_enabled=false
		elif arg=="--without-collision-prefetch":preload("res://scripts/world3d/stream_collision_preparer.gd").prefetch_enabled=false
		elif arg.begins_with("--model-workers="):
			var count:=arg.trim_prefix("--model-workers=")
			if count not in ["1","2","3","4"]:push_error("--model-workers must be 1..4");quit(1);return
			preload("res://scripts/world3d/map_loader.gd").initial_model_workers_override=count.to_int()
			report.initial_model_workers_override=count.to_int()
	if not Paths.allowed(map_path,Paths.external_root().path_join("cache/world3d")) or not FileAccess.file_exists(map_path):quit(1);return
	if not Paths.allowed(output,Paths.external_root().path_join("review_artifacts")):quit(1);return
	Engine.max_fps=60;root.size=Vector2i(1440,900);root.content_scale_size=root.size
	create_timer(600).timeout.connect(func():report.timeout=true;finish_failed_measurement();persist();quit(2))
	report.deferred_native_preparation=preload("res://scripts/world3d/deferred_asset_loader.gd").native_preparation_enabled
	report.deferred_native_budget=preload("res://scripts/world3d/deferred_asset_loader.gd").native_budget_enabled
	report.prefab_texture_preparation=preload("res://scripts/world3d/deferred_asset_loader.gd").prefab_texture_preparation_enabled
	report.native_entry_prefetch=preload("res://scripts/world3d/deferred_asset_loader.gd").native_entry_prefetch_enabled
	report.shared_prefab_textures=preload("res://scripts/world3d/deferred_asset_loader.gd").shared_prefab_texture_preparation_enabled
	report.bridge_texture_preparation=preload("res://scripts/world3d/deferred_asset_loader.gd").bridge_texture_preparation_enabled
	report.collision_geometry=preload("res://scripts/world3d/model_collision_requirements.gd").enabled
	report.model_texture_sharing=preload("res://scripts/world3d/model_texture_cache.gd").enabled
	report.background_navigation=preload("res://scripts/world3d/world_3d.gd").navigation_background_enabled
	report.background_wind=preload("res://scripts/world3d/world_3d.gd").wind_background_enabled
	report.building_readiness=preload("res://scripts/world3d/world_3d.gd").building_readiness_enabled
	report.collision_first=preload("res://scripts/world3d/deferred_asset_loader.gd").collision_first_enabled
	report.collision_query_cache=preload("res://scripts/world3d/deferred_asset_loader.gd").collision_query_cache_enabled
	report.no_collision_proof=preload("res://scripts/world3d/collision_dependency_loader.gd").no_collision_proof_enabled
	report.texture_stage_profile=preload("res://scripts/world3d/runtime_texture_cache.gd").profile_enabled
	report.collision_candidate_cache=preload("res://scripts/world3d/world_stream.gd").collision_candidate_cache_enabled
	report.collision_query_profile=preload("res://scripts/world3d/deferred_asset_loader.gd").collision_query_profile_enabled
	report.deferred_ready_worker_yield=preload("res://scripts/world3d/deferred_asset_loader.gd").ready_worker_yield_enabled
	report.prepared_collision_faces=preload("res://scripts/world3d/stream_collision_preparer.gd").prepared_faces_enabled
	report.collision_face_prefetch=preload("res://scripts/world3d/stream_collision_preparer.gd").prefetch_enabled
	report.map=map_path;report.map_sha=FileAccess.get_sha256(map_path);report.formal_sha=FileAccess.get_sha256(SOURCE)
	if reset_index:
		# The map was restricted to the temporary map root above. Remove only
		# its hashed derived directory, never a source map or resource payload.
		var index_path:String=preload("res://scripts/world3d/map_dependency_index.gd").cache_path(map_path,Paths.external_root())
		if index_path.is_empty() or not Paths.allowed(index_path,Paths.external_root().path_join("cache/world3d/dependency_indexes")):
			push_error("Invalid temporary dependency index path");quit(1);return
		report.dependency_index_removed=index_path
		if FileAccess.file_exists(index_path):
			var removal_ok:=DirAccess.remove_absolute(index_path)==OK
			check(removal_ok,"remove only temporary map dependency index")
			if not removal_ok:quit(1);return
	var existing_caches:Dictionary={};var removed:Array=[]
	for cache_path:String in cooked_files(map_path):
		if not FileAccess.file_exists(cache_path):continue
		existing_caches[ProjectSettings.globalize_path(cache_path)]=true
		if reset_cache:
			check(DirAccess.remove_absolute(cache_path)==OK,"remove only temporary map cooked geometry cache")
			removed.append(ProjectSettings.globalize_path(cache_path))
	report.cache_files_before=existing_caches.keys();report.cache_files_removed=removed
	report.reset_cache_scope="complete_and_selected_cooked_geometry_for_temporary_map"
	report.reset_derived_cache=reset_cache;persist()
	preload("res://tools/world3d_test_character.gd").ensure(self)
	var session=root.get_node("GameSession")
	session.spawn_data={"character":session.selected_character.duplicate(true),"equipment":[],"world_mode":"world3d"}
	session.world3d_map_path=map_path
	if spawn_override is Vector3:
		session.world3d_spawn=spawn_override
		report.requested_spawn=[spawn_override.x,spawn_override.y,spawn_override.z]
		var cell:Vector2i=preload("res://scripts/world3d/world_stream.gd").chunk_key(spawn_override)
		report.requested_chunk=[cell.x,cell.y]
	report.entry_epoch_s=Time.get_unix_time_from_system()
	preload("res://scripts/world3d/river_materials.gd").reset_index_profile()
	started=Time.get_ticks_usec();previous=started;sampling=true;process_frame.connect(observe)
	if monitor_enabled:monitor=preload("res://tools/load_monitor.gd").new();monitor.start(self)
	session.go_world_3d()
	while true:
		await process_frame
		if is_instance_valid(current_scene) and current_scene.has_node("FailActions"):
			check(false,"actual loading screen rejects map: "+str(current_scene.status_label.text));finish_failed_measurement();persist();quit(1);return
		if is_instance_valid(current_scene) and current_scene.has_meta("entry_loading_error"):
			if current_scene.has_method("entry_readiness_shadow_report"):report.entry_readiness_shadow=current_scene.entry_readiness_shadow_report()
			var failed_map:Node=current_scene.get("_map_root")
			if is_instance_valid(failed_map):
				report.failed_map_profile=failed_map.get_meta("load_profile",{}).duplicate(true)
				var failed_collision:Node=failed_map.get_node_or_null("CollisionDependencyLoader")
				if failed_collision!=null:report.failed_collision_profile=failed_collision.snapshot()
				var failed_deferred:Node=failed_map.get_node_or_null("DeferredAssets")
				if failed_deferred!=null:
					report.failed_deferred_profile=failed_deferred.profile.duplicate(true)
					report.failed_instances=failed_deferred.instance_errors.duplicate()
			check(false,"actual entry rejects incomplete safety: "+str(current_scene.get_meta("entry_loading_error")));finish_failed_measurement();persist();quit(1);return
		if is_instance_valid(current_scene) and current_scene.has_method("is_world_ready") and current_scene.is_world_ready() and not session._world_transition_active:break
	observe();sampling=false;process_frame.disconnect(observe)
	report.entry_ms=(Time.get_ticks_usec()-started)/1000.;report.max_frame_ms=frame_max;report.slow_frames=slow
	report.entry_end_epoch_s=Time.get_unix_time_from_system()
	var world=current_scene
	report.session_profile=session.last_loading_profile.duplicate(true);report.world_profile=world.loading_profile.duplicate(true)
	if world.has_method("entry_readiness_shadow_report"):
		report.entry_readiness_shadow=world.entry_readiness_shadow_report()
	check(world._player!=null and not world._player.input_locked and session.get_node_or_null("WorldTransition")==null,"actual loading screen hands off to controllable world")
	if world._player==null:persist();quit(1);return
	report.map_profile=world._map_root.get_meta("load_profile",{}).duplicate(true)
	var actual_cache:String=report.map_profile.get("mesh_cache_path","")
	report.cache_path=ProjectSettings.globalize_path(actual_cache) if not actual_cache.is_empty() else ""
	report.cache_existed=existing_caches.has(report.cache_path)
	report.cache_scope=report.map_profile.get("mesh_cache_scope","unknown")
	report.cache_candidate=report.map_profile.get("mesh_cache_candidate",false)
	report.navigation_profile=world._navigation.loading_profile.duplicate(true)
	var deferred:Node=world._map_root.get_node_or_null("DeferredAssets")
	if deferred!=null:report.entry_deferred_profile=deferred.profile.duplicate(true)
	var collision_loader:Node=world._map_root.get_node_or_null("CollisionDependencyLoader")
	if collision_loader!=null:report.entry_collision_profile=collision_loader.snapshot()
	report.entry_collision_query=preload("res://scripts/world3d/world_stream.gd").collision_candidate_cache_stats(world._map_root)
	if world._map_root.has_meta("entry_plan"):
		var plan:Dictionary=world._map_root.get_meta("entry_plan")
		report.entry_plan=plan.duplicate(true)
		report.entry_core_ready_ms=(int(plan.core_resources_ready_us)-started)/1000.
		# Legacy neighbours_started_us marks activation/publication, not private
		# required-boundary preparation, which can now overlap core construction.
		check(int(plan.core_resources_ready_us)>started and int(plan.neighbours_started_us)>=int(plan.core_resources_ready_us),"formal safety publication starts after core completion")
		if deferred!=null and int(deferred.profile.get("entry_prefetch_jobs",0))>0:
			check(int(deferred.profile.entry_prefetch_first_dispatch_us)<int(plan.core_resources_ready_us) and deferred.profile.entry_prefetch_mode=="handoff","required safety models actually prepare during core construction and reuse the queue")
		check(int(world.loading_profile.entry_prefetch_started_us)>=int(world.loading_profile.entry_playable_ready_us),"ordinary prefetch cannot delay core or safety activation")
		check(not world._map_root.has_meta("entry_stream_clip") and (deferred==null or deferred.get_demand_scope().is_empty()),"entry scope releases for subsequent movement and neighbouring chunks")
		var batcher:Node=world._map_root.get_node_or_null("GroundRenderBatches")
		var actual_draws:=true
		for spec:Dictionary in world._map_root.get_meta("stream_library",[]):
			if not preload("res://scripts/world3d/world_stream.gd")._in_entry_scope(spec,plan.safety_clip):continue
			var source:Variant=world._map_root.get_meta("stream_meshes",{}).get(spec.uuid)
			if source==null or not source.mesh is CpuMesh:continue
			var key:String=str(batcher._member_groups.get(str(spec.uuid),"")) if batcher!=null else ""
			var visual:Variant=batcher.groups.get(key,{}).get("visual") if batcher!=null else null
			actual_draws=actual_draws and ((visual is MeshInstance3D and visual.mesh!=null) or (visual is MultiMeshInstance3D and visual.multimesh!=null and visual.multimesh.mesh!=null))
		check(actual_draws,"entry CPU-only sources have actual GPU mesh draws before control")
	report.initial_pending=deferred.pending.size() if deferred!=null else 0
	report.cpu_river_index={"deferred_overrides":preload("res://scripts/world3d/river_materials.gd").cpu_index_override_count,"temporary_gpu_restores":preload("res://scripts/world3d/river_materials.gd").cpu_index_legacy_restore_count,"water_cpu_normal_hits":preload("res://scripts/world3d/river_materials.gd").water_cpu_normal_hits}
	if report.initial_pending>0:check(world._navigation.geometry_pending and not world._navigation.fully_ready,"initial navigation never claims distant unprepared geometry complete")
	report.spawn=[world._player.position.x,world._player.position.y,world._player.position.z]
	if spawn_override is Vector3:
		check(Vector2(world._player.position.x,world._player.position.z).distance_to(Vector2(spawn_override.x,spawn_override.z))<.15,"direct entry uses the requested problem location without a subsequent teleport")
		check(preload("res://scripts/world3d/world_stream.gd").nearby_collision_ready(world._map_root,spawn_override),"problem spawn collision is ready before the loading screen retires")
	report.stream_specs=world._map_root.get_meta("stream_library",[]).size()
	report.collision_bodies=world._map_root.get_meta("stream_bodies",{}).size()
	report.entry_navigation_capability=world._navigation.capability_status()
	report.entry_wind_capability=world._weather.wind_objects.capability_status()
	report.effective_background_navigation=world._navigation_async(world._map_root)
	if report.effective_background_navigation:
		var exclude:Array[RID]=[world._player.get_rid()]
		check(world._hud!=null and report.collision_bodies>0 and world._physical_destination_fits(world._map_root,world.get_world_3d().direct_space_state,world._player.global_position,exclude),"HUD and synchronized physical support exist before play without a navigation dependency")
	else:check(world._hud!=null and world._navigation.ready_for_queries and report.collision_bodies>0,"HUD navigation and nearby collision exist before play")
	persist();print("GAME_ENTRY_READY ms=",report.entry_ms," map=",JSON.stringify(report.map_profile))
	if wait_deferred and deferred!=null:
		# Explicit benchmark-only demand. Normal gameplay must leave distant
		# records dormant; this switch retains the historical full-load control.
		deferred.set_demand("benchmark_all",AABB(Vector3(-100000,-100000,-100000),Vector3(200000,200000,200000)),100)
		var background_started:=Time.get_ticks_usec()
		var background_max:=0.;var last:=background_started
		var was_locked:=false;var lock_position:=Vector3.ZERO
		if teleport_probe:
			world._player.position=Vector3(292.9,5,151.4);world._guard_deferred_geometry()
			was_locked=world._player.input_locked;lock_position=world._player.position
			check(was_locked,"instant move into unprepared district waits for its geometry")
		while not deferred.is_complete() and deferred.error.is_empty():
			await process_frame
			if monitor!=null:monitor.frame("background_assets",{"pending":deferred.pending.size(),"models":deferred.profile.models,"active_workers":deferred.active_workers()})
			var now:=Time.get_ticks_usec();background_max=maxf(background_max,(now-last)/1000.);last=now
			if teleport_probe and was_locked and world._player.geometry_blocked and world._player.position!=lock_position:check(false,"guard holds player above unfinished collision")
			if teleport_probe and was_locked and not world._player.input_locked:was_locked=false;report.guard_released_ms=(now-background_started)/1000.
		check(deferred.error.is_empty(),"distant asset queue completes without errors")
		report.background_ms=(Time.get_ticks_usec()-background_started)/1000.;report.background_max_frame_ms=background_max;report.deferred_profile=deferred.profile.duplicate(true)
		report.final_specs=world._map_root.get_meta("stream_library",[]).size()
		check(deferred.pending.is_empty() and (world._navigation.streaming_geometry or not world._navigation.geometry_pending),"explicit whole-map benchmark demand completes without declaring a streaming map permanently resident")
		var settle_started:=Time.get_ticks_usec()
		var Stream=preload("res://scripts/world3d/world_stream.gd")
		while teleport_probe and (world._player.input_locked or world._map_root.get_meta("stream_chunk",Vector2i(2147483647,2147483647))!=Stream.chunk_key(world._player.position)) and Time.get_ticks_usec()-settle_started<60000000:await process_frame
		report.final_settle_ms=(Time.get_ticks_usec()-settle_started)/1000.
		if teleport_probe:check(not world._player.input_locked and world._map_root.get_meta("stream_chunk",Vector2i(2147483647,2147483647))==Stream.chunk_key(world._player.position),"prepared district collision settles and movement unlocks")
		persist();print("GAME_BACKGROUND_READY ms=",report.background_ms," specs=",report.final_specs," profile=",JSON.stringify(report.deferred_profile))
	if monitor!=null:
		# Fixed known services only: never walk the scene tree while measuring.
		# Independent callbacks are outside World3D.frame_timings and must retain
		# their own frame stamps (wind refresh does not run every render frame).
		var profiled:Array=[]
		var services:Dictionary={"world":world,"weather":world._weather,"outline":world._outline,"character":world._player._model,"hud":world._hud,"camera":world._camera,"player":world._player}
		if is_instance_valid(world._weather):services.wind=world._weather.wind_objects
		for node:Variant in services.values():
			if not is_instance_valid(node):continue
			profiled.append({"node":node,"had":node.has_meta("profile_frame"),"previous":node.get_meta("profile_frame",false)})
			node.set_meta("profile_frame",true)
		report.playable_world_frames=[]
		report.playable_runtime_frames=[]
		report.playable_runtime_note="Optional timers only. Camera breakdown is nested inside World3D.camera. World timings exclude weather, wind, outline, character and HUD callbacks. Components retain their own frame stamps; periodic values are emitted once. Player samples are only the latest physics tick observed per render frame: do not multiply them by tick counts. Use player cumulative start/end counters for exact covered CPU totals. Probe state sampling is measured separately; CPU/GPU times may overlap and must not be added as frame wall time."
		report.playable_player_physics_start=world._player.get_meta("physics_profile",{}).duplicate()
		var last_component_frame:Dictionary={}
		var sample_total_us:=0;var sample_max_us:=0
		var post_started:=Time.get_ticks_usec()
		while Time.get_ticks_usec()-post_started<10000000:
			await process_frame
			var background_active:bool=deferred!=null and not deferred.is_idle()
			monitor.frame("playable_background" if background_active else "playable_steady",{"pending":deferred.pending.size() if deferred!=null else 0})
			var sample_started:=Time.get_ticks_usec()
			var row:Dictionary={"observed_frame":Engine.get_process_frames(),"physics_frame":Engine.get_physics_frames(),"at_ms":(sample_started-post_started)/1000.0}
			if world.has_meta("frame_timings"):
				var timing:Dictionary=world.get_meta("frame_timings")
				if int(timing.get("frame",-1))!=int(last_component_frame.get("world",-2)):
					last_component_frame.world=int(timing.frame);report.playable_world_frames.append(timing.duplicate());row.world=timing.duplicate()
			for key:String in ["weather","outline","character","hud","camera"]:
				var node:Variant=services.get(key)
				if not is_instance_valid(node) or not node.has_meta("frame_timing"):continue
				var timing:Dictionary=node.get_meta("frame_timing")
				if int(timing.get("frame",-1))==int(last_component_frame.get(key,-2)):continue
				last_component_frame[key]=int(timing.get("frame",-1));row[key]=timing.duplicate()
			if world._player.has_meta("physics_timing"):
				var timing:Dictionary=world._player.get_meta("physics_timing")
				var tick:=int(timing.get("physics_frame",-1))
				if tick!=int(last_component_frame.get("player_physics",-2)):
					last_component_frame.player_physics=tick;row.player_physics=timing.duplicate()
			if world._player.has_meta("motion_timing"):
				var timing:Dictionary=world._player.get_meta("motion_timing")
				# Authority's historical frame field is a physics frame number.
				var tick:=int(timing.get("frame",-1))
				if tick!=int(last_component_frame.get("player_motion",-2)):
					last_component_frame.player_motion=tick;row.player_motion=timing.duplicate(true)
			if world.has_meta("traversal_timing"):
				var timing:Dictionary=world.get_meta("traversal_timing")
				if int(timing.frame)!=int(last_component_frame.get("traversal",-2)):
					last_component_frame.traversal=int(timing.frame);row.traversal=timing.duplicate()
			var wind:Variant=services.get("wind")
			if is_instance_valid(wind):
				for key:String in ["advance_timing","refresh_timing"]:
					if not wind.has_meta(key):continue
					var timing:Dictionary=wind.get_meta(key);var frame:=int(timing.get("frame",-1))
					if frame==int(last_component_frame.get(key,-2)):continue
					last_component_frame[key]=frame;row["wind_"+key]=timing.duplicate()
				row.wind_state={"enabled":wind.enabled,"shared_state":wind.shared_state_enabled,"receivers":wind.receivers.size(),"active":wind.active_rows.size(),"scan_pending":wind._scan_pending}
			var batches:Node=world._map_root.get_node_or_null("GroundRenderBatches")
			row.stream_state={"specs":world._map_root.get_meta("stream_library",[]).size(),"append_pending":world._map_root.get_meta("stream_append_pending",[]).size(),"jobs":world._map_root.get_meta("stream_jobs",[]).size(),"batch_pending":batches.pending.size() if batches!=null else 0,"batch_workers":batches._workers.size() if batches!=null else 0}
			row.camera_state={"cutaway_enabled":world._camera.cutaway.enabled,"cutaway_active":world._camera.cutaway.active_key,"excluded":world._camera.cutaway.excluded.size()}
			var used:=Time.get_ticks_usec()-sample_started
			sample_total_us+=used;sample_max_us=maxi(sample_max_us,used);row.sample_us=used
			report.playable_runtime_frames.append(row)
		report.final_player_position=[world._player.position.x,world._player.position.y,world._player.position.z]
		report.playable_player_physics_end=world._player.get_meta("physics_profile",{}).duplicate()
		report.playable_runtime_sampling={"frames":report.playable_runtime_frames.size(),"total_us":sample_total_us,"max_us":sample_max_us}
		for entry:Dictionary in profiled:
			if not is_instance_valid(entry.node):continue
			if entry.had:entry.node.set_meta("profile_frame",entry.previous)
			else:entry.node.remove_meta("profile_frame")
		report.monitor=monitor.finish();monitor=null
		report.frame_work_budget_after_monitor=preload("res://scripts/world3d/frame_work_budget.gd").report()
		persist()
	if physics_probe:
		report.physics_probe=await preload("res://tools/problem_chunk_physics_probe.gd").new().run(world,{"samples":7,"warmup":2,"max_seconds":180.0})
		check(report.physics_probe.get("ok",false),"local collision isolation restores all runtime state: "+str(report.physics_probe.get("error","")))
		persist()
	if collision_query_pair:
		report.collision_query_pair=await preload("res://tools/profile_collision_query_pair.gd").new().run(world)
		check(report.collision_query_pair.get("ok",false),"post-monitor paired collision queries preserve complete receipts and restore flags")
		persist()
	if deferred!=null:
		report.deferred_profile=deferred.profile.duplicate(true)
		report.remaining_deferred=deferred.pending.size();report.demand_idle=deferred.is_idle()
	if town_route:
		if town_route_return_only:
			report.town_route=await preload("res://tools/town_loading_route.gd").new().run(world,[Vector2(321.2,160.3)],Vector2(325.14145,163.78111),15.,true)
			report.town_route.diagnostic_only=true
			check(report.town_route.ok,"diagnostic return leg completes through normal player movement")
		else:
			report.town_route=await preload("res://tools/town_loading_route.gd").new().run(world)
			check(report.town_route.ok,"normal player movement visits and revisits the three reported district points")
		persist()
	report.frame_work_budget=preload("res://scripts/world3d/frame_work_budget.gd").report()
	report.final_navigation_capability=world._navigation.capability_status()
	report.final_wind_capability=world._weather.wind_objects.capability_status()
	if deferred!=null:report.final_deferred_profile=deferred.profile.duplicate(true)
	if is_instance_valid(collision_loader):report.final_collision_profile=collision_loader.snapshot()
	if preload("res://scripts/world3d/runtime_texture_cache.gd").profile_enabled:
		report.texture_stages=preload("res://scripts/world3d/runtime_texture_cache.gd").profile_snapshot()
		report.paint_texture_stages=preload("res://scripts/world3d/surface_materials.gd").profile_snapshot()
	report.final_collision_query=preload("res://scripts/world3d/world_stream.gd").collision_candidate_cache_stats(world._map_root)
	report.definition_cache=preload("res://scripts/world3d/definition_cache_policy.gd").snapshot()
	var expected=Doc.open_file(map_path)
	var actual:Dictionary=world._map_root.get_meta("extras",{})
	var entry_profile:Dictionary=world._map_root.get_meta("load_profile",{})
	if entry_profile.get("reference_index_hit",false) or entry_profile.get("reference_index_rebuilt_before_models",false):
		var snapshot=preload("res://scripts/world3d/document_source_snapshot.gd").read_file(map_path)
		var native:int=preload("res://scripts/world3d/document_open_cursor.gd").native_root(snapshot._data)
		check(native>=0 and Pose.same(snapshot._data.nodes[native].extras,world._map_root.get_meta("author_reference_extras",{})),"indexed runtime preserves the complete compact author document")
		var expected_by_id:Dictionary={};var loaded_ids:Dictionary={};var subset_valid:=expected!=null
		if expected!=null:
			for record:Dictionary in expected.records:expected_by_id[record.uuid]=record
		for record:Dictionary in actual.get("rmmo_records",[]):
			if loaded_ids.has(record.uuid) or not expected_by_id.has(record.uuid) or not Pose.same(record,expected_by_id[record.uuid]):subset_valid=false
			loaded_ids[record.uuid]=true
		check(subset_valid,"every published runtime record matches its authored definition and pose without duplicates")
		report.authored_record_count=expected_by_id.size();report.resident_record_count=loaded_ids.size()
	else:check(expected!=null and Pose.same(expected.records,actual.get("rmmo_records",[])),"all authored records survive actual game entry")
	if expected!=null:
		for key in expected.map_meta:check(Pose.same(expected.map_meta[key],actual.get(key)),"metadata retained: "+str(key))
	report.model_texture_observation_epoch_s=Time.get_unix_time_from_system()
	report.model_texture_observation=model_texture_observation(world._map_root)
	if memory_pages:
		report.memory_pages=memory_pages_observation()
		check(report.memory_pages.get("ok",false),"post-measurement Windows working-set classification is complete")
		persist()
	# Scene evidence should not be obscured by the avatar at a close camera.
	# Hide only its render root AFTER every measurement/assertion, then restore;
	# the player, physics, readiness and timed loading path remain unchanged.
	var capture_avatar:Node3D=world._player._model
	var capture_avatar_visible:bool=capture_avatar.visible if is_instance_valid(capture_avatar) else false
	if is_instance_valid(capture_avatar):capture_avatar.visible=false
	report.screenshot_avatar_hidden=is_instance_valid(capture_avatar)
	await RenderingServer.frame_post_draw
	report.screenshot=output.get_basename()+".png"
	check(root.get_texture().get_image().save_png(report.screenshot)==OK,"first playable frame captured after measurement")
	if is_instance_valid(capture_avatar):capture_avatar.visible=capture_avatar_visible
	check(FileAccess.get_sha256(map_path)==report.map_sha and FileAccess.get_sha256(SOURCE)==report.formal_sha,"temporary checkpoint and formal map unchanged")
	persist();print("GAME_ENTRY_FINISHED failures=",report.failures," report=",output)
	world.free();current_scene=null
	for frame in 3:await process_frame
	quit(0 if report.failures==0 else 1)
