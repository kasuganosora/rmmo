extends RefCounted
## Docked workspace; map files live in File menu so the palette stays available.

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
	layer.add_child(panel)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var root := VBoxContainer.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_theme_constant_override("separation", 6)
	panel.add_child(root)
	var menu := HBoxContainer.new()
	root.add_child(menu)
	var file := MenuButton.new()
	file.text = "文件 / 地图"
	menu.add_child(file)
	for label in ["打开地图…", "保存  Ctrl+S", "另存为…", "恢复上次保存…"]: file.get_popup().add_item(label)
	file.get_popup().id_pressed.connect(func(id: int):
		match id:
			0: editor._file_dialog(false)
			1: editor._save()
			2: editor._file_dialog(true)
			3: editor._restore_previous()
	)
	button(menu, "撤销", func():
		if editor._doc.undo():
			editor._dirty = true
			editor._rebuild()
			editor._inspector.select(editor._inspector.selection)
	)
	button(menu, "复制物件", editor._duplicate_selected).tooltip_text = "Ctrl+D"
	button(menu, "保存", editor._save)
	button(menu, "▶ 试玩", editor._play).tooltip_text = "F5"
	var tools := HBoxContainer.new()
	root.add_child(tools)
	var mode := OptionButton.new()
	for label in ["摆放素材", "选择 / 编辑", "NPC", "采集点", "传送点"]: mode.add_item(label)
	mode.item_selected.connect(func(index: int): editor._mode = index; editor._stroke.end())
	tools.add_child(mode)
	var label := Label.new()
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
	var split := HSplitContainer.new()
	split.mouse_filter = Control.MOUSE_FILTER_IGNORE
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)
	var library := VBoxContainer.new()
	library.custom_minimum_size.x = 180
	split.add_child(library)
	label = Label.new()
	label.text = "素材库"
	library.add_child(label)
	var assets := HBoxContainer.new()
	library.add_child(assets)
	button(assets, "导入…", editor._import_asset)
	button(assets, "管理…", editor._manage_asset)
	button(library, "重新关联选中物件…", func(): editor._import_asset(true))
	var search := LineEdit.new()
	search.placeholder_text = "搜索素材 / 分类"
	search.text_changed.connect(editor._on_search)
	library.add_child(search)
	editor._palette = ItemList.new()
	editor._palette.size_flags_vertical = Control.SIZE_EXPAND_FILL
	editor._palette.add_theme_constant_override("v_separation", 18)
	editor._palette.item_selected.connect(func(index: int): editor._pick = index; editor._preview.show_asset(str(editor._selected().get("asset_path", ""))); mode.select(0); editor._mode = 0; editor._status.text = editor._hint())
	library.add_child(editor._palette)
	editor._preview = preload("res://scripts/world_editor/asset_preview.gd").new()
	library.add_child(editor._preview)
	var center := HSplitContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(center)
	editor._canvas = SubViewportContainer.new()
	editor._canvas.stretch = true
	editor._canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	editor._canvas.custom_minimum_size = Vector2(240, 200)
	editor._canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	environment.background_color = Color("252c35")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b3c6d6")
	environment.ambient_light_energy = 0.5
	editor._camera.environment = environment
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 285
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	center.add_child(scroll)
	button(menu, "属性面板", func(): scroll.visible = not scroll.visible)
	button(menu, "网格", func(): editor._grid.visible = not editor._grid.visible)
	editor._inspector = preload("res://scripts/world_editor/inspector.gd").new()
	scroll.add_child(editor._inspector)
	editor._inspector.setup(editor)
	editor._status = Label.new()
	editor._status.text = "左键摆放/选择 · 右键旋转视角 · 中键平移 · 滚轮缩放 · 方向键微调 · Q/E 旋转"
	editor._status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	root.add_child(editor._status)
	editor._refresh_palette()
	editor._add_grid()
