extends VBoxContainer
## Numeric edits preserve decimal meters and keep one undo snapshot per edit.
var editor: Node
var selection := ""
var _live_input: SpinBox
var _number_edit_spin: SpinBox
var _number_edit_selection := ""
var _number_edit_history: Variant
var _coalesce_number := false
var _updating := false
var fields := {}
var title: Label
var identity_toggle: Button
var identity_details: VBoxContainer
var identity_id: LineEdit
var identity_kind: Label
var rows := {}
var tile_note: Label
var multi_scale: SpinBox
var component_toggle: CheckButton
var building_note: Label
var wind_panel: VBoxContainer
var banner_panel: VBoxContainer
var tree_panel: VBoxContainer
var model_component_panel: VBoxContainer


func setup(owner: Node) -> void:
	editor = owner
	title = Label.new()
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.theme_type_variation = "EditorHeading"
	add_child(title)
	identity_toggle = Button.new()
	identity_toggle.text = "对象信息"
	identity_toggle.toggle_mode = true
	identity_toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_child(identity_toggle)
	identity_details = VBoxContainer.new()
	identity_details.hide()
	add_child(identity_details)
	identity_kind = Label.new()
	identity_details.add_child(identity_kind)
	identity_id = LineEdit.new()
	identity_id.editable = false
	identity_id.tooltip_text = "内部 ID（可选择并复制）"
	identity_details.add_child(identity_id)
	identity_toggle.toggled.connect(func(expanded: bool): identity_details.visible = expanded)
	component_toggle=CheckButton.new(); component_toggle.text="构件编辑（单独修改墙、楼梯等）"
	add_child(component_toggle)
	component_toggle.toggled.connect(func(enabled):
		if not _updating: editor._selection_tools.set_component_edit(enabled)
	)
	building_note=Label.new(); building_note.custom_minimum_size.x=270
	building_note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	add_child(building_note)
	tile_note = Label.new()
	tile_note.custom_minimum_size.x = 270
	tile_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(tile_note)
	for group in ["position", "rotation", "size"]:
		var label := Label.new()
		label.text = {"position": "位置 (m)", "rotation": "旋转 (°)", "size": "尺寸 (m)"}[group]
		add_child(label)
		var row := HBoxContainer.new()
		add_child(row)
		rows[group] = [label, row]
		for axis in 3:
			var value := SpinBox.new()
			value.min_value = 0.001 if group == "size" else -100000.0
			value.max_value = 100000.0
			value.step = 0.001
			_add_axis_field(row, value, axis)
			fields["%s_%d" % [group, axis]] = value
			value.value_changed.connect(func(v: float): _number_changed(group, axis, v))
			value.get_line_edit().text_changed.connect(func(text: String): _number_text_changed(group, axis, value, text))
			value.get_line_edit().focus_exited.connect(finish_number_edit)
			value.get_line_edit().text_submitted.connect(func(_text: String): finish_number_edit())
	for key in ["line", "item_id", "target_path", "skills"]:
		var label := Label.new()
		label.text = {"line": "NPC 对话", "item_id": "采集物品 ID", "target_path": "传送目标地图", "skills": "敌对技能 ID（逗号分隔）"}[key]
		add_child(label)
		var value := LineEdit.new()
		add_child(value)
		fields[key] = value
		rows[key] = [label, value]
		value.text_submitted.connect(func(text: String): _text_changed(key, text))
		value.focus_exited.connect(func(): _text_changed(key, value.text))
	var scale_label := Label.new()
	scale_label.text = "整体等比缩放"
	add_child(scale_label)
	multi_scale = SpinBox.new()
	multi_scale.min_value = 0.01
	multi_scale.max_value = 1000
	multi_scale.step = 0.01
	multi_scale.value = 1.0
	multi_scale.suffix = "倍"
	add_child(multi_scale)
	rows["multi_scale"] = [scale_label, multi_scale]
	multi_scale.value_changed.connect(func(value: float):
		if not _updating: editor._selection_tools.transform_numeric("size", 0, value)
	)
	var label := Label.new()
	label.text = "目标出生脚点 (m)"
	add_child(label)
	var row := HBoxContainer.new()
	add_child(row)
	rows["spawn"] = [label, row]
	for axis in 3:
		var value := SpinBox.new()
		value.min_value = -100000.0
		value.max_value = 100000.0
		value.step = 0.001
		_add_axis_field(row, value, axis)
		fields["spawn_%d" % axis] = value
		value.value_changed.connect(func(v: float): _number_changed("spawn", axis, v + (0.9 if axis == 1 else 0.0)))
		value.get_line_edit().text_changed.connect(func(text: String): _number_text_changed("spawn", axis, value, text))
		value.get_line_edit().focus_exited.connect(finish_number_edit)
		value.get_line_edit().text_submitted.connect(func(_text: String): finish_number_edit())
	for key in ["hostile", "ally"]:
		var toggle := CheckBox.new()
		toggle.text = "敌对 NPC（可攻击 / 寻路追击）" if key == "hostile" else "伙伴 NPC（跟随 / 可复活）"
		add_child(toggle)
		fields[key] = toggle
		rows[key] = [toggle]
		toggle.toggled.connect(func(value: bool):
			if _updating or selection.is_empty(): return
			editor._doc.checkpoint()
			var record: Dictionary = editor._doc._find(selection)
			record[key] = value
			if value: record["ally" if key == "hostile" else "hostile"] = false
			editor._dirty = true
			select(selection)
		)
	select("")
	wind_panel = preload("res://scripts/world_editor/wind_panel.gd").new()
	tree_panel=preload("res://scripts/world_editor/tree_panel.gd").new();add_child(tree_panel);tree_panel.setup(editor);tree_panel.refresh()
	add_child(wind_panel); wind_panel.setup(editor); wind_panel.refresh()
	banner_panel=preload("res://scripts/world_editor/banner_panel.gd").new()
	add_child(banner_panel);banner_panel.setup(editor);banner_panel.refresh()
	model_component_panel=preload("res://scripts/world_editor/model_component_panel.gd").new()
	add_child(model_component_panel);model_component_panel.setup(editor);model_component_panel.refresh()


