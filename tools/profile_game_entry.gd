extends SceneTree
## Actual loading screen -> world transition -> first playable frame, on a
## private desktop. Only a pre-existing temporary reference map is accepted.
const Paths=preload("res://scripts/world3d/map_paths.gd")
const Cache=preload("res://scripts/world3d/runtime_mesh_cache.gd")
const Doc=preload("res://scripts/world3d/world_document.gd")
const Pose=preload("res://scripts/world3d/pose_save.gd")
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
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if not value:report.failures+=1
func persist()->void:
	var file:=FileAccess.open(output,FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(report,"\t"));file.close()
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
	var reset_cache:=false
	var wait_deferred:=false
	var teleport_probe:=false
	var monitor_enabled:=false
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--map="):map_path=arg.trim_prefix("--map=")
		elif arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		elif arg=="--reset-derived-cache":reset_cache=true
		elif arg=="--wait-deferred":wait_deferred=true
		elif arg=="--teleport-probe":teleport_probe=true
		elif arg=="--monitor":monitor_enabled=true
	if not Paths.allowed(map_path,Paths.external_root().path_join("cache/world3d")) or not FileAccess.file_exists(map_path):quit(1);return
	if not Paths.allowed(output,Paths.external_root().path_join("review_artifacts")):quit(1);return
	Engine.max_fps=60;root.size=Vector2i(1440,900);root.content_scale_size=root.size
	create_timer(600).timeout.connect(func():report.timeout=true;persist();quit(2))
	report.map=map_path;report.map_sha=FileAccess.get_sha256(map_path);report.formal_sha=FileAccess.get_sha256(SOURCE)
	var cache_path:=Cache.cache_path(map_path)
	report.cache_path=ProjectSettings.globalize_path(cache_path);report.cache_existed=FileAccess.file_exists(cache_path)
	# Exact disposable cache file only; never directories or a formal map cache.
	if reset_cache and FileAccess.file_exists(cache_path):
		check(DirAccess.remove_absolute(cache_path)==OK,"remove only temporary map derived cache")
	report.reset_derived_cache=reset_cache;persist()
	preload("res://tools/world3d_test_character.gd").ensure(self)
	var session=root.get_node("GameSession")
	session.spawn_data={"character":session.selected_character.duplicate(true),"equipment":[],"world_mode":"world3d"}
	session.world3d_map_path=map_path
	started=Time.get_ticks_usec();previous=started;sampling=true;process_frame.connect(observe)
	if monitor_enabled:monitor=preload("res://tools/load_monitor.gd").new();monitor.start(self)
	session.go_world_3d()
	while true:
		await process_frame
		if is_instance_valid(current_scene) and current_scene.has_node("FailActions"):
			check(false,"actual loading screen rejects map: "+str(current_scene.status_label.text));persist();quit(1);return
		if is_instance_valid(current_scene) and current_scene.has_method("is_world_ready") and current_scene.is_world_ready() and not session._world_transition_active:break
	observe();sampling=false;process_frame.disconnect(observe)
	report.entry_ms=(Time.get_ticks_usec()-started)/1000.;report.max_frame_ms=frame_max;report.slow_frames=slow
	var world=current_scene
	report.session_profile=session.last_loading_profile.duplicate(true);report.world_profile=world.loading_profile.duplicate(true)
	check(world._player!=null and not world._player.input_locked and session.get_node_or_null("WorldTransition")==null,"actual loading screen hands off to controllable world")
	if world._player==null:persist();quit(1);return
	report.map_profile=world._map_root.get_meta("load_profile",{}).duplicate(true)
	report.navigation_profile=world._navigation.loading_profile.duplicate(true)
	var deferred:Node=world._map_root.get_node_or_null("DeferredAssets")
	report.initial_pending=deferred.pending.size() if deferred!=null else 0
	if report.initial_pending>0:check(world._navigation.geometry_pending and not world._navigation.fully_ready,"initial navigation never claims distant unprepared geometry complete")
	report.spawn=[world._player.position.x,world._player.position.y,world._player.position.z]
	report.stream_specs=world._map_root.get_meta("stream_library",[]).size()
	report.collision_bodies=world._map_root.get_meta("stream_bodies",{}).size()
	check(world._hud!=null and world._navigation.ready_for_queries and report.collision_bodies>0,"HUD navigation and nearby collision exist before play")
	persist();print("GAME_ENTRY_READY ms=",report.entry_ms," map=",JSON.stringify(report.map_profile))
	if wait_deferred and deferred!=null:
		var background_started:=Time.get_ticks_usec()
		var background_max:=0.;var last:=background_started
		var was_locked:=false;var lock_position:=Vector3.ZERO
		if teleport_probe:
			world._player.position=Vector3(292.9,5,151.4);world._guard_deferred_geometry()
			was_locked=world._player.input_locked;lock_position=world._player.position
			check(was_locked,"instant move into unprepared district waits for its geometry")
		while not deferred.is_complete() and deferred.error.is_empty():
			await process_frame
			if monitor!=null:monitor.frame("background_assets",{"pending":deferred.pending.size(),"models":deferred.profile.models,"worker_alive":deferred._worker!=null and deferred._worker.is_alive()})
			var now:=Time.get_ticks_usec();background_max=maxf(background_max,(now-last)/1000.);last=now
			if teleport_probe and was_locked and world._player.geometry_blocked and world._player.position!=lock_position:check(false,"guard holds player above unfinished collision")
			if teleport_probe and was_locked and not world._player.input_locked:was_locked=false;report.guard_released_ms=(now-background_started)/1000.
		check(deferred.error.is_empty(),"distant asset queue completes without errors")
		report.background_ms=(Time.get_ticks_usec()-background_started)/1000.;report.background_max_frame_ms=background_max;report.deferred_profile=deferred.profile.duplicate(true)
		report.final_specs=world._map_root.get_meta("stream_library",[]).size()
		check(deferred.pending.is_empty() and not world._navigation.geometry_pending,"all deferred instances published before full navigation resumes")
		var settle_started:=Time.get_ticks_usec()
		var Stream=preload("res://scripts/world3d/world_stream.gd")
		while teleport_probe and (world._player.input_locked or world._map_root.get_meta("stream_chunk",Vector2i(2147483647,2147483647))!=Stream.chunk_key(world._player.position)) and Time.get_ticks_usec()-settle_started<60000000:await process_frame
		report.final_settle_ms=(Time.get_ticks_usec()-settle_started)/1000.
		if teleport_probe:check(not world._player.input_locked and world._map_root.get_meta("stream_chunk",Vector2i(2147483647,2147483647))==Stream.chunk_key(world._player.position),"prepared district collision settles and movement unlocks")
		persist();print("GAME_BACKGROUND_READY ms=",report.background_ms," specs=",report.final_specs," profile=",JSON.stringify(report.deferred_profile))
	if monitor!=null:
		var post_started:=Time.get_ticks_usec()
		while Time.get_ticks_usec()-post_started<10000000:
			await process_frame
			var background_active:bool=deferred!=null and not deferred.is_complete()
			monitor.frame("playable_background" if background_active else "playable_steady",{"pending":deferred.pending.size() if deferred!=null else 0})
		report.monitor=monitor.finish();monitor=null;persist()
	var expected=Doc.open_file(map_path)
	var actual:Dictionary=world._map_root.get_meta("extras",{})
	check(expected!=null and Pose.same(expected.records,actual.get("rmmo_records",[])),"all authored records survive actual game entry")
	if expected!=null:
		for key in expected.map_meta:check(Pose.same(expected.map_meta[key],actual.get(key)),"metadata retained: "+str(key))
	await RenderingServer.frame_post_draw
	report.screenshot=output.get_basename()+".png"
	check(root.get_texture().get_image().save_png(report.screenshot)==OK,"first playable frame captured after measurement")
	check(FileAccess.get_sha256(map_path)==report.map_sha and FileAccess.get_sha256(SOURCE)==report.formal_sha,"temporary checkpoint and formal map unchanged")
	persist();print("GAME_ENTRY_FINISHED failures=",report.failures," report=",output)
	world.free();current_scene=null
	for frame in 3:await process_frame
	quit(0 if report.failures==0 else 1)
