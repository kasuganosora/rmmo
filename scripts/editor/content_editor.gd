extends Control
## In-game content pack editor (maps tree, paint, assets, zip).

const ContentPack = preload("res://scripts/editor/content_pack.gd")
const MapDocument = preload("res://scripts/editor/map_document.gd")
const PaintTools = preload("res://scripts/editor/paint_tools.gd")
const PackZip = preload("res://scripts/editor/pack_zip.gd")
const MapFieldScript = preload("res://scripts/map/map_field.gd")
const MapExt = preload("res://scripts/map/map_ext.gd")
const TilePalette = preload("res://scripts/editor/tile_palette.gd")
const Rtp = preload("res://scripts/editor/rtp.gd")
const Net = preload("res://scripts/net/net.gd")
const MapTreeScript = preload("res://scripts/editor/map_tree.gd")
const EntityInspector = preload("res://scripts/editor/entity_inspector.gd")
const ResourceManager = preload("res://scripts/editor/resource_manager.gd")

var pack: RefCounted
var doc: RefCounted
var current_map_id: String = ""
var paint: RefCounted
var map_field: Node2D
var _vp: SubViewport
var _vpc: SubViewportContainer
var _cam: Camera2D
var _tree: Tree
var _status: Label
var _layer_opt: OptionButton
var _tool_opt: OptionButton
var _palette
var _space_down: bool = false
var _panning: bool = false
var _file_dlg: FileDialog
var _file_mode: String = ""
var _cursor: Vector2i = Vector2i(2, 2)
var _map_ctx: PopupMenu
var _set_dlg: ConfirmationDialog
var _set_name: LineEdit
var _set_w: SpinBox
var _set_h: SpinBox
var _set_ts: OptionButton
var _set_start: CheckBox
var _del_dlg: ConfirmationDialog
var _ctx_map_id: String = ""
var _hscroll: HScrollBar
var _vscroll: VScrollBar
var _zoom_lbl: Label
var _mode_map_btn: Button
var _mode_evt_btn: Button
var _pass_btn: Button
var _start_btn: Button
var _tool_btns: Dictionary = {}
var _mode: int = 0 ## 0 map, 1 event
var _placing_start: bool = false
var _zoom: float = 1.0
var _syncing_scroll: bool = false
var _saved_scale_mode: int = 1
var _saved_scale_aspect: int = 1
var _saved_scale_size: Vector2i = Vector2i(1280, 720)
var _scale_grabbed: bool = false
var _cam_ready: bool = false
var _rename_dlg: ConfirmationDialog
var _rename_edit: LineEdit
var _unsaved_dlg: ConfirmationDialog
var _pending_switch: String = ""
var _open_dlg: AcceptDialog
var _open_list: ItemList
var _saveas_dlg: ConfirmationDialog
var _saveas_edit: LineEdit
var _asset_list: ItemList
var _slot_opt: OptionButton
var _inspector
var _asset_win: Window
var _entity_win: Window

enum {
	MENU_FILE_NEW = 10,
	MENU_FILE_OPEN = 15,
	MENU_FILE_SAVE = 11,
	MENU_FILE_SAVE_AS = 16,
	MENU_FILE_OPEN_DEMO = 17,
	MENU_FILE_IMPORT = 12,
	MENU_FILE_EXPORT = 13,
	MENU_FILE_LEAVE = 14,
	MENU_EDIT_UNDO = 20,
	MENU_EDIT_REDO = 21,
	MENU_MAP_ADD = 30,
	MENU_MAP_DEL = 31,
	MENU_MAP_CHEST = 32,
	MENU_MAP_SETTINGS = 33,
	CTX_SETTINGS = 60,
	CTX_ADD = 61,
	CTX_START = 62,
	CTX_DEL = 63,
	CTX_RENAME = 64,
	CTX_DUP = 65,
	MENU_ASSET_TILE = 40,
	MENU_ASSET_CHAR = 41,
	MENU_ASSET_AUDIO = 42,
	MENU_ASSET_LIB = 43,
	MENU_ENTITY = 36,
	CTX_REPARENT = 66,
	MENU_GAME_PLAY = 50,
}


func _ready() -> void:
	_grab_window_scale()
	paint = PaintTools.new()
	paint.tile_id = 2816
	_build_ui()
	Rtp.ensure_runtime_assets()
	_open_or_create_default()
	call_deferred("_fit_layout")


func _exit_tree() -> void:
	_restore_window_scale()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		if k.ctrl_pressed and k.keycode == KEY_S:
			_save()
			_mark_handled()
		elif k.ctrl_pressed and k.keycode == KEY_Z:
			_undo_edit()
			_mark_handled()
		elif k.ctrl_pressed and k.keycode == KEY_Y:
			_redo_edit()
			_mark_handled()
		elif k.ctrl_pressed and k.keycode == KEY_D:
			_dup_map(current_map_id)
			_mark_handled()
		elif k.keycode == KEY_ESCAPE:
			_mark_handled()
			_leave()
		elif k.keycode == KEY_F2:
			_open_rename(current_map_id)
			_mark_handled()
		elif k.keycode == KEY_G:
			if map_field:
				map_field.show_grid = not map_field.show_grid
			_mark_handled()
		elif k.keycode == KEY_1:
			_set_tool(PaintTools.Tool.PENCIL)
			_mark_handled()
		elif k.keycode == KEY_2:
			_set_tool(PaintTools.Tool.RECT)
			_mark_handled()
		elif k.keycode == KEY_3:
			_set_tool(PaintTools.Tool.FILL)
			_mark_handled()
		elif k.keycode == KEY_4:
			_set_tool(PaintTools.Tool.EYEDROP)
			_mark_handled()
		elif k.keycode == KEY_5:
			_set_tool(PaintTools.Tool.ERASE)
			_mark_handled()
		elif k.keycode == KEY_EQUAL or k.keycode == KEY_KP_ADD:
			_set_zoom(_zoom * 1.25)
			_mark_handled()
		elif k.keycode == KEY_MINUS or k.keycode == KEY_KP_SUBTRACT:
			_set_zoom(_zoom / 1.25)
			_mark_handled()
		elif not k.ctrl_pressed and _cam != null:
			var step := float(doc.tile_size if doc else 48) * 4.0 / maxf(_zoom, 0.05)
			var delta := Vector2.ZERO
			if k.keycode == KEY_A or k.keycode == KEY_LEFT:
				delta.x = -step
			elif k.keycode == KEY_D or k.keycode == KEY_RIGHT:
				delta.x = step
			elif k.keycode == KEY_W or k.keycode == KEY_UP:
				delta.y = -step
			elif k.keycode == KEY_S or k.keycode == KEY_DOWN:
				delta.y = step
			if delta != Vector2.ZERO:
				_cam.position += delta
				_clamp_camera()
				_sync_scrollbars()
				_update_edit_observer()
				_mark_handled()


