extends VBoxContainer
const Thumbnails = preload("res://scripts/world_editor/material_thumbnails.gd")
const UI = preload("res://scripts/world_editor/placement_panel.gd")
var editor: Node3D
var picker: ItemList
var search: LineEdit
var result_label: Label
var current_label: Label
signal catalog_changed
var _catalog_thread: Thread
var _catalog_repeat := false
var _catalog_chosen := ""
var _catalog_root := ""
var _entries: Array = []
var _loader: Node
var _filtered: Array = []
var _by_id := {}
var _indices := {}
var _visible_indices := {}
var _visible_dirty := true
var _placeholder: Texture2D
var category_picker: OptionButton
var preview: TextureRect
var mapping: OptionButton
var fields := {}
var target: Label
var _mode_buttons := {}
var _apply_button: Button
var _reset_button: Button
var _custom_button: Button
var _drawer: PanelContainer

func setup(owner: Node3D) -> void:
	editor = owner
	_catalog_root = preload("res://scripts/world3d/map_paths.gd").external_root()
	_placeholder = ImageTexture.create_from_image(Thumbnails.decode("", {"color": [0.16, 0.17, 0.19, 1.0]}))
	_loader = Thumbnails.new(); _loader.placeholder = _placeholder; add_child(_loader)
	_loader.available.connect(_thumbnail_ready)
	name = "材质"
	add_theme_constant_override("separation", 8)
	var heading := Label.new()
	heading.text = "表面材质笔刷"
	add_child(heading)
	category_picker = OptionButton.new(); category_picker.name = "SurfaceCategory"
	category_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(category_picker)
	category_picker.item_selected.connect(func(_index): _refresh_materials())
	search = LineEdit.new(); search.name = "SurfaceSearch"
	search.placeholder_text = "搜索材质名称、分类…"
	search.clear_button_enabled = true
	add_child(search)
	search.text_changed.connect(func(_text): _refresh_materials())
	result_label = Label.new(); result_label.name = "SurfaceResults"
	result_label.add_theme_font_size_override("font_size", 12)
	var results := HBoxContainer.new(); add_child(results)
	result_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	results.add_child(result_label)
	UI.button(results, "重置筛选", func():
		search.text = ""
		category_picker.select(0)
		_refresh_materials()
	, "ResetSurfaceFilter")
	picker = ItemList.new(); picker.name = "SurfaceMaterial"
	picker.custom_minimum_size = Vector2(260, 220)
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.max_columns = 2; picker.fixed_column_width = 126
	picker.icon_mode = ItemList.ICON_MODE_TOP
	picker.fixed_icon_size = Vector2i(104, 64)
	picker.max_text_lines = 2
	picker.add_theme_font_size_override("font_size", 13)
	add_child(picker)
	picker.item_selected.connect(func(_index): _choose())
	picker.resized.connect(func(): _visible_dirty = true)
	picker.get_v_scroll_bar().value_changed.connect(func(_value): _visible_dirty = true)
	var current := HBoxContainer.new(); add_child(current)
	preview = TextureRect.new()
	preview.custom_minimum_size = Vector2(64, 64)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	current.add_child(preview)
	current_label = Label.new(); current_label.name = "CurrentSurfaceMaterial"
	current_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	current_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	current.add_child(current_label)
	_custom_button = UI.button(self, "自定义…", func(): _set_drawer(not _drawer.visible), "CustomizeSurfaceMaterial")
	_custom_button.toggle_mode = true
	var actions := HBoxContainer.new(); add_child(actions)
	for spec in [["paint", "开始刷面", "BeginSurfacePaint"], ["pick", "选面", "PickPaintFace"], ["restore", "擦除材质", "BeginSurfaceRestore"]]:
		var mode: String = spec[0]
		var button := UI.button(actions, spec[1], func(): _begin(mode), spec[2])
		button.toggle_mode = true
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_mode_buttons[mode] = button
	target = Label.new(); target.name = "PaintTarget"; target.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; target.custom_minimum_size = Vector2(260, 24); target.text = "可直接刷面；指定应用时先用「选面」。"
	add_child(target)
	_apply_button = UI.button(self, "应用到所选面", _apply, "ApplySurfacePaint")
	_apply_button.tooltip_text = "先用「选面」点选场景中的表面，再应用当前材质"
	var layer := CanvasLayer.new(); layer.layer = 20; add_child(layer)
	_drawer = preload("res://scripts/world_editor/surface_material_drawer.gd").new()
	layer.add_child(_drawer)
	_drawer.setup()
	_drawer.close_requested.connect(func(): _set_drawer(false))
	_drawer.restore_requested.connect(func():
		var selected: Dictionary = editor._material_tool.selected
		if selected.get("ok", false): editor._material_tool.report(editor._material_tool.clear_paint(selected.id))
	)
	_drawer.defaults_restored.connect(_sync)
	mapping = _drawer.mapping
	fields = _drawer.fields
	_reset_button = _drawer.restore_button
	UI.button(self, "导入新贴图…", _import, "ImportSurfaceTexture")
	var note := Label.new(); note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; note.custom_minimum_size.x = 260
	note.text = "选材质 → 开始刷面 → 在场景中涂刷。\n按住左键连续刷面；Esc 退出，Ctrl+Z 撤销。\n也可先选面，再应用。自动瓦片刷后冻结造型。"
	add_child(note)
	editor._material_tool.target_changed.connect(func():
		var selected: Dictionary = editor._material_tool.selected
		target.text = "%s · 面 %d / 槽 %d" % [selected.id, selected.target.face, selected.target.surface] if selected.get("ok", false) else "可直接刷面；指定应用时先用「选面」。"
	)
	visibility_changed.connect(func():
		_visible_dirty = true
		if not is_visible_in_tree():
			_loader.request([])
			if _drawer.visible: _set_drawer(false)
	)
	current_label.text = "正在加载材质库…"
	refresh()

