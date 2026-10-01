extends VBoxContainer
const Rules = preload("res://scripts/world3d/auto_tile_rules.gd")
var library = Rules.Kits.new()
var editor: Node3D
var fields := {}
var kit_select: OptionButton
var family_select: OptionButton
var description: Label
var entries: Array = []

func setup(host: Node3D) -> void:
	editor = host
	add_theme_constant_override("separation", 10)
	description = Label.new()
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(description)
	family_select = OptionButton.new()
	for family in Rules.FAMILIES: family_select.add_item(Rules.LABELS[family])
	family_select.item_selected.connect(func(index):
		var chosen := false
		for i in editor._palette_items.size():
			if editor._palette_items[i].get("auto_family", "") == Rules.FAMILIES[index]:
				editor._on_palette_selected(i)
				editor._set_mode(0)
				chosen = true
				break
		if not chosen: editor._status.text = "该模块被素材搜索条件隐藏，请先清除素材搜索"
		refresh()
	)
	add_child(family_select)
	field("base_height", "基底高度（米）", -1000, 1000, -2)
	field("rise", "升高（米）", .1, 8, 2)
	field("rail_height", "栏杆高度（米）", .3, 3, 1)
	var direction := OptionButton.new()
	for title in ["向北上升（-Z）", "向东上升（+X）", "向南上升（+Z）", "向西上升（-X）"]: direction.add_item(title)
	direction.item_selected.connect(func(_index): editor._finish_auto_stroke())
	fields.direction = direction
	add_child(direction)
	var label := Label.new(); label.text = "拼接模型套件"; add_child(label)
	kit_select = OptionButton.new()
	kit_select.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	kit_select.item_selected.connect(func(_index): editor._finish_auto_stroke())
	add_child(kit_select)
	var import_button := Button.new(); import_button.text = "导入套件清单…"
	import_button.pressed.connect(import_dialog)
	add_child(import_button)
	var hint := Label.new()
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.text = "画布上方设置格宽与高度。高台同一基底重刷可改变高度；楼梯高度为下端，升高为两端高差；屋顶高度为檐口；桥高度为桥面。\n\n套件使用静态 GLB 模型与 JSON 邻接清单，导入时复制到独立资源库。变换或刷材质会冻结当前拼接造型。"
	add_child(hint)
	refresh()

func field(key: String, title: String, low: float, high: float, value: float) -> void:
	var box := VBoxContainer.new()
	var label := Label.new(); label.text = title; box.add_child(label)
	var spin := SpinBox.new(); spin.min_value = low; spin.max_value = high; spin.step = .1; spin.value = value
	spin.value_changed.connect(func(_value): editor._finish_auto_stroke())
	box.add_child(spin); add_child(box)
	fields[key] = spin

func refresh(preferred: String = "") -> void:
	var family := str(editor._selected().get("auto_family", ""))
	description.text = "自动拼接 · " + Rules.LABELS.get(family, "请先选择自动模块")
	family_select.select(maxi(0, Rules.FAMILIES.find(family)))
	fields.base_height.get_parent().visible = family == "cliff"
	fields.rise.get_parent().visible = family in ["stairs", "roof"]
	fields.rail_height.get_parent().visible = family == "bridge"
	fields.direction.visible = family == "stairs"
	var previous := preferred
	if previous.is_empty() and kit_select.selected > 0: previous = str(kit_select.get_item_metadata(kit_select.selected))
	kit_select.clear(); kit_select.add_item("内置基础模型"); kit_select.set_item_metadata(0, "")
	entries = library.entries()
	for entry in entries:
		if entry.family != family: continue
		kit_select.add_item(entry.name)
		kit_select.set_item_metadata(kit_select.item_count - 1, entry.kit_id)
		if entry.kit_id == previous: kit_select.select(kit_select.item_count - 1)

func options(family: String) -> Dictionary:
	var result := {}
	match family:
		"cliff": result.base_height = fields.base_height.value
		"stairs": result.merge({"rise": fields.rise.value, "direction": fields.direction.selected})
		"roof": result.rise = fields.rise.value
		"bridge": result.rail_height = fields.rail_height.value
	if kit_select.selected > 0:
		var loaded := library.read(str(kit_select.get_item_metadata(kit_select.selected)))
		if not loaded.ok: return {"error": loaded.error}
		result.kit = loaded.kit
	return result

func import_dialog() -> void:
	var dialog := FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.filters = PackedStringArray(["*.json ; 自动拼接套件"])
	dialog.current_dir = preload("res://scripts/world3d/map_paths.gd").external_root()
	dialog.file_selected.connect(func(path):
		var result := library.import_kit(path)
		editor._status.text = "已导入套件：" + result.name if result.ok else result.error
		if result.ok: refresh(result.kit_id)
		dialog.queue_free()
	)
	dialog.canceled.connect(dialog.queue_free)
	editor.add_child(dialog); dialog.popup_centered_ratio(.7)