func _add_axis_field(row: HBoxContainer, value: SpinBox, axis: int) -> void:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 2)
	row.add_child(column)
	var label := Label.new()
	label.text = ["X", "Y", "Z"][axis]
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(label)
	value.custom_minimum_size.x = 85
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.tooltip_text = label.text + " 轴"
	column.add_child(value)


func _record_name(record: Dictionary) -> String:
	for key in ["editor_name", "label", "name", "asset_name"]:
		var value := str(record.get(key, "")).strip_edges()
		if not value.is_empty(): return value
	return {"asset": "模型物件", "npc": "NPC", "gather": "采集点", "warp": "传送点", "box": "方块", "floor": "地面"}.get(str(record.get("kind", "")), "场景物件")


func select(uuid: String) -> void:
	if editor._selection_tools != null:
		editor._selection_tools.set_ids([uuid] if not uuid.is_empty() else [])
		return
	selection = uuid
	refresh()


func refresh(refresh_scene: bool=true) -> void:
	_updating = true
	var record: Dictionary = editor._doc._find(selection)
	if record.is_empty(): selection = ""
	var count: int = editor._selection_tools.ids.size()
	var multi := count > 1
	var whole: bool = editor._selection_tools.whole
	component_toggle.visible = (record.has("building") or editor._selection_tools.component_edit) and not record.get("prefab_locked",false)
	component_toggle.button_pressed = editor._selection_tools.component_edit
	building_note.visible = component_toggle.visible
	building_note.text = "整栋选择 · XYZ 移动 / Y 轴旋转\n改宽深、层数请用建筑参数；移动会检查碰撞。" if whole else "构件编辑已开启：点击单独构件。手工改动后，重新生成会提示冲突。"
	title.text = "已选择 %d 件 · 共同中心" % count if multi else ("选择物件编辑" if record.is_empty() else _record_name(record))
	identity_toggle.visible = not record.is_empty() and not multi
	identity_details.visible = identity_toggle.visible and identity_toggle.button_pressed
	identity_id.text = selection
	identity_kind.text = "类型：" + str(record.get("kind", ""))
	if whole: title.text="整栋建筑 · %d 个构件"%count
	if record.get("prefab_locked",false):
		title.text=_record_name(record) + " · 固定预制件";building_note.visible=true
		building_note.text="已烘焙 · 整栋移动、旋转、复制、删除
