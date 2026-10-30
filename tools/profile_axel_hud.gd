extends "res://tools/profile_axel_game_pipeline.gd"
## Full game comparison; the map is an immutable temporary copy, all gameplay
## systems remain enabled; diagnostic switches are recorded in the report.
var _ready_frames:=0
var _game_world:Node
var _hud_probe_installed:=false
var _ui_step:=-1
var _ui_finished:=false
var _draw_frames:Dictionary={}
var _replay_step:=0
var _completed_audit:RefCounted
var _completed_sample_count:=0
const WINDOWS=["map","inventory","skills","character","system"]

func runtime_observation_finished()->bool:
	return _ui_finished

func _initialize()->void:
	var scan_proxy:bool="--scan-proxy-sources" in OS.get_cmdline_user_args()
	preload("res://scripts/world3d/distant_building_proxy.gd").source_catalog_enabled=not scan_proxy
	report.proxy_source_catalog=not scan_proxy
	if "--native-cpu-handoff" in OS.get_cmdline_user_args():preload("res://scripts/world3d/compiled_asset_preparation.gd").native_cpu_handoff_enabled=true
	if "--without-native-cpu-handoff" in OS.get_cmdline_user_args():preload("res://scripts/world3d/compiled_asset_preparation.gd").native_cpu_handoff_enabled=false
	report.native_cpu_handoff=preload("res://scripts/world3d/compiled_asset_preparation.gd").native_cpu_handoff_enabled
	preload("res://scripts/world3d/ground_batcher.gd").private_layered_upload_enabled="--private-layered-upload" in OS.get_cmdline_user_args()
	report.private_layered_upload=preload("res://scripts/world3d/ground_batcher.gd").private_layered_upload_enabled
	preload("res://scripts/world3d/ground_batcher.gd").private_road_upload_enabled="--private-road-upload" in OS.get_cmdline_user_args()
	report.private_road_upload=preload("res://scripts/world3d/ground_batcher.gd").private_road_upload_enabled
	var old_disposal:bool="--without-source-retirement" in OS.get_cmdline_user_args()
	preload("res://scripts/world3d/world_navigation.gd").sliced_source_disposal_enabled=not old_disposal
	preload("res://scripts/world3d/dependency_index_proof.gd").cpu_snapshot_retirement_enabled=not old_disposal
	preload("res://scripts/world3d/world_stream.gd").cpu_author_retirement_enabled=not old_disposal
	preload("res://scripts/world3d/world_stream.gd").sliced_record_disposal_enabled=not old_disposal
	report.source_owner_retirement=not old_disposal
	var old_presentation:bool="--without-presentation-retirement" in OS.get_cmdline_user_args()
	preload("res://scripts/world3d/building_cutaway.gd").incremental_catalog_enabled=not old_presentation
	preload("res://scripts/ui/world_map_terrain_layer.gd").sliced_retirement_enabled=not old_presentation
	report.presentation_retirement=not old_presentation
	var prefab=preload("res://scripts/world3d/house_prefab.gd")
	prefab.fused_texture_checks_enabled=not "--without-fused-texture-checks" in OS.get_cmdline_user_args()
	prefab.texture_check_profile_enabled=true
	report.fused_texture_checks=prefab.fused_texture_checks_enabled
	var map_data=preload("res://scripts/world3d/world_map_data.gd")
	map_data.native_visible_order_enabled=not "--scripted-map-query-order" in OS.get_cmdline_user_args()
	report.native_map_query_order=map_data.native_visible_order_enabled
	if "--trace-completed-jobs" in OS.get_cmdline_user_args():
		preload("res://scripts/world3d/completed_job_trace.gd").start()
		_completed_audit=preload("res://tools/completed_job_audit_probe.gd").new()
		report.completed_job_samples=[]
		report.completed_job_diagnostic=true
		report.normal_performance_sample=false
	var copy:=OS.get_environment("RMMO_HUD_TEST_MAP").replace("\\","/").simplify_path()
	if not preload("res://scripts/world3d/map_paths.gd").allowed(copy,TEST_ROOT) or not FileAccess.file_exists(copy):
		printerr("HUD profile requires an existing temporary map under review_artifacts");quit(2);return
	selected_map=copy
	super._initialize()

func source_snapshot(folder:String="res://scripts")->Dictionary:
	var result:=super.source_snapshot(folder)
	if folder=="res://scripts":
		for path:String in ["res://tools/profile_axel_hud.gd","res://tools/profile_axel_game_pipeline.gd"]:result[path]=FileAccess.get_sha256(path)
		if _completed_audit!=null:result["res://tools/completed_job_audit_probe.gd"]=FileAccess.get_sha256("res://tools/completed_job_audit_probe.gd")
	return result

