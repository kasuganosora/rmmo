extends Control
## In-game content pack editor (maps tree, paint, assets, zip).

const ContentPack = preload("res://scripts/editor/content_pack.gd")
const MapDocument = preload("res://scripts/editor/map_document.gd")
const PaintTools = preload("res://scripts/editor/paint_tools.gd")
const PackZip = preload("res://scripts/editor/pack_zip.gd")
const MapFieldScript = preload("res://scripts/map/map_field.gd")
const MapExt = preload("res://scripts/map/map_ext.gd")
const Net = preload("res://scripts/net/net.gd")

var pack: RefCounted
var doc: RefCounted
var current_map_id: String = ""
var paint: RefCounted
var map_field: Node2D
var _vp: SubViewport
var _cam: Camera2D
var _tree: Tree
var _status: Label
var _layer_opt: OptionButton
var _tool_opt: OptionButton
var _tile_spin: SpinBox
var _space_down: bool = false
var _panning: bool = false
var _file_dlg: FileDialog
var _file_mode: String = ""
var _cursor: Vector2i = Vector2i(2, 2)


func _ready() -> void:
	paint = PaintTools.new()
	_build_ui()
	_new_pack()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if k.ctrl_pressed and k.keycode == KEY_S:
			_save()
			get_viewport().set_input_as_handled()
		elif k.ctrl_pressed and k.keycode == KEY_Z:
			if doc:
				doc.undo()
				_refresh_dirty([Vector2i(0, 0)])
			get_viewport().set_input_as_handled()
		elif k.ctrl_pressed and k.keycode == KEY_Y:
			if doc:
				doc.redo()
				_reload_field()
			get_viewport().set_input_as_handled()
		elif k.keycode == KEY_ESCAPE:
			_leave()
			get_viewport().set_input_as_handled()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.09, 0.11, 1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 4)
	add_child(root)
	_status = Label.new()
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	root.add_child(top)
	_btn(top, "新建包", _new_pack)
	_btn(top, "保存", _save)
	_btn(top, "导出 .rmpack", func(): _file_mode = "export"; _pick_file(true))
	_btn(top, "导入 .rmpack", func(): _file_mode = "import"; _pick_file(false))
	_btn(top, "试玩", _playtest)
	_btn(top, "返回", _leave)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_status)
	var mid := HBoxContainer.new()
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(mid)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(240, 0)
	mid.add_child(left)
	_add_lbl(left, "地图树")
	_tree = Tree.new()
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.item_selected.connect(_on_tree_sel)
	left.add_child(_tree)
	var tree_btns := HBoxContainer.new()
	left.add_child(tree_btns)
	_btn(tree_btns, "子地图", _add_child_map)
	_btn(tree_btns, "删除", _del_map)
	_add_lbl(left, "素材库")
	_btn(left, "导入图块 PNG", func(): _file_mode = "tilesheet"; _pick_file(false))
	_btn(left, "导入行走图 PNG", func(): _file_mode = "charset"; _pick_file(false))
	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_child(center)
	var vpc := SubViewportContainer.new()
	vpc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vpc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vpc.stretch = true
	vpc.mouse_filter = Control.MOUSE_FILTER_STOP
	vpc.gui_input.connect(_on_canvas_input)
	center.add_child(vpc)
	_vp = SubViewport.new()
	_vp.size = Vector2i(960, 540)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.handle_input_locally = false
	vpc.add_child(_vp)
	map_field = MapFieldScript.new()
	map_field.skip_ready_rebuild = true
	map_field.edit_mode = true
	map_field.show_grid = true
	_vp.add_child(map_field)
	_cam = Camera2D.new()
	_cam.enabled = true
	_cam.position = Vector2(480, 270)
	_vp.add_child(_cam)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(220, 0)
	mid.add_child(right)
	_add_lbl(right, "图层")
	_layer_opt = OptionButton.new()
	_layer_opt.add_item("地面 z0", 0)
	_layer_opt.add_item("叠层 z1", 1)
	_layer_opt.add_item("物件 z2", 2)
	_layer_opt.add_item("上层 z3", 3)
	_layer_opt.add_item("阴影 z4", 4)
	_layer_opt.add_item("区域 z5", 5)
	var i := 6
	for id in MapExt.LAYER_IDS:
		_layer_opt.add_item("ext:" + id, 100 + i)
		i += 1
	_layer_opt.item_selected.connect(_on_layer)
	right.add_child(_layer_opt)
	_add_lbl(right, "工具")
	_tool_opt = OptionButton.new()
	_tool_opt.add_item("铅笔", PaintTools.Tool.PENCIL)
	_tool_opt.add_item("矩形", PaintTools.Tool.RECT)
	_tool_opt.add_item("填充", PaintTools.Tool.FILL)
	_tool_opt.add_item("吸管", PaintTools.Tool.EYEDROP)
	_tool_opt.add_item("橡皮", PaintTools.Tool.ERASE)
	_tool_opt.item_selected.connect(func(idx): paint.tool = _tool_opt.get_item_id(idx))
	right.add_child(_tool_opt)
	_add_lbl(right, "图块 ID")
	_tile_spin = SpinBox.new()
	_tile_spin.max_value = 8191
	_tile_spin.value = 1536
	_tile_spin.value_changed.connect(func(v): paint.tile_id = int(v))
	right.add_child(_tile_spin)
	paint.tile_id = 1536
	_add_lbl(right, "快捷")
	var presets := HBoxContainer.new()
	right.add_child(presets)
	_btn(presets, "地板1536", func(): _tile_spin.value = 1536)
	_btn(presets, "空0", func(): _tile_spin.value = 0)
	_btn(right, "此格加宝箱事件", _add_chest_event)
	_file_dlg = FileDialog.new()
	_file_dlg.access = FileDialog.ACCESS_FILESYSTEM
	_file_dlg.file_selected.connect(_on_file)
	add_child(_file_dlg)


