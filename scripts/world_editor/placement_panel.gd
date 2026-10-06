extends RefCounted

static func button(parent: Node, label: String, action: Callable, node_name: String = "") -> Button:
	var result := Button.new()
	result.text = label
	if not node_name.is_empty(): result.name = node_name
	result.pressed.connect(action)
	parent.add_child(result)
	return result

static func show_panel(editor: Node3D) -> void:
	var dialog := AcceptDialog.new()
	dialog.name = "PlacementDialog"
	dialog.title = "摆放与排列"
	dialog.ok_button_text = "关闭"
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	dialog.add_child(content)
	var note := Label.new()
	note.text = "完整组合视为一个整体；每次操作可撤销。\n对齐以最后选中的物件 / 组合为基准。"
	content.add_child(note)
	var normal := CheckBox.new()
	normal.name = "AlignSurfaceNormal"
	normal.text = "旋转物件，贴合表面方向"
	content.add_child(normal)
	var clearance := SpinBox.new()
	clearance.name = "SurfaceClearance"
	clearance.prefix = "离面距离"
	clearance.suffix = "m"
	clearance.min_value = 0
	clearance.max_value = 100
	clearance.step = 0.01
	content.add_child(clearance)
	var distance := SpinBox.new()
	distance.prefix = "向下搜索"
	distance.suffix = "m"
	distance.min_value = 0.01
	distance.max_value = 10000
	distance.value = 100
	distance.step = 1
	content.add_child(distance)
	var result := Label.new()
	result.name = "PlacementResult"
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result.custom_minimum_size = Vector2(380, 36)
	var report := func(outcome: Dictionary):
		editor._placement_tools.report(outcome)
		result.text = editor._status.text
	var actions := HBoxContainer.new()
	content.add_child(actions)
	button(actions, "向下贴地", func(): report.call(editor._placement_tools.drop_selection(normal.button_pressed, distance.value, clearance.value)), "DropSelection")
	button(actions, "点选目标表面…", func():
		editor._placement_tools.begin_surface(normal.button_pressed, clearance.value)
		if editor._placement_tools.active: dialog.queue_free()
		else: result.text = editor._status.text
	)
	content.add_child(HSeparator.new())
	var axis := OptionButton.new()
	axis.name = "ArrangeAxis"
	for label in ["X 轴", "Y 轴", "Z 轴"]: axis.add_item(label)
	content.add_child(axis)
	var alignment := HBoxContainer.new()
	content.add_child(alignment)
	var anchor := OptionButton.new()
	anchor.name = "AlignAnchor"
	for label in ["负方向边缘", "中心", "正方向边缘"]: anchor.add_item(label)
	anchor.select(1)
	alignment.add_child(anchor)
	button(alignment, "对齐到最后选中", func(): report.call(editor._placement_tools.align_selection(axis.selected, ["min", "center", "max"][anchor.selected])), "AlignSelection")
	var distribution := HBoxContainer.new()
	content.add_child(distribution)
	var spacing := OptionButton.new()
	spacing.name = "DistributionSpacing"
	for label in ["边缘间隙相等", "中心距离相等"]: spacing.add_item(label)
	distribution.add_child(spacing)
	button(distribution, "保持两端，分布中间", func(): report.call(editor._placement_tools.distribute_selection(axis.selected, ["gaps", "centers"][spacing.selected])), "DistributeSelection")
	content.add_child(result)
	dialog.confirmed.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	editor.add_child(dialog)
	dialog.popup_centered(Vector2i(430, 490))
