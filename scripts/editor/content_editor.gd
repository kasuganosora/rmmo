extends Control
class_name ContentEditor
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
const EditorMinimapBridge = preload("res://scripts/editor/interface/editor_minimap_bridge.gd")
const EditorSession = preload("res://scripts/editor/application/editor_session.gd")
const AtmosphereModule = preload("res://scripts/editor/field/atmosphere_module.gd")
const EntityModule = preload("res://scripts/editor/field/entity_module.gd")
const AssetModule = preload("res://scripts/editor/field/asset_module.gd")
const McpModule = preload("res://scripts/editor/field/mcp_module.gd")
const SpecModule = preload("res://scripts/editor/field/spec_module.gd")
const TreeModule = preload("res://scripts/editor/field/tree_module.gd")
const TilesetModule = preload("res://scripts/editor/field/tileset_module.gd")
const MenuDialogModule = preload("res://scripts/editor/field/menu_dialog_module.gd")
const CanvasModule = preload("res://scripts/editor/field/canvas_module.gd")
var _canvas_module_logic: CanvasModule = CanvasModule.new(self)
var _menu_dialog_module_logic: MenuDialogModule = MenuDialogModule.new(self)
var _tileset_module_logic: TilesetModule = TilesetModule.new(self)
var _tree_module_logic: TreeModule = TreeModule.new(self)
var _spec_module_logic: SpecModule = SpecModule.new(self)
var _mcp_module_logic: McpModule = McpModule.new(self)
var _asset_module_logic: AssetModule = AssetModule.new(self)
var _entity_module_logic: EntityModule = EntityModule.new(self)
var _atmosphere_module_logic: AtmosphereModule = AtmosphereModule.new(self)

var session := EditorSession.new()
var pack: RefCounted:
	get:
		return session.pack
	set(v):
		session.pack = v
var doc: RefCounted:
	get:
		return session.doc
	set(v):
		session.doc = v
var current_map_id: String:
	get:
		return session.current_map_id
	set(v):
		session.current_map_id = v
var paint: RefCounted:
	get:
		return session.paint
	set(v):
		session.paint = v
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
	_tree_module_logic._exit_tree()
func _unhandled_input(event: InputEvent) -> void:
	_canvas_module_logic._unhandled_input(event)
func _mark_handled() -> void:
	_canvas_module_logic._mark_handled()
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
	_menu_dialog_module_logic._add_popup(bar, title, items)
func _on_menu(id: int) -> void:
	_menu_dialog_module_logic._on_menu(id)
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
	EditorSession.open_or_create_default(self)


func _new_pack() -> void:
	EditorSession.new_pack(self)


func _save() -> void:
	EditorSession.save(self)


func _leave() -> void:
	EditorSession.leave(self)


func _playtest(from_cursor: bool = false) -> void:
	EditorSession.playtest(self, from_cursor)


func _select_map(id: String) -> void:
	EditorSession.select_map(self, id)


func _do_select_map(id: String) -> void:
	EditorSession.do_select_map(self, id)


func _confirm_switch_save() -> void:
	EditorSession.confirm_switch_save(self)


func _unsaved_action(action: String) -> void:
	EditorSession.unsaved_action(self, action)


func _open_pack_dialog() -> void:
	_menu_dialog_module_logic._open_pack_dialog()
func _confirm_open_pack() -> void:
	_menu_dialog_module_logic._confirm_open_pack()
func _confirm_save_as() -> void:
	EditorSession.confirm_save_as(self)


func _open_demo_copy() -> void:
	EditorSession.open_demo_copy(self)


func _on_reparent(src: String, parent: String) -> void:
	EditorSession.on_reparent(self, src, parent)



func _popup_win(win: Window) -> void:
	_menu_dialog_module_logic._popup_win(win)
func _open_asset_win() -> void:
	_asset_module_logic._open_asset_win()
func _open_tileset_win() -> void:
	_tileset_module_logic._open_tileset_win()
func _on_tileset_catalog() -> void:
	_tileset_module_logic._on_tileset_catalog()
func _on_tileset_apply(ts_id: String) -> void:
	_tileset_module_logic._on_tileset_apply(ts_id)
func _open_entity_win() -> void:
	_entity_module_logic._open_entity_win()
func _on_rm_slot(slot: int, sheet: String) -> void:
	if pack == null or doc == null:
		return
	var ts_id := str(doc.tileset_id)
	if pack.set_tileset_slot(ts_id, slot, sheet):
		EditorSession.finish_sheet_assign(self, slot, sheet)


func _on_assets_changed() -> void:
	_asset_module_logic._on_assets_changed()
func _reload_assets() -> void:
	EditorSession.reload_assets(self)


func _on_entity_changed() -> void:
	_entity_module_logic._on_entity_changed()
func _on_entity_jump(c: Vector2i) -> void:
	_entity_module_logic._on_entity_jump(c)
func _refresh_tree() -> void:
	_tree_module_logic._refresh_tree()
func _fill_tree(parent_item: TreeItem, parent_id: String, by_parent: Dictionary) -> void:
	_tree_module_logic._fill_tree(parent_item, parent_id, by_parent)
func _on_tree_sel() -> void:
	_tree_module_logic._on_tree_sel()
func _on_tree_mouse(pos: Vector2, button: int) -> void:
	_tree_module_logic._on_tree_mouse(pos, button)
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
	EditorSession.add_child_map(self)


func _del_map() -> void:
	EditorSession.del_map(self)


func _ask_del_map(mid: String) -> void:
	EditorSession.ask_del_map(self, mid)


func _confirm_del_map() -> void:
	EditorSession.confirm_del_map(self)


