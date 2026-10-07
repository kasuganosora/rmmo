extends "res://tools/test_world3d_mcp.gd"
const Art = preload("res://scripts/asset/art_paths.gd")
var completed_response := {}
var phases := {}
var frame_gaps: Array[float] = []
var previous_frame := 0
var publish_delay := 1200

func track_frame() -> void:
	if not is_instance_valid(editor) or not editor.saving(): previous_frame = 0; return
	var now := Time.get_ticks_usec()
	if previous_frame > 0: frame_gaps.append((now-previous_frame)/1000.0)
	previous_frame = now
	phases[editor._save_job.state().phase] = true

func delayed_publish(stage: String) -> bool:
	if stage == "resources_ready": OS.delay_msec(publish_delay)
	return false

func default_save() -> void:
	completed_response = await call_tool("save_world")

func run() -> void:
	Engine.max_fps = 60
	root.size = Vector2i(1280, 900); root.content_scale_size = root.size
	create_timer(240).timeout.connect(func(): quit(2))
	var directory := Paths.cache_directory("save_progress_%d" % Time.get_ticks_usec())
	var path := directory.path_join("map.gltf")
	var doc := Doc.new()
	doc.add_box("ground", Vector3(0,-.1,0), Vector3(40,.2,40))
	doc.add_box("block", Vector3(0,1.5,0), Vector3(4,3,4))
	check(doc.save(path)==OK, "temporary map saved")
	var session = preload("res://scripts/net/net.gd").session()
	session.world3d_editor_doc = doc; session.world3d_editor_path = path
	editor = preload("res://scripts/world_editor/world_editor.gd").new()
	editor._mcp_autostart = false; editor._draft_directory = directory.path_join("drafts")
	root.add_child(editor); await settle(); editor._safety.enabled = false
	var probe := TCPServer.new(); port = 31640
	while probe.listen(port,"127.0.0.1") != OK: port += 1
	probe.stop(); check(editor.start_mcp(port).ok,"HTTP server")
	var definitions: Array = (await rpc("tools/list")).result.tools
	check(definitions.size()==preload("res://scripts/world_editor/mcp_schema.gd").tools().size() and definitions.any(func(d): return d.name=="save_world" and d.inputSchema.properties.has("background")), "3D discovery exposes background saves")
	process_frame.connect(track_frame)
	Io.save_fault = delayed_publish
	var dialog := AcceptDialog.new(); editor.add_child(dialog); dialog.popup_centered()
	var started := await call_tool("save_world", {"background":true})
	check(started.pending and not started.saved and editor.saving(), "background HTTP immediately returns a job, never false saved success")
	var before: Dictionary = doc.recovery_snapshot()
	check(editor._canvas.get_child(0).render_target_update_mode==SubViewport.UPDATE_DISABLED,"unchanged 3D frame is retained during save")
	check(root.gui_disable_input and dialog.gui_disable_input,"main GUI and embedded dialogs both lock during save")
	dialog.hide()
	await call_tool("save_world", {}, false)
	await call_tool("undo", {}, false)
	await call_tool("open_world", {"path":path}, false)
	await call_tool("close_editor", {"action":"discard"}, false)
	check(equivalent(before,doc.recovery_snapshot()), "busy requests have no document/history side effects")
	var live := await call_tool("editor_state")
	check(live.save.active and live.save.job_id==started.job_id and live.save.elapsed_seconds>0, "HTTP state remains responsive while exporting")
	check(editor._save_progress.visible and editor._status.text.begins_with("保存中"), "status bar shows live stage, count and elapsed time")
	editor._safety.request_exit()
	check(not editor._safety.state().close_pending and editor.saving(), "window close cannot interrupt publication")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(Art.review_path("save_progress/status_bar.png"))
	var finished: Dictionary = await editor._save_job.wait_result()
	check(finished.ok and not editor._save_progress.visible and not editor._dirty, "successful completion clears busy indicator and dirty flag")
	check(editor._canvas.get_child(0).render_target_update_mode!=SubViewport.UPDATE_DISABLED,"3D rendering resumes after save")
	check(not root.gui_disable_input and not dialog.gui_disable_input,"main GUI and embedded dialogs restore after save")
	dialog.queue_free()
	check((await call_tool("editor_state")).save.result.saved, "completed result remains queryable")
	# Default HTTP keeps its response pending while other clients keep working.
	publish_delay = 11000 # Longer than the server's ordinary 10-second idle limit.
	completed_response = {}; default_save()
	while not editor.saving(): await process_frame
	var responsive := await call_tool("editor_state")
	check(responsive.save.active and completed_response.is_empty(), "default wait does not block HTTP progress queries")
	while completed_response.is_empty(): await process_frame
	check(completed_response.saved and not completed_response.pending, "default response still means fully published")
	publish_delay = 1200
	# UI keyboard uses the same job and blocks editing shortcuts while it runs.
	editor._dirty = true
	var event := InputEventKey.new(); event.keycode=KEY_S; event.ctrl_pressed=true; event.pressed=true
	Input.parse_input_event(event); await settle()
	check(editor.saving(), "Ctrl+S starts the shared asynchronous job")
	var undos: int = doc._undo.size()
	event.keycode=KEY_Z; Input.parse_input_event(event); await settle()
	check(doc._undo.size()==undos, "UI undo blocked while saving")
	await editor._save_job.wait_result()
	Io.save_fault = Callable()
	await call_tool("open_world", {"path":path})
	check(equivalent(doc.records,editor._doc.records), "asynchronous save reopens with exact records")
	# Failure ends progress, keeps the old file and unsaved changes, and allows retry.
	var signature := FileAccess.get_sha256(path)
	editor._dirty = true
	Io.save_fault = func(stage): return stage=="before_publish"
	await call_tool("save_world", {}, false)
	check(editor._dirty and not editor.saving() and not editor._save_progress.visible and FileAccess.get_sha256(path)==signature, "failed publication preserves file and dirty state, unlocks UI")
	check((await call_tool("editor_state")).save.phase=="failed", "failure is exposed through progress state")
	Io.save_fault = Callable()
	await call_tool("save_world")
	var previous_job: int = editor._save_job.state().job_id
	await call_tool("save_world", {"path":"C:/outside.gltf","background":true}, false)
	await call_tool("save_world", {"background":"yes"}, false)
	check(editor._save_job.state().job_id==previous_job and not editor.saving(), "illegal path/schema does not start a save")
	check(phases.has("reuse") and phases.has("publish") and frame_gaps.size()>60, "render frames advance across resource verification and publication")
	var report := {"failures":failed,"phases":phases.keys(),"frames":frame_gaps.size(),"max_frame_ms":frame_gaps.max()}
	var file := FileAccess.open(Art.review_path("save_progress/http.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t")); file.close()
	editor._mcp.stop(); editor.queue_free(); await settle()
	Io._remove_tree(directory)
	print("SAVE_PROGRESS_FINISHED ",report); quit(0 if failed==0 else 1)