结构固定；刷面工具可换墙材质。\n建筑面板可开合门窗、替换单窗格栅。"
		if record.has("fortification"):building_note.text="城防结构已固定，不能拆改。\n通过城防面板整体删除或开合城门。"
		elif record.has("bridge_mesh"):building_note.text="桥梁网格已固定，加载时不重新生成。\n跨度、拱孔与材质不可修改。"
	tile_note.visible = not multi and record.has("tile3d")
	if tile_note.visible:
		var tile: Dictionary = record.tile3d
		var rules = preload("res://scripts/world3d/auto_tile_rules.gd")
		var detail: String = rules.shape_name(int(tile.mask)) if str(tile.family) in ["road", "wall", "bridge"] else "地形过渡"
		var options: Dictionary = tile.get("options", {})
		match str(tile.family):
			"cliff": detail = "基底 %.1f → 顶面 %.1f m" % [options.get("base_height", 0), tile.elevation]
			"stairs": detail = "下端 %.1f · 升高 %.1f m · 向%s" % [tile.elevation, options.get("rise", 2), ["北", "东", "南", "西"][int(options.get("direction", 0))]]
			"roof": detail = "檐口 %.1f · 升高 %.1f m" % [tile.elevation, options.get("rise", 2)]
		if options.has("kit"): detail += " · " + str(options.kit.name)
		tile_note.text = "%s · %s\n%s" % [rules.LABELS.get(str(tile.family), "自动模块"), detail, "自由变换会脱离自动拼接；撤销可恢复。" if rules.attached(record) else "独立物件，不再跟随邻居变化。"]
	for group in ["position", "rotation", "size", "spawn"]:
		var values: Array = record.get(group, [1, 1, 1] if group == "size" else [0, 0, 0])
		if multi:
			var pivot: Vector3 = editor._selection_tools.pivot()
			values = [pivot.x, pivot.y, pivot.z] if group == "position" else [0, 0, 0]
		for axis in 3:
			var value: SpinBox = fields["%s_%d" % [group, axis]]
			value.editable = not record.is_empty() and not (whole and (group=="size" or (group=="rotation" and axis!=1)))
			if value != _live_input: value.value = float(values[axis]) - (0.9 if group == "spawn" and axis == 1 else 0.0)
	for key in ["line", "item_id", "target_path", "skills"]:
		fields[key].text = ", ".join(record.get(key, [])) if key == "skills" else str(record.get(key, ""))
		fields[key].editable = not record.is_empty()
	var kind := str(record.get("kind", ""))
	rows["size"][0].text = "缩放倍率" if kind == "asset" else "尺寸 (m)"
	rows["position"][0].text = "组合中心 (m)" if multi else "位置 (m)"
	rows["rotation"][0].text = "绕组合中心旋转 (增量 °)" if multi else "旋转 (°)"
	multi_scale.value = 1.0
	for key in rows:
		var show: bool = not record.is_empty()
		if key in ["line", "hostile", "ally"]: show = kind == "npc"
		if key == "skills": show = kind == "npc" and bool(record.get("hostile", false))
		if key == "item_id": show = kind == "gather"
		if key in ["target_path", "spawn"]: show = kind == "warp"
		if multi: show = key in ["position", "rotation", "multi_scale"] and not (whole and key=="multi_scale")
		elif key == "multi_scale": show = false
		for control in rows[key]: control.visible = show
	for key in ["hostile", "ally"]: fields[key].button_pressed = bool(record.get(key, false))
	# Transform callers already updated outlines, visual nodes and collision bodies.
	if refresh_scene: editor._refresh_selection()
	if wind_panel != null: wind_panel.refresh()
	if tree_panel != null: tree_panel.refresh()
	if banner_panel != null:banner_panel.refresh()
	if model_component_panel != null:model_component_panel.refresh()
	_updating = false


