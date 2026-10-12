extends SceneTree
## Headless UI regression: virtual focus, identity and precise numeric editing.
const Paths = preload("res://scripts/world3d/map_paths.gd")
var failed := 0
var selections: Array[int] = []

func _initialize() -> void: run.call_deferred()
func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok: failed += 1
func frames(count: int = 5) -> void:
	for i in count: await process_frame
func key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = code; event.pressed = pressed
		Input.parse_input_event(event)
		await frames(2)
func run() -> void:
	create_timer(60).timeout.connect(func(): print("FAIL test timeout"); quit(2))
	root.size = Vector2i(1280, 800); root.content_scale_size = root.size
	var directory := Paths.cache_directory("editor_focus_identity_%d" % Time.get_ticks_usec())
	var doc = preload("res://scripts/world3d/world_document.gd").new()
	doc.add_box("ground", Vector3(0, -0.1, 0), Vector3(20, 0.2, 20))
	var id: String = doc.add_box("block", Vector3(0, 1.5, 0), Vector3(4, 3, 0.4))
	doc._find(id).editor_name = "院墙转角测试物件"
	var session = preload("res://scripts/net/net.gd").session()
	session.world3d_editor_path = directory.path_join("map.gltf"); session.world3d_editor_doc = doc
	var editor = preload("res://scripts/world_editor/world_editor.gd").new()
	editor._mcp_autostart = false; editor._draft_directory = directory.path_join("drafts")
	root.add_child(editor)
	await frames(15)
	editor._selection_tools.set_ids([id])
	var inspector = editor._inspector
	check(inspector.title.text == "院墙转角测试物件" and not inspector.title.text.contains(id), "inspector uses friendly object name")
	check(inspector.identity_id.text == id and not inspector.identity_details.visible, "internal ID remains copyable in collapsed details")
	inspector.identity_toggle.button_pressed = true
	check(inspector.identity_details.visible, "object identity details expand without changing selection")
	var number: SpinBox = inspector.fields.rotation_1
	check(number.prefix.is_empty() and number.get_parent().get_child(0).text == "Y", "axis label remains outside long numeric values")
	var undo_count: int = doc._undo.size()
	inspector._number_text_changed("rotation", 1, number, "133.113")
	inspector._number_text_changed("rotation", 1, number, "133.114")
	check(absf(doc._find(id).rotation[1] - 133.114) < 0.000001, "precise rotation still applies immediately")
	check(doc._undo.size() == undo_count + 1, "live numeric input preserves one coalesced undo step")
	inspector.finish_number_edit(); editor._undo()
	check(absf(doc._find(id).rotation[1]) < 0.000001, "numeric edit undoes to original transform")

	# Exercise production virtual palette with enough items to cross many pages.
	editor._dock_tabs.current_tab = 0
	var palette = editor._palette
	var entries: Array = []
	for i in 500: entries.append({"label": "素材 %d" % i, "category": "测试"})
	palette.item_selected.disconnect(editor._on_palette_selected)
	palette.item_selected.connect(func(index: int): selections.append(index))
	palette.set_entries(entries, null)
	await frames(10)
	palette.grab_focus(); await frames()
	check(palette._focused_index == 0 and root.gui_get_focus_owner() == palette._active[0], "Tab entry focuses first virtual item")
	await key(KEY_END)
	check(palette._focused_index == 499 and palette._active.has(499) and root.gui_get_focus_owner() == palette._active[499], "End reaches and reveals final virtual item")
	check(palette._pool.size() < 60, "keyboard scrolling retains bounded virtualization")
	check(selections.is_empty(), "browsing does not activate a placement asset")
	await key(KEY_ENTER)
	check(selections == [499], "Enter activates exactly one item beyond first nine")
	await key(KEY_UP)
	check(palette._focused_index == 499 - palette._columns, "Up uses current responsive column count")
	await key(KEY_HOME)
	check(palette._focused_index == 0 and palette.scroll_vertical == 0, "Home returns to first row")
	await key(KEY_PAGEDOWN)
	check(palette._focused_index >= palette._columns and palette._active.has(palette._focused_index), "Page Down reveals logical focus")
	var logical_focus: int = palette._focused_index
	palette.scroll_vertical += 200
	await frames()
	check(palette._focused_index == logical_focus, "pool reuse preserves logical keyboard focus")
	check(doc._find(id).position == [0.0, 1.5, 0.0], "palette arrows never move the selected scene object")
	palette.set_entries([], null); await frames()
	palette.grab_focus(); await key(KEY_ENTER)
	check(selections == [499], "empty palette ignores activation")
	var theme = preload("res://scripts/world_editor/workspace_theme.gd").build()
	check(theme.get_stylebox("focus", "Button") is StyleBoxFlat and theme.get_stylebox("focus", "Button").border_width_left == 2, "keyboard focus has a visible border")

	# Filtering never conceals that additional scatter assets remain selected.
	editor._assets.entries = [
		{"asset_path": "D:/test/elm.glb", "label": "榆树"},
		{"asset_path": "D:/test/oak.glb", "label": "橡树"},
	]
	editor._shared_assets.clear()
	var scatter = editor._city.panel.scatter_panel
	scatter.selected_assets = ["D:/test/elm.glb", "D:/test/oak.glb"]
	scatter.search.text = "榆树"; scatter.refresh_assets()
	check(scatter.selection_summary.text.contains("已选 2 / 8") and scatter.selection_summary.text.contains("1 种不在当前列表"), "scatter summary exposes hidden selected assets")
	check(scatter.selected_chips.get_child_count() == 2, "scatter removal summary retains filtered-out selections")
	scatter.selected_chips.get_child(1).pressed.emit()
	check(scatter.selected_assets == ["D:/test/elm.glb"] and scatter.selection_summary.text.contains("已选 1 / 8"), "hidden asset can be removed without clearing other choices")
	editor.queue_free(); await frames(10)
	print("EDITOR_FOCUS_IDENTITY_FINISHED failures=", failed)
	quit(1 if failed else 0)
