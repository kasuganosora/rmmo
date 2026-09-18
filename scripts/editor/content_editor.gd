extends Control
## In-game content pack editor (maps tree, paint, assets, zip).

const ContentPack = preload("res://scripts/editor/domain/content_pack.gd")
const MapDocument = preload("res://scripts/editor/domain/map_document.gd")
const PaintTools = preload("res://scripts/editor/domain/paint_tools.gd")
const PackZip = preload("res://scripts/editor/infrastructure/pack_zip.gd")
const MapFieldScript = preload("res://scripts/map/map_field.gd")
const MapExt = preload("res://scripts/map/map_ext.gd")
const TilePalette = preload("res://scripts/editor/interface/tile_palette.gd")
const Rtp = preload("res://scripts/editor/infrastructure/rtp.gd")
const Net = preload("res://scripts/net/net.gd")
const MapTreeScript = preload("res://scripts/editor/interface/map_tree.gd")
const EntityInspector = preload("res://scripts/editor/interface/entity_inspector.gd")
const ResourceManager = preload("res://scripts/editor/infrastructure/resource_manager.gd")
const EventCommands = preload("res://scripts/editor/domain/event_commands.gd")
const TilesetManager = preload("res://scripts/editor/interface/tileset_manager.gd")
const EditorMcp = preload("res://scripts/editor/adapters/editor_mcp.gd")
const MapMinimap = preload("res://scripts/editor/interface/map_minimap.gd")
const MapShapes = preload("res://scripts/editor/domain/map_shapes.gd")
const TileLabels = preload("res://scripts/editor/domain/tile_labels.gd")
const EditorMenus = preload("res://scripts/editor/interface/editor_menus.gd")
const EditorDialogs = preload("res://scripts/editor/interface/editor_dialogs.gd")
const EditorSpecPanel = preload("res://scripts/editor/interface/editor_spec_panel.gd")
const EditorCanvas = preload("res://scripts/editor/interface/editor_canvas.gd")
const EditorAtmosphere = preload("res://scripts/editor/interface/editor_atmosphere.gd")

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
var _layer_tree: Tree
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
var _saved_scale_size: Vector2i = Vector2i(2560, 1440)
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
var _spec_box: VBoxContainer
var _spec_hint: Label
var _meta_box: HBoxContainer
var _shadow_box: HBoxContainer
var _region_spin: SpinBox
var _light_opt: OptionButton
var _sound_opt: OptionButton
var _foot_opt: OptionButton
var _far_sx: SpinBox
var _far_sy: SpinBox
var _water_thru: CheckBox
var _spec_kind: String = ""
var _spec_meta_bit: int = 0
var _spec_shadow: int = 15
var _set_far_sx: SpinBox
var _set_far_sy: SpinBox
var _set_water: CheckBox
var _set_env: OptionButton
var _set_bgm: OptionButton
var _set_light: OptionButton
var _light_bar: OptionButton
var _weather_bar: OptionButton
var _preview_weather: String = "clear"
var _preview_weather_i: float = 0.8
var _fx_color_bar: ColorPickerButton
var _fx_color: ColorPickerButton
var _set_fx_color: ColorPickerButton
var _editor_modulate: CanvasModulate
var _light_syncing: bool = false
var _fx_syncing: bool = false
var _asset_list: ItemList
var _slot_opt: OptionButton
var _inspector
var _asset_win: Window
var _entity_win: Window
var _tileset_win: Window
var _mcp: Node
var _mcp_popup: PopupMenu
var _entity_clip: Dictionary = {}
var _minimap: Control
var _minimap_timer: Timer
var _pass_overlay_btn: Button
var _poly_pts: Array[Vector2i] = []
var _undo_dlg: AcceptDialog
var _undo_list: ItemList
var _bm_opt: OptionButton
var _ref_alpha: HSlider

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
	MENU_EDIT_COPY = 22,
	MENU_EDIT_CUT = 23,
	MENU_EDIT_PASTE = 24,
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
	MENU_ASSET_TILESET = 44,
	MENU_ENTITY = 36,
	CTX_REPARENT = 66,
	MENU_GAME_PLAY = 50,
	MENU_GAME_PLAY_CURSOR = 51,
	MENU_MCP_TOGGLE = 70,
}


func _ready() -> void:
	_grab_window_scale()
	paint = PaintTools.new()
	paint.tile_id = 2816
	_build_ui()
	Rtp.ensure_runtime_assets()
	_open_or_create_default()
	call_deferred("_fit_layout")
	if _want_mcp_autostart():
		call_deferred("_toggle_mcp")