func _mark_handled() -> void:
	var vp := get_viewport()
	if vp:
		vp.set_input_as_handled()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.09, 0.11, 1)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)
	var menu_wrap := PanelContainer.new()
	var ms := StyleBoxFlat.new()
	ms.bg_color = Color(0.12, 0.13, 0.16, 1)
	ms.content_margin_left = 6
	ms.content_margin_right = 8
	ms.content_margin_top = 0
	ms.content_margin_bottom = 0
	menu_wrap.add_theme_stylebox_override("panel", ms)
	menu_wrap.add_child(_build_menu_bar())
	root.add_child(menu_wrap)
	root.add_child(_build_toolbar())
	var mid := HBoxContainer.new()
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 4)
	root.add_child(mid)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(220, 0)
	mid.add_child(left)
	var tree_head := HBoxContainer.new()
	left.add_child(tree_head)
	_add_lbl(tree_head, "地图")
	tree_head.add_spacer(false)
	_btn(tree_head, "+", _add_child_map)
	_btn(tree_head, "-", _del_map)
	_tree = MapTreeScript.new()
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.hide_root = false
	_tree.allow_rmb_select = true
	_tree.drop_mode_flags = Tree.DROP_MODE_ON_ITEM
	_tree.item_selected.connect(_on_tree_sel)
	_tree.item_mouse_selected.connect(_on_tree_mouse)
	_tree.reparent_requested.connect(_on_reparent)
	left.add_child(_tree)
	_map_ctx = PopupMenu.new()
	_map_ctx.add_item("地图设置…", CTX_SETTINGS)
	_map_ctx.add_item("重命名", CTX_RENAME)
	_map_ctx.add_item("新建子地图", CTX_ADD)
	_map_ctx.add_item("复制地图", CTX_DUP)
	_map_ctx.add_item("移到当前地图下", CTX_REPARENT)
	_map_ctx.add_separator()
	_map_ctx.add_item("设为起始地图", CTX_START)
	_map_ctx.add_separator()
	_map_ctx.add_item("删除", CTX_DEL)
	_map_ctx.id_pressed.connect(_on_map_ctx)
	add_child(_map_ctx)
	_build_map_settings_dialog()
	_del_dlg = ConfirmationDialog.new()
	_del_dlg.title = "删除地图"
	_del_dlg.ok_button_text = "删除"
	_del_dlg.cancel_button_text = "取消"
	_del_dlg.confirmed.connect(_confirm_del_map)
	add_child(_del_dlg)
	_rename_dlg = ConfirmationDialog.new()
	_rename_dlg.title = "重命名地图"
	_rename_dlg.ok_button_text = "确定"
	_rename_dlg.confirmed.connect(_apply_rename)
	_rename_edit = LineEdit.new()
	_rename_dlg.add_child(_rename_edit)
	add_child(_rename_dlg)
	_unsaved_dlg = ConfirmationDialog.new()
	_unsaved_dlg.title = "未保存的修改"
	_unsaved_dlg.dialog_text = "当前地图已修改。保存后切换？"
	_unsaved_dlg.ok_button_text = "保存并切换"
	_unsaved_dlg.cancel_button_text = "取消"
	_unsaved_dlg.confirmed.connect(_confirm_switch_save)
	_unsaved_dlg.add_button("放弃修改", true, "discard")
	_unsaved_dlg.custom_action.connect(_unsaved_action)
	add_child(_unsaved_dlg)
	_open_dlg = AcceptDialog.new()
	_open_dlg.title = "打开内容包"
	_open_dlg.ok_button_text = "打开"
	_open_list = ItemList.new()
	_open_list.custom_minimum_size = Vector2(360, 240)
	_open_dlg.add_child(_open_list)
	_open_dlg.confirmed.connect(_confirm_open_pack)
	add_child(_open_dlg)
	_saveas_dlg = ConfirmationDialog.new()
	_saveas_dlg.title = "另存为"
	_saveas_edit = LineEdit.new()
	_saveas_edit.placeholder_text = "新包 id"
	_saveas_dlg.add_child(_saveas_edit)
	_saveas_dlg.confirmed.connect(_confirm_save_as)
	add_child(_saveas_dlg)
	_build_asset_window()
	_build_entity_window()
	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_child(center)
	var canvas_row := HBoxContainer.new()
	canvas_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	canvas_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas_row.add_theme_constant_override("separation", 0)
	center.add_child(canvas_row)
	_vpc = SubViewportContainer.new()
	_vpc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_vpc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vpc.stretch = false
	_vpc.mouse_filter = Control.MOUSE_FILTER_STOP
	_vpc.gui_input.connect(_on_canvas_input)
	_vpc.resized.connect(_sync_vp_size)
	canvas_row.add_child(_vpc)
	_vp = SubViewport.new()
	_vp.size = Vector2i(64, 64)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_vp.handle_input_locally = false
	_vpc.add_child(_vp)
	_vscroll = VScrollBar.new()
	_vscroll.custom_minimum_size = Vector2(14, 0)
	_vscroll.value_changed.connect(_on_vscroll)
	canvas_row.add_child(_vscroll)
	_hscroll = HScrollBar.new()
	_hscroll.custom_minimum_size = Vector2(0, 14)
	_hscroll.value_changed.connect(_on_hscroll)
	center.add_child(_hscroll)
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
	right.custom_minimum_size = Vector2(400, 0)
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
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
	_tool_opt.item_selected.connect(func(idx): _set_tool(_tool_opt.get_item_id(idx)))
	right.add_child(_tool_opt)
	_palette = TilePalette.new()
	_palette.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_palette.tile_selected.connect(_on_palette_tile)
	_palette.tileset_changed.connect(_on_palette_tileset)
	_palette.flags_changed.connect(_on_flags_changed)
	right.add_child(_palette)
	var status_wrap := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.09, 1)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	status_wrap.add_theme_stylebox_override("panel", sb)
	root.add_child(status_wrap)
	_status = Label.new()
	_status.text = "就绪"
	status_wrap.add_child(_status)
	_file_dlg = FileDialog.new()
	_file_dlg.access = FileDialog.ACCESS_FILESYSTEM
	_file_dlg.file_selected.connect(_on_file)
	add_child(_file_dlg)