func refresh_transform(live_record: Variant = null) -> void:
	# A drag only changes these numbers. Resource inspectors and topology/UI
	# visibility are refreshed on selection/change completion, not mouse motion.
	_updating=true
	var record: Dictionary=editor._doc._find(selection) if live_record == null else live_record
	var multi: bool=editor._selection_tools.ids.size()>1
	var pivot: Vector3=editor._selection_tools.pivot() if multi else Vector3.ZERO
	for field in ["position","rotation","size"]:
		var values: Array=record.get(field,[0,0,0])
		if multi: values=[pivot.x,pivot.y,pivot.z] if field=="position" else [0,0,0]
		for axis in 3: fields["%s_%d"%[field,axis]].set_value_no_signal(float(values[axis]))
	_updating=false

func finish_number_edit() -> void:
	_number_edit_spin = null
	_number_edit_history = null
	_number_edit_selection = ""

func _number_text_changed(group: String, axis: int, spin: SpinBox, text: String) -> void:
	# Absolute single-object numbers can be applied immediately. Group rotation
	# and scale are deltas and must not accumulate while their text is incomplete.
	if _updating or not spin.editable or editor._selection_tools.ids.size() != 1: return
	var input := text.strip_edges()
	# Keep partial negatives/decimals and expressions intact. SpinBox may still
	# evaluate a complete expression on Enter; an unfinished string is no edit.
	if not input.is_valid_float(): return
	var number := input.to_float()
	if not is_finite(number) or number < spin.min_value or number > spin.max_value: return
	var undo: Array = editor._doc._undo
	var previous_history: Variant = null if undo.is_empty() else undo.back()
	_coalesce_number = _number_edit_spin == spin and _number_edit_selection == selection and not undo.is_empty() and is_same(undo.back(), _number_edit_history)
	_live_input = spin
	_number_changed(group, axis, number + (0.9 if group == "spawn" and axis == 1 else 0.0))
	_live_input = null
	if not undo.is_empty() and (_coalesce_number or not is_same(previous_history, undo.back())):
		_number_edit_spin = spin
		_number_edit_selection = selection
		_number_edit_history = undo.back()
	_coalesce_number = false


func _number_changed(group: String, axis: int, value: float) -> void:
	if _updating or editor._load_failed or selection.is_empty() or not is_finite(value):
		return
	if editor._selection_tools.ids.size() > 1:
		editor._selection_tools.transform_numeric(group, axis, value)
		return
	var record: Dictionary = editor._doc._find(selection)
	if record.is_empty():
		return
	var values: Array = record.get(group, [0, 0.9, 4] if group == "spawn" else [0, 0, 0]).duplicate()
	# Relative float equality loses a 0.001 degree step at angles above 100.
	if absf(float(values[axis]) - value) < 0.0000001: return
	values[axis] = value
	if group in ["position", "rotation", "size"]:
		editor._selection_tools.set_object_transform(selection, {group: values}, not _coalesce_number)
		return
	if not _coalesce_number: editor._doc.checkpoint()
	record[group] = values
	editor._dirty = true
	editor._rebuild()


func _text_changed(key: String, value: String) -> void:
	var record: Dictionary = editor._doc._find(selection)
	var previous := ", ".join(record.get(key, [])) if key == "skills" else str(record.get(key, ""))
	if _updating or editor._load_failed or editor._selection_tools.ids.size() > 1 or record.is_empty() or previous == value:
		return
	editor._doc.checkpoint()
	if key == "skills":
		var skills: Array = []
		for entry in value.replace("，", ",").split(",", false):
			var skill := entry.strip_edges()
			if not skill.is_empty() and not skills.has(skill): skills.append(skill)
		record[key] = skills
	else: record[key] = value
	editor._dirty = true