func _exit_tree() -> void:
	if _mcp != null and _mcp.has_method("stop"):
		_mcp.stop()
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
		elif k.ctrl_pressed and k.keycode == KEY_C:
			if _mode == 1 and _copy_entity():
				_mark_handled()
			else:
				_copy_tiles()
				_mark_handled()
		elif k.ctrl_pressed and k.keycode == KEY_X:
			_cut_tiles()
			_mark_handled()
		elif k.ctrl_pressed and k.keycode == KEY_V:
			if _mode == 1 and _paste_entity():
				_mark_handled()
			else:
				_paste_tiles()
				_mark_handled()
		elif k.ctrl_pressed and k.keycode == KEY_A:
			_select_all()
			_mark_handled()
		elif k.keycode == KEY_F5:
			_playtest(k.shift_pressed)
			_mark_handled()
		elif k.keycode == KEY_DELETE:
			if _mode == 1 and _inspector:
				_inspector.cell = _cursor
				_inspector._delete()
			elif paint and paint.tool == PaintTools.Tool.SELECT:
				_erase_selection()
			_mark_handled()
		elif k.ctrl_pressed and k.keycode == KEY_D:
			_dup_map(current_map_id)
			_mark_handled()
		elif k.keycode == KEY_ESCAPE:
			if _poly_pts.size() > 0:
				_poly_pts.clear()
				_status.text = "已取消折线"
				_mark_handled()
			else:
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
		elif k.keycode == KEY_6:
			_set_tool(PaintTools.Tool.SELECT)
			_mark_handled()
		elif k.keycode == KEY_7:
			_set_tool(PaintTools.Tool.LINE)
			_mark_handled()
		elif k.keycode == KEY_8:
			_set_tool(PaintTools.Tool.POLYLINE)
			_mark_handled()
		elif k.keycode == KEY_9:
			_set_tool(PaintTools.Tool.ELLIPSE)
			_mark_handled()
		elif k.keycode == KEY_0:
			_set_tool(PaintTools.Tool.RING)
			_mark_handled()
		elif k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER:
			if paint and paint.tool == PaintTools.Tool.POLYLINE:
				_commit_polyline(false)
				_mark_handled()
		elif k.keycode == KEY_BRACKETLEFT:
			_cycle_layer(-1)
			_mark_handled()
		elif k.keycode == KEY_BRACKETRIGHT:
			_cycle_layer(1)
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
	menu_wrap.add_child(EditorMenus.build_menu_bar(self))
	root.add_child(menu_wrap)
	root.add_child(EditorMenus.build_toolbar(self))
	var mid := HBoxContainer.new()
	mid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 4)
	root.add_child(mid)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(220, 0)
	mid.add_child(left)
	_add_lbl(left, "缩略图")
	_minimap = MapMinimap.new()
	_minimap.custom_minimum_size = Vector2(0, 176)
	_minimap.jump_to_world.connect(_on_minimap_jump)
	left.add_child(_minimap)
	_bm_opt = OptionButton.new()
	_bm_opt.focus_mode = Control.FOCUS_NONE
	_bm_opt.item_selected.connect(_on_bookmark_sel)
	left.add_child(_bm_opt)
	_refresh_bookmarks()
	_minimap_timer = Timer.new()
	_minimap_timer.one_shot = true
	_minimap_timer.wait_time = 0.2
	_minimap_timer.timeout.connect(_rebuild_minimap)
	add_child(_minimap_timer)
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
	EditorDialogs.build_map_settings_dialog(self)
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
	EditorDialogs.build_asset_window(self)
	EditorDialogs.build_entity_window(self)
	EditorDialogs.build_tileset_window(self)
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
	_editor_modulate = CanvasModulate.new()
	_editor_modulate.name = "MapLight"
	_vp.add_child(_editor_modulate)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(400, 0)
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_child(right)
	_add_lbl(right, "图层（勾选显示）")
	_layer_tree = Tree.new()
	_layer_tree.columns = 2
	_layer_tree.hide_root = true
	_layer_tree.hide_folding = true
	_layer_tree.select_mode = Tree.SELECT_SINGLE
	_layer_tree.custom_minimum_size = Vector2(0, 220)
	_layer_tree.set_column_expand(0, false)
	_layer_tree.set_column_custom_minimum_width(0, 28)
	_layer_tree.set_column_expand(1, true)
	_layer_tree.item_selected.connect(_on_layer_tree)
	_layer_tree.item_edited.connect(_on_layer_vis)
	right.add_child(_layer_tree)
	var alpha_row := HBoxContainer.new()
	right.add_child(alpha_row)
	_add_lbl(alpha_row, "上层α")
	var us := HSlider.new()
	us.min_value = 0
	us.max_value = 1
	us.step = 0.05
	us.value = 1
	us.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	us.value_changed.connect(func(v):
		if map_field and map_field.has_method("set_bucket_alpha"):
			map_field.set_bucket_alpha("Upper", float(v))
	)
	alpha_row.add_child(us)
	_fill_layer_tree()
	EditorSpecPanel.build_spec_panel(self, right)
	_sync_spec_panel(_spec_kind, "")
	_add_lbl(right, "工具")
	_tool_opt = OptionButton.new()
	_tool_opt.add_item("铅笔", PaintTools.Tool.PENCIL)
	_tool_opt.add_item("矩形", PaintTools.Tool.RECT)
	_tool_opt.add_item("填充", PaintTools.Tool.FILL)
	_tool_opt.add_item("吸管", PaintTools.Tool.EYEDROP)
	_tool_opt.add_item("橡皮", PaintTools.Tool.ERASE)
	_tool_opt.add_item("选区", PaintTools.Tool.SELECT)
	_tool_opt.add_item("线", PaintTools.Tool.LINE)
	_tool_opt.add_item("折线", PaintTools.Tool.POLYLINE)
	_tool_opt.add_item("椭圆", PaintTools.Tool.ELLIPSE)
	_tool_opt.add_item("圆环", PaintTools.Tool.RING)
	_tool_opt.item_selected.connect(func(idx): _set_tool(_tool_opt.get_item_id(idx)))
	right.add_child(_tool_opt)
	_palette = TilePalette.new()
	_palette.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_palette.tile_selected.connect(_on_palette_tile)
	_palette.tileset_changed.connect(_on_palette_tileset)
	_palette.flags_changed.connect(_on_flags_changed)
	if _palette.has_signal("stamp_changed"):
		_palette.stamp_changed.connect(_on_stamp)
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
		MENU_EDIT_COPY:
			_copy_tiles()
		MENU_EDIT_CUT:
			_cut_tiles()
		MENU_EDIT_PASTE:
			_paste_tiles()
		25:
			_copy_entity()
		26:
			_paste_entity()
		27:
			_rotate_clip(true)
		28:
			_flip_clip(true)
		29:
			_replace_prompt()
		71:
			_show_undo_list()
		37:
			_pick_reference()
		38:
			_clear_reference()
		39:
			_add_bookmark_here()
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
		MENU_ASSET_TILESET:
			_open_tileset_win()
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
		MENU_GAME_PLAY_CURSOR:
			_playtest(true)
		MENU_MCP_TOGGLE:
			_toggle_mcp()


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


func _playtest(from_cursor: bool = false) -> void:
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
	if from_cursor:
		sc = _cursor
		if doc:
			sc = Vector2i(clampi(sc.x, 0, doc.width - 1), clampi(sc.y, 0, doc.height - 1))
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
	_fix_autotiles()
	_refresh_tree()
	_sync_palette()
	_reload_assets()
	_reload_field()
	_sync_light_controls()
	_apply_editor_light()
	_sync_fx_color_controls()
	_apply_editor_fx_color()
	if _inspector:
		if _inspector.has_method("bind_pack"):
			_inspector.bind_pack(pack)
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
	if pack and current_map_id != "" and pack.has_method("reload_map"):
		if not pack.reload_map(current_map_id):
			if doc:
				doc.dirty = false
	elif doc:
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



func _popup_win(win: Window) -> void:
	if win == null:
		return
	win.popup_centered()


func _open_asset_win() -> void:
	if _asset_win and _asset_win.has_method("bind_pack"):
		_asset_win.bind_pack(pack)
	_popup_win(_asset_win)



func _open_tileset_win() -> void:
	if _tileset_win and _tileset_win.has_method("bind_pack"):
		_tileset_win.bind_pack(pack)
	_popup_win(_tileset_win)


func _on_tileset_catalog() -> void:
	if pack:
		pack.dirty = true
	_sync_palette()
	if _tileset_win and _tileset_win.has_method("bind_pack"):
		_tileset_win.bind_pack(pack)
	_status.text = "图块套已更新（未写入磁盘，Ctrl+S 保存）"


func _on_tileset_apply(ts_id: String) -> void:
	if pack == null or current_map_id == "" or ts_id.strip_edges() == "":
		return
	if pack.set_map_tileset(current_map_id, ts_id):
		_sync_palette()
		_reload_field()
		var label: String = pack.tileset_label(ts_id) if pack.has_method("tileset_label") else ts_id
		_status.text = "当前地图使用图块套：%s" % label


func _open_entity_win() -> void:
	if _inspector:
		if _inspector.has_method("bind_pack"):
			_inspector.bind_pack(pack)
		_inspector.load_cell(doc, _cursor)
	if map_field:
		map_field.edit_cursor_cell = _cursor
	_popup_win(_entity_win)


func _on_rm_slot(slot: int, sheet: String) -> void:
	if pack == null or doc == null:
		return
	var ts_id := str(doc.tileset_id)
	if pack.set_tileset_slot(ts_id, slot, sheet):
		_finish_sheet_assign(slot, sheet)


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
	if map_field:
		map_field.edit_cursor_cell = _cursor
	_status.text = "已更新实体"


