extends RefCounted
## U2U-style library and canvas; resource-pack maps open in a separate window.
const Style = preload("res://scripts/world_editor/workspace_theme.gd")

static func button(parent: Node, text: String, action: Callable) -> Button:
	var control := Button.new()
	control.text = text
	control.focus_mode = Control.FOCUS_NONE
	control.pressed.connect(action)
	parent.add_child(control)
	return control


static func build(editor: Node3D) -> void:
	var layer := CanvasLayer.new()
	editor.add_child(layer)
	var panel := PanelContainer.new()
	panel.name = "ContentWorkspace"
	panel.theme = Style.build()
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
	var action_panel := PanelContainer.new()
	root.add_child(action_panel)
	var menu := HBoxContainer.new()
	action_panel.add_child(menu)
	var file := MenuButton.new()
	file.text = "文件"
	menubar.add_child(file)
	for label in ["资源包地图…", "保存  Ctrl+S", "另存为…", "恢复上次保存…"]: file.get_popup().add_item(label)
	file.get_popup().id_pressed.connect(func(id: int):
		match id:
			0: editor._open_pack_maps()
			1: editor._save()
			2: editor._file_dialog(true)
			3: editor._restore_previous()
	)
	var edit_menu := MenuButton.new()
	edit_menu.text = "编辑"
	menubar.add_child(edit_menu)
	edit_menu.get_popup().add_item("撤销  Ctrl+Z", 0)
	edit_menu.get_popup().add_item("复制物件  Ctrl+D", 1)
	edit_menu.get_popup().id_pressed.connect(func(id: int):
		if id == 0: editor._undo()
		else: editor._duplicate_selected()
	)
	var view_menu := MenuButton.new()
	view_menu.text = "视图"
	menubar.add_child(view_menu)
	for text in ["素材库", "物件属性", "显示 / 隐藏网格", "俯视"]: view_menu.get_popup().add_item(text)
	view_menu.get_popup().id_pressed.connect(func(id: int):
		match id:
			0: editor._dock_tabs.current_tab = 0
			1: editor._dock_tabs.current_tab = 1
			2: editor._grid.visible = not editor._grid.visible
			3: editor._top_view()
	)
	menubar.add_spacer(false)
	var title := Label.new()
	title.text = "内容编辑器 · 3D"
	title.add_theme_color_override("font_color", Color("82919e"))
	menubar.add_child(title)
	button(menu, "资源包地图", editor._open_pack_maps)
	button(menu, "保存", editor._save)
	menu.add_child(VSeparator.new())
	button(menu, "↶ 撤销", editor._undo)
	button(menu, "复制物件", editor._duplicate_selected).tooltip_text = "Ctrl+D"
	menu.add_child(VSeparator.new())
	button(menu, "导入模型", editor._import_asset)
	button(menu, "素材管理", editor._manage_asset)
	menu.add_spacer(false)
	button(menu, "▶ 试玩", editor._play).tooltip_text = "F5"
	var split := HSplitContainer.new()
	split.name = "WorkspaceSplit"
	split.split_offset = 330
	split.mouse_filter = Control.MOUSE_FILTER_IGNORE
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)
	var label: Label
	editor._dock_tabs = TabContainer.new()
	editor._dock_tabs.custom_minimum_size = Vector2(310, 280)
	editor._dock_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(editor._dock_tabs)
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
	var modes := HFlowContainer.new()
	rows.add_child(modes)
	var tools := HFlowContainer.new()
	rows.add_child(tools)
	var group := ButtonGroup.new()
	for index in 5:
		var mode := button(modes, ["摆放素材", "选择 / 移动", "NPC", "采集点", "传送点"][index], editor._set_mode.bind(index))
		mode.toggle_mode = true
		mode.button_group = group
		mode.button_pressed = index == editor._mode
		editor._mode_buttons.append(mode)
	modes.add_child(VSeparator.new())
	button(modes, "属性", func(): editor._dock_tabs.current_tab = 1)
	button(modes, "网格", func(): editor._grid.visible = not editor._grid.visible)
	label = Label.new()
	label.text = "  位置吸附"
	tools.add_child(label)
	var snap := OptionButton.new()
	for text in ["关闭", "0.01 m", "0.1 m", "0.25 m", "0.5 m", "1 m"]: snap.add_item(text)
	snap.select(3)
	snap.item_selected.connect(func(index: int): editor._snap = [0.0, 0.01, 0.1, 0.25, 0.5, 1.0][index])
	tools.add_child(snap)
	label = Label.new()
	label.text = "  旋转吸附"
	tools.add_child(label)
	var rotation := OptionButton.new()
	for text in ["1°", "15°", "45°", "90°"]: rotation.add_item(text)
	rotation.select(1)
	rotation.item_selected.connect(func(index: int): editor._rotation_snap = [1.0, 15.0, 45.0, 90.0][index])
	tools.add_child(rotation)
	button(tools, "↶", func(): editor._rotate_selected(-1)).tooltip_text = "Q · 旋转选中物件"
	button(tools, "↷", func(): editor._rotate_selected(1)).tooltip_text = "E · 旋转选中物件"
	button(tools, "聚焦", editor._focus_selected).tooltip_text = "F"
	button(tools, "俯视", editor._top_view)
	editor._canvas = SubViewportContainer.new()
	editor._canvas.stretch = true
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
	editor._status = Label.new()
	editor._status.text = "左键摆放/选择 · 右键旋转视角 · 中键平移 · 滚轮缩放 · 方向键微调 · Q/E 旋转"
	editor._status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var status_panel := PanelContainer.new()
	root.add_child(status_panel)
	status_panel.add_child(editor._status)
	editor._thumbnails = preload("res://scripts/world_editor/asset_thumbnails.gd").new()
	editor.add_child(editor._thumbnails)
	editor._thumbnails.available.connect(editor._apply_thumbnail)
	editor._thumbnails.import_finished.connect(func(_key, path, error):
		editor._status.text = "模型和缩略图已保存到资源包" if error == OK else "模型已导入，但缩略图保存失败：" + path
	)
	editor._palette.visible_entries_changed.connect(editor._update_visible_thumbnails)
	editor._refresh_palette()
	editor._add_grid()