func _build_menu_bar() -> MenuBar:
	var bar := MenuBar.new()
	bar.flat = true
	bar.switch_on_hover = true
	_add_popup(bar, "文件", [
		["新建内容包", MENU_FILE_NEW],
		["打开包…", MENU_FILE_OPEN],
		["保存\tCtrl+S", MENU_FILE_SAVE],
		["另存为…", MENU_FILE_SAVE_AS],
		["打开工程 demo_map（副本）", MENU_FILE_OPEN_DEMO],
		[],
		["导入 .rmpack…", MENU_FILE_IMPORT],
		["导出 .rmpack…", MENU_FILE_EXPORT],
		[],
		["返回", MENU_FILE_LEAVE],
	])
	_add_popup(bar, "编辑", [
		["撤销\tCtrl+Z", MENU_EDIT_UNDO],
		["重做\tCtrl+Y", MENU_EDIT_REDO],
	])
	_add_popup(bar, "地图", [
		["地图设置…", MENU_MAP_SETTINGS],
		["重命名\tF2", 34],
		["新建子地图", MENU_MAP_ADD],
		["复制地图\tCtrl+D", 35],
		["删除当前地图", MENU_MAP_DEL],
		[],
		["实体编辑…", MENU_ENTITY],
		["在此格放置宝箱事件", MENU_MAP_CHEST],
	])
	_add_popup(bar, "素材", [
		["素材库…", MENU_ASSET_LIB],
		[],
		["导入图块 PNG…", MENU_ASSET_TILE],
		["导入行走图 PNG…", MENU_ASSET_CHAR],
		["导入音频…", MENU_ASSET_AUDIO],
	])
	_add_popup(bar, "游戏", [
		["试玩", MENU_GAME_PLAY],
	])
	return bar


func _build_toolbar() -> Control:
	var wrap := PanelContainer.new()
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.10, 0.11, 0.14, 1)
	st.content_margin_left = 8
	st.content_margin_right = 8
	st.content_margin_top = 4
	st.content_margin_bottom = 4
	wrap.add_theme_stylebox_override("panel", st)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	wrap.add_child(row)
	_mode_map_btn = _tb_toggle(row, "地图", true, func(): _set_mode(0))
	_mode_evt_btn = _tb_toggle(row, "事件", false, func(): _set_mode(1))
	_pass_btn = _tb_toggle(row, "通行", false, func(): _set_mode(2))
	row.add_child(_vsep())
	_tool_btns.clear()
	_tool_btns[PaintTools.Tool.PENCIL] = _tb_toggle(row, "铅笔", true, func(): _set_tool(PaintTools.Tool.PENCIL))
	_tool_btns[PaintTools.Tool.RECT] = _tb_toggle(row, "矩形", false, func(): _set_tool(PaintTools.Tool.RECT))
	_tool_btns[PaintTools.Tool.FILL] = _tb_toggle(row, "填充", false, func(): _set_tool(PaintTools.Tool.FILL))
	_tool_btns[PaintTools.Tool.EYEDROP] = _tb_toggle(row, "吸管", false, func(): _set_tool(PaintTools.Tool.EYEDROP))
	_tool_btns[PaintTools.Tool.ERASE] = _tb_toggle(row, "橡皮", false, func(): _set_tool(PaintTools.Tool.ERASE))
	row.add_child(_vsep())
	_start_btn = _tb_toggle(row, "起始点", false, _toggle_start_tool)
	row.add_child(_vsep())
	_tb_btn(row, "−", func(): _set_zoom(_zoom / 1.25))
	_zoom_lbl = Label.new()
	_zoom_lbl.text = "100%"
	_zoom_lbl.custom_minimum_size = Vector2(48, 0)
	_zoom_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(_zoom_lbl)
	_tb_btn(row, "+", func(): _set_zoom(_zoom * 1.25))
	_tb_btn(row, "适应", _zoom_fit)
	return wrap


func _vsep() -> Control:
	var s := VSeparator.new()
	return s


