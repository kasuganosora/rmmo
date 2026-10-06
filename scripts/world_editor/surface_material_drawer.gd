extends PanelContainer
## Brush settings live outside the browsing dock; editing never paints a surface.
const UI = preload("res://scripts/world_editor/placement_panel.gd")
const Style = preload("res://scripts/world_editor/workspace_theme.gd")
const DEFAULTS = {"scale_u": 1.0, "scale_v": 1.0, "rotation": 0.0, "offset_u": 0.0, "offset_v": 0.0}
signal close_requested
signal restore_requested
signal defaults_restored
var mapping: OptionButton
var fields := {}
var restore_button: Button
var _material_name: Label

func setup() -> void:
	name = "SurfaceMaterialDrawer"
	visible = false
	theme = Style.build()
	add_theme_stylebox_override("panel", Style.panel(Color("24252c"), 12))
	mouse_filter = Control.MOUSE_FILTER_STOP
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var content := VBoxContainer.new(); content.name = "SurfaceUVSettings"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	scroll.add_child(content)
	var header := HBoxContainer.new(); content.add_child(header)
	var title := Label.new(); title.text = "自定义材质"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL; header.add_child(title)
	UI.button(header, "← 收起", func(): close_requested.emit(), "CloseSurfaceDrawer")
	_material_name = Label.new(); _material_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_material_name)
	var label := Label.new(); label.text = "贴图铺设方式"; content.add_child(label)
	mapping = OptionButton.new(); mapping.name = "SurfaceMapping"
	mapping.add_item("平面投影（整面铺一张）")
	mapping.add_item("模型原始 UV")
	mapping.add_item("按米重复（材质建议尺寸）")
	content.add_child(mapping)
	for spec in [["scale_u", "横向重复", 0.01, 100.0], ["scale_v", "纵向重复", 0.01, 100.0], ["rotation", "旋转 °", -3600.0, 3600.0], ["offset_u", "横向偏移", -100.0, 100.0], ["offset_v", "纵向偏移", -100.0, 100.0]]:
		var row := HBoxContainer.new(); content.add_child(row)
		var field_label := Label.new(); field_label.text = spec[1]
		field_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(field_label)
		var value := SpinBox.new(); value.name = spec[0]
		value.min_value = spec[2]; value.max_value = spec[3]
		value.step = 1.0 if spec[0] == "rotation" else (0.01 if str(spec[0]).begins_with("scale_") else 0.1)
		value.value = DEFAULTS[spec[0]]; value.custom_minimum_size.x = 120
		row.add_child(value); fields[spec[0]] = value
	var note := Label.new()
	note.text = "重复值越大，图案越小；0.5 表示放大一倍。"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; note.custom_minimum_size.x = 260
	content.add_child(note)
	UI.button(content, "恢复默认参数", reset_defaults, "ResetSurfaceDefaults")
	var hint := Label.new()
	hint.text = "参数自动保留，收起后可继续刷面。\n恢复默认仅重置参数，不改动已刷表面。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; hint.custom_minimum_size.x = 260
	content.add_child(hint)
	content.add_child(HSeparator.new())
	restore_button = UI.button(content, "恢复所选物件全部原材质", func(): restore_requested.emit(), "ResetObjectMaterials")
	restore_button.tooltip_text = "移除此物件所有刷面记录，可用 Ctrl+Z 撤销"

func set_material_name(value: String) -> void:
	_material_name.text = value

func _commit_text() -> void:
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit and focus.get_parent() in fields.values(): focus.get_parent().apply()

func options() -> Dictionary:
	_commit_text()
	return {"mapping": ["planar", "uv", "meters"][mapping.selected], "scale": [fields.scale_u.value, fields.scale_v.value], "rotation": fields.rotation.value, "offset": [fields.offset_u.value, fields.offset_v.value]}

func reset_defaults() -> void:
	_commit_text()
	mapping.select(0)
	for key in DEFAULTS: fields[key].value = DEFAULTS[key]
	defaults_restored.emit()