func _btn(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _add_lbl(parent: Node, text: String) -> void:
	var l := Label.new()
	l.text = text
	parent.add_child(l)


func _new_pack() -> void:
	pack = ContentPack.new()
	var pid := "pack_%d" % int(Time.get_unix_time_from_system())
	pack.new_blank(pid, "新内容包", 24, 16)
	pack.save_dir()
	_select_map(pack.start_map)
	_status.text = "已新建 %s" % pack.root


func _save() -> void:
	if pack == null:
		return
	if pack.save_dir():
		_status.text = "已保存 %s" % pack.root
	else:
		_status.text = "保存失败"


func _leave() -> void:
	var sess = get_node_or_null("/root/GameSession")
	if sess and sess.get("editor_return"):
		sess.editor_return = false
		sess.go_world()
	elif sess:
		sess.go_character_select()
	else:
		get_tree().change_scene_to_file("res://scenes/login.tscn")


func _playtest() -> void:
	if pack == null:
		return
	pack.save_dir()
	var sess = get_node_or_null("/root/GameSession")
	if sess == null:
		_status.text = "无会话"
		return
	sess.editor_return = true
	sess.editor_pack_root = pack.root
	sess.editor_map_id = current_map_id
	var ch: Dictionary = sess.active_character() if sess.has_method("active_character") else {}
	if ch.is_empty():
		ch = {"name": "编辑器", "look_id": "1", "gender": "female", "level": 1, "class_id": "adventurer"}
	sess.spawn_data = {
		"pack_path": pack.root,
		"map_id": current_map_id,
		"cell": {"x": 2, "y": 2},
		"character": ch,
		"content_id": pack.pack_id,
	}
	sess.loading_mode = "transfer"
	sess.go_loading()


func _select_map(id: String) -> void:
	current_map_id = id
	doc = pack.get_map(id)
	_refresh_tree()
	_reload_field()


func _refresh_tree() -> void:
	_tree.clear()
	var root_item := _tree.create_item()
	root_item.set_text(0, pack.pack_name)
	root_item.set_selectable(0, false)
	var by_parent := {}
	for item in pack.map_tree:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var p := str(item.get("parent", ""))
		if not by_parent.has(p):
			by_parent[p] = []
		by_parent[p].append(item)
	_fill_tree(root_item, "", by_parent)


func _fill_tree(parent_item: TreeItem, parent_id: String, by_parent: Dictionary) -> void:
	var kids: Array = by_parent.get(parent_id, [])
	for item in kids:
		var it := _tree.create_item(parent_item)
		var mid := str(item.get("id", ""))
		it.set_text(0, "%s (%s)" % [str(item.get("name", mid)), mid])
		it.set_meta("map_id", mid)
		if mid == current_map_id:
			it.select(0)
		_fill_tree(it, mid, by_parent)


func _on_tree_sel() -> void:
	var it := _tree.get_selected()
	if it == null or not it.has_meta("map_id"):
		return
	var mid := str(it.get_meta("map_id"))
	if mid != current_map_id:
		_select_map(mid)


func _add_child_map() -> void:
	if pack == null:
		return
	var nid := "Map%03d" % (pack.maps.size() + 1)
	pack.add_map(nid, "新地图", current_map_id, 20, 15)
	_select_map(nid)


func _del_map() -> void:
	if pack == null or current_map_id == "":
		return
	if pack.maps.size() <= 1:
		_status.text = "至少留一张地图"
		return
	pack.remove_map(current_map_id)
	_select_map(pack.start_map)


func _reload_field() -> void:
	if map_field == null or pack == null or doc == null:
		return
	pack.save_dir()
	map_field.pack_path = pack.root
	map_field.edit_map_id = current_map_id
	map_field.edit_mode = true
	map_field.edit_doc = doc
	map_field.show_grid = true
	map_field.skip_ready_rebuild = true
	map_field.rebuild()
	if _cam:
		_cam.position = Vector2(float(doc.width * doc.tile_size) * 0.5, float(doc.height * doc.tile_size) * 0.5)
	_status.text = "%s · %dx%d · %s" % [doc.display_name, doc.width, doc.height, pack.root]


func _on_layer(idx: int) -> void:
	var id := _layer_opt.get_item_id(idx)
	if id < 100:
		paint.layer_z = id
		paint.ext_layer = ""
	else:
		paint.layer_z = -1
		var ext_i := id - 106
		if ext_i >= 0 and ext_i < MapExt.LAYER_IDS.size():
			paint.ext_layer = MapExt.LAYER_IDS[ext_i]


func _on_canvas_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.keycode == KEY_SPACE:
			_space_down = k.pressed
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_MIDDLE or (_space_down and mb.button_index == MOUSE_BUTTON_LEFT):
			_panning = mb.pressed
			return
		if not mb.pressed:
			if paint.tool == PaintTools.Tool.RECT and paint.rect_start.x >= 0 and doc:
				var cell := _mouse_cell(mb.position)
				var dirty: Array[Vector2i] = paint.apply_rect(doc, paint.rect_start, cell, mb.button_index == MOUSE_BUTTON_RIGHT)
				paint.rect_start = Vector2i(-1, -1)
				_refresh_dirty(dirty)
			return
		var cell2 := _mouse_cell(mb.position)
		_cursor = cell2
		if paint.tool == PaintTools.Tool.RECT:
			paint.rect_start = cell2
			return
		var erase := mb.button_index == MOUSE_BUTTON_RIGHT
		var dirty2: Array[Vector2i] = paint.apply_cell(doc, cell2, erase)
		_refresh_dirty(dirty2)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _panning and _cam:
			_cam.position -= mm.relative
			if map_field:
				map_field.set_edit_camera_cell(map_field.world_to_cell(_cam.position))
			return
		if (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0 and paint.tool == PaintTools.Tool.PENCIL:
			var dirty3: Array[Vector2i] = paint.apply_cell(doc, _mouse_cell(mm.position), false)
			_refresh_dirty(dirty3)
		elif (mm.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0 and paint.tool == PaintTools.Tool.PENCIL:
			var dirty4: Array[Vector2i] = paint.apply_cell(doc, _mouse_cell(mm.position), true)
			_refresh_dirty(dirty4)


func _mouse_cell(pos: Vector2) -> Vector2i:
	if map_field == null or _vp == null:
		return Vector2i.ZERO
	var local := pos
	var world: Vector2 = _cam.position - Vector2(_vp.size) * 0.5 + local
	return map_field.world_to_cell(world)


func _refresh_dirty(cells: Array) -> void:
	if map_field and map_field.has_method("rebuild_dirty_cells"):
		map_field.rebuild_dirty_cells(cells)


func _pick_file(save: bool) -> void:
	if save:
		_file_dlg.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		_file_dlg.filters = PackedStringArray(["*.rmpack ; Content pack"])
	else:
		_file_dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		if _file_mode == "import":
			_file_dlg.filters = PackedStringArray(["*.rmpack ; Content pack", "*.zip ; Zip"])
		else:
			_file_dlg.filters = PackedStringArray(["*.png ; PNG", "*.ogg ; OGG", "*.wav ; WAV"])
	_file_dlg.popup_centered_ratio(0.6)


func _on_file(path: String) -> void:
	match _file_mode:
		"export":
			if PackZip.export_zip(pack.root, path):
				_status.text = "已导出 %s" % path
			else:
				_status.text = "导出失败"
		"import":
			var dest := "%s/imp_%d" % [ContentPack.USER_PACKS, int(Time.get_unix_time_from_system())]
			var res: Dictionary = PackZip.import_zip(path, dest)
			if bool(res.get("ok", false)):
				pack = ContentPack.new()
				if pack.load_dir(str(res.get("root", dest))):
					_select_map(pack.start_map)
					_status.text = "已导入 %s" % pack.pack_id
				else:
					_status.text = "导入后无法加载"
			else:
				_status.text = str(res.get("error", "导入失败"))
		"tilesheet", "charset":
			_import_asset(path, _file_mode)


func _add_chest_event() -> void:
	if doc == null:
		return
	var eid := "chest_%d_%d" % [_cursor.x, _cursor.y]
	doc.events.append({
		"id": eid,
		"cell": {"x": _cursor.x, "y": _cursor.y},
		"trigger": "action",
		"through": false,
		"pages": [{
			"when": {},
			"commands": [
				{"op": "text", "text": "打开了宝箱！"},
				{"op": "give_item", "item_id": "potion_hp_small", "qty": 1},
			],
		}],
	})
	doc.dirty = true
	_status.text = "已在 %d,%d 放事件 %s" % [_cursor.x, _cursor.y, eid]


func _import_asset(src: String, kind: String) -> void:
	if pack == null:
		return
	var id := src.get_file().get_basename()
	var sub := "tilesheet" if kind == "tilesheet" else "charset"
	var dest := "%s/assets/%s/%s.png" % [pack.root, sub, id]
	var abs_dest := ProjectSettings.globalize_path(dest) if dest.begins_with("user://") else dest
	DirAccess.make_dir_recursive_absolute(abs_dest.get_base_dir())
	var bytes := FileAccess.get_file_as_bytes(src)
	var f := FileAccess.open(abs_dest, FileAccess.WRITE)
	if f == null:
		_status.text = "导入失败"
		return
	f.store_buffer(bytes)
	_status.text = "已导入 %s → %s" % [kind, id]
	# If tilesheet, drop into first empty tileset name slot.
	if kind == "tilesheet" and pack.tilesets.has("default"):
		var ts: Dictionary = pack.tilesets["default"]
		var names: Variant = ts.get("tilesetNames", [])
		if typeof(names) == TYPE_ARRAY:
			var arr: Array = names
			while arr.size() < 9:
				arr.append("")
			arr[4] = id
			ts["tilesetNames"] = arr
			pack.tilesets["default"] = ts
			pack.dirty = true
			pack.save_dir()
			_reload_field()