func _tb_btn(parent: Node, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _tb_toggle(parent: Node, text: String, on: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_pressed = on
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _add_popup(bar: MenuBar, title: String, items: Array) -> void:
	var pm := PopupMenu.new()
	pm.name = title
	for it in items:
		if typeof(it) != TYPE_ARRAY or (it as Array).is_empty():
			pm.add_separator()
			continue
		var row: Array = it
		pm.add_item(str(row[0]), int(row[1]))
	pm.id_pressed.connect(_on_menu)
	bar.add_child(pm)


func _on_menu(id: int) -> void:
	match id:
		MENU_FILE_NEW:
			_new_pack()
		MENU_FILE_OPEN:
			_open_pack_dialog()
		MENU_FILE_SAVE:
			_save()
		MENU_FILE_SAVE_AS:
			_saveas_edit.text = pack.pack_id if pack else "pack"
			_saveas_dlg.popup_centered()
		MENU_FILE_OPEN_DEMO:
			_open_demo_copy()
		MENU_FILE_IMPORT:
			_file_mode = "import"
			_pick_file(false)
		MENU_FILE_EXPORT:
			_file_mode = "export"
			_pick_file(true)
		MENU_FILE_LEAVE:
			_leave()
		MENU_EDIT_UNDO:
			if doc:
				doc.undo()
				_reload_field()
		MENU_EDIT_REDO:
			if doc:
				doc.redo()
				_reload_field()
		MENU_MAP_SETTINGS:
			_open_map_settings(current_map_id)
		34:
			_open_rename(current_map_id)
		MENU_MAP_ADD:
			_add_child_map()
		35:
			_dup_map(current_map_id)
		MENU_MAP_DEL:
			_ask_del_map(current_map_id)
		MENU_MAP_CHEST:
			_add_chest_event()
		MENU_ENTITY:
			_open_entity_win()
		MENU_ASSET_LIB:
			_open_asset_win()
		MENU_ASSET_TILE:
			_file_mode = "tilesheet"
			_pick_file(false)
		MENU_ASSET_CHAR:
			_file_mode = "charset"
			_pick_file(false)
		MENU_ASSET_AUDIO:
			_file_mode = "audio"
			_pick_file(false)
		MENU_GAME_PLAY:
			_playtest()


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


func _open_or_create_default() -> void:
	var path := ContentPack.pack_dir_for(Rtp.DEFAULT_PACK_ID)
	pack = ContentPack.new()
	if pack.load_dir(path):
		if pack.dirty:
			pack.save_dir()
		_select_map(pack.start_map)
		_status.text = "已打开默认包 · %s" % pack.root
		return
	pack.new_blank(Rtp.DEFAULT_PACK_ID, "默认内容包", 25, 20)
	pack.save_dir()
	_select_map(pack.start_map)
	_status.text = "已创建默认包（MV 室外图块）· %s" % pack.root


func _new_pack() -> void:
	current_map_id = ""
	pack = ContentPack.new()
	var pid := "pack_%d" % int(Time.get_unix_time_from_system())
	pack.new_blank(pid, "新内容包", 25, 20)
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
	_restore_window_scale()
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
	var sc: Vector2i = doc.start_cell if doc else Vector2i(2, 2)
	sess.spawn_data = {
		"pack_path": pack.root,
		"map_id": current_map_id,
		"cell": {"x": sc.x, "y": sc.y},
		"character": ch,
		"content_id": pack.pack_id,
	}
	sess.loading_mode = "transfer"
	sess.go_loading()


func _select_map(id: String) -> void:
	if id == current_map_id:
		return
	if current_map_id != "" and pack != null and pack.has_method("map_is_dirty") and pack.map_is_dirty(current_map_id):
		_pending_switch = id
		_unsaved_dlg.popup_centered()
		return
	_do_select_map(id)


func _do_select_map(id: String) -> void:
	if id != current_map_id:
		_cam_ready = false
	current_map_id = id
	doc = pack.get_map(id)
	_refresh_tree()
	_sync_palette()
	_reload_assets()
	_reload_field()
	if _inspector:
		_inspector.load_cell(doc, _cursor)


func _confirm_switch_save() -> void:
	_save()
	var nid := _pending_switch
	_pending_switch = ""
	if nid != "":
		_do_select_map(nid)


func _unsaved_action(action: String) -> void:
	if action != "discard":
		return
	_unsaved_dlg.hide()
	var nid := _pending_switch
	_pending_switch = ""
	if doc:
		doc.dirty = false
	if nid != "":
		_do_select_map(nid)


func _open_pack_dialog() -> void:
	_open_list.clear()
	var packs: Array = ContentPack.list_user_packs()
	for p in packs:
		if typeof(p) != TYPE_DICTIONARY:
			continue
		_open_list.add_item("%s  (%s)" % [str(p.get("name", "")), str(p.get("id", ""))])
		_open_list.set_item_metadata(_open_list.item_count - 1, str(p.get("root", "")))
	_open_dlg.popup_centered()


func _confirm_open_pack() -> void:
	var idx := _open_list.get_selected_items()
	if idx.is_empty():
		return
	var root_path := str(_open_list.get_item_metadata(idx[0]))
	current_map_id = ""
	pack = ContentPack.new()
	if pack.load_dir(root_path):
		_do_select_map(pack.start_map)
		_status.text = "已打开 %s" % pack.pack_id
	else:
		_status.text = "无法打开 %s" % root_path


func _confirm_save_as() -> void:
	if pack == null:
		return
	var nid := _saveas_edit.text.strip_edges()
	if nid == "":
		return
	if pack.save_as(nid):
		_status.text = "已另存为 %s" % pack.pack_id
	else:
		_status.text = "另存为失败"


func _open_demo_copy() -> void:
	current_map_id = ""
	pack = ContentPack.new()
	if not pack.load_dir("res://demo_map"):
		_status.text = "无法读取 res://demo_map"
		return
	var nid := "demo_copy_%d" % int(Time.get_unix_time_from_system())
	if pack.adopt_as_user_pack(nid, "demo_map 副本"):
		_do_select_map(pack.start_map)
		_status.text = "已复制 demo_map → %s" % pack.root
	else:
		_status.text = "无法保存 user 副本"


func _on_reparent(src: String, parent: String) -> void:
	if pack == null:
		return
	if pack.set_parent(src, parent):
		_refresh_tree()
		_status.text = "已将 %s 移到 %s 下" % [src, parent]
	else:
		_status.text = "无法移动（环路？）"


func _build_asset_window() -> void:
	var rm = ResourceManager.new()
	rm.visible = false
	_asset_win = rm
	rm.assets_changed.connect(_on_assets_changed)
	rm.tileset_slot_assigned.connect(_on_rm_slot)
	add_child(rm)


func _build_entity_window() -> void:
	_entity_win = Window.new()
	_entity_win.title = "实体编辑"
	_entity_win.size = Vector2i(380, 460)
	_entity_win.visible = false
	_entity_win.close_requested.connect(func(): _entity_win.hide())
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	_entity_win.add_child(margin)
	_inspector = EntityInspector.new()
	_inspector.changed.connect(_on_entity_changed)
	margin.add_child(_inspector)
	add_child(_entity_win)


func _popup_win(win: Window) -> void:
	if win == null:
		return
	win.popup_centered()


func _open_asset_win() -> void:
	if _asset_win and _asset_win.has_method("bind_pack"):
		_asset_win.bind_pack(pack)
	_popup_win(_asset_win)


func _open_entity_win() -> void:
	if _inspector:
		_inspector.load_cell(doc, _cursor)
	_popup_win(_entity_win)


func _on_rm_slot(slot: int, sheet: String) -> void:
	if pack == null or doc == null:
		return
	var ts_id := str(doc.tileset_id)
	if pack.set_tileset_slot(ts_id, slot, sheet):
		_sync_palette()
		_reload_field()
		var slot_names := ["A1", "A2", "A3", "A4", "A5", "B", "C", "D", "E"]
		var slot_lbl: String = str(slot)
		if slot >= 0 and slot < slot_names.size():
			slot_lbl = str(slot_names[slot])
		_status.text = "槽 %s ← %s" % [slot_lbl, sheet]


func _on_assets_changed() -> void:
	if pack:
		pack.dirty = true
	_reload_assets()


func _reload_assets() -> void:
	if _asset_win and _asset_win.has_method("bind_pack") and _asset_win.visible:
		_asset_win.bind_pack(pack)


func _on_entity_changed() -> void:
	if pack:
		pack.dirty = true
	_status.text = "已更新实体"


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
		var mark := " ★" if pack != null and mid == pack.start_map else ""
		it.set_text(0, "%s (%s)%s" % [str(item.get("name", mid)), mid, mark])
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


func _on_tree_mouse(pos: Vector2, button: int) -> void:
	if button != MOUSE_BUTTON_RIGHT:
		return
	var it := _tree.get_item_at_position(pos)
	if it == null or not it.has_meta("map_id"):
		return
	var mid := str(it.get_meta("map_id"))
	_ctx_map_id = mid
	if mid != current_map_id:
		_select_map(mid)
	var last: bool = pack != null and pack.maps.size() <= 1
	_map_ctx.set_item_disabled(_map_ctx.get_item_index(CTX_DEL), last)
	_map_ctx.position = Vector2i(_tree.get_global_mouse_position())
	_map_ctx.popup()


func _on_map_ctx(id: int) -> void:
	var mid := _ctx_map_id if _ctx_map_id != "" else current_map_id
	match id:
		CTX_SETTINGS:
			_open_map_settings(mid)
		CTX_RENAME:
			_open_rename(mid)
		CTX_ADD:
			if mid != current_map_id:
				_select_map(mid)
			_add_child_map()
		CTX_DUP:
			_dup_map(mid)
		CTX_REPARENT:
			_on_reparent(mid, current_map_id)
		CTX_START:
			_set_start_map(mid)
		CTX_DEL:
			_ask_del_map(mid)


func _add_child_map() -> void:
	if pack == null:
		return
	var nid: String = pack.next_map_id() if pack.has_method("next_map_id") else ("Map%03d" % (pack.maps.size() + 1))
	var ts := ""
	if doc:
		ts = str(doc.tileset_id)
	pack.add_map(nid, "新地图", current_map_id, 20, 15, ts)
	_select_map(nid)


func _del_map() -> void:
	_ask_del_map(current_map_id)


func _ask_del_map(mid: String) -> void:
	if pack == null or mid == "":
		return
	if pack.maps.size() <= 1:
		_status.text = "至少留一张地图"
		return
	_ctx_map_id = mid
	var d = pack.get_map(mid)
	var label := str(d.display_name) if d else mid
	_del_dlg.dialog_text = "确定删除地图「%s」？子地图会提升到上一级。" % label
	_del_dlg.popup_centered()


func _confirm_del_map() -> void:
	var mid := _ctx_map_id if _ctx_map_id != "" else current_map_id
	if pack == null or not pack.maps.has(mid):
		return
	if pack.maps.size() <= 1:
		_status.text = "至少留一张地图"
		return
	pack.remove_map(mid)
	_select_map(pack.start_map)
	_status.text = "已删除 %s" % mid


func _set_start_map(mid: String) -> void:
	if pack == null or not pack.maps.has(mid):
		return
	pack.start_map = mid
	pack.dirty = true
	_refresh_tree()
	_status.text = "起始地图 → %s" % mid


func _build_map_settings_dialog() -> void:
	_set_dlg = ConfirmationDialog.new()
	_set_dlg.title = "地图设置"
	_set_dlg.min_size = Vector2i(380, 260)
	_set_dlg.ok_button_text = "确定"
	_set_dlg.cancel_button_text = "取消"
	_set_dlg.confirmed.connect(_apply_map_settings)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_set_dlg.add_child(v)
	_add_lbl(v, "显示名")
	_set_name = LineEdit.new()
	v.add_child(_set_name)
	var size_row := HBoxContainer.new()
	size_row.add_theme_constant_override("separation", 8)
	v.add_child(size_row)
	_add_lbl(size_row, "宽")
	_set_w = SpinBox.new()
	_set_w.min_value = 1
	_set_w.max_value = 1000
	_set_w.value = 25
	size_row.add_child(_set_w)
	_add_lbl(size_row, "高")
	_set_h = SpinBox.new()
	_set_h.min_value = 1
	_set_h.max_value = 1000
	_set_h.value = 20
	size_row.add_child(_set_h)
	_add_lbl(v, "图块套")
	_set_ts = OptionButton.new()
	v.add_child(_set_ts)
	_set_start = CheckBox.new()
	_set_start.text = "设为起始地图"
	v.add_child(_set_start)
	add_child(_set_dlg)


func _open_map_settings(mid: String) -> void:
	if pack == null or mid == "":
		return
	if mid != current_map_id:
		_select_map(mid)
	if doc == null:
		return
	_ctx_map_id = mid
	_set_name.text = str(doc.display_name)
	_set_w.value = doc.width
	_set_h.value = doc.height
	_set_start.button_pressed = pack.start_map == mid
	_set_ts.clear()
	var keys: Array = pack.tilesets.keys()
	keys.sort()
	var i := 0
	for k in keys:
		var sid := str(k)
		_set_ts.add_item(Rtp.display_name(sid), i)
		_set_ts.set_item_metadata(i, sid)
		if sid == str(doc.tileset_id):
			_set_ts.select(i)
		i += 1
	_set_dlg.popup_centered()


func _apply_map_settings() -> void:
	if pack == null or doc == null:
		return
	var mid := current_map_id
	var new_name := _set_name.text.strip_edges()
	if new_name == "":
		new_name = mid
	pack.rename_map(mid, new_name)
	var ts_id := str(_set_ts.get_item_metadata(_set_ts.selected)) if _set_ts.item_count > 0 else ""
	if ts_id != "":
		pack.set_map_tileset(mid, ts_id)
	var nw := int(_set_w.value)
	var nh := int(_set_h.value)
	if nw != int(doc.width) or nh != int(doc.height):
		doc.resize(nw, nh)
		var sc: Vector2i = doc.start_cell
		doc.start_cell = Vector2i(clampi(sc.x, 0, doc.width - 1), clampi(sc.y, 0, doc.height - 1))
	if _set_start.button_pressed:
		pack.start_map = mid
		pack.dirty = true
	pack.dirty = true
	_refresh_tree()
	_sync_palette()
	_reload_field()
	_status.text = "已更新地图设置 · %s %dx%d（未写入磁盘，Ctrl+S 保存）" % [new_name, doc.width, doc.height]


func _reload_field() -> void:
	if map_field == null or pack == null or doc == null:
		return
	map_field.pack_path = pack.root
	map_field.edit_map_id = current_map_id
	map_field.edit_mode = true
	map_field.edit_doc = doc
	map_field.show_grid = true
	map_field.edit_start_cell = doc.start_cell
	map_field.edit_show_passage = _mode == 2
	map_field.skip_ready_rebuild = true
	map_field.rebuild()
	if _palette and map_field.has_method("set_edit_flags"):
		map_field.set_edit_flags(_palette._flags)
	if _cam:
		_cam.zoom = Vector2(_zoom, _zoom)
		if not _cam_ready:
			var sc: Vector2i = doc.start_cell
			_cam.position = Vector2((float(sc.x) + 0.5) * float(doc.tile_size), (float(sc.y) + 0.5) * float(doc.tile_size))
			_cam_ready = true
		_clamp_camera()
	call_deferred("_sync_scrollbars")
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
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if not mb.pressed:
				return
			if mb.ctrl_pressed:
				var factor := 1.25 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.25
				_zoom_at(mb.position, _zoom * factor)
			elif mb.shift_pressed and _hscroll:
				var delta := _hscroll.page * 0.12
				_hscroll.value += -delta if mb.button_index == MOUSE_BUTTON_WHEEL_UP else delta
			elif _vscroll:
				var delta2 := _vscroll.page * 0.12
				_vscroll.value += -delta2 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else delta2
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_LEFT or mb.button_index == MOUSE_BUTTON_WHEEL_RIGHT:
			return
		if mb.button_index == MOUSE_BUTTON_MIDDLE or (_space_down and mb.button_index == MOUSE_BUTTON_LEFT):
			_panning = mb.pressed
			return
		if not mb.pressed:
			if paint.tool == PaintTools.Tool.RECT and paint.rect_start.x >= 0 and doc and not _placing_start:
				var cell := _mouse_cell(mb.position)
				if _mode == 2:
					_passage_rect(paint.rect_start, cell, mb.button_index == MOUSE_BUTTON_RIGHT)
				elif _mode == 0:
					paint.exact_autotile = mb.shift_pressed
					var dirty: Array[Vector2i] = paint.apply_rect(doc, paint.rect_start, cell, mb.button_index == MOUSE_BUTTON_RIGHT)
					paint.exact_autotile = false
					_refresh_dirty(dirty)
				paint.rect_start = Vector2i(-1, -1)
				if map_field:
					map_field.edit_rect_a = Vector2i(-1, -1)
					map_field.edit_rect_b = Vector2i(-1, -1)
			return
		var cell2 := _mouse_cell(mb.position)
		_cursor = cell2
		_set_hover(cell2)
		if _placing_start:
			_set_start_cell(cell2)
			return
		if _mode == 1:
			_cursor = cell2
			_open_entity_win()
			_status.text = "实体格 %d,%d" % [cell2.x, cell2.y]
			return
		if paint.tool == PaintTools.Tool.RECT:
			paint.rect_start = cell2
			if map_field:
				map_field.edit_rect_a = cell2
				map_field.edit_rect_b = cell2
			return
		if _mode == 2:
			if paint.tool == PaintTools.Tool.FILL:
				_passage_fill(cell2, mb.button_index == MOUSE_BUTTON_RIGHT)
			else:
				_paint_passage(cell2, mb.button_index == MOUSE_BUTTON_RIGHT)
			return
		paint.exact_autotile = mb.shift_pressed
		var erase := mb.button_index == MOUSE_BUTTON_RIGHT
		var dirty2: Array[Vector2i] = paint.apply_cell(doc, cell2, erase)
		paint.exact_autotile = false
		if paint.tool == PaintTools.Tool.EYEDROP and _palette:
			_palette.select_tile(paint.tile_id)
		_status.text = "画 %d @ %d,%d%s" % [paint.tile_id, cell2.x, cell2.y, " · Shift精确" if mb.shift_pressed else ""]
		_refresh_dirty(dirty2)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		var hover := _mouse_cell(mm.position)
		_set_hover(hover)
		if _panning and _cam:
			var z := maxf(_zoom, 0.05)
			_cam.position -= mm.relative / z
			_clamp_camera()
			_sync_scrollbars()
			_update_edit_observer()
			return
		if _placing_start:
			return
		if paint.tool == PaintTools.Tool.RECT and paint.rect_start.x >= 0 and map_field:
			map_field.edit_rect_b = hover
			return
		if _mode == 2:
			if (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0 and paint.tool == PaintTools.Tool.PENCIL:
				_paint_passage(hover, false)
			elif (mm.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0 and paint.tool == PaintTools.Tool.PENCIL:
				_paint_passage(hover, true)
			return
		if _mode != 0:
			return
		paint.exact_autotile = mm.shift_pressed
		if (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0 and paint.tool == PaintTools.Tool.PENCIL:
			var dirty3: Array[Vector2i] = paint.apply_cell(doc, hover, false)
			_refresh_dirty(dirty3)
		elif (mm.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0 and paint.tool == PaintTools.Tool.PENCIL:
			var dirty4: Array[Vector2i] = paint.apply_cell(doc, hover, true)
			_refresh_dirty(dirty4)
		paint.exact_autotile = false


func _sync_vp_size() -> void:
	if _vpc == null or _vp == null:
		return
	var s := Vector2i(maxi(1, int(_vpc.size.x)), maxi(1, int(_vpc.size.y)))
	if _vp.size != s:
		_vp.size = s
	_sync_scrollbars()
	_update_edit_observer()


func _mouse_cell(pos: Vector2) -> Vector2i:
	if map_field == null or _vp == null:
		return Vector2i.ZERO
	var vp_pos := pos
	if _vpc != null and _vpc.size.x > 0.5 and _vpc.size.y > 0.5:
		vp_pos = Vector2(
			pos.x * float(_vp.size.x) / _vpc.size.x,
			pos.y * float(_vp.size.y) / _vpc.size.y
		)
	var xform: Transform2D = _vp.get_canvas_transform()
	var world: Vector2 = xform.affine_inverse() * vp_pos
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
		elif _file_mode == "audio":
			_file_dlg.filters = PackedStringArray(["*.ogg ; OGG", "*.wav ; WAV", "*.mp3 ; MP3"])
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
				current_map_id = ""
				pack = ContentPack.new()
				if pack.load_dir(str(res.get("root", dest))):
					_select_map(pack.start_map)
					_status.text = "已导入 %s" % pack.pack_id
				else:
					_status.text = "导入后无法加载"
			else:
				_status.text = str(res.get("error", "导入失败"))
		"tilesheet", "charset", "audio":
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
	if pack.root.is_empty():
		pack.save_dir()
	var id := ""
	if pack.has_method("import_asset_file"):
		id = pack.import_asset_file(src, kind)
	if id == "":
		_status.text = "导入失败"
		return
	_status.text = "已导入 %s → %s" % [kind, id]
	_reload_assets()
	if kind != "tilesheet":
		return
	var ts_id := str(doc.tileset_id) if doc else ""
	if ts_id == "" or not pack.tilesets.has(ts_id):
		ts_id = "outside" if pack.tilesets.has("outside") else (str(pack.tilesets.keys()[0]) if not pack.tilesets.is_empty() else "")
	if ts_id == "":
		return
	var ts: Dictionary = pack.tilesets[ts_id]
	var names: Variant = ts.get("tilesetNames", [])
	if typeof(names) != TYPE_ARRAY:
		return
	var arr: Array = names
	while arr.size() < 9:
		arr.append("")
	var slot := 4
	for s in range(9):
		if str(arr[s]).strip_edges() == "":
			slot = s
			break
	arr[slot] = id
	ts["tilesetNames"] = arr
	pack.tilesets[ts_id] = ts
	pack.dirty = true
	pack.save_dir()
	_sync_palette()
	_reload_field()


func _sync_palette() -> void:
	if _palette == null or pack == null:
		return
	var ts := ""
	if doc:
		ts = str(doc.tileset_id)
	_palette.set_catalog(pack.tilesets, ts)
	paint.tile_id = int(_palette.selected_id)


func _on_palette_tile(id: int) -> void:
	paint.tile_id = id


func _on_palette_tileset(ts_id: String) -> void:
	if pack == null or current_map_id == "":
		return
	if pack.set_map_tileset(current_map_id, ts_id):
		_reload_field()
		_status.text = "图块套 %s" % ts_id


func _set_hover(cell: Vector2i) -> void:
	if map_field:
		map_field.edit_hover_cell = cell
	if doc == null or cell.x < 0:
		return
	var z: int = int(paint.layer_z) if paint else 0
	var tid := int(doc.tile(cell.x, cell.y, z)) if z >= 0 else int(doc.ext_tile(paint.ext_layer, cell.x, cell.y))
	var mark := ""
	if map_field and map_field.has_method("edit_cell_passable"):
		match int(map_field.edit_cell_passable(cell.x, cell.y)):
			0:
				mark = "○"
			1:
				mark = "×"
			2:
				mark = "强制○"
			3:
				mark = "强制×"
	_status.text = "%d,%d  图块 %d  通行%s" % [cell.x, cell.y, tid, (" " + mark) if mark != "" else ""]


func _undo_edit() -> void:
	if doc == null or not doc.has_method("undo_cells"):
		return
	var cells: Array[Vector2i] = doc.undo_cells()
	if paint and paint.has_method("refresh_autotiles"):
		paint.refresh_autotiles(doc, cells, cells)
	if cells.is_empty():
		cells.append(_cursor)
	_refresh_dirty(cells)


func _redo_edit() -> void:
	if doc == null or not doc.has_method("redo_cells"):
		return
	var cells: Array[Vector2i] = doc.redo_cells()
	if paint and paint.has_method("refresh_autotiles"):
		paint.refresh_autotiles(doc, cells, cells)
	if cells.is_empty():
		cells.append(_cursor)
	_refresh_dirty(cells)


func _dup_map(mid: String) -> void:
	if pack == null or not pack.has_method("duplicate_map"):
		return
	var nid: String = pack.duplicate_map(mid)
	if nid == "":
		_status.text = "复制失败"
		return
	_select_map(nid)
	_status.text = "已复制为 %s" % nid


func _open_rename(mid: String) -> void:
	if pack == null or mid == "":
		return
	_ctx_map_id = mid
	var d = pack.get_map(mid)
	_rename_edit.text = str(d.display_name) if d else mid
	_rename_dlg.popup_centered()
	_rename_edit.grab_focus()
	_rename_edit.select_all()


func _apply_rename() -> void:
	var mid := _ctx_map_id if _ctx_map_id != "" else current_map_id
	var nm := _rename_edit.text.strip_edges()
	if nm == "" or pack == null:
		return
	pack.rename_map(mid, nm)
	_refresh_tree()
	_status.text = "已重命名为 %s" % nm


func _passage_rect(a: Vector2i, b: Vector2i, right: bool) -> void:
	var x0 := mini(a.x, b.x)
	var x1 := maxi(a.x, b.x)
	var y0 := mini(a.y, b.y)
	var y1 := maxi(a.y, b.y)
	if doc and doc.has_method("begin_undo_batch"):
		doc.begin_undo_batch()
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			_paint_passage(Vector2i(x, y), right)
	if doc and doc.has_method("end_undo_batch"):
		doc.end_undo_batch()


func _passage_fill(start: Vector2i, right: bool) -> void:
	if doc == null or map_field == null or not map_field.has_method("edit_cell_passable"):
		_paint_passage(start, right)
		return
	var w: int = int(doc.width)
	var h: int = int(doc.height)
	if start.x < 0 or start.y < 0 or start.x >= w or start.y >= h:
		return
	var old_st: int = int(map_field.edit_cell_passable(start.x, start.y))
	if doc.has_method("begin_undo_batch"):
		doc.begin_undo_batch()
	var stack: Array[Vector2i] = [start]
	var seen := {}
	var n := 0
	while not stack.is_empty() and n < 20000:
		var c: Vector2i = stack.pop_back()
		var key := "%d,%d" % [c.x, c.y]
		if seen.has(key):
			continue
		seen[key] = true
		n += 1
		if int(map_field.edit_cell_passable(c.x, c.y)) != old_st:
			continue
		_paint_passage(c, right)
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n2: Vector2i = c + d
			if n2.x >= 0 and n2.y >= 0 and n2.x < w and n2.y < h:
				stack.append(n2)
	if doc.has_method("end_undo_batch"):
		doc.end_undo_batch()


func _on_flags_changed(ts_id: String, flags: PackedInt32Array) -> void:
	if pack == null or ts_id == "":
		return
	if pack.tilesets.has(ts_id):
		var ts: Dictionary = pack.tilesets[ts_id]
		var arr: Array = []
		arr.resize(flags.size())
		for i in range(flags.size()):
			arr[i] = int(flags[i])
		ts["flags"] = arr
		pack.tilesets[ts_id] = ts
	pack.dirty = true
	if map_field and map_field.has_method("set_edit_flags"):
		map_field.set_edit_flags(flags)
	_status.text = "已改图块通行 · %s #%d" % [ts_id, paint.tile_id if paint else 0]


func _paint_passage(cell: Vector2i, right: bool) -> void:
	if doc == null or cell.x < 0 or cell.y < 0 or cell.x >= doc.width or cell.y >= doc.height:
		return
	var meta: int = int(doc.ext_tile("meta", cell.x, cell.y))
	meta &= ~(MapExt.META_FORCE_BLOCK | MapExt.META_FORCE_PASS)
	var label := "清除"
	if paint.tool != PaintTools.Tool.ERASE:
		if right:
			meta |= MapExt.META_FORCE_PASS
			label = "通行"
		else:
			meta |= MapExt.META_FORCE_BLOCK
			label = "阻挡"
	doc.set_ext_tile("meta", cell.x, cell.y, meta)
	if pack:
		pack.dirty = true
	_cursor = cell
	_status.text = "通行覆盖 %d,%d · %s" % [cell.x, cell.y, label]


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_WM_SIZE_CHANGED:
		call_deferred("_fit_layout")


func _grab_window_scale() -> void:
	var win := get_tree().root
	if win == null:
		return
	_saved_scale_mode = win.content_scale_mode
	_saved_scale_aspect = win.content_scale_aspect
	_saved_scale_size = win.content_scale_size
	_scale_grabbed = true
	# EXPAND grows the 2D layout with the window (KEEP letterboxes a 1280×720 UI).
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	if not win.size_changed.is_connected(_on_win_resize):
		win.size_changed.connect(_on_win_resize)


func _restore_window_scale() -> void:
	if not _scale_grabbed:
		return
	_scale_grabbed = false
	var win := get_tree().root
	if win == null:
		return
	if win.size_changed.is_connected(_on_win_resize):
		win.size_changed.disconnect(_on_win_resize)
	win.content_scale_mode = _saved_scale_mode as Window.ContentScaleMode
	win.content_scale_aspect = _saved_scale_aspect as Window.ContentScaleAspect
	win.content_scale_size = _saved_scale_size


func _on_win_resize() -> void:
	call_deferred("_fit_layout")


func _fit_layout() -> void:
	var win := get_tree().root
	if win:
		win.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size = get_viewport_rect().size
	_sync_vp_size()
	_sync_scrollbars()


func _set_mode(mode: int) -> void:
	_mode = mode
	_placing_start = false
	if _mode_map_btn:
		_mode_map_btn.set_pressed_no_signal(mode == 0)
	if _mode_evt_btn:
		_mode_evt_btn.set_pressed_no_signal(mode == 1)
	if _pass_btn:
		_pass_btn.set_pressed_no_signal(mode == 2)
	if _start_btn:
		_start_btn.set_pressed_no_signal(false)
	if _palette and _palette.has_method("set_show_passage"):
		_palette.set_show_passage(mode == 2)
	if map_field:
		map_field.edit_show_passage = mode == 2
	if mode == 2:
		_status.text = "通行：图块点 ○/×/★，地图左键强制阻挡、右键强制通行"
	elif mode == 1:
		_status.text = "事件模式：点击格子"
	else:
		_status.text = "地图模式"


func _set_tool(tool_id: int) -> void:
	paint.tool = tool_id
	_placing_start = false
	if _start_btn:
		_start_btn.set_pressed_no_signal(false)
	if _tool_opt:
		for i in range(_tool_opt.item_count):
			if _tool_opt.get_item_id(i) == tool_id:
				_tool_opt.select(i)
				break
	for k in _tool_btns.keys():
		var b: Button = _tool_btns[k]
		b.set_pressed_no_signal(int(k) == tool_id)


func _toggle_start_tool() -> void:
	_placing_start = not _placing_start
	if _start_btn:
		_start_btn.set_pressed_no_signal(_placing_start)
	if _placing_start:
		_status.text = "点击地图设置起始点"


func _set_start_cell(cell: Vector2i) -> void:
	if doc == null:
		return
	cell.x = clampi(cell.x, 0, doc.width - 1)
	cell.y = clampi(cell.y, 0, doc.height - 1)
	doc.start_cell = cell
	doc.dirty = true
	if pack:
		pack.dirty = true
	if map_field:
		map_field.edit_start_cell = cell
		map_field.queue_redraw()
	_placing_start = false
	if _start_btn:
		_start_btn.set_pressed_no_signal(false)
	_status.text = "起始点 %d,%d" % [cell.x, cell.y]


func _set_zoom(z: float) -> void:
	_zoom = clampf(z, 0.25, 4.0)
	if _cam:
		_cam.zoom = Vector2(_zoom, _zoom)
	if _zoom_lbl:
		_zoom_lbl.text = "%d%%" % int(round(_zoom * 100.0))
	_clamp_camera()
	_sync_scrollbars()
	_update_edit_observer()


func _zoom_at(local_pos: Vector2, z: float) -> void:
	var before := _mouse_world(local_pos)
	_set_zoom(z)
	var after := _mouse_world(local_pos)
	if _cam:
		_cam.position += before - after
		_clamp_camera()
		_sync_scrollbars()


func _zoom_fit() -> void:
	if doc == null or _vp == null:
		return
	var mw := float(doc.width * doc.tile_size)
	var mh := float(doc.height * doc.tile_size)
	if mw <= 1.0 or mh <= 1.0:
		return
	var zx := float(_vp.size.x) / mw
	var zy := float(_vp.size.y) / mh
	_set_zoom(minf(zx, zy))
	_cam.position = Vector2(mw * 0.5, mh * 0.5)
	_sync_scrollbars()


func _mouse_world(pos: Vector2) -> Vector2:
	if _vp == null:
		return Vector2.ZERO
	var vp_pos := pos
	if _vpc != null and _vpc.size.x > 0.5 and _vpc.size.y > 0.5:
		vp_pos = Vector2(pos.x * float(_vp.size.x) / _vpc.size.x, pos.y * float(_vp.size.y) / _vpc.size.y)
	return _vp.get_canvas_transform().affine_inverse() * vp_pos


func _clamp_camera() -> void:
	if _cam == null or _vp == null or doc == null:
		return
	var z := maxf(_zoom, 0.05)
	var view_w := float(_vp.size.x) / z
	var view_h := float(_vp.size.y) / z
	var map_w := float(doc.width * doc.tile_size)
	var map_h := float(doc.height * doc.tile_size)
	var min_x := view_w * 0.5
	var max_x := maxf(min_x, map_w - view_w * 0.5)
	var min_y := view_h * 0.5
	var max_y := maxf(min_y, map_h - view_h * 0.5)
	_cam.position.x = clampf(_cam.position.x, min_x, max_x)
	_cam.position.y = clampf(_cam.position.y, min_y, max_y)


func _sync_scrollbars() -> void:
	if _syncing_scroll or _cam == null or _vp == null or doc == null or _hscroll == null:
		return
	_syncing_scroll = true
	var z := maxf(_zoom, 0.05)
	var view_w := maxf(float(_vp.size.x) / z, 1.0)
	var view_h := maxf(float(_vp.size.y) / z, 1.0)
	var map_w := float(maxi(doc.width, 1) * doc.tile_size)
	var map_h := float(maxi(doc.height, 1) * doc.tile_size)
	_hscroll.min_value = 0
	_hscroll.max_value = maxf(map_w, view_w)
	_hscroll.page = view_w
	_vscroll.min_value = 0
	_vscroll.max_value = maxf(map_h, view_h)
	_vscroll.page = view_h
	_hscroll.value = _cam.position.x - view_w * 0.5
	_vscroll.value = _cam.position.y - view_h * 0.5
	_syncing_scroll = false


func _on_hscroll(v: float) -> void:
	if _syncing_scroll or _cam == null or _vp == null:
		return
	var z := maxf(_zoom, 0.05)
	_cam.position.x = v + float(_vp.size.x) / z * 0.5
	_update_edit_observer()


func _on_vscroll(v: float) -> void:
	if _syncing_scroll or _cam == null or _vp == null:
		return
	var z := maxf(_zoom, 0.05)
	_cam.position.y = v + float(_vp.size.y) / z * 0.5
	_update_edit_observer()


func _update_edit_observer() -> void:
	if map_field == null or _cam == null:
		return
	map_field.set_edit_camera_cell(map_field.world_to_cell(_cam.position))