func _on_entity_jump(c: Vector2i) -> void:
	_cursor = c
	if map_field:
		map_field.edit_cursor_cell = c
		map_field.edit_hover_cell = c
	if _cam and doc:
		_cam.position = Vector2((float(c.x) + 0.5) * float(doc.tile_size), (float(c.y) + 0.5) * float(doc.tile_size))
		_clamp_camera()
		_sync_scrollbars()
		_update_edit_observer()
	_status.text = "实体格 %d,%d" % [c.x, c.y]


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
	if _set_far_sx:
		_set_far_sx.value = doc.far_scroll.x
	if _set_far_sy:
		_set_far_sy.value = doc.far_scroll.y
	if _set_water:
		_set_water.button_pressed = doc.water_through
	if _set_env:
		var env := MapExt.ENV_OUTDOOR
		if "environment" in doc:
			env = MapExt.normalize_environment(doc.environment)
		_set_env.select(1 if env == MapExt.ENV_INDOOR else 0)
	_fill_bgm_opt(str(doc.bgm) if "bgm" in doc else "")
	_fill_preset_opt(_set_light, "res://data/map/light_presets.json", ["日间", "黄昏", "夜晚"])
	_select_opt_id(_set_light, int(doc.light_preset) if "light_preset" in doc else 0)
	if _set_fx_color:
		_set_fx_color.color = doc.light_fx_color if "light_fx_color" in doc else Color(1, 1, 1, 1)
	_set_ts.clear()
	var keys: Array = pack.tilesets.keys()
	keys.sort()
	var i := 0
	for k in keys:
		var sid := str(k)
		var label: String = pack.tileset_label(sid) if pack.has_method("tileset_label") else Rtp.display_name(sid)
		_set_ts.add_item(label, i)
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
	if _set_far_sx and _set_far_sy:
		doc.far_scroll = Vector2(_set_far_sx.value, _set_far_sy.value)
		doc.dirty = true
	if _set_water:
		doc.water_through = _set_water.button_pressed
		doc.dirty = true
	if _set_env:
		var env_id := MapExt.ENV_OUTDOOR
		if _set_env.selected >= 0:
			env_id = MapExt.normalize_environment(_set_env.get_item_metadata(_set_env.selected))
		doc.environment = env_id
		doc.dirty = true
	if _set_bgm and "bgm" in doc:
		var bgm_id := ""
		if _set_bgm.selected >= 0:
			bgm_id = str(_set_bgm.get_item_metadata(_set_bgm.selected))
		doc.bgm = bgm_id
		doc.dirty = true
	if _set_light and "light_preset" in doc:
		doc.light_preset = int(_set_light.get_item_id(_set_light.selected)) if _set_light.item_count > 0 else 0
		doc.dirty = true
		_sync_light_controls()
		_apply_editor_light()
	if _set_fx_color and "light_fx_color" in doc:
		doc.light_fx_color = _set_fx_color.color
		doc.dirty = true
		_sync_fx_color_controls()
		_apply_editor_fx_color()
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


func _fix_autotiles() -> void:
	if paint == null or doc == null or not paint.has_method("refresh_all_floor_autotiles"):
		return
	var n: int = int(paint.refresh_all_floor_autotiles(doc))
	if n > 0:
		doc.dirty = true


func _reload_field() -> void:
	if map_field == null or pack == null or doc == null:
		return
	map_field.pack_path = pack.root
	map_field.edit_map_id = current_map_id
	map_field.edit_mode = true
	map_field.edit_doc = doc
	map_field.show_grid = true
	map_field.edit_start_cell = doc.start_cell
	map_field.edit_cursor_cell = _cursor
	map_field.edit_show_passage = _mode == 2
	map_field.edit_spec_kind = _spec_kind if _is_spec_paint() else ""
	map_field.skip_ready_rebuild = true
	map_field.rebuild()
	if _palette and map_field.has_method("set_edit_flags"):
		map_field.set_edit_flags(_palette._flags)
	_apply_editor_light()
	_apply_editor_fx_color()
	_rebuild_minimap()
	_refresh_bookmarks()
	if _cam:
		_cam.zoom = Vector2(_zoom, _zoom)
		if not _cam_ready:
			var sc: Vector2i = doc.start_cell
			_cam.position = Vector2((float(sc.x) + 0.5) * float(doc.tile_size), (float(sc.y) + 0.5) * float(doc.tile_size))
			_cam_ready = true
		_clamp_camera()
	_update_edit_observer()
	if map_field and map_field.has_method("bake_observer_chunk"):
		map_field.bake_observer_chunk()
	call_deferred("_sync_scrollbars")
	_status.text = _map_status_line()


func _fill_layer_tree() -> void:
	if _layer_tree == null:
		return
	_layer_tree.clear()
	var root := _layer_tree.create_item()
	var groups: Array = [
		{"label": "MV 图层", "rows": [
			{"z": 0, "ext": "", "spec": "", "name": "地面 z0（先铺草地）"},
			{"z": 1, "ext": "", "spec": "", "name": "叠层 z1（路/沙盖在草上）"},
			{"z": 2, "ext": "", "spec": "", "name": "物件 z2"},
			{"z": 3, "ext": "", "spec": "", "name": "上层 z3"},
			{"z": 4, "ext": "", "spec": "shadow", "name": "阴影 z4"},
			{"z": 5, "ext": "", "spec": "region", "name": "区域 z5"},
		]},
		{"label": "扩展绘制", "rows": []},
		{"label": "逻辑", "rows": []},
	]
	for id in MapExt.VISUAL_EXT:
		(groups[1]["rows"] as Array).append({"z": -1, "ext": id, "spec": id, "name": MapExt.layer_label(id)})
	for id in MapExt.SPEC_EXT:
		(groups[2]["rows"] as Array).append({"z": -1, "ext": id, "spec": id, "name": MapExt.layer_label(id)})
	var first: TreeItem = null
	for g in groups:
		var head := _layer_tree.create_item(root)
		head.set_text(1, str(g["label"]))
		head.set_selectable(0, false)
		head.set_selectable(1, false)
		head.set_custom_color(1, Color(0.65, 0.68, 0.72, 1))
		for row in g["rows"]:
			var it := _layer_tree.create_item(head)
			it.set_cell_mode(0, TreeItem.CELL_MODE_CHECK)
			it.set_checked(0, true)
			it.set_editable(0, true)
			it.set_text(1, str(row["name"]))
			it.set_metadata(0, row)
			if first == null:
				first = it
	if first:
		first.select(1)



func _sync_shadow_brush() -> void:
	var bits := 0
	if _shadow_box == null:
		return
	for c in _shadow_box.get_children():
		if c is Button and c.button_pressed:
			bits |= int(c.get_meta("bit", 0))
	_spec_shadow = bits


func _fill_preset_opt(opt: OptionButton, path: String, fallback: PackedStringArray) -> void:
	EditorAtmosphere.fill_preset_opt(self, opt, path, fallback)
func _fill_bgm_opt(current: String) -> void:
	EditorAtmosphere.fill_bgm_opt(self, current)