func observe()->void:
	super.observe()
	if sampling and _completed_audit!=null and report.queues.size()!=_completed_sample_count:
		_completed_sample_count=report.queues.size()
		var observed:=observation_map()
		var queue:Node=observed.get_node_or_null("DeferredAssets") if observed!=null else null
		if queue!=null:report.completed_job_samples.append(_completed_audit.sample(queue,Time.get_ticks_usec()-began,phase,preload("res://scripts/world3d/completed_job_trace.gd").events))
	if not frames.is_empty():frames.back().engine_frame=Engine.get_process_frames()
	if not sampling or current_scene==null or not current_scene.has_method("is_world_ready"):return
	var world:Node=current_scene
	if not world.is_world_ready() or root.get_node("GameSession")._world_transition_active:return
	_game_world=world
	if not _hud_probe_installed:
		_hud_probe_installed=true
		if is_instance_valid(world._hud) and is_instance_valid(world._hud._radar):world._hud._radar.set_meta("profile_frame",true)
	if is_instance_valid(world._hud):
		if not report.has("map_draws"):report.map_draws=[]
		for view:Node in [world._hud._radar,world._hud._map_overview]:
			if not is_instance_valid(view):continue
			if not view.has_meta("profile_frame"):view.set_meta("profile_frame",true)
			var timing:Dictionary=view.get_draw_timing()
			if not timing.is_empty() and int(_draw_frames.get(view.get_instance_id(),-1))!=int(timing.frame):
				_draw_frames[view.get_instance_id()]=timing.frame
				report.map_draws.append({"view":"radar" if view.radar else "overview","at_ms":(Time.get_ticks_usec()-began)/1000.,"phase":phase,"timing":timing})
	if report.has("full_ready"):
		_run_ui_schedule(world)
		return
	var map:Node=world._map_root
	var queue:Node=map.get_node_or_null("DeferredAssets")
	var batches:Node=map.get_node_or_null("GroundRenderBatches")
	var ready:bool=queue!=null and queue._demanded_by_id.is_empty() and queue._jobs.is_empty() and map.get_meta("stream_jobs",[]).is_empty() and map.has_meta("stream_chunk")
	if batches!=null:ready=ready and batches._preparation.is_empty() and batches.pending.is_empty() and batches._workers.is_empty()
	_ready_frames=_ready_frames+1 if ready else 0
	if _ready_frames==3:
		report.full_ready={"at_ms":(Time.get_ticks_usec()-began)/1000.,"frame":Engine.get_process_frames(),"contract":"Full game is playable and current demand/jobs/render-batches are empty for three frames. Native texture entry readiness uses the game's existing gate, not forced full mip residency."}
		phase="steady"
		print("AXEL_HUD_FULL_READY ",JSON.stringify(report.full_ready))

func _run_ui_schedule(world:Node)->void:
	var seconds:float=((Time.get_ticks_usec()-began)/1000.-float(report.full_ready.at_ms))/1000.
	if seconds<30.:return
	if not is_instance_valid(world._hud):_ui_finished=true;return
	if OS.get_environment("RMMO_HUD_REPLAY")=="1" and seconds>=64. and seconds<70. and _replay_step<6 and seconds>=64.+_replay_step*.8:
		_replay_update(world._hud)
	var step:=mini(int((seconds-30.)/8.),WINDOWS.size())
	if step!=_ui_step:
		_ui_step=step
		var before:=Time.get_ticks_usec()
		if step<WINDOWS.size():
			phase="ui_open_"+WINDOWS[step]
			world._hud._toggle_window(WINDOWS[step])
		else:
			phase="ui_closed"
			for id:String in WINDOWS:world._hud._windows[id].hide()
		if not report.has("ui_actions"):report.ui_actions=[]
		report.ui_actions.append({"at_ms":(Time.get_ticks_usec()-began)/1000.,"phase":phase,"call_ms":(Time.get_ticks_usec()-before)/1000.})
	if seconds>=80.:_ui_finished=true

func _replay_update(hud:Control)->void:
	var map_id:int=hud._map_overview.get_instance_id()
	var started:=Time.get_ticks_usec()
	match _replay_step:
		0:hud.apply_inventory_snapshot(hud._server_inventory,hud._server_gold+1)
		1:hud.apply_combat_stats({"hp":hud._hp,"hp_max":hud._hp_max})
		2:hud.apply_quest_snapshot(hud._server_quests)
		3:hud.apply_skill_catalog(hud._server_skills)
		4,5:hud.note_skill_cooldown("basic_attack",4.,5.)
	if not report.has("ui_replay"):report.ui_replay=[]
	report.ui_replay.append({"step":_replay_step,"call_ms":(Time.get_ticks_usec()-started)/1000.,"at_ms":(Time.get_ticks_usec()-began)/1000.,"map_rebuilt":map_id!=hud._map_overview.get_instance_id(),"scope":"controlled HUD-only snapshot replay; game server state unchanged"})
	_replay_step+=1

func save()->void:
	# Optional main-thread journal; serialize only after timed observation, just
	# like the existing frame/queue samples. Include lifecycle generation IDs so
	# initial load and the later return cannot be confused as the same job.
	if report.get("completed_job_diagnostic",false):
		report.completed_job_trace=preload("res://scripts/world3d/completed_job_trace.gd").snapshot(began)
	super.save()

func finish(code:int)->void:
	var prefab=preload("res://scripts/world3d/house_prefab.gd")
	report.texture_check_work={"owner_reads":prefab.texture_owner_reads,"catalog_reads":prefab.texture_catalog_reads}
	if code==0:
		check(report.has("full_ready"),"full-game current demand settles within observation window")
		if is_instance_valid(_game_world):
			report.viewport_size=root.size
			var proxies:Node=_game_world._map_root.get_node_or_null("DistantBuildingProxy")
			if proxies!=null:report.distant_proxy_profile=proxies.profile.duplicate(true)
			report.collision_candidate_cache=preload("res://scripts/world3d/world_stream.gd").collision_candidate_cache_stats(_game_world._map_root)
			report.hud_present=is_instance_valid(_game_world._hud)
			if not report.has("actual_scope"):report.actual_scope="Full game: avatar, navigation, weather, events and ordinary residency. Only HUD is controlled. Stationary baseline followed by ordinary map/inventory/skills/character/settings window opens; no claim of walking or far eviction."
	await super.finish(code)
