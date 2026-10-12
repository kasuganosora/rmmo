extends RefCounted
## U2U-style library and canvas; resource-pack maps open in a separate window.
const Style = preload("res://scripts/world_editor/workspace_theme.gd")
const Typography = preload("res://scripts/world_editor/workspace_typography.gd")

static func button(parent: Node, text: String, action: Callable) -> Button:
	var control := Button.new()
	control.text = text
	control.focus_mode = Control.FOCUS_ALL
	control.pressed.connect(action)
	parent.add_child(control)
	return control


static func build(editor: Node3D) -> void:
	var measured:=Time.get_ticks_usec()
	var startup:Dictionary={}
	var profile:bool=editor.has_meta("profile_startup")
	var layer := CanvasLayer.new()
	editor.add_child(layer)
	var panel := PanelContainer.new()
	panel.name = "ContentWorkspace"
	panel.theme = Style.build()
	Typography.apply(panel,clampi(int(editor._workspace_preferences.read("font_size", 14)), 14, 18))
	panel.add_theme_stylebox_override("panel", Style.panel(Color("1f2026"), 0))
	layer.add_child(panel)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var root := VBoxContainer.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_theme_constant_override("separation", 0)
	panel.add_child(root)
	var menubar := HBoxContainer.new()
	root.add_child(menubar)
	var file := MenuButton.new()
	file.text = "文件"
	menubar.add_child(file)
	for label in ["资源包地图…", "保存  Ctrl+S", "另存为…", "恢复上次保存…", "返回登录…", "保存草稿", "恢复草稿…", "自动草稿设置…"]: file.get_popup().add_item(label)
	file.get_popup().id_pressed.connect(func(id: int):
		match id:
			0: editor._open_pack_maps()
			1: editor._save_async()
			2: editor._file_dialog(true)
			3: editor._restore_previous()
			4: editor._request_exit()
			5:
				editor._finish_edits()
				var result: Dictionary = editor._safety.save_draft()
				editor._report_result(result,"草稿已保存，正式地图未修改","保存草稿")
			6: editor._safety.show_recovery()
			7: preload("res://scripts/world_editor/recovery_panel.gd").show_settings(editor)
	)
	var edit_menu := MenuButton.new()
	edit_menu.text = "编辑"
	menubar.add_child(edit_menu)
	edit_menu.get_popup().add_item("撤销  Ctrl+Z", 0)
	edit_menu.get_popup().add_item("复制物件  Ctrl+D", 1)
	edit_menu.get_popup().add_item("重做  Ctrl+Y / Ctrl+Shift+Z", 2)
	edit_menu.get_popup().add_item("成组  Ctrl+G", 3)
	edit_menu.get_popup().add_item("解组  Ctrl+Shift+G", 4)
	edit_menu.get_popup().add_item("保存预制件…", 5)
	edit_menu.get_popup().add_separator()
	edit_menu.get_popup().add_item("摆放与排列…", 6)
	edit_menu.get_popup().add_item("向下贴地  End", 7)
	edit_menu.get_popup().add_item("贴地并贴合坡面  Shift+End", 8)
	edit_menu.get_popup().add_item("点选表面放置  V", 9)
	edit_menu.get_popup().add_item("表面材质笔刷…", 10)
	edit_menu.get_popup().id_pressed.connect(func(id: int):
		if id == 0: editor._undo()
		elif id == 1: editor._duplicate_selected()
		elif id == 2: editor._redo()
		elif id == 3: editor._selection_tools.group()
		elif id == 4: editor._selection_tools.ungroup()
		elif id == 5: editor._save_prefab_dialog()
		elif id == 6: editor._show_placement_panel()
		elif id == 7: editor._placement_tools.report(editor._placement_tools.drop_selection())
		elif id == 8: editor._placement_tools.report(editor._placement_tools.drop_selection(true))
		elif id == 9: editor._placement_tools.begin_surface()
		elif id == 10: editor._dock_tabs.current_tab = 3
	)
	var view_menu := MenuButton.new()
	view_menu.text = "视图"
	menubar.add_child(view_menu)
	for text in ["素材库", "物件属性", "显示 / 隐藏网格", "俯视", "场景物件列表"]: view_menu.get_popup().add_item(text)
	view_menu.get_popup().add_item("恢复侧栏标准宽度", 5)
	view_menu.get_popup().add_separator("界面文字")
	for index in 3:
		view_menu.get_popup().add_radio_check_item(["标准 · 14", "较大 · 16", "大 · 18"][index], 20 + index)
		view_menu.get_popup().set_item_checked(view_menu.get_popup().item_count - 1, panel.theme.default_font_size == 14 + index * 2)
	view_menu.get_popup().id_pressed.connect(func(id: int):
		match id:
			0: editor._dock_tabs.current_tab = 0
			1: editor._dock_tabs.current_tab = 1
			2: editor._grid.visible = not editor._grid.visible
			3: editor._top_view()
			4: editor._dock_tabs.current_tab = 2
			5: editor.find_child("WorkspaceSplit",true,false).split_offset = 330; editor._workspace_preferences.write("dock_width",330)
			20, 21, 22:
				Typography.apply(panel,14 + (id - 20) * 2)
				editor._workspace_preferences.write("font_size", panel.theme.default_font_size)
				for index in 3: view_menu.get_popup().set_item_checked(view_menu.get_popup().get_item_index(20 + index), id == 20 + index)
	)
	var resource_menu := MenuButton.new(); resource_menu.name = "WorkspaceResourcesMenu"
	resource_menu.text = "资源"; menubar.add_child(resource_menu)
	resource_menu.get_popup().add_item("导入模型…", 0)
	resource_menu.get_popup().add_item("素材管理…", 1)
	resource_menu.get_popup().add_item("重新生成选中素材缩略图", 2)
	resource_menu.get_popup().id_pressed.connect(func(id: int):
		if id == 0: editor._import_asset()
		elif id == 1: editor._manage_asset()
		elif id == 2:
			var ops=preload("res://scripts/world_editor/mcp_ops.gd").new(); ops.editor=editor
			var result: Dictionary=ops.repair_thumbnails([ops.asset_id(editor._selected())])
			editor._report_result(result,"已排队生成缩略图","素材缩略图")
	)
	var play_menu := MenuButton.new(); play_menu.name = "WorkspacePlayMenu"
	play_menu.text = "试玩"; menubar.add_child(play_menu)
	play_menu.get_popup().add_item("临时试玩  F5", 0)
	play_menu.get_popup().set_item_tooltip(0, "使用当前未保存内容的副本，不修改正式地图")
	play_menu.get_popup().add_item("楼层与出生点设置…", 1)
	play_menu.get_popup().id_pressed.connect(func(id: int):
		if id == 0: editor._play()
		elif id == 1: editor._dock_tabs.current_tab = 7
	)
	var service_menu := MenuButton.new()
	service_menu.text = "工具"
	menubar.add_child(service_menu)
	editor._mcp_popup = service_menu.get_popup()
	editor._mcp_popup.add_check_item("启用 3D MCP", 0)
	editor._mcp_popup.add_item("复制 MCP 地址", 1)
	editor._mcp_popup.set_item_disabled(1, true)
	editor._mcp_popup.id_pressed.connect(func(id: int):
		if id == 0: editor._toggle_mcp()
		elif id == 1: editor._copy_mcp_url()
	)
	menubar.add_spacer(false)
	var document_title := Label.new(); document_title.name = "WorkspaceDocumentTitle"
	document_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	document_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	menubar.add_child(document_title)
	editor._recovery_button = button(menubar, "恢复草稿", func(): editor._safety.show_recovery())
	editor._recovery_button.visible = false
	editor._workspace_feedback = preload("res://scripts/world_editor/workspace_feedback.gd").new()
	root.add_child(editor._workspace_feedback)
	editor._workspace_feedback.setup(editor, document_title)
	var scene_toolbar := PanelContainer.new(); scene_toolbar.name = "SceneToolbar"
	root.add_child(scene_toolbar)
	var scene_actions := HFlowContainer.new(); scene_actions.name = "SceneToolbarActions"
	scene_toolbar.add_child(scene_actions)
	var split := HSplitContainer.new()
	split.name = "WorkspaceSplit"
	split.split_offset = clampi(int(editor._workspace_preferences.read("dock_width", 330)), 310, 440)
	var constrain_dock := func():
		# Keep a usable scene beside forms even after resizing a previously wide window.
		var maximum := maxi(310, mini(520, int(split.size.x * 0.45)))
		if split.split_offset > maximum: split.split_offset = maximum
	split.resized.connect(func(): constrain_dock.call_deferred())
	var layout_save := Timer.new(); layout_save.one_shot = true; layout_save.wait_time = 0.5
	editor.add_child(layout_save)
	split.dragged.connect(func(_offset): constrain_dock.call(); layout_save.start())
	layout_save.timeout.connect(func(): editor._workspace_preferences.write("dock_width", split.split_offset))
	split.mouse_filter = Control.MOUSE_FILTER_IGNORE
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)
	var label: Label
	editor._dock_tabs = TabContainer.new()
	editor._dock_tabs.custom_minimum_size = Vector2(310, 280)
	editor._dock_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var dock := VBoxContainer.new(); dock.name = "WorkspaceDock"
	dock.custom_minimum_size.x = 310
	split.add_child(dock)
	var task_nav := HFlowContainer.new(); task_nav.name = "WorkspaceTaskNavigation"
	dock.add_child(task_nav)
	var task_group := ButtonGroup.new()
	for entry in [["素材", 0], ["属性", 1], ["地形", 10], ["建筑", 8], ["城镇", 9], ["城防", 11]]:
		var task := button(task_nav, entry[0], func(): editor._dock_tabs.current_tab = entry[1])
		task.toggle_mode = true; task.button_group = task_group
		task.set_meta("tab_index", entry[1])
	var navigator := MenuButton.new(); navigator.name = "WorkspacePanelPicker"; navigator.text = "更多"
	navigator.tooltip_text = "全部工作面板，包括物件列表、材质、事件与环境"
	task_nav.add_child(navigator)
	dock.add_child(editor._dock_tabs)
	editor._dock_tabs.tabs_visible = false
	navigator.get_popup().id_pressed.connect(func(index): editor._dock_tabs.current_tab = index)
	editor._dock_tabs.tab_changed.connect(func(index):
		for item in navigator.get_popup().item_count: navigator.get_popup().set_item_checked(item, item == index)
		for task in task_nav.get_children():
			if task.has_meta("tab_index"): task.set_pressed_no_signal(task.get_meta("tab_index") == index)
		navigator.text = "更多" if index in [0,1,8,9,10,11] else editor._dock_tabs.get_tab_title(index)
	)
	var library := VBoxContainer.new()
	library.name = "素材"
	editor._dock_tabs.add_child(library)
	var search := LineEdit.new()
	search.placeholder_text = "搜索素材 / 分类"
	search.clear_button_enabled = true
	editor._search_timer = Timer.new()
	editor._search_timer.one_shot = true
	editor._search_timer.wait_time = 0.18
	editor.add_child(editor._search_timer)
	search.text_changed.connect(func(_text): editor._search_timer.start())
	editor._search_timer.timeout.connect(func(): editor._on_search(search.text))
	library.add_child(search)
	editor._asset_category_picker = OptionButton.new()
	editor._asset_category_picker.name = "AssetCategory"
	library.add_child(editor._asset_category_picker)
	editor._asset_category_picker.item_selected.connect(func(index):
		editor._asset_category = str(editor._asset_category_picker.get_item_metadata(index))
		editor._pick = 0
		editor._refresh_palette()
	)
	var assets := HBoxContainer.new()
	library.add_child(assets)
	label = Label.new()
	label.text = "物件 / 基础模块"
	assets.add_child(label)
	assets.add_spacer(false)
	button(assets, "导入…", editor._import_asset)
	editor._palette = preload("res://scripts/world_editor/asset_palette.gd").new()
	editor._palette.size_flags_vertical = Control.SIZE_EXPAND_FILL
	editor._palette.item_selected.connect(editor._on_palette_selected)
	library.add_child(editor._palette)
	editor._preview = preload("res://scripts/world_editor/asset_preview.gd").new()
	library.add_child(editor._preview)
	editor._preview.custom_minimum_size.y = 110
	var center := VBoxContainer.new()
	center.name = "MapWorkspace"
	center.add_theme_constant_override("separation", 0)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(center)
	var tools_panel := PanelContainer.new()
	center.add_child(tools_panel)
	var rows := VBoxContainer.new()
	tools_panel.add_child(rows)
	var modes := HBoxContainer.new(); modes.name = "SelectionTools"; scene_actions.add_child(modes)
	var transforms := HBoxContainer.new(); transforms.name = "TransformTools"; scene_actions.add_child(transforms)
	var camera_tools := HBoxContainer.new(); camera_tools.name = "CameraTools"; scene_actions.add_child(camera_tools)
	var tools := HFlowContainer.new()
	rows.add_child(tools)
	var group := ButtonGroup.new()
	for index in 2:
		var mode := button(modes, ["摆放素材", "选择 / 变换", "NPC", "采集点", "传送点"][index], editor._set_mode.bind(index))
		mode.toggle_mode = true
		mode.button_group = group
		mode.button_pressed = index == editor._mode
		editor._mode_buttons.append(mode)
	editor._add_mode_menu = MenuButton.new(); editor._add_mode_menu.text = "添加…"; modes.add_child(editor._add_mode_menu)
	for text in ["NPC", "采集点", "传送点"]: editor._add_mode_menu.get_popup().add_item(text)
	editor._add_mode_menu.get_popup().id_pressed.connect(func(index): editor._set_mode(index + 2))
	button(camera_tools, "网格", func(): editor._grid.visible = not editor._grid.visible)
	editor._walk_button=button(camera_tools,"胶囊行走 F6",editor._toggle_walk_mode)
	editor._walk_button.name="CapsuleWalkButton";editor._walk_button.toggle_mode=true
	editor._walk_button.tooltip_text="以可见胶囊体在当前地图行走；仍可选择、移动和摆放物件。F6 / Esc 退出并恢复视角。"
	transforms.add_child(VSeparator.new())
	var transform_group := ButtonGroup.new()
	for index in 3:
		var control := button(transforms, ["移动 W", "旋转 R", "缩放 T"][index], editor._set_transform_mode.bind(index))
		control.toggle_mode = true
		control.button_group = transform_group
		control.button_pressed = index == editor._transform_mode
		editor._transform_buttons.append(control)
	editor._space_button = button(transforms, "世界轴", editor._toggle_transform_space)
	editor._space_button.tooltip_text = "L · 切换世界 / 局部坐标轴"
	button(camera_tools, "聚焦 F", editor._focus_selected)
	button(camera_tools, "俯视", editor._top_view)
	editor._box_button = button(modes, "框选 B", editor._toggle_box_select)
	editor._box_button.toggle_mode = true
	button(modes, "摆放…", editor._show_placement_panel).tooltip_text = "贴地、贴表面、XYZ 对齐与分布"
	var position_group := HBoxContainer.new(); position_group.name = "PositionSnapGroup"; tools.add_child(position_group)
	var rotation_group := HBoxContainer.new(); rotation_group.name = "RotationSnapGroup"; tools.add_child(rotation_group)
	var scale_group := HBoxContainer.new(); scale_group.name = "ScaleSnapGroup"; tools.add_child(scale_group)
	label = Label.new()
	label.text = "  位置吸附"
	position_group.add_child(label)
	var snap := OptionButton.new()
	for text in ["关闭", "0.01 m", "0.1 m", "0.25 m", "0.5 m", "1 m"]: snap.add_item(text)
	snap.select(3)
	snap.item_selected.connect(func(index: int): editor._snap = [0.0, 0.01, 0.1, 0.25, 0.5, 1.0][index])
	position_group.add_child(snap)
	label = Label.new()
	label.text = "  旋转吸附"
	rotation_group.add_child(label)
	var rotation := OptionButton.new()
	for text in ["关闭", "1°", "15°", "45°", "90°"]: rotation.add_item(text)
	rotation.select(2)
	rotation.item_selected.connect(func(index: int): editor._rotation_snap = [0.0, 1.0, 15.0, 45.0, 90.0][index])
	rotation_group.add_child(rotation)
	label = Label.new()
	label.text = "  缩放吸附"
	scale_group.add_child(label)
	var scaling := OptionButton.new()
	for text in ["关闭", "10%", "25%", "50%"]: scaling.add_item(text)
	scaling.item_selected.connect(func(index: int): editor._scale_snap = [0.0, 0.1, 0.25, 0.5][index])
	scale_group.add_child(scaling)
	editor._snap_controls = {"position_snap": snap, "rotation_snap": rotation, "scale_snap": scaling}
	editor._gravity_toggle = CheckBox.new()
	editor._gravity_toggle.name = "GravityPlacement"
	editor._gravity_toggle.text = "重力放置"
	editor._gravity_toggle.tooltip_text = "普通物件拖动/旋转遇障停止，松手后下落到承托面；使用旋转包围盒，组合整体落地。"
	tools.add_child(editor._gravity_toggle)
	editor._gravity_toggle.toggled.connect(editor._gravity.configure)
	editor._auto_toolbar = HFlowContainer.new()
	rows.add_child(editor._auto_toolbar)
	label = Label.new()
	label.text = "自动拼接 · 格宽"
	editor._auto_toolbar.add_child(label)
	var cell_size := OptionButton.new()
	for text in ["1 m", "2 m", "4 m", "8 m"]: cell_size.add_item(text)
	cell_size.select(2)
	cell_size.item_selected.connect(func(index: int): editor._finish_auto_stroke(); editor._auto_cell_size = [1.0, 2.0, 4.0, 8.0][index])
	editor._auto_toolbar.add_child(cell_size)
	var height := SpinBox.new()
	height.prefix = "高度"
	height.suffix = "m"
	height.min_value = -1000
	height.max_value = 1000
	height.step = 0.1
	height.custom_minimum_size.x = 140
	height.tooltip_text = "地形表面 / 墙底的固定高度；不同高度单独连接"
	height.value_changed.connect(func(value: float): editor._finish_auto_stroke(); editor._auto_height = value; editor._status.text = editor._hint())
	editor._auto_toolbar.add_child(height)
	var erase := CheckButton.new()
	erase.text = "擦除"
	erase.tooltip_text = "只擦除当前高度、格宽和类型；Shift+左键临时擦除"
	erase.focus_mode = Control.FOCUS_NONE
	erase.toggled.connect(func(value: bool): editor._finish_auto_stroke(); editor._auto_erase = value)
	editor._auto_toolbar.add_child(erase)
	button(editor._auto_toolbar, "高差 / 套件…", func(): editor._auto_panel.refresh(); editor._dock_tabs.current_tab = 4)
	editor._auto_toolbar.visible = false
	editor._canvas = SubViewportContainer.new()
	editor._canvas.stretch = true
	editor._canvas.tooltip_text="中键拖动平移 · 按住中键 + WASD 水平移动 · ↑ / ↓ 垂直移动 · Shift 加速"
	editor._canvas.mouse_filter = Control.MOUSE_FILTER_PASS
	editor._canvas.set_drag_forwarding(Callable(), editor._can_drop_palette, editor._drop_palette)
	editor._canvas.custom_minimum_size = Vector2(240, 200)
	editor._canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	editor._canvas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(editor._canvas)
	var viewport := SubViewport.new()
	viewport.world_3d = editor.get_world_3d()
	viewport.gui_disable_input = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	editor._canvas.add_child(viewport)
	editor._city.overlay = preload("res://scripts/world_editor/city_overlay.gd").new()
	editor._canvas.add_child(editor._city.overlay)
	editor._city.overlay.setup(editor._city)
	editor._gizmo = preload("res://scripts/world_editor/transform_gizmo.gd").new()
	editor._canvas.add_child(editor._gizmo)
	editor._gizmo.setup(editor)
	editor._selection_tools = preload("res://scripts/world_editor/object_selection.gd").new()
	editor._canvas.add_child(editor._selection_tools)
	editor._selection_tools.setup(editor)
	editor._placement_tools = preload("res://scripts/world_editor/placement_tools.gd").new()
	editor._canvas.add_child(editor._placement_tools)
	editor._placement_tools.setup(editor)
	editor._material_tool = preload("res://scripts/world_editor/surface_paint_tool.gd").new()
	editor._canvas.add_child(editor._material_tool)
	editor._material_tool.setup(editor)
	var auto_preview := preload("res://scripts/world_editor/auto_tile_preview.gd").new()
	editor._canvas.add_child(auto_preview)
	auto_preview.setup(editor)
	editor._camera.reparent(viewport)
	editor._camera.current = true
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("a9adb0")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b3c6d6")
	environment.ambient_light_energy = 0.5
	editor._camera.environment = environment
	var scroll := ScrollContainer.new()
	scroll.name = "属性"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	editor._dock_tabs.add_child(scroll)
	editor._inspector = preload("res://scripts/world_editor/inspector.gd").new()
	scroll.add_child(editor._inspector)
	editor._inspector.setup(editor)
	button(editor._inspector, "重新关联选中物件…", func(): editor._import_asset(true))
	button(editor._inspector, "保存所选为预制件…", editor._save_prefab_dialog)
	editor._object_list = preload("res://scripts/world_editor/object_list.gd").new()
	editor._dock_tabs.add_child(editor._object_list)
	editor._object_list.setup(editor)
	var material_scroll := ScrollContainer.new()
	material_scroll.name = "材质"
	material_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	editor._dock_tabs.add_child(material_scroll)
	editor._material_panel = preload("res://scripts/world_editor/surface_paint_panel.gd").new()
	editor._material_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	material_scroll.add_child(editor._material_panel)
	editor._material_panel.setup(editor)
	if profile:startup["base_and_material_ms"]=(Time.get_ticks_usec()-measured)/1000.;measured=Time.get_ticks_usec()
	var auto_scroll := ScrollContainer.new()
	auto_scroll.name = "拼接"
	auto_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	editor._dock_tabs.add_child(auto_scroll)
	editor._auto_panel = preload("res://scripts/world_editor/auto_tile_panel.gd").new()
	editor._auto_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	auto_scroll.add_child(editor._auto_panel)
	editor._auto_panel.setup(editor)
	if profile:startup["auto_panel_ms"]=(Time.get_ticks_usec()-measured)/1000.;measured=Time.get_ticks_usec()
	var event_scroll := ScrollContainer.new(); event_scroll.name = "事件"; event_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	editor._dock_tabs.add_child(event_scroll)
	editor._event_panel = preload("res://scripts/world_editor/event_panel.gd").new(); editor._event_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	event_scroll.add_child(editor._event_panel); editor._event_panel.setup(editor)
	if profile:startup["event_panel_ms"]=(Time.get_ticks_usec()-measured)/1000.;measured=Time.get_ticks_usec()
	var environment_page := VBoxContainer.new(); environment_page.name = "环境"
	editor._dock_tabs.add_child(environment_page)
	button(environment_page, "应用环境设置", func(): editor._environment_panel.apply())
	var environment_scroll := ScrollContainer.new(); environment_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	environment_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	environment_page.add_child(environment_scroll)
	editor._environment_panel = preload("res://scripts/world_editor/environment_panel.gd").new(); editor._environment_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	environment_scroll.add_child(editor._environment_panel); editor._environment_panel.setup(editor)
	if profile:startup["environment_panel_ms"]=(Time.get_ticks_usec()-measured)/1000.;measured=Time.get_ticks_usec()
	var view_scroll := ScrollContainer.new(); view_scroll.name = "楼层/试玩"; view_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	editor._dock_tabs.add_child(view_scroll)
	editor._view_panel = preload("res://scripts/world_editor/view_panel.gd").new(); editor._view_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view_scroll.add_child(editor._view_panel); editor._view_panel.setup(editor)
	if profile:startup["view_panel_ms"]=(Time.get_ticks_usec()-measured)/1000.;measured=Time.get_ticks_usec()
	var building_scroll := ScrollContainer.new(); building_scroll.name = "建筑"; building_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	editor._dock_tabs.add_child(building_scroll)
	editor._building_panel = preload("res://scripts/world_editor/building_panel.gd").new(); editor._building_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	building_scroll.add_child(editor._building_panel); editor._building_panel.setup(editor)
	if profile:startup["building_panel_ms"]=(Time.get_ticks_usec()-measured)/1000.;measured=Time.get_ticks_usec()
	var city_scroll := ScrollContainer.new(); city_scroll.name = "城镇布局"; city_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	editor._dock_tabs.add_child(city_scroll)
	var city_panel := preload("res://scripts/world_editor/city_panel.gd").new(); city_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var fortification_page := VBoxContainer.new(); fortification_page.name = "城防"
	city_scroll.add_child(city_panel); city_panel.setup(editor, fortification_page)
	if profile:startup["city_panel_ms"]=(Time.get_ticks_usec()-measured)/1000.;measured=Time.get_ticks_usec()
	editor._ground_draw=preload("res://scripts/world_editor/terrain_region_draw.gd").new()
	editor._canvas.add_child(editor._ground_draw); editor._ground_draw.setup(editor)
	editor._terrain_brush=preload("res://scripts/world_editor/terrain_brush.gd").new()
	editor._canvas.add_child(editor._terrain_brush); editor._terrain_brush.setup(editor)
	var terrain_scroll:=VBoxContainer.new(); terrain_scroll.name="地形"
	editor._dock_tabs.add_child(terrain_scroll)
	editor._terrain_panel=preload("res://scripts/world_editor/terrain_panel.gd").new(); editor._terrain_panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	editor._terrain_panel.size_flags_vertical=Control.SIZE_EXPAND_FILL
	terrain_scroll.add_child(editor._terrain_panel); editor._terrain_panel.setup(editor)
	editor._dock_tabs.add_child(fortification_page)
	city_panel.fortification_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if profile:startup["terrain_panel_ms"]=(Time.get_ticks_usec()-measured)/1000.;measured=Time.get_ticks_usec()
	for index in editor._dock_tabs.get_tab_count(): navigator.get_popup().add_radio_check_item(editor._dock_tabs.get_tab_title(index),index)
	navigator.get_popup().set_item_checked(editor._dock_tabs.current_tab,true)
	for task in task_nav.get_children():
		if task.has_meta("tab_index"): task.set_pressed_no_signal(task.get_meta("tab_index") == editor._dock_tabs.current_tab)
	editor._status = Label.new()
	editor._status.text = "左键摆放/选择 · 右键旋转视角 · 中键平移 · 滚轮缩放 · 方向键微调 · Q/E 旋转"
	editor._status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var status_panel := PanelContainer.new()
	root.add_child(status_panel)
	var status_row := HBoxContainer.new()
	status_row.add_theme_constant_override("separation", 12)
	status_panel.add_child(status_row)
	editor._status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_row.add_child(editor._status)
	editor._save_progress = ProgressBar.new()
	editor._save_progress.name = "SaveProgress"
	editor._save_progress.custom_minimum_size = Vector2(210, 14)
	editor._save_progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	editor._save_progress.show_percentage = false
	editor._save_progress.tooltip_text = "当前保存阶段的进度；无法计数的阶段显示活动动画"
	editor._save_progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	editor._save_progress.hide()
	status_row.add_child(editor._save_progress)
	editor._thumbnails = preload("res://scripts/world_editor/asset_thumbnails.gd").new()
	editor.add_child(editor._thumbnails)
	editor._thumbnails.available.connect(editor._apply_thumbnail)
	editor._thumbnails.import_finished.connect(func(_key, path, error):
		if error == OK: editor._status.text = "素材缩略图已生成"
		else: editor._report_error("缩略图生成失败，可从资源菜单重试：" + path, "素材缩略图")
	)
	editor._palette.visible_entries_changed.connect(editor._update_visible_thumbnails)
	editor._refresh_palette()
	editor._add_grid()
	if profile:
		startup["finish_ms"]=(Time.get_ticks_usec()-measured)/1000.
		editor.set_meta("startup_workspace",startup)