func refresh(chosen: String = "") -> void:
	_catalog_chosen = chosen
	if _catalog_thread != null:
		_catalog_repeat = true
		return
	result_label.text = "正在更新材质库…"
	_catalog_thread = Thread.new()
	var library = editor._material_tool.library
	var error := _catalog_thread.start(_load_catalog.bind(library.directory, library.include_shared, _catalog_root))
	if error != OK:
		_catalog_thread = null
		result_label.text = "材质库加载失败，请重新打开编辑器"
	set_process(true)

static func _load_catalog(folder: String, shared: bool, content_root: String) -> Array:
	# Explicit root keeps the shared library reader independent of SceneTree/autoloads.
	var library = preload("res://scripts/world_editor/surface_material_library.gd").new(folder)
	library.include_shared = shared
	var entries: Array = library.entries(content_root)
	for entry in entries:
		Thumbnails.prepare(entry, content_root)
		entry["search_text"] = (str(entry.material.name) + " " + str(entry.get("category", "内置")) + " " + str(entry.material_id)).to_lower()
	return entries

func _apply_catalog(chosen: String) -> void:
	_by_id.clear()
	for entry in _entries: _by_id[entry.material_id] = entry
	var selected_category := str(category_picker.get_item_metadata(category_picker.selected)) if category_picker.selected >= 0 else ""
	category_picker.clear(); category_picker.add_item("全部分类"); category_picker.set_item_metadata(0, "")
	var categories: Array = []
	for entry in _entries:
		var category := str(entry.get("category", "内置"))
		if not categories.has(category): categories.append(category)
	categories.sort()
	for category in categories:
		var index := category_picker.item_count
		category_picker.add_item(category); category_picker.set_item_metadata(index, category)
		if category == selected_category: category_picker.select(index)
	if not chosen.is_empty():
		category_picker.select(0)
		search.text = ""
		editor._material_tool.material_id = chosen
	_refresh_materials()
	if not chosen.is_empty(): picker.call_deferred("ensure_current_is_visible")
	_show_current()
	catalog_changed.emit()

func _refresh_materials(_chosen: String = "") -> void:
	# Browsing must never silently replace the brush's current material.
	var id := str(editor._material_tool.material_id)
	picker.clear(); _filtered.clear(); _indices.clear(); _visible_indices.clear()
	_loader.request([])
	var category := str(category_picker.get_item_metadata(category_picker.selected)) if category_picker.selected >= 0 else ""
	var query := search.text.strip_edges().to_lower()
	for entry in _entries:
		var entry_category := str(entry.get("category", "内置"))
		if not category.is_empty() and category != entry_category: continue
		if not query.is_empty() and not str(entry.search_text).contains(query): continue
		var index := picker.item_count
		_filtered.append(entry); _indices[entry.material_id] = index
		picker.add_item(str(entry.material.name), _placeholder)
		picker.set_item_metadata(index, entry.material_id)
		picker.set_item_tooltip(index, "%s\n%s · %s\n单击选择材质，再点「开始刷面」" % [entry.material.name, entry_category, entry.get("origin", "内置")])
		if entry.material_id == id: picker.select(index)

	result_label.text = "没有匹配的材质" if picker.item_count == 0 else "%d 种材质 · 单击选择" % picker.item_count
	result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_label.custom_minimum_size.x = 170
	_visible_dirty = true
	set_process(true)

func _process(_delta: float) -> void:
	if _catalog_thread != null and not _catalog_thread.is_alive():
		var result: Array = _catalog_thread.wait_to_finish()
		_catalog_thread = null
		if _catalog_repeat:
			_catalog_repeat = false
			refresh(_catalog_chosen)
		else:
			_entries = result
			_apply_catalog(_catalog_chosen)
	if not is_visible_in_tree(): return
	if _drawer.visible: _position_drawer()
	for mode in _mode_buttons:
		var active: bool = editor._material_tool.active and editor._material_tool.action == mode
		_mode_buttons[mode].set_pressed_no_signal(active)
		if mode == "paint": _mode_buttons[mode].text = "结束刷面" if active else "开始刷面"
	var has_target: bool = editor._material_tool.selected.get("ok", false)
	_apply_button.disabled = not has_target
	_reset_button.disabled = not has_target
	if _visible_dirty:
		_visible_dirty = false
		_update_visible_thumbnails()