func _set_far_scroll(x: float, y: float) -> void:
	EditorAtmosphere.set_far_scroll(self, x, y)
func _on_layer_tree() -> void:
	var it := _layer_tree.get_selected() if _layer_tree else null
	if it == null:
		return
	var meta: Variant = it.get_metadata(0)
	if typeof(meta) != TYPE_DICTIONARY:
		return
	var z := int(meta.get("z", 0))
	var ext := str(meta.get("ext", ""))
	if z >= 0:
		paint.layer_z = z
		paint.ext_layer = ""
	else:
		paint.layer_z = -1
		paint.ext_layer = ext
	_sync_spec_panel(str(meta.get("spec", "")), str(meta.get("name", "")))
	var vis: String = "显示" if it.is_checked(0) else "隐藏"
	if _status:
		_status.text = "绘制 %s（%s）" % [str(meta.get("name", "")), vis]


func _sync_spec_panel(spec: String, layer_name: String) -> void:
	_spec_kind = spec
	if map_field:
		var overlay := spec if spec in ["meta", "settings", "shadow", "region"] else ""
		map_field.edit_spec_kind = overlay
	var hide_pal := spec in ["meta", "settings", "shadow", "region"]
	if _palette:
		_palette.visible = not hide_pal
	if _spec_box == null:
		return
	var show := spec != ""
	_spec_box.visible = show
	if _meta_box:
		_meta_box.visible = spec == "meta"
	if _shadow_box:
		_shadow_box.visible = spec == "shadow"
	var region_row := _spec_box.get_node_or_null("RegionRow")
	if region_row:
		region_row.visible = spec == "region"
	var set_row := _spec_box.get_node_or_null("SettingsRow")
	if set_row:
		set_row.visible = spec == "settings"
	var far_row := _spec_box.get_node_or_null("FarRow")
	if far_row:
		far_row.visible = spec == "far"
	if _water_thru:
		_water_thru.visible = spec == "water"
	var fx_row := _spec_box.get_node_or_null("LightFxRow")
	if fx_row:
		fx_row.visible = spec == "light"
	if _spec_hint:
		match spec:
			"meta":
				_spec_hint.text = "格子标记：室内藏屋顶；强制阻挡/通行覆盖图块通行。"
			"settings":
				_spec_hint.text = "氛围：按格写入光照、环境音、脚步（走到该格时生效）。"
			"shadow":
				_spec_hint.text = "阴影：勾选四角后在地图上画（不是图块）。"
			"region":
				_spec_hint.text = "区域号：给格子编号，便于事件/脚本区分。"
			"far":
				_spec_hint.text = "远景：用图块板绘制。滚动 0 跟地图，>0 随镜头视差。"
			"water":
				_spec_hint.text = "水面：有图即挡路；勾选「水面可走」则整层不挡。"
			"roof":
				_spec_hint.text = "屋顶：室内标记格子上会自动隐藏。"
			"light":
				_spec_hint.text = "光效：叠在角色上方的加色层。颜色可自定，与地图光照无关。"
			_:
				_spec_hint.text = layer_name
	if spec == "far" and doc and _far_sx and _far_sy:
		_far_sx.set_value_no_signal(doc.far_scroll.x)
		_far_sy.set_value_no_signal(doc.far_scroll.y)
	if spec == "water" and doc and _water_thru:
		_water_thru.set_pressed_no_signal(doc.water_through)
	if spec == "light":
		_sync_fx_color_controls()


func _on_layer_vis() -> void:
	if _layer_tree == null or map_field == null:
		return
	var it := _layer_tree.get_edited()
	if it == null:
		return
	var meta: Variant = it.get_metadata(0)
	if typeof(meta) != TYPE_DICTIONARY:
		return
	var hidden := not it.is_checked(0)
	var z := int(meta.get("z", -1))
	var ext := str(meta.get("ext", ""))
	if z >= 0:
		map_field.set_layer_hidden_z(z, hidden)
	elif ext != "":
		map_field.set_layer_hidden_ext(ext, hidden)
	if _status:
		_status.text = "%s %s" % ["隐藏" if hidden else "显示", str(meta.get("name", ""))]


func _cycle_layer(delta: int) -> void:
	if _layer_tree == null:
		return
	var it := _layer_tree.get_selected()
	if it == null:
		it = _layer_tree.get_root().get_first_child() if _layer_tree.get_root() else null
		if it:
			it.select(1)
			_on_layer_tree()
		return
	var nxt: TreeItem = it.get_next() if delta > 0 else it.get_prev()
	if nxt == null:
		var root := _layer_tree.get_root()
		if root == null:
			return
		if delta > 0:
			nxt = root.get_first_child()
		else:
			nxt = root.get_first_child()
			while nxt != null and nxt.get_next() != null:
				nxt = nxt.get_next()
	if nxt:
		nxt.select(1)
		_on_layer_tree()