func _set_start_map(mid: String) -> void:
	EditorSession.set_start_map(self, mid)



func _open_map_settings(mid: String) -> void:
	EditorSession.open_map_settings(self, mid)


func _apply_map_settings() -> void:
	EditorSession.apply_map_settings(self)


func _fix_autotiles() -> void:
	EditorSession.fix_autotiles(self)


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
	_tree_module_logic._fill_layer_tree()
func _sync_shadow_brush() -> void:
	var bits := 0
	if _shadow_box == null:
		return
	for c in _shadow_box.get_children():
		if c is Button and c.button_pressed:
			bits |= int(c.get_meta("bit", 0))
	_spec_shadow = bits


func _fill_preset_opt(opt: OptionButton, path: String, fallback: PackedStringArray) -> void:
	_tileset_module_logic._fill_preset_opt(opt, path, fallback)
func _fill_bgm_opt(current: String) -> void:
	_atmosphere_module_logic._fill_bgm_opt(current)
func _set_far_scroll(x: float, y: float) -> void:
	_canvas_module_logic._set_far_scroll(x, y)
func _on_layer_tree() -> void:
	_tree_module_logic._on_layer_tree()
func _sync_spec_panel(spec: String, layer_name: String) -> void:
	_spec_module_logic._sync_spec_panel(spec, layer_name)
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
	_canvas_module_logic._on_canvas_input(event)
func _sync_vp_size() -> void:
	EditorCanvas.sync_vp_size(self)
func _mouse_cell(pos: Vector2) -> Vector2i:
	return _canvas_module_logic._mouse_cell(pos)
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
	_menu_dialog_module_logic._on_file(path)
func _add_chest_event() -> void:
	_entity_module_logic._add_chest_event()
func _import_asset(src: String, kind: String) -> void:
	_asset_module_logic._import_asset(src, kind)
func _finish_sheet_assign(slot: int, sheet: String) -> void:
	_tileset_module_logic._finish_sheet_assign(slot, sheet)
func _sync_palette() -> void:
	_tileset_module_logic._sync_palette()
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
	_canvas_module_logic._set_hover(cell)
func _undo_edit() -> void:
	_menu_dialog_module_logic._undo_edit()
func _redo_edit() -> void:
	_menu_dialog_module_logic._redo_edit()
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
	return _mcp_module_logic._want_mcp_autostart()
func _toggle_mcp() -> void:
	_mcp_module_logic._toggle_mcp()
func mcp_refresh(cell: Vector2i = Vector2i(-1, -1)) -> void:
	_mcp_module_logic.mcp_refresh(cell)
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
	EditorSession.dup_map(self, mid)


func _open_rename(mid: String) -> void:
	EditorSession.open_rename(self, mid)


func _apply_rename() -> void:
	EditorSession.apply_rename(self)


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
	return _spec_module_logic._spec_read(cell)
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
	_spec_module_logic._spec_write(cell, erase)
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
	_spec_module_logic._spec_eyedrop(cell)
func _on_toolbar_light() -> void:
	_atmosphere_module_logic._on_toolbar_light()
func _sync_light_controls() -> void:
	_atmosphere_module_logic._sync_light_controls()
func _apply_editor_light() -> void:
	_atmosphere_module_logic._apply_editor_light()
func _on_toolbar_weather() -> void:
	_atmosphere_module_logic._on_toolbar_weather()
func _apply_editor_atmosphere() -> void:
	_atmosphere_module_logic._apply_editor_atmosphere()
func _on_fx_color_changed(c: Color) -> void:
	_atmosphere_module_logic._on_fx_color_changed(c)
func _sync_fx_color_controls() -> void:
	_atmosphere_module_logic._sync_fx_color_controls()
func _apply_editor_fx_color() -> void:
	_atmosphere_module_logic._apply_editor_fx_color()
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
	_canvas_module_logic._set_zoom(z)
func _zoom_at(local_pos: Vector2, z: float) -> void:
	_canvas_module_logic._zoom_at(local_pos, z)
func _zoom_fit() -> void:
	_canvas_module_logic._zoom_fit()
func _mouse_world(pos: Vector2) -> Vector2:
	return EditorCanvas.mouse_world(self, pos)
func _clamp_camera() -> void:
	_canvas_module_logic._clamp_camera()
func _sync_scrollbars() -> void:
	_canvas_module_logic._sync_scrollbars()
func _canvas_wheel_scroll(horizontal: bool, toward_positive: bool) -> void:
	_canvas_module_logic._canvas_wheel_scroll(horizontal, toward_positive)
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
	EditorMinimapBridge.rebuild_minimap(self)
func _schedule_minimap(cells: Array = []) -> void:
	EditorMinimapBridge.schedule_minimap(self, cells)
func _sync_minimap_view() -> void:
	EditorMinimapBridge.sync_minimap_view(self)
func _on_minimap_jump(world: Vector2) -> void:
	EditorMinimapBridge.on_minimap_jump(self, world)
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
	_entity_module_logic._replace_prompt()
func _show_undo_list() -> void:
	_menu_dialog_module_logic._show_undo_list()
func _pick_reference() -> void:
	_file_mode = "reference"
	_pick_file(false)


func _clear_reference() -> void:
	if map_field and map_field.has_method("set_reference_image"):
		map_field.set_reference_image("", 0.0)
	_status.text = "已清除参考图"


func _add_bookmark_here() -> void:
	_menu_dialog_module_logic._add_bookmark_here()
func _refresh_bookmarks() -> void:
	EditorMinimapBridge.refresh_bookmarks(self)
func _on_bookmark_sel(idx: int) -> void:
	EditorMinimapBridge.on_bookmark_sel(self, idx)
