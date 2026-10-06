extends VBoxContainer
## Numeric edits preserve decimal meters and keep one undo snapshot per edit.
var editor: Node
var selection := ""
var _updating := false
var fields := {}
var title: Label
var rows := {}
var tile_note: Label
var multi_scale: SpinBox
var component_toggle: CheckButton
var building_note: Label
var wind_panel: VBoxContainer
var banner_panel: VBoxContainer
var tree_panel: VBoxContainer


func setup(owner: Node) -> void:
	editor = owner
	title = Label.new()
	add_child(title)
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
	wind_panel = preload("res://scripts/world_editor/wind_panel.gd").new()
	tree_panel=preload("res://scripts/world_editor/tree_panel.gd").new();add_child(tree_panel);tree_panel.setup(editor);tree_panel.refresh()
	add_child(wind_panel); wind_panel.setup(editor); wind_panel.refresh()
	banner_panel=preload("res://scripts/world_editor/banner_panel.gd").new()
	add_child(banner_panel);banner_panel.setup(editor);banner_panel.refresh()


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
	title.text = "已选择 %d 件 · 共同中心" % count if multi else ("选择物件编辑" if record.is_empty() else "%s · %s" % [selection, record.get("kind", "")])
	if whole: title.text="整栋建筑 · %d 个构件"%count
	if record.get("prefab_locked",false):
		title.text="固定预制件";building_note.visible=true
		building_note.text="已烘焙 · 整栋移动、旋转、复制、删除
内部结构与材质固定；门窗仍可开合。"
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
			value.value = float(values[axis]) - (0.9 if group == "spawn" and axis == 1 else 0.0)
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
	_updating = false


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
	if is_equal_approx(float(values[axis]), value): return
	values[axis] = value
	if group in ["position", "rotation", "size"]:
		editor._selection_tools.set_object_transform(selection, {group: values})
		return
	editor._doc.checkpoint()
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
