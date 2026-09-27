extends VBoxContainer
## Numeric edits preserve decimal meters and keep one undo snapshot per edit.
var editor: Node
var selection := ""
var _updating := false
var fields := {}
var title: Label
var rows := {}


func setup(owner: Node) -> void:
	editor = owner
	title = Label.new()
	add_child(title)
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
			value.custom_minimum_size.x = 85
			value.tooltip_text = ["X", "Y", "Z"][axis]
			value.prefix = ["X", "Y", "Z"][axis]
			row.add_child(value)
			fields["%s_%d" % [group, axis]] = value
			value.value_changed.connect(func(v: float): _number_changed(group, axis, v))
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
		value.custom_minimum_size.x = 85
		row.add_child(value)
		fields["spawn_%d" % axis] = value
		value.value_changed.connect(func(v: float): _number_changed("spawn", axis, v + (0.9 if axis == 1 else 0.0)))
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


func select(uuid: String) -> void:
	selection = uuid
	_updating = true
	var record: Dictionary = editor._doc._find(uuid)
	title.text = "选择物件编辑" if record.is_empty() else "%s · %s" % [uuid, record.get("kind", "")]
	for group in ["position", "rotation", "size", "spawn"]:
		var values: Array = record.get(group, [1, 1, 1] if group == "size" else [0, 0, 0])
		for axis in 3:
			var value: SpinBox = fields["%s_%d" % [group, axis]]
			value.editable = not record.is_empty()
			value.value = float(values[axis]) - (0.9 if group == "spawn" and axis == 1 else 0.0)
	for key in ["line", "item_id", "target_path", "skills"]:
		fields[key].text = ", ".join(record.get(key, [])) if key == "skills" else str(record.get(key, ""))
		fields[key].editable = not record.is_empty()
	var kind := str(record.get("kind", ""))
	rows["size"][0].text = "缩放倍率" if kind == "asset" else "尺寸 (m)"
	for key in rows:
		var show: bool = not record.is_empty()
		if key in ["line", "hostile", "ally"]: show = kind == "npc"
		if key == "skills": show = kind == "npc" and bool(record.get("hostile", false))
		if key == "item_id": show = kind == "gather"
		if key in ["target_path", "spawn"]: show = kind == "warp"
		for control in rows[key]: control.visible = show
	for key in ["hostile", "ally"]: fields[key].button_pressed = bool(record.get(key, false))
	editor._refresh_selection()
	_updating = false


func _number_changed(group: String, axis: int, value: float) -> void:
	if _updating or selection.is_empty() or not is_finite(value):
		return
	var record: Dictionary = editor._doc._find(selection)
	if record.is_empty():
		return
	editor._doc.checkpoint()
	var values: Array = record.get(group, [0, 0.9, 4] if group == "spawn" else [0, 0, 0]).duplicate()
	values[axis] = value
	record[group] = values
	editor._dirty = true
	editor._rebuild()


func _text_changed(key: String, value: String) -> void:
	var record: Dictionary = editor._doc._find(selection)
	var previous := ", ".join(record.get(key, [])) if key == "skills" else str(record.get(key, ""))
	if _updating or record.is_empty() or previous == value:
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
