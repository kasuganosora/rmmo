extends Node
const Store = preload("res://scripts/world_editor/draft_store.gd")
const Doc = preload("res://scripts/world3d/world_document.gd")
var editor: Node3D
var store
var timer: Timer
var enabled := true
var interval_seconds := 60.0
var last_saved_at := 0.0
var last_error := ""
var prompt: ConfirmationDialog
var _close_window := true
var _auto_quit_before := true
var _draft_thread: Thread
var _draft_prepared := {}
var _discard_pending := false
var _preparing := false

func setup(owner: Node3D) -> void:
	editor = owner
	store = Store.new(editor._draft_directory)
	_auto_quit_before = get_tree().auto_accept_quit
	get_tree().auto_accept_quit = false
	get_tree().root.close_requested.connect(request_exit.bind(true))
	timer = Timer.new()
	timer.wait_time = interval_seconds
	timer.timeout.connect(tick)
	add_child(timer)
	timer.start()
	call_deferred("refresh_notice")

func _exit_tree() -> void:
	if _draft_thread!=null and _draft_thread.is_started():
		_draft_thread.wait_to_finish()
		if _discard_pending: store.discard(store.own_id(_draft_prepared.map_path))
		_draft_thread=null; _draft_prepared.clear()
	if get_tree() == null: return
	if get_tree().root.close_requested.is_connected(request_exit.bind(true)): get_tree().root.close_requested.disconnect(request_exit.bind(true))
	get_tree().auto_accept_quit = _auto_quit_before

func busy() -> bool:
	if _preparing or _draft_thread!=null: return true
	if editor.saving(): return true
	if editor._terrain_brush!=null and editor._terrain_brush.pointer_down: return true
	if editor._city.busy(): return true
	if editor._playtest != null and editor._playtest.active(): return true
	if editor._authoring.picking: return true
	if editor._building_area_busy(): return true
	if editor._material_tool != null and editor._material_tool.pointer_down: return true
	return editor._transform_drag.active or editor._auto_stroke.active or editor._stroke._open or editor._selection_tools.marquee or editor._placement_tools.active or editor.get_viewport().gui_get_focus_owner() is LineEdit

func state() -> Dictionary:
	return {"enabled": enabled, "active":_preparing or _draft_thread!=null,"interval_seconds": interval_seconds, "last_saved_at": last_saved_at, "last_error": last_error, "close_pending": is_instance_valid(prompt) and prompt.visible}

func configure(on: bool, interval: float) -> Dictionary:
	if not is_finite(interval) or interval < 15 or interval > 600: return Store.fail("自动草稿间隔须为 15–600 秒")
	enabled = on
	interval_seconds = interval
	timer.stop()
	timer.wait_time = interval_seconds
	if enabled: timer.start()
	return {"ok": true, "autosave": state()}

func tick() -> void:
	if not enabled or not editor._dirty or editor._load_failed or busy() or (is_instance_valid(prompt) and prompt.visible): return
	_draft_prepared=store.snapshot(editor._path,editor._doc)
	if not _draft_prepared.ok:
		last_error=_draft_prepared.error; editor._status.text=last_error; _draft_prepared.clear(); return
	_discard_pending=false; _preparing=true; _validate_and_encode.call_deferred()

func _validate_and_encode() -> void:
	var issue: String=Store.validate_meta(_draft_prepared.state)
	var ids:={}; var slice:=Time.get_ticks_usec()
	if issue.is_empty():
		for record in _draft_prepared.state.records:
			issue=Store.validate_record(record,_draft_prepared.state,ids)
			if not issue.is_empty(): break
			if Time.get_ticks_usec()-slice>=4000:
				await get_tree().process_frame; slice=Time.get_ticks_usec()
	if issue.is_empty(): issue=Store.validate_ownership(_draft_prepared.state)
	_preparing=false
	if not issue.is_empty():
		last_error=issue; _draft_prepared.clear(); editor._status.text=last_error; return
	if _discard_pending: _draft_prepared.clear(); return
	_draft_thread=Thread.new()
	var err:=_draft_thread.start(store.encode_and_publish.bind(_draft_prepared,Store.Paths.external_root()),Thread.PRIORITY_LOW)
	if err!=OK:
		_draft_thread=null; _draft_prepared.clear(); last_error="无法启动草稿保存："+error_string(err)

func _process(_dt: float) -> void:
	if _draft_thread==null or _draft_thread.is_alive(): return
	var result: Dictionary=_draft_thread.wait_to_finish(); _draft_thread=null
	if _discard_pending: result=store.discard(store.own_id(_draft_prepared.map_path))
	_draft_prepared.clear()
	if result.ok:
		last_saved_at=float(result.get("saved_at",last_saved_at)); last_error=""; refresh_notice()
	else:
		last_error=result.error; editor._status.text=last_error

func save_draft() -> Dictionary:
	if busy(): return Store.fail("请先结束当前操作或文字输入，再保存草稿")
	if editor._load_failed: return Store.fail("读取失败的空文档不能覆盖草稿")
	var result: Dictionary = store.write(editor._path, editor._doc)
	if result.ok:
		last_saved_at = float(result.get("saved_at", last_saved_at))
		last_error = ""
		refresh_notice()
	else: last_error = str(result.error)
	return result

