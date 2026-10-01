extends "res://tools/test_world3d_mcp.gd"
const Store = preload("res://scripts/world_editor/draft_store.gd")

func make_editor(path: String, draft_root: String) -> void:
	var session = preload("res://scripts/net/net.gd").session()
	session.world3d_editor_path = path
	session.world3d_editor_doc = null
	editor = preload("res://scripts/world_editor/world_editor.gd").new()
	editor._mcp_autostart = false
	editor._draft_directory = draft_root
	root.add_child(editor)
	await settle()

func wait_file(path: String, seconds: int = 15) -> bool:
	var deadline := Time.get_ticks_msec() + seconds * 1000
	while not FileAccess.file_exists(path) and Time.get_ticks_msec() < deadline: await create_timer(0.05).timeout
	return FileAccess.file_exists(path)

func child_args(extra: Array) -> PackedStringArray:
	return PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tools/test_world3d_recovery.gd", "--"] + extra)

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and args[0] == "--interrupted-draft":
		var document = Doc.open_file(args[1])
		var storage := Store.new(args[2])
		storage.session_id = "aabbccddeeff00112233445566778899"
		document.records[0].position = [1, 2, 3]
		storage.write(args[1], document)
		document.records[0].position = [77, 2, 3]
		storage.write_fault = func(_stage):
			var marker := FileAccess.open(args[3], FileAccess.WRITE)
			marker.store_string(storage.own_id(args[1])); marker.close()
			while true: OS.delay_msec(50)
			return false
		storage.write(args[1], document)
		quit(2); return
	if args.size() > 0 and args[0] == "--close-host":
		await make_editor(args[1], args[2])
		editor._doc.records[0].position = [0, 9, 0]
		editor._dirty = true
		var draft: Dictionary = editor._safety.save_draft()
		var started: Dictionary = editor.start_mcp(int(args[3]))
		var marker := FileAccess.open(args[4], FileAccess.WRITE)
		marker.store_string(JSON.stringify({"ok": started.ok and draft.ok, "draft_id": draft.get("draft_id", "")})); marker.close()
		return
	var directory := Paths.cache_directory("recovery_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	var path := directory.path_join("map.gltf")
	var draft_root := directory.path_join("drafts")
	var doc := Doc.new()
	var id: String = doc.add_box("block", Vector3(0, 1, 0), Vector3(2, 2, 2))
	doc.map_meta = {"spawn": [0, 0.9, 4], "label": "original"}
	check(doc.save(path) == OK, "create isolated recovery map")
	await make_editor(path, draft_root)
	var probe := TCPServer.new()
	while probe.listen(port, "127.0.0.1") != OK: port += 1
	probe.stop()
	check(editor.start_mcp(port).ok, "start recovery HTTP fixture")
	var listed := await rpc("tools/list")
	check(listed.result.tools.size() == 65, "discovery includes draft, autosave and close tools")
	var status := await call_tool("editor_state")
	check(status.autosave.enabled and status.autosave.interval_seconds == 60 and not auto_accept_quit, "autosave defaults and native close guard are enabled")
	await call_tool("configure_autosave", {"enabled": true, "interval_seconds": 15})
	await call_tool("configure_autosave", {"interval_seconds": 1}, false)
	await call_tool("set_object_transform", {"id": id, "position": [2.25, 3.5, 4.75]})
	editor._doc.map_meta.label = "unsaved draft metadata"
	var disk_hash := FileAccess.get_sha256(path)
	var draft := await call_tool("save_editor_draft")
	var draft_id: String = draft.draft_id
	check(FileAccess.get_sha256(path) == disk_hash and editor._dirty and editor._doc.editor_dirty, "draft preserves published map and dirty state")
	var rows := await call_tool("list_editor_drafts", {"limit": 1})
	check(rows.total == 1 and rows.drafts[0].draft_id == draft_id and not rows.drafts[0].source_changed, "draft listing reports source and timestamp")
	var before: Array = editor._doc.records.duplicate(true)
	await call_tool("restore_editor_draft", {"draft_id": draft_id}, false)
	check(editor._doc.records == before, "recovery requires explicit handling of current edits")
	await call_tool("open_world", {"path": path, "discard_changes": true})
	await call_tool("restore_editor_draft", {"draft_id": draft_id})
	check(Geometry.vector(editor._doc._find(id), "position").is_equal_approx(Vector3(2.25, 3.5, 4.75)) and editor._doc.map_meta.label == "unsaved draft metadata", "draft restores transform and map metadata")
	await call_tool("undo")
	check(editor._doc.map_meta.label == "original" and Geometry.vector(editor._doc._find(id), "position") == Vector3(0, 1, 0), "undo recovery restores records, metadata and disk baseline")
	await call_tool("redo")
	check(editor._doc.map_meta.label == "unsaved draft metadata", "redo restores complete recovery snapshot")
	var own_file: String = editor._safety.store.file_for(draft_id)
	var draft_hash := FileAccess.get_sha256(own_file)
	editor._doc._find(id).position[0] = 8.0
	editor._safety.store.write_fault = func(_stage): return true
	await call_tool("save_editor_draft", {}, false)
	check(FileAccess.get_sha256(own_file) == draft_hash and FileAccess.get_sha256(path) == disk_hash, "interrupted publish preserves previous draft and formal map")
	editor._safety.store.write_fault = Callable()
	editor._stroke.begin(editor._doc)
	editor._safety.tick()
	check(FileAccess.get_sha256(own_file) == draft_hash, "automatic draft skips active paint transaction")
	editor._stroke.end()
	await call_tool("configure_autosave", {"enabled": false})
	editor._safety.tick()
	check(FileAccess.get_sha256(own_file) == draft_hash, "disabled autosave does not write")
	await call_tool("configure_autosave", {"enabled": true})
	# Accelerate only the test timer; production schema retains a 15 second minimum.
	editor._safety.timer.start(0.05)
	await create_timer(0.3).timeout
	check(FileAccess.get_sha256(own_file) != draft_hash and editor._safety.last_error.is_empty(), "timer saves completed changes without a manual command")
	editor._safety.timer.start(60)
	var other := Store.new(draft_root)
	var second: Dictionary = other.write(path, editor._doc)
	check(second.ok and second.draft_id != draft_id, "concurrent editing sessions use independent draft files")
	await call_tool("save_world")
	check(not FileAccess.file_exists(own_file) and FileAccess.file_exists(other.file_for(second.draft_id)), "successful save removes only this session's draft")
	await call_tool("undo")
	await call_tool("save_world")
	check(editor._doc._disk_signature == FileAccess.get_sha256(path), "undo after save keeps a current save-conflict baseline")
	# External edit after a checkpoint must not be overwritten by restoring it.
	var stale := Store.new(draft_root)
	var stale_draft: Dictionary = stale.write(path, editor._doc)
	var external = Doc.open_file(path)
	external.map_meta.external_revision = 2
	check(external.save(path) == OK, "simulate an external map writer")
	await call_tool("restore_editor_draft", {"draft_id": stale_draft.draft_id})
	var external_hash := FileAccess.get_sha256(path)
	await call_tool("save_world", {}, false)
	check(FileAccess.get_sha256(path) == external_hash and editor._dirty, "restored stale draft cannot overwrite a newer map")
	var copy_path := directory.path_join("recovered_copy.gltf")
	await call_tool("save_world", {"path": copy_path})
	check(FileAccess.get_sha256(path) == external_hash and FileAccess.file_exists(copy_path), "save-as recovers edits without replacing external changes")
	await call_tool("restore_editor_draft", {"draft_id": "../../outside"}, false)
	await call_tool("discard_editor_draft", {"draft_id": "../../outside"}, false)
	# Corrupt payload: reject before backing up or changing the current document.
	var broken: Dictionary = other.write(copy_path, editor._doc)
	var broken_file := FileAccess.open(other.file_for(broken.draft_id), FileAccess.READ_WRITE)
	broken_file.seek_end(); broken_file.store_string("corrupt"); broken_file.close()
	before = editor._doc.records.duplicate(true)
	await call_tool("restore_editor_draft", {"draft_id": broken.draft_id}, false)
	check(editor._doc.records == before and not editor._dirty, "corrupt draft fails without altering current document")
	check(other.write(copy_path, editor._doc).ok and other.read(broken.draft_id).ok, "saving identical content repairs a corrupt draft body")
	var invalid_state: Dictionary = editor._doc.recovery_snapshot()
	invalid_state.next = 1
	check(not Store.validate(invalid_state).is_empty(), "draft identity counter cannot collide with restored objects")
	await call_tool("discard_editor_draft", {"draft_id": broken.draft_id})
	# Native close signal must flush controls before checking dirty state.
	await call_tool("set_object_transform", {"id": id, "position": [1, 6, 2]})
	root.close_requested.emit()
	root.close_requested.emit()
	await settle()
	check(is_instance_valid(editor._safety.prompt) and editor._safety.prompt.visible and editor.get_children().filter(func(child): return child.name == "UnsavedMapDialog").size() == 1, "native window close opens one protective prompt")
	await call_tool("delete_selection", {}, false)
	Io.save_fault = func(_stage): return true
	var close_result: Dictionary = editor._safety.close_action("save")
	Io.save_fault = Callable()
	check(not close_result.ok and editor._safety.prompt.visible and editor._dirty, "failed close-save leaves editor and prompt open")
	await call_tool("close_editor", {"action": "cancel"})
	await settle()
	check(not is_instance_valid(editor._safety.prompt), "MCP can cancel pending close without losing edits")
	if DisplayServer.get_name() != "headless":
		root.size = Vector2i(1024, 720); root.content_scale_size = root.size
		await call_tool("save_world")
		editor._selection_tools.set_ids([id])
		var input: LineEdit = editor._inspector.fields.position_0.get_line_edit()
		input.grab_focus()
		input.text = "12.75"
		check(not editor._dirty, "uncommitted numeric input starts from a clean document")
		root.close_requested.emit(); await settle()
		check(editor._dirty and editor._doc.records[0].position[0] == 12.75 and is_instance_valid(editor._safety.prompt), "native close commits typed numeric input before checking dirty state")
		editor._safety.close_action("cancel"); await settle()
		editor._safety.show_recovery()
		await settle()
		var panel: AcceptDialog = editor.get_node("DraftRecoveryDialog")
		check(panel.visible and panel.find_child("DraftList", true, false).item_count >= 1, "recovery panel lists available drafts")
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(preload("res://scripts/asset/art_paths.gd").review_path("editor_recovery/recovery_panel.png"))
		var draft_list: ItemList = panel.find_child("DraftList", true, false)
		draft_list.select(0)
		panel.find_child("RestoreDraft", true, false).pressed.emit(); await settle()
		var confirmation: ConfirmationDialog = panel.get_node("DraftActionConfirm")
		confirmation.confirmed.emit(); await settle()
		check(editor.get_node_or_null("DraftRecoveryDialog") == null and editor._dirty and FileAccess.get_sha256(editor._path) == external_hash, "recovery UI restores in memory and preserves the published map")
		check(editor._safety.store.read(editor._safety.store.own_id(copy_path)).state.records[0].position[0] == 12.75, "switching maps through recovery preserves current unsaved input in its own draft")
		preload("res://scripts/world_editor/recovery_panel.gd").show_settings(editor)
		await settle()
		var settings: AcceptDialog = editor.get_node("AutosaveSettings")
		settings.find_child("AutosaveEnabled", true, false).button_pressed = false
		settings.confirmed.emit(); await settle()
		check(not editor._safety.enabled, "settings UI uses shared autosave configuration")
		root.close_requested.emit(); await settle()
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(preload("res://scripts/asset/art_paths.gd").review_path("editor_recovery/close_guard.png"))
		editor._safety.close_action("cancel"); await settle()
	# Kill only the owned headless writer during staged publication.
	var marker := directory.path_join("interrupted.ready")
	var child := OS.create_process(OS.get_executable_path(), child_args(["--interrupted-draft", path, draft_root, marker]))
	check(child > 0 and await wait_file(marker), "child draft writer reaches interrupted publication")
	if child > 0: OS.kill(child)
	await create_timer(0.2).timeout
	if FileAccess.file_exists(marker):
		var interrupted_id := FileAccess.get_file_as_string(marker)
		var recovered := Store.new(draft_root).read(interrupted_id)
		check(recovered.ok and recovered.state.records[0].position == [1.0, 2.0, 3.0], "fresh recovery reader sees the last complete draft after forced process death")
	# Real HTTP close commands run in owned child processes, preserving this test runner.
	var parent_port := port
	for action in ["save", "keep_draft", "discard"]:
		var child_path := directory.path_join("close_" + action + "/map.gltf")
		var child_doc := Doc.new()
		child_doc.add_box("block", Vector3(0, 1, 0), Vector3.ONE)
		child_doc.save(child_path)
		var original_hash := FileAccess.get_sha256(child_path)
		port = parent_port + 1
		while probe.listen(port, "127.0.0.1") != OK: port += 1
		probe.stop()
		var ready := directory.path_join(action + ".ready")
		child = OS.create_process(OS.get_executable_path(), child_args(["--close-host", child_path, draft_root, str(port), ready]))
		check(child > 0 and await wait_file(ready), "start owned close host: " + action)
		if FileAccess.file_exists(ready):
			var child_info: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ready))
			check(child_info.ok, "child map and draft ready")
			await call_tool("close_editor", {"action": action})
			var deadline := Time.get_ticks_msec() + 5000
			while OS.is_process_running(child) and Time.get_ticks_msec() < deadline: await create_timer(0.05).timeout
			check(not OS.is_process_running(child), "close command exits owned process: " + action)
			var stored := Store.new(draft_root)
			if action == "save": check(Doc.open_file(child_path).records[0].position[1] == 9 and not FileAccess.file_exists(stored.file_for(child_info.draft_id)), "save-and-close publishes map and clears its draft")
			elif action == "keep_draft": check(FileAccess.get_sha256(child_path) == original_hash and stored.read(child_info.draft_id).state.records[0].position[1] == 9, "keep-draft-and-close preserves unsaved work without touching map")
			else: check(FileAccess.get_sha256(child_path) == original_hash and not FileAccess.file_exists(stored.file_for(child_info.draft_id)), "discard-and-close removes own draft without changing map")
		if child > 0 and OS.is_process_running(child): OS.kill(child)
	port = parent_port
	editor._mcp.stop()
	editor.queue_free(); await settle()
	check(auto_accept_quit, "leaving editor restores prior application close policy")
	preload("res://scripts/net/net.gd").session().world3d_editor_doc = null
	preload("res://scripts/net/net.gd").session().world3d_editor_path = ""
	Io._remove_tree(directory)
	print("test_world3d_recovery: %s" % ("PASS" if failed == 0 else "FAIL (%d)" % failed))
	quit(0 if failed == 0 else 1)
