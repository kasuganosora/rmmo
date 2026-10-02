extends VBoxContainer
const Paint = preload("res://scripts/world3d/surface_materials.gd")
const UI = preload("res://scripts/world_editor/placement_panel.gd")
var editor: Node3D
var picker: OptionButton
var category_picker: OptionButton
var preview: TextureRect
var mapping: OptionButton
var fields := {}
var target: Label

func setup(owner: Node3D) -> void:
	editor = owner
	name = "材质"
	add_theme_constant_override("separation", 8)
	var heading := Label.new()
	heading.text = "表面材质笔刷"
	add_child(heading)
	category_picker = OptionButton.new(); category_picker.name = "SurfaceCategory"
	category_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(category_picker)
	category_picker.item_selected.connect(func(_index): _refresh_materials())
	picker = OptionButton.new(); picker.name = "SurfaceMaterial"
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	picker.clip_text = true
	add_child(picker)
	picker.item_selected.connect(func(_index): _choose())
	UI.button(self, "导入贴图…", _import, "ImportSurfaceTexture")
	preview = TextureRect.new()
	preview.custom_minimum_size = Vector2(260, 90)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(preview)
	mapping = OptionButton.new(); mapping.name = "SurfaceMapping"
	mapping.add_item("平面投影（整面铺一张）"); mapping.add_item("模型原始 UV"); mapping.add_item("按米重复（材质建议尺寸）")
	add_child(mapping)
	for spec in [["scale_u", "横向重复", 0.01, 100.0, 1.0], ["scale_v", "纵向重复", 0.01, 100.0, 1.0], ["rotation", "旋转 °", -3600.0, 3600.0, 0.0], ["offset_u", "横向偏移", -100.0, 100.0, 0.0], ["offset_v", "纵向偏移", -100.0, 100.0, 0.0]]:
		var row := HBoxContainer.new(); add_child(row)
		var label := Label.new(); label.text = spec[1]; label.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(label)
		var value := SpinBox.new(); value.name = str(spec[0]); value.min_value = spec[2]; value.max_value = spec[3]; value.step = 1.0 if spec[0] == "rotation" else 0.1; value.value = spec[4]; value.custom_minimum_size.x = 120
		row.add_child(value); fields[spec[0]] = value
	target = Label.new(); target.name = "PaintTarget"; target.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; target.custom_minimum_size = Vector2(260, 44); target.text = "先点选一个墙面、地面或屋顶。"
	add_child(target)
	var actions := HBoxContainer.new(); add_child(actions)
	UI.button(actions, "选面", func(): _sync(); editor._material_tool.begin("pick"), "PickPaintFace")
	UI.button(actions, "刷材质", func(): _sync(); editor._material_tool.begin("paint"), "BeginSurfacePaint")
	UI.button(actions, "恢复原材质", func(): editor._material_tool.begin("restore"), "BeginSurfaceRestore")
	UI.button(self, "应用到所选面", _apply, "ApplySurfacePaint")
	UI.button(self, "恢复此物件全部原材质", func():
		var selected: Dictionary = editor._material_tool.selected
		if selected.get("ok", false): editor._material_tool.report(editor._material_tool.clear_paint(selected.id))
	, "ResetObjectMaterials")
	var note := Label.new(); note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; note.custom_minimum_size.x = 260
	note.text = "重复值越大，图案越小；0.5 表示放大一倍。\n按住左键可连续刷面，一笔撤销；Esc 取消。\n自动瓦片刷材质后冻结造型。"
	add_child(note)
	editor._material_tool.target_changed.connect(func():
		var selected: Dictionary = editor._material_tool.selected
		target.text = "%s · 面 %d / 槽 %d" % [selected.id, selected.target.face, selected.target.surface] if selected.get("ok", false) else "先点选一个墙面、地面或屋顶。"
	)
	refresh()

func refresh(chosen: String = "") -> void:
	var selected_category := str(category_picker.get_item_metadata(category_picker.selected)) if category_picker.selected >= 0 else ""
	category_picker.clear(); category_picker.add_item("全部分类"); category_picker.set_item_metadata(0, "")
	for category in editor._material_tool.library.categories():
		var index := category_picker.item_count
		category_picker.add_item(category); category_picker.set_item_metadata(index, category)
		if category == selected_category: category_picker.select(index)
	if not chosen.is_empty(): category_picker.select(0)
	_refresh_materials(chosen)

func _refresh_materials(chosen: String = "") -> void:
	var id := chosen if not chosen.is_empty() else str(editor._material_tool.material_id)
	picker.clear()
	var category := str(category_picker.get_item_metadata(category_picker.selected)) if category_picker.selected >= 0 else ""
	for entry in editor._material_tool.library.search("", category):
		var index := picker.item_count
		picker.add_item("%s · %s" % [entry.get("category", "内置"), entry.material.name])
		picker.set_item_metadata(index, entry.material_id)
		if entry.material_id == id: picker.select(index)
	_choose()

func _choose() -> void:
	if picker.selected < 0: return
	editor._material_tool.material_id = picker.get_item_metadata(picker.selected)
	var material: Dictionary = editor._material_tool.library.find(editor._material_tool.material_id)
	preview.texture = Paint.texture(material)

func _sync() -> void:
	var focus := editor.get_viewport().gui_get_focus_owner()
	if focus is LineEdit and focus.get_parent() in fields.values(): focus.get_parent().apply()
	editor._material_tool.options = {"mapping": ["planar", "uv", "meters"][mapping.selected], "scale": [fields.scale_u.value, fields.scale_v.value], "rotation": fields.rotation.value, "offset": [fields.offset_u.value, fields.offset_v.value]}

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