func _on_canvas_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.keycode == KEY_SPACE:
			_space_down = k.pressed
		if k.pressed and not k.echo and paint and paint.tool == PaintTools.Tool.POLYLINE:
			if k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER:
				_commit_polyline(false)
				_mark_handled()
				return
			if k.keycode == KEY_ESCAPE:
				_poly_pts.clear()
				_status.text = "已取消折线"
				_mark_handled()
				return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if not mb.pressed:
				return
			if mb.ctrl_pressed:
				var factor := 1.25 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.25
				_zoom_at(mb.position, _zoom * factor)
			elif mb.shift_pressed:
				_canvas_wheel_scroll(true, mb.button_index == MOUSE_BUTTON_WHEEL_DOWN)
			else:
				_canvas_wheel_scroll(false, mb.button_index == MOUSE_BUTTON_WHEEL_DOWN)
			_mark_handled()
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_LEFT or mb.button_index == MOUSE_BUTTON_WHEEL_RIGHT:
			if mb.pressed:
				_canvas_wheel_scroll(true, mb.button_index == MOUSE_BUTTON_WHEEL_RIGHT)
				_mark_handled()
			return
		if mb.button_index == MOUSE_BUTTON_MIDDLE or (_space_down and mb.button_index == MOUSE_BUTTON_LEFT):
			_panning = mb.pressed
			return
		if not mb.pressed:
			if paint.rect_start.x >= 0 and doc and not _placing_start:
				var cell := _mouse_cell(mb.position)
				if paint.tool == PaintTools.Tool.SELECT and _mode == 0:
					if map_field:
						map_field.edit_rect_b = cell
					_status.text = "选区 %d,%d → %d,%d" % [paint.rect_start.x, paint.rect_start.y, cell.x, cell.y]
				elif paint.tool == PaintTools.Tool.RECT:
					if _mode == 2:
						_passage_rect(paint.rect_start, cell, mb.button_index == MOUSE_BUTTON_RIGHT)
					elif _mode == 0 and _is_spec_paint():
						_spec_rect(paint.rect_start, cell, mb.button_index == MOUSE_BUTTON_RIGHT)
					elif _mode == 0:
						paint.exact_autotile = mb.shift_pressed
						var dirty: Array[Vector2i] = paint.apply_rect(doc, paint.rect_start, cell, mb.button_index == MOUSE_BUTTON_RIGHT)
						paint.exact_autotile = false
						_refresh_dirty(dirty)
					paint.rect_start = Vector2i(-1, -1)
					if map_field:
						map_field.edit_rect_a = Vector2i(-1, -1)
						map_field.edit_rect_b = Vector2i(-1, -1)
				elif _mode == 0 and paint.tool in [PaintTools.Tool.LINE, PaintTools.Tool.ELLIPSE, PaintTools.Tool.RING]:
					_commit_shape(paint.rect_start, cell, mb.button_index == MOUSE_BUTTON_RIGHT)
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
			if map_field:
				map_field.edit_cursor_cell = cell2
			_open_entity_win()
			_status.text = "实体格 %d,%d" % [cell2.x, cell2.y]
			return
		if paint.tool == PaintTools.Tool.POLYLINE and _mode == 0:
			if mb.button_index == MOUSE_BUTTON_RIGHT:
				_commit_polyline(false)
				return
			_poly_pts.append(cell2)
			_status.text = "折线 %d 点 · 右键/Enter 完成 / Esc 取消" % _poly_pts.size()
			return
		if paint.tool == PaintTools.Tool.RECT or paint.tool == PaintTools.Tool.SELECT or paint.tool == PaintTools.Tool.LINE or paint.tool == PaintTools.Tool.ELLIPSE or paint.tool == PaintTools.Tool.RING:
			paint.rect_start = cell2
			if map_field:
				map_field.edit_rect_a = cell2
				map_field.edit_rect_b = cell2
			return
		if paint.has_method("begin_stroke"):
			paint.begin_stroke()
		if _mode == 2:
			if paint.tool == PaintTools.Tool.FILL:
				_passage_fill(cell2, mb.button_index == MOUSE_BUTTON_RIGHT)
			else:
				_paint_passage(cell2, mb.button_index == MOUSE_BUTTON_RIGHT)
			return
		if _is_spec_paint():
			if paint.tool == PaintTools.Tool.FILL:
				_spec_fill(cell2, mb.button_index == MOUSE_BUTTON_RIGHT)
			elif paint.tool == PaintTools.Tool.EYEDROP:
				_spec_eyedrop(cell2)
			else:
				_paint_spec(cell2, mb.button_index == MOUSE_BUTTON_RIGHT)
			return
		paint.exact_autotile = mb.shift_pressed
		var erase := mb.button_index == MOUSE_BUTTON_RIGHT
		var dirty2: Array[Vector2i] = paint.apply_cell(doc, cell2, erase)
		paint.exact_autotile = false
		if paint.tool == PaintTools.Tool.EYEDROP and _palette:
			_palette.select_tile(paint.tile_id)
			paint.set_stamp(1, 1, PackedInt32Array())
			if map_field:
				map_field.edit_stamp_size = Vector2i(1, 1)
		_status.text = "画 %d @ %d,%d%s" % [paint.tile_id, cell2.x, cell2.y, " · Shift精确" if mb.shift_pressed else ""]
		_refresh_dirty(dirty2)
	elif event is InputEventPanGesture:
		var pg := event as InputEventPanGesture
		_canvas_pan_pixels(pg.delta)
		_mark_handled()
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
		if (paint.tool == PaintTools.Tool.RECT or paint.tool == PaintTools.Tool.SELECT or paint.tool == PaintTools.Tool.LINE or paint.tool == PaintTools.Tool.ELLIPSE or paint.tool == PaintTools.Tool.RING) and paint.rect_start.x >= 0 and map_field:
			map_field.edit_rect_b = hover
			return
		if _mode == 0 and _is_spec_paint() and paint.tool == PaintTools.Tool.PENCIL:
			if (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
				_paint_spec(hover, false)
			elif (mm.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0:
				_paint_spec(hover, true)
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
	EditorCanvas.sync_vp_size(self)
func _mouse_cell(pos: Vector2) -> Vector2i:
	return EditorCanvas.mouse_cell(self, pos)
func _refresh_dirty(cells: Array) -> void:
	if map_field and map_field.has_method("rebuild_dirty_cells"):
		map_field.rebuild_dirty_cells(cells)
	_schedule_minimap(cells)


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
		"reference":
			if map_field and map_field.has_method("set_reference_image"):
				map_field.set_reference_image(path, 0.35)
			_status.text = "参考图 %s" % path.get_file()


func _add_chest_event() -> void:
	if doc == null:
		return
	if doc.has_method("remove_entity_at"):
		doc.remove_entity_at(_cursor)
	var ev: Dictionary = EventCommands.make_chest(_cursor)
	doc.events.append(ev)
	doc.dirty = true
	if pack:
		pack.dirty = true
	if map_field:
		map_field.edit_cursor_cell = _cursor
	if _inspector:
		_inspector.load_cell(doc, _cursor)
	_open_entity_win()
	_status.text = "已在 %d,%d 放宝箱 %s" % [_cursor.x, _cursor.y, str(ev.get("id", ""))]


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
	_finish_sheet_assign(slot, id)


func _finish_sheet_assign(slot: int, sheet: String) -> void:
	var ts_id := str(doc.tileset_id) if doc else ""
	if ts_id != "" and pack.has_method("init_slot_passage"):
		pack.init_slot_passage(ts_id, slot)
	_sync_palette()
	_reload_field()
	if _palette and _palette.has_method("select_slot"):
		_palette.select_slot(slot)
	_set_mode(2)
	var names: PackedStringArray = ["A1", "A2", "A3", "A4", "A5", "B", "C", "D", "E"]
	var lbl: String = names[slot] if slot >= 0 and slot < names.size() else str(slot)
	var hint := "× 阻挡" if slot == 2 or slot == 3 else "○ 可走"
	_status.text = "已编入 %s ← %s（默认%s）。点图块改 ○/×/★" % [lbl, sheet, hint]


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
	if _palette and int(_palette.stamp_w) <= 1 and int(_palette.stamp_h) <= 1:
		paint.set_stamp(1, 1, PackedInt32Array())
		if map_field:
			map_field.edit_stamp_size = Vector2i(1, 1)


func _on_stamp(w: int, h: int, tiles: PackedInt32Array) -> void:
	if paint == null:
		return
	paint.set_stamp(w, h, tiles)
	if map_field:
		map_field.edit_stamp_size = Vector2i(w, h) if w * h > 1 else Vector2i(1, 1)
	if w * h > 1:
		_status.text = "图章 %d×%d" % [w, h]


func _on_palette_tileset(ts_id: String) -> void:
	if pack == null or current_map_id == "":
		return
	if pack.set_map_tileset(current_map_id, ts_id):
		_reload_field()
		_status.text = "图块套 %s" % ts_id


func _set_hover(cell: Vector2i) -> void:
	if map_field:
		map_field.edit_hover_cell = cell
		map_field.edit_cursor_cell = _cursor
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


func _selection_bounds() -> Array[Vector2i]:
	var a := _cursor
	var b := _cursor
	if paint and paint.rect_start.x >= 0:
		a = paint.rect_start
		if map_field and map_field.edit_rect_b.x >= 0:
			b = map_field.edit_rect_b
		else:
			b = a
	var out: Array[Vector2i] = []
	out.append(a)
	out.append(b)
	return out


func _copy_entity() -> bool:
	if doc == null or not doc.has_method("copy_entity_at"):
		return false
	var clip: Dictionary = doc.copy_entity_at(_cursor)
	if clip.is_empty():
		return false
	_entity_clip = clip
	if _inspector:
		_inspector.clip = clip.duplicate(true)
	_status.text = "已复制实体 %s @ %d,%d" % [str(clip.get("kind", "")), _cursor.x, _cursor.y]
	return true


func _paste_entity() -> bool:
	if doc == null or not doc.has_method("paste_entity_at"):
		return false
	var clip: Dictionary = _entity_clip
	if clip.is_empty() and _inspector:
		clip = _inspector.clip
	if clip.is_empty():
		_status.text = "没有可粘贴的实体"
		return false
	if not doc.paste_entity_at(clip, _cursor):
		return false
	_entity_clip = clip
	if pack:
		pack.dirty = true
	if _inspector:
		_inspector.clip = clip.duplicate(true)
		_inspector.load_cell(doc, _cursor)
	_reload_field()
	_status.text = "已粘贴实体 %s @ %d,%d" % [str(clip.get("kind", "")), _cursor.x, _cursor.y]
	return true


func _want_mcp_autostart() -> bool:
	var env := OS.get_environment("RMMO_EDITOR_MCP").strip_edges().to_lower()
	if env in ["1", "true", "yes", "on"]:
		return true
	for a in OS.get_cmdline_user_args():
		if str(a) == "--mcp":
			return true
	return false


func _toggle_mcp() -> void:
	if _mcp != null and bool(_mcp.running):
		_mcp.stop()
		if _mcp_popup:
			_mcp_popup.set_item_checked(_mcp_popup.get_item_index(MENU_MCP_TOGGLE), false)
		_status.text = "MCP 已关闭"
		return
	if _mcp == null:
		_mcp = EditorMcp.new()
		_mcp.editor = self
		add_child(_mcp)
	var info: Dictionary = _mcp.start()
	var on := bool(info.get("ok", false))
	if _mcp_popup:
		_mcp_popup.set_item_checked(_mcp_popup.get_item_index(MENU_MCP_TOGGLE), on)
	if on:
		var url := str(info.get("url", ""))
		DisplayServer.clipboard_set(url)
		_status.text = "MCP 已启用 · %s（已复制）" % url
	else:
		_status.text = "MCP 启动失败：%s" % str(info.get("error", "未知"))


func mcp_refresh(cell: Vector2i = Vector2i(-1, -1)) -> void:
	if cell.x >= 0:
		_cursor = cell
	if _inspector:
		_inspector.bind_pack(pack)
		if doc:
			_inspector.load_cell(doc, _cursor)
	_reload_field()
	if _tree:
		_refresh_tree()


func _copy_tiles() -> void:
	if doc == null or paint == null:
		return
	var bnds: Array[Vector2i] = _selection_bounds()
	paint.copy_rect(doc, bnds[0], bnds[1])
	var clip: Dictionary = paint.clipboard
	_status.text = "已复制 %d×%d" % [int(clip.get("w", 0)), int(clip.get("h", 0))]


func _cut_tiles() -> void:
	if doc == null or paint == null:
		return
	var bnds: Array[Vector2i] = _selection_bounds()
	var dirty: Array[Vector2i] = paint.cut_rect(doc, bnds[0], bnds[1])
	_refresh_dirty(dirty)
	var clip: Dictionary = paint.clipboard
	_status.text = "已剪切 %d×%d" % [int(clip.get("w", 0)), int(clip.get("h", 0))]


func _paste_tiles() -> void:
	if doc == null or paint == null:
		return
	if paint.clipboard.is_empty():
		_status.text = "剪贴板为空"
		return
	var dirty: Array[Vector2i] = paint.paste_at(doc, _cursor)
	_refresh_dirty(dirty)
	var clip: Dictionary = paint.clipboard
	_status.text = "已粘贴 %d×%d @ %d,%d" % [int(clip.get("w", 0)), int(clip.get("h", 0)), _cursor.x, _cursor.y]


func _erase_selection() -> void:
	if doc == null or paint == null:
		return
	var bnds: Array[Vector2i] = _selection_bounds()
	var dirty: Array[Vector2i] = paint.apply_rect(doc, bnds[0], bnds[1], true)
	_refresh_dirty(dirty)
	_status.text = "已清除选区"


func _select_all() -> void:
	if doc == null or paint == null:
		return
	_set_tool(PaintTools.Tool.SELECT)
	paint.rect_start = Vector2i.ZERO
	if map_field:
		map_field.edit_rect_a = Vector2i.ZERO
		map_field.edit_rect_b = Vector2i(doc.width - 1, doc.height - 1)
	_status.text = "已全选 %d×%d" % [doc.width, doc.height]


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


func _is_spec_paint() -> bool:
	return _spec_kind in ["meta", "settings", "shadow", "region"]


func _spec_read(cell: Vector2i) -> int:
	if doc == null:
		return 0
	match _spec_kind:
		"meta":
			return int(doc.ext_tile("meta", cell.x, cell.y))
		"settings":
			return int(doc.ext_tile("settings", cell.x, cell.y))
		"shadow":
			return int(doc.tile(cell.x, cell.y, 4)) & 0x0f
		"region":
			return int(doc.tile(cell.x, cell.y, 5))
		_:
			return 0


func _spec_brush_value() -> int:
	match _spec_kind:
		"meta":
			return _spec_meta_bit
		"settings":
			var light := int(_light_opt.get_item_id(_light_opt.selected)) if _light_opt and _light_opt.item_count > 0 else 0
			var sound := int(_sound_opt.get_item_id(_sound_opt.selected)) if _sound_opt and _sound_opt.item_count > 0 else 0
			var foot := int(_foot_opt.get_item_id(_foot_opt.selected)) if _foot_opt and _foot_opt.item_count > 0 else 0
			return MapExt.pack_settings(light, sound, foot)
		"shadow":
			return _spec_shadow
		"region":
			return int(_region_spin.value) if _region_spin else 1
		_:
			return 0


func _spec_write(cell: Vector2i, erase: bool) -> void:
	if doc == null:
		return
	var cur := _spec_read(cell)
	var nxt := 0
	if _spec_kind == "meta":
		if erase:
			nxt = cur & ~_spec_meta_bit
		else:
			nxt = cur | _spec_meta_bit
			if _spec_meta_bit == MapExt.META_FORCE_BLOCK:
				nxt &= ~MapExt.META_FORCE_PASS
			elif _spec_meta_bit == MapExt.META_FORCE_PASS:
				nxt &= ~MapExt.META_FORCE_BLOCK
		if nxt != cur:
			doc.set_ext_tile("meta", cell.x, cell.y, nxt)
	elif _spec_kind == "settings":
		nxt = 0 if erase else _spec_brush_value()
		if nxt != cur:
			doc.set_ext_tile("settings", cell.x, cell.y, nxt)
	elif _spec_kind == "shadow":
		nxt = 0 if erase else (_spec_shadow & 0x0f)
		if nxt != cur:
			doc.set_tile(cell.x, cell.y, 4, nxt)
	elif _spec_kind == "region":
		nxt = 0 if erase else _spec_brush_value()
		if nxt != cur:
			doc.set_tile(cell.x, cell.y, 5, nxt)


func _paint_spec(cell: Vector2i, erase: bool) -> void:
	if doc == null or cell.x < 0 or cell.y < 0 or cell.x >= doc.width or cell.y >= doc.height:
		return
	_spec_write(cell, erase)
	var dirty: Array[Vector2i] = [cell]
	_refresh_dirty(dirty)


func _spec_rect(a: Vector2i, b: Vector2i, erase: bool) -> void:
	if doc == null:
		return
	if doc.has_method("begin_undo_batch"):
		doc.begin_undo_batch()
	var dirty: Array[Vector2i] = []
	var x0 := mini(a.x, b.x)
	var x1 := maxi(a.x, b.x)
	var y0 := mini(a.y, b.y)
	var y1 := maxi(a.y, b.y)
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var c := Vector2i(x, y)
			_spec_write(c, erase)
			dirty.append(c)
	if doc.has_method("end_undo_batch"):
		doc.end_undo_batch()
	_refresh_dirty(dirty)


func _spec_fill(start: Vector2i, erase: bool) -> void:
	if doc == null:
		return
	var target := _spec_read(start)
	if doc.has_method("begin_undo_batch"):
		doc.begin_undo_batch()
	var stack: Array[Vector2i] = [start]
	var seen := {}
	var dirty: Array[Vector2i] = []
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		var key := "%d,%d" % [c.x, c.y]
		if seen.has(key):
			continue
		seen[key] = true
		if c.x < 0 or c.y < 0 or c.x >= doc.width or c.y >= doc.height:
			continue
		if _spec_read(c) != target:
			continue
		_spec_write(c, erase)
		dirty.append(c)
		stack.append(c + Vector2i(1, 0))
		stack.append(c + Vector2i(-1, 0))
		stack.append(c + Vector2i(0, 1))
		stack.append(c + Vector2i(0, -1))
	if doc.has_method("end_undo_batch"):
		doc.end_undo_batch()
	_refresh_dirty(dirty)


func _spec_eyedrop(cell: Vector2i) -> void:
	var v := _spec_read(cell)
	match _spec_kind:
		"meta":
			if v != 0:
				if (v & MapExt.META_INDOOR) != 0:
					_spec_meta_bit = MapExt.META_INDOOR
				elif (v & MapExt.META_WATER) != 0:
					_spec_meta_bit = MapExt.META_WATER
				elif (v & MapExt.META_NO_DASH) != 0:
					_spec_meta_bit = MapExt.META_NO_DASH
				if _meta_box:
					for c in _meta_box.get_children():
						if c is Button:
							c.set_pressed_no_signal(int(c.get_meta("bit", 0)) == _spec_meta_bit)
		"settings":
			var light := v & 0xff
			var sound := (v >> 8) & 0xff
			var foot := (v >> 16) & 0xff
			_select_opt_id(_light_opt, light)
			_select_opt_id(_sound_opt, sound)
			_select_opt_id(_foot_opt, foot)
		"shadow":
			_spec_shadow = v & 0x0f
			if _shadow_box:
				for c in _shadow_box.get_children():
					if c is Button:
						c.set_pressed_no_signal(((_spec_shadow & int(c.get_meta("bit", 0))) != 0))
		"region":
			if _region_spin:
				_region_spin.value = v
	_status.text = "取样 %s = %d" % [_spec_kind, v]


func _on_toolbar_light() -> void:
	EditorAtmosphere.on_toolbar_light(self)
func _sync_light_controls() -> void:
	EditorAtmosphere.sync_light_controls(self)
func _apply_editor_light() -> void:
	EditorAtmosphere.apply_editor_light(self)
func _on_toolbar_weather() -> void:
	EditorAtmosphere.on_toolbar_weather(self)
func _apply_editor_atmosphere() -> void:
	EditorAtmosphere.apply_editor_atmosphere(self)
func _on_fx_color_changed(c: Color) -> void:
	EditorAtmosphere.on_fx_color_changed(self, c)
func _sync_fx_color_controls() -> void:
	EditorAtmosphere.sync_fx_color_controls(self)
func _apply_editor_fx_color() -> void:
	EditorAtmosphere.apply_editor_fx_color(self)
func _select_opt_id(opt: OptionButton, id: int) -> void:
	EditorAtmosphere.select_opt_id(self, opt, id)
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
	# EXPAND grows the 2D layout with the window (KEEP letterboxes the project viewport).
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
	EditorCanvas.fit_layout(self)
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
		_status.text = "事件模式：点击格子编辑事件/NPC/传送"
	else:
		_status.text = "地图模式"


func _set_tool(tool_id: int) -> void:
	paint.tool = tool_id
	_placing_start = false
	_poly_pts.clear()
	if tool_id != PaintTools.Tool.SELECT and tool_id != PaintTools.Tool.RECT and tool_id != PaintTools.Tool.LINE and tool_id != PaintTools.Tool.ELLIPSE and tool_id != PaintTools.Tool.RING:
		paint.rect_start = Vector2i(-1, -1)
		if map_field:
			map_field.edit_rect_a = Vector2i(-1, -1)
			map_field.edit_rect_b = Vector2i(-1, -1)
	if _start_btn:
		_start_btn.set_pressed_no_signal(false)
	if tool_id == PaintTools.Tool.SELECT:
		_status.text = "选区：拖拽后 Ctrl+C 复制、Ctrl+X 剪切、Ctrl+V 粘贴、Delete 清除"
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
	EditorCanvas.set_zoom(self, z)
func _zoom_at(local_pos: Vector2, z: float) -> void:
	EditorCanvas.zoom_at(self, local_pos, z)
func _zoom_fit() -> void:
	EditorCanvas.zoom_fit(self)
func _mouse_world(pos: Vector2) -> Vector2:
	return EditorCanvas.mouse_world(self, pos)
func _clamp_camera() -> void:
	EditorCanvas.clamp_camera(self)
func _sync_scrollbars() -> void:
	EditorCanvas.sync_scrollbars(self)
func _canvas_wheel_scroll(horizontal: bool, toward_positive: bool) -> void:
	EditorCanvas.canvas_wheel_scroll(self, horizontal, toward_positive)
func _canvas_pan_pixels(delta: Vector2) -> void:
	EditorCanvas.canvas_pan_pixels(self, delta)
func _on_hscroll(v: float) -> void:
	EditorCanvas.on_hscroll(self, v)
func _on_vscroll(v: float) -> void:
	EditorCanvas.on_vscroll(self, v)
func _map_status_line() -> String:
	return EditorCanvas.map_status_line(self)
func _update_edit_observer() -> void:
	EditorCanvas.update_edit_observer(self)
func _rebuild_minimap() -> void:
	if _minimap == null or map_field == null or doc == null:
		return
	if _palette != null and _palette.sheets.size() > 0 and map_field.pack != null:
		map_field.pack.sheets = _palette.sheets
		if _palette._flags.size() > 0:
			map_field.pack.flags = _palette._flags
	_minimap.rebuild(map_field, doc)
	_sync_minimap_view()


func _schedule_minimap(cells: Array = []) -> void:
	if _minimap == null:
		return
	if cells.size() > 0 and cells.size() <= 80 and _minimap.has_method("patch_cells"):
		_minimap.patch_cells(map_field, cells)
		_sync_minimap_view()
		return
	if _minimap_timer:
		_minimap_timer.start()


func _sync_minimap_view() -> void:
	if _minimap == null or _cam == null or _vp == null:
		return
	var z := maxf(_zoom, 0.05)
	var view := Vector2(float(_vp.size.x) / z, float(_vp.size.y) / z)
	_minimap.set_view_world(Rect2(_cam.position - view * 0.5, view))
	if map_field != null and map_field.has_method("current_chunk_rect") and _minimap.has_method("set_chunk_world"):
		var cr: Rect2i = map_field.current_chunk_rect()
		var ts := float(maxi(int(doc.tile_size) if doc else 48, 1))
		_minimap.set_chunk_world(Rect2(Vector2(cr.position) * ts, Vector2(cr.size) * ts))


func _on_minimap_jump(world: Vector2) -> void:
	if _cam == null:
		return
	_cam.position = world
	_clamp_camera()
	_sync_scrollbars()
	_update_edit_observer()


func _toggle_pass_overlay() -> void:
	if map_field == null:
		return
	var on := true
	if _pass_overlay_btn:
		on = bool(_pass_overlay_btn.button_pressed)
	map_field.edit_passage_overlay = on
	map_field.queue_redraw()
	var ov: Node = map_field.get_node_or_null("EditOverlay")
	if ov:
		ov.queue_redraw()
	_status.text = "叠通行 " + ("开" if on else "关")


func _commit_shape(a: Vector2i, b: Vector2i, erase: bool) -> void:
	if doc == null or paint == null:
		return
	var cells: Array[Vector2i] = []
	match int(paint.tool):
		PaintTools.Tool.LINE:
			cells = MapShapes.line_cells(a, b)
		PaintTools.Tool.ELLIPSE:
			var rx := absi(b.x - a.x)
			var ry := absi(b.y - a.y)
			cells = MapShapes.ellipse_cells(a.x, a.y, rx, ry, true)
		PaintTools.Tool.RING:
			var r := maxi(absi(b.x - a.x), absi(b.y - a.y))
			cells = MapShapes.ring_cells(a.x, a.y, r, r, 1, [])
		_:
			return
	var dirty: Array[Vector2i] = paint.apply_cells(doc, cells, erase)
	_refresh_dirty(dirty)
	_status.text = "形状 %d 格" % dirty.size()


func _commit_polyline(erase: bool) -> void:
	if _poly_pts.size() < 1 or doc == null:
		_poly_pts.clear()
		return
	var cells: Array[Vector2i] = MapShapes.polyline_cells(_poly_pts, 1)
	_poly_pts.clear()
	var dirty: Array[Vector2i] = paint.apply_cells(doc, cells, erase)
	_refresh_dirty(dirty)
	_status.text = "折线 %d 格" % dirty.size()


func _rotate_clip(cw: bool) -> void:
	if paint:
		paint.rotate_clipboard(cw)
		_status.text = "剪贴板已旋转 %d×%d" % [int(paint.clipboard.get("w", 0)), int(paint.clipboard.get("h", 0))]


func _flip_clip(horizontal: bool) -> void:
	if paint:
		paint.flip_clipboard(horizontal)
		_status.text = "剪贴板已翻转"


func _replace_prompt() -> void:
	if doc == null or paint == null:
		return
	var old_id := int(paint.tile_id)
	var dlg := ConfirmationDialog.new()
	dlg.title = "替换图块"
	dlg.dialog_text = "把当前层中与图块 %d（%s）同类的格子换成新 id。\n在调色板选好目标图块后确定。" % [old_id, TileLabels.label_of(old_id)]
	dlg.confirmed.connect(func():
		var dirty: Array[Vector2i] = paint.replace_id(doc, old_id, int(paint.tile_id), true)
		_refresh_dirty(dirty)
		_status.text = "已替换 %d 格" % dirty.size()
		dlg.queue_free()
	)
	add_child(dlg)
	dlg.popup_centered()


func _show_undo_list() -> void:
	if _undo_dlg == null:
		_undo_dlg = AcceptDialog.new()
		_undo_dlg.title = "撤销历史"
		_undo_list = ItemList.new()
		_undo_list.custom_minimum_size = Vector2(320, 240)
		_undo_dlg.add_child(_undo_list)
		add_child(_undo_dlg)
	_undo_list.clear()
	if doc == null:
		_undo_dlg.popup_centered()
		return
	var stack: Array = doc.get("_undo") if "_undo" in doc else []
	_undo_list.add_item("共 %d 步（最近在上）" % stack.size())
	for i in range(stack.size() - 1, maxi(stack.size() - 16, -1), -1):
		if i < 0:
			break
		var cmd: Dictionary = stack[i] if typeof(stack[i]) == TYPE_DICTIONARY else {}
		var n: int = doc._cmd_cells(cmd).size() if doc.has_method("_cmd_cells") else 0
		_undo_list.add_item("%s · %d 格" % [str(cmd.get("t", "?")), n])
	_undo_dlg.popup_centered()


func _pick_reference() -> void:
	_file_mode = "reference"
	_pick_file(false)


func _clear_reference() -> void:
	if map_field and map_field.has_method("set_reference_image"):
		map_field.set_reference_image("", 0.0)
	_status.text = "已清除参考图"


func _add_bookmark_here() -> void:
	if doc == null:
		return
	if not ("bookmarks" in doc):
		doc.bookmarks = []
	var name := "点%d" % (doc.bookmarks.size() + 1)
	doc.bookmarks.append({"name": name, "x": _cursor.x, "y": _cursor.y})
	doc.dirty = true
	_refresh_bookmarks()
	_status.text = "书签 %s @ %d,%d" % [name, _cursor.x, _cursor.y]


func _refresh_bookmarks() -> void:
	if _bm_opt == null:
		return
	_bm_opt.clear()
	_bm_opt.add_item("书签")
	if doc == null or not ("bookmarks" in doc):
		return
	for bm in doc.bookmarks:
		if typeof(bm) == TYPE_DICTIONARY:
			_bm_opt.add_item("%s (%d,%d)" % [str(bm.get("name", "")), int(bm.get("x", 0)), int(bm.get("y", 0))])


func _on_bookmark_sel(idx: int) -> void:
	if idx <= 0 or doc == null or not ("bookmarks" in doc):
		return
	var bm: Dictionary = doc.bookmarks[idx - 1] if idx - 1 < doc.bookmarks.size() else {}
	if bm.is_empty():
		return
	_cursor = Vector2i(int(bm.get("x", 0)), int(bm.get("y", 0)))
	if _cam and doc:
		_cam.position = Vector2((float(_cursor.x) + 0.5) * float(doc.tile_size), (float(_cursor.y) + 0.5) * float(doc.tile_size))
		_clamp_camera()
		_sync_scrollbars()
