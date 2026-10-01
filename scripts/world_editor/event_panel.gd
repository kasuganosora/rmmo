extends VBoxContainer
const Templates = preload("res://scripts/world3d/event_templates.gd")
const Form = preload("res://scripts/world_editor/settings_form.gd")
const LABELS = {"name": "名称", "enabled": "事件启用", "trigger": "触发（action 按 E / player_touch 接触）", "text": "对话 / 完成提示", "empty_text": "完成后再次交互的提示", "once": "每个实例只执行一次", "item_id": "奖励物品", "quantity": "奖励数量", "gold": "奖励金币", "shop_id": "关联商店", "map_path": "目标地图 glTF 路径", "spawn": "目标出生脚点（米）", "required_switch": "前置全局开关（留空不限制）", "required_item": "前置持有物品（不消耗）", "required_quantity": "前置物品数量", "set_switch": "完成后开启全局开关（可留空）", "offset": "相对物件原点的事件偏移（米）", "touch_size": "接触区域大小（米）", "radius": "按键交互距离（米）"}
var editor: Node3D
var type_select: OptionButton
var form: VBoxContainer
var position_form: VBoxContainer
var note: Label
var preview: TextEdit
var _key := ""

func setup(host: Node3D) -> void:
	editor = host; add_theme_constant_override("separation", 7)
	note = Label.new(); note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; add_child(note)
	type_select = OptionButton.new()
	for type in Templates.LABELS: type_select.add_item(Templates.LABELS[type]); type_select.set_item_metadata(type_select.item_count - 1, type)
	add_child(type_select)
	type_select.item_selected.connect(func(_index): fill(Templates.defaults(type_select.get_item_metadata(type_select.selected))))
	var actions := HFlowContainer.new(); add_child(actions)
	button(actions, "应用到所选物件", apply_selected)
	button(actions, "移除所选事件", func(): report(editor._gameplay.clear_event(selected_id())))
	button(actions, "生成事件预览", show_preview)
	var create_toggle := CheckButton.new(); create_toggle.text = "在指定位置新建事件"; add_child(create_toggle)
	var create_box := VBoxContainer.new(); create_box.visible = false; add_child(create_box)
	create_toggle.toggled.connect(func(on): create_box.visible = on)
	position_form = Form.new(); create_box.add_child(position_form)
	position_form.build({"properties": {"position": Templates.Schema.vector(-100000, 100000)}}, {"position": [0,0,0]}, {"position": "新建位置脚点（米）"})
	button(create_box, "在此位置新建事件", create_event)
	form = Form.new(); add_child(form)
	preview = TextEdit.new(); preview.editable = false; preview.custom_minimum_size.y = 130; preview.visible = false; add_child(preview)
	refresh()

func button(parent: Node, text_: String, callback: Callable) -> void:
	var control := Button.new(); control.text = text_; control.pressed.connect(callback); parent.add_child(control)

func selected_id() -> String:
	return str(editor._selection_tools.ids[0]) if editor._selection_tools.ids.size() == 1 else ""

func refresh() -> void:
	if form == null: return
	var record: Dictionary = editor._doc._find(selected_id())
	var key := selected_id() + JSON.stringify(record.get("event_template", {}))
	if key == _key: return
	_key = key
	note.text = "选择一个物件可挂载事件；也可在指定脚点新建事件标记。" if record.is_empty() else "当前物件：" + str(record.get("editor_name", record.uuid))
	var type := str(record.get("event_template", {}).get("template", "dialogue"))
	type_select.select(Templates.LABELS.keys().find(type))
	fill(record.get("event_template", {}).get("parameters", Templates.defaults(type)))

func fill(values: Dictionary) -> void:
	var choices: Dictionary = editor._gameplay.resources()
	var blank := [{"id": "", "name": "无"}]
	var ordered := {}
	for key in ["name", "enabled", "trigger", "text", "item_id", "quantity", "gold", "shop_id", "map_path", "spawn", "once", "empty_text"]:
		if values.has(key): ordered[key] = values[key]
	ordered.merge(values)
	var labels := LABELS.merged({"trigger": "触发方式"}, true)
	form.build(Templates.parameters_schema(), ordered, labels, {"trigger": [{"id":"action", "name":"按 E 交互"}, {"id":"player_touch", "name":"接触触发"}], "item_id": blank + choices.items, "required_item": blank + choices.items, "shop_id": blank + choices.shops})
	if preview != null: preview.visible = false

func apply_selected() -> void:
	report(editor._gameplay.set_event(selected_id(), type_select.get_item_metadata(type_select.selected), form.values()))

func create_event() -> void:
	var p: Array = position_form.values().position
	report(editor._gameplay.create_event(type_select.get_item_metadata(type_select.selected), Vector3(p[0], p[1], p[2]), form.values()))

func show_preview() -> void:
	var result: Dictionary = editor._gameplay.prepare(type_select.get_item_metadata(type_select.selected), form.values())
	if not result.ok: report(result); return
	preview.text = JSON.stringify(Templates.compile(result.value), "  "); preview.visible = true

func report(result: Dictionary) -> void:
	editor._status.text = "事件设置已应用，可撤销" if result.ok else str(result.error)
	if result.ok: refresh()
