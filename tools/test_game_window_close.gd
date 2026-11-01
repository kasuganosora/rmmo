extends SceneTree
## The host sends a real WM_CLOSE to this private-desktop game window.
## This fixture never replaces that request with quit() on its success path.
var output_path:String
var game:Node

func _initialize()->void:
	root.close_requested.connect(_close_requested)
	root.tree_exited.connect(func():_note("root_tree_exited"))
	run.call_deferred()

func _note(event:String,extra:Dictionary={})->void:
	extra=extra.duplicate();extra.event=event;extra.ticks_us=Time.get_ticks_usec()
	print("WINDOW_CLOSE_PROBE ",JSON.stringify(extra))

func run()->void:
	var map_path:=OS.get_environment("RMMO_CLOSE_PROBE_MAP")
	output_path=OS.get_environment("RMMO_CLOSE_PROBE_READY")
	var paths=preload("res://scripts/world3d/map_paths.gd")
	if not paths.allowed(map_path,paths.external_root().path_join("cache/world3d")) or not FileAccess.file_exists(map_path):
		push_error("Window-close test requires an existing temporary map");quit(2);return
	if not paths.allowed(output_path,paths.external_root().path_join("review_artifacts")):
		push_error("Window-close handshake must stay in review_artifacts");quit(2);return
	create_timer(240).timeout.connect(func():_note("fixture_timeout");quit(2))
	preload("res://tools/world3d_test_character.gd").ensure(self)
	var session:=root.get_node("GameSession")
	session.spawn_data={"character":session.selected_character.duplicate(true),"equipment":[],"world_mode":"world3d"}
	session.world3d_map_path=map_path
	_note("entry_started",{"map_sha256":FileAccess.get_sha256(map_path)})
	session.go_world_3d()
	while true:
		await process_frame
		if is_instance_valid(current_scene) and (current_scene.has_node("FailActions") or current_scene.has_meta("entry_loading_error")):
			var detail:String=str(current_scene.get_meta("entry_loading_error",""))
			var status:Variant=current_scene.get("status_label")
			if status is Label:detail=status.text
			_note("entry_failed",{"detail":detail});quit(2);return
		if is_instance_valid(current_scene) and current_scene.has_method("is_world_ready") and current_scene.is_world_ready() and not session._world_transition_active:break
	game=current_scene
	game.tree_exited.connect(func():_note("world_tree_exited"))
	_note("playable")
	await create_timer(3.0).timeout
	var receipt:={"pid":OS.get_process_id(),"hwnd":DisplayServer.window_get_native_handle(DisplayServer.WINDOW_HANDLE,root.get_window_id()),"ready_ticks_us":Time.get_ticks_usec(),"viewport_disabled":root.disable_3d}
	var file:=FileAccess.open(output_path,FileAccess.WRITE)
	file.store_string(JSON.stringify(receipt));file.close()
	_note("waiting_for_native_close",receipt)

func _close_requested()->void:
	_note("native_close_received",{"auto_accept_quit":auto_accept_quit,"viewport_disabled":root.disable_3d})

func _finalize()->void:
	_note("scene_tree_finalized")