func _update_visible_thumbnails() -> void:
	var visible_now := {}
	var wanted: Array = []
	var current := str(editor._material_tool.material_id)
	if _by_id.has(current): wanted.append(_by_id[current])
	if picker.item_count > 0:
		# Native hit testing accounts for list scrolling, wrapping and item text height.
		var first := maxi(0, picker.get_item_at_position(Vector2(4, 4), false) - 2)
		var last := mini(picker.item_count - 1, picker.get_item_at_position(Vector2(picker.size.x - 24, picker.size.y - 4), false) + 2)
		for index in range(first, last + 1):
			visible_now[index] = true
			wanted.append(_filtered[index])
			picker.set_item_icon(index, _loader.lookup(_filtered[index]))
	for index in _visible_indices:
		if not visible_now.has(index): picker.set_item_icon(index, _placeholder)
	_visible_indices = visible_now
	_loader.request(wanted)

func _thumbnail_ready(id: String, texture: Texture2D) -> void:
	if _indices.has(id) and _visible_indices.has(_indices[id]): picker.set_item_icon(_indices[id], texture)
	if str(editor._material_tool.material_id) == id: preview.texture = texture

func _choose() -> void:
	var selected := picker.get_selected_items()
	if selected.is_empty(): return
	editor._material_tool.material_id = picker.get_item_metadata(selected[0])
	_show_current()

func _show_current() -> void:
	var id := str(editor._material_tool.material_id)
	for entry in _entries:
		if entry.material_id != id: continue
		preview.texture = _loader.lookup(entry)
		_visible_dirty = true
		current_label.text = "当前材质\n%s" % entry.material.name
		_drawer.set_material_name(str(entry.material.name))
		current_label.tooltip_text = str(entry.material.name) + "\n" + str(entry.get("category", "内置"))
		return
	preview.texture = null
	current_label.text = "当前材质不可用，请重新选择"

func _position_drawer() -> void:
	var viewport_size := get_viewport_rect().size
	var dock_rect: Rect2 = editor._dock_tabs.get_global_rect()
	_drawer.position = Vector2(minf(dock_rect.end.x + 6, viewport_size.x - 332), dock_rect.position.y)
	_drawer.size = Vector2(320, maxf(200, viewport_size.y - dock_rect.position.y - 32))

func _set_drawer(open: bool) -> void:
	if not open: _sync()
	_drawer.visible = open
	_custom_button.set_pressed_no_signal(open)
	_custom_button.text = "收起自定义" if open else "自定义…"
	if open:
		_position_drawer()
		mapping.grab_focus()
	elif is_visible_in_tree():
		_custom_button.grab_focus()

func drawer_input(event: InputEvent) -> bool:
	if _drawer == null or not _drawer.visible: return false
	if event is InputEventKey:
		if event.pressed and event.keycode == KEY_ESCAPE:
			_set_drawer(false)
			get_viewport().set_input_as_handled()
			return true
		var focus := get_viewport().gui_get_focus_owner()
		return focus != null and _drawer.is_ancestor_of(focus)
	return event is InputEventMouse and _drawer.get_global_rect().has_point(event.position)

func _begin(mode: String) -> void:
	if editor._material_tool.active and editor._material_tool.action == mode:
		editor._material_tool.cancel()
	else:
		_sync()
		editor._material_tool.begin(mode)

func _sync() -> void:
	editor._material_tool.options = _drawer.options()

func _apply() -> void:
	_sync()
	editor._material_tool.cancel()
	var selected: Dictionary = editor._material_tool.selected
	if not selected.get("ok", false): editor._status.text = "请先点选表面"; return
	editor._material_tool.report(editor._material_tool.paint(selected.id, selected.target, editor._material_tool.material_id, editor._material_tool.options))

func _import() -> void:
	editor._finish_edits()
	var dialog := FileDialog.new()
	dialog.title = "导入表面贴图"
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.current_dir = preload("res://scripts/world3d/map_paths.gd").external_root()
	dialog.filters = PackedStringArray(["*.png,*.jpg,*.jpeg,*.webp ; 表面贴图"])
	dialog.file_selected.connect(func(path):
		var result: Dictionary = editor._material_tool.library.import_texture(path)
		if result.ok: refresh(result.material_id)
		editor._status.text = "贴图已复制到材质库" if result.ok else str(result.error)
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	editor.add_child(dialog); dialog.popup_centered(Vector2i(860, 560))

func _exit_tree() -> void:
	if _catalog_thread != null:
		_catalog_thread.wait_to_finish()
		_catalog_thread = null