func saved(previous_path: String) -> void:
	if not _draft_prepared.is_empty() and Store.canonical(previous_path)==_draft_prepared.map_path: _discard_pending=true
	var result: Dictionary = store.discard(store.own_id(previous_path))
	if not result.ok: last_error = str(result.error)
	refresh_notice()

func refresh_notice() -> void:
	# The badge only needs the count, not source signatures or recovery metadata.
	var found: Dictionary = store.list_drafts(0, 0)
	if editor._recovery_button == null: return
	var count := int(found.get("total", 0))
	editor._recovery_button.visible = count > 0
	editor._recovery_button.text = "恢复草稿 (%d)" % count

func restore(id: String, discard_changes: bool = false) -> Dictionary:
	if busy(): return Store.fail("请先结束当前编辑操作")
	if editor._dirty and not discard_changes: return Store.fail("当前有未保存修改，请先保存或显式允许替换")
	var loaded: Dictionary = store.read(id)
	if not loaded.ok: return loaded
	# Keep current unsaved content recoverable even when switching to another map.
	if editor._dirty and not editor._load_failed:
		var backup := save_draft()
		if not backup.ok: return backup
	var path: String = loaded.header.map_path
	var same := Store.canonical(editor._path) == Store.canonical(path)
	if same: editor._doc.checkpoint_recovery()
	else: editor._doc = Doc.new()
	editor._doc.apply_recovery(loaded.state)
	editor._material_tool.clear_target()
	editor._path = path
	editor._load_failed = false
	editor._dirty = true
	editor._load_asset_scope()
	editor._rebuild()
	editor._selection_tools.set_ids([])
	editor._refresh_palette()
	preload("res://scripts/net/net.gd").session().world3d_editor_path = path
	var changed := FileAccess.get_sha256(path) != str(loaded.header.source_signature)
	editor._status.text = "草稿已恢复到编辑器；正式地图尚未修改" + (" · 磁盘版本已变化，请另存为" if changed else "")
	return {"ok": true, "map_path": path, "source_changed": changed, "undoable": same, "missing_assets": editor._doc.missing_assets()}

func discard(id: String) -> Dictionary:
	if not _draft_prepared.is_empty() and id==store.own_id(_draft_prepared.map_path): return Store.fail("草稿正在保存，请稍后再删除")
	var result: Dictionary = store.discard(id)
	refresh_notice()
	return result

func request_exit(close_window: bool = true) -> void:
	if editor.saving(): return
	if editor._playtest != null and editor._playtest.active(): editor._playtest.stop(); return
	if is_instance_valid(prompt): return
	editor._finish_edits()
	_close_window = close_window
	if not editor._dirty: call_deferred("_finish_exit"); return
	prompt = ConfirmationDialog.new()
	prompt.name = "UnsavedMapDialog"
	prompt.title = "地图有未保存修改"
	prompt.dialog_text = "保存后再关闭，或保留一份可恢复的草稿。" if close_window else "保存后返回登录，或保留一份可恢复的草稿。"
	prompt.ok_button_text = "保存并关闭" if close_window else "保存并返回登录"
	prompt.cancel_button_text = "继续编辑"
	prompt.dialog_hide_on_ok = false
	prompt.add_button("保留草稿并关闭" if close_window else "保留草稿并返回", true, "keep_draft")
	prompt.add_button("放弃修改并关闭" if close_window else "放弃修改并返回", true, "discard")
	prompt.confirmed.connect(close_after_save)
	prompt.custom_action.connect(close_action)
	prompt.canceled.connect(func(): close_action("cancel"))
	editor.add_child(prompt)
	prompt.popup_centered(Vector2i(570, 160))

func close_action(action: String) -> Dictionary:
	if editor.saving(): return Store.fail("正在保存，请等待保存完成后关闭")
	if action == "cancel":
		if is_instance_valid(prompt): prompt.queue_free(); prompt = null
		return {"ok": true, "closing": false}
	if action not in ["save", "keep_draft", "discard"]: return Store.fail("关闭操作无效")
	editor._finish_edits()
	var result := {"ok": true}
	if action == "save" and not editor._save(): result = Store.fail(editor._status.text)
	elif action == "keep_draft": result = save_draft()
	elif action == "discard": result = discard(store.own_id(editor._path))
	if not result.ok:
		if is_instance_valid(prompt): prompt.dialog_text = str(result.error) + "\n当前地图仍保持打开。"
		return result
	if is_instance_valid(prompt): prompt.queue_free(); prompt = null
	call_deferred("_finish_exit")
	return {"ok": true, "closing": true}

func close_after_save() -> void:
	if editor.saving(): return
	if is_instance_valid(prompt): prompt.hide()
	if await editor._save_async():
		if is_instance_valid(prompt): prompt.queue_free(); prompt = null
		call_deferred("_finish_exit")
	elif is_instance_valid(prompt):
		prompt.dialog_text = editor._status.text + "\n当前地图仍保持打开。"
		prompt.popup_centered()

func _finish_exit() -> void:
	preload("res://scripts/net/net.gd").session().world3d_editor_doc = null
	if _close_window: get_tree().quit()
	else: editor._exit_editor()

func show_recovery() -> void:
	editor._finish_edits()
	if editor.get_node_or_null("DraftRecoveryDialog") != null: return
	preload("res://scripts/world_editor/recovery_panel.gd").show_panel(editor)
