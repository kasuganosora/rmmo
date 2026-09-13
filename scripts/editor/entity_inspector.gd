extends VBoxContainer
## Place/edit map events, NPCs, and pack-internal warps.

signal changed

var _kind: OptionButton
var _name: LineEdit
var _text: LineEdit
var _charset: LineEdit
var _to_map: LineEdit
var _to_x: SpinBox
var _to_y: SpinBox
var _info: Label
var cell: Vector2i = Vector2i.ZERO
var doc: RefCounted


func _ready() -> void:
	add_theme_constant_override("separation", 4)
	var k := Label.new()
	k.text = "实体"
	add_child(k)
	_kind = OptionButton.new()
	_kind.add_item("事件", 0)
	_kind.add_item("NPC", 1)
	_kind.add_item("传送", 2)
	add_child(_kind)
	_add("名称")
	_name = LineEdit.new()
	add_child(_name)
	_add("对话 / 说明")
	_text = LineEdit.new()
	add_child(_text)
	_add("行走图 charset")
	_charset = LineEdit.new()
	_charset.placeholder_text = "Actor1"
	add_child(_charset)
	_add("传送目标地图 id")
	_to_map = LineEdit.new()
	_to_map.placeholder_text = "Map002"
	add_child(_to_map)
	var row := HBoxContainer.new()
	add_child(row)
	_add_to(row, "X")
	_to_x = SpinBox.new()
	_to_x.max_value = 1000
	row.add_child(_to_x)
	_add_to(row, "Y")
	_to_y = SpinBox.new()
	_to_y.max_value = 1000
	row.add_child(_to_y)
	var btns := HBoxContainer.new()
	add_child(btns)
	_btn(btns, "写入此格", _apply)
	_btn(btns, "删除此格", _delete)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_info)


func load_cell(p_doc: RefCounted, p_cell: Vector2i) -> void:
	doc = p_doc
	cell = p_cell
	_info.text = "格子 %d,%d" % [cell.x, cell.y]
	if doc == null or not doc.has_method("entity_at"):
		return
	var hit: Dictionary = doc.entity_at(cell)
	if hit.is_empty():
		return
	var data: Dictionary = hit.get("data", {})
	match str(hit.get("kind", "")):
		"event":
			_kind.select(0)
			_name.text = str(data.get("id", ""))
			var pages: Variant = data.get("pages", [])
			_text.text = _first_text(pages)
		"npc":
			_kind.select(1)
			_name.text = str(data.get("name", ""))
			_charset.text = str(data.get("charset", ""))
			_text.text = str(data.get("interact_text", ""))
		"warp":
			_kind.select(2)
			_to_map.text = str(data.get("to_map", data.get("to_map_id", "")))
			var tc: Variant = data.get("to_cell", {})
			if typeof(tc) == TYPE_DICTIONARY:
				_to_x.value = int(tc.get("x", 0))
				_to_y.value = int(tc.get("y", 0))


func _apply() -> void:
	if doc == null:
		return
	_delete_silent()
	var k := _kind.get_selected_id()
	match k:
		0:
			var ev: Dictionary = doc.add_event(cell, _text.text if _text.text != "" else "……")
			if _name.text.strip_edges() != "":
				ev["id"] = _name.text.strip_edges()
		1:
			var cs := _charset.text.strip_edges()
			if cs == "":
				cs = "Actor1"
			var n: Dictionary = doc.add_npc(cell, cs, _name.text if _name.text != "" else "NPC")
			n["interact_text"] = _text.text
		2:
			var tm := _to_map.text.strip_edges()
			if tm == "":
				tm = "Map002"
			doc.add_warp(cell, tm, Vector2i(int(_to_x.value), int(_to_y.value)))
	changed.emit()
	_info.text = "已写入 %d,%d" % [cell.x, cell.y]


func _delete() -> void:
	_delete_silent()
	changed.emit()
	_info.text = "已清除 %d,%d" % [cell.x, cell.y]


func _delete_silent() -> void:
	if doc == null:
		return
	_strip(doc.events, "cell")
	_strip(doc.npcs, "cell")
	var next_w: Array = []
	for w in doc.warps:
		if typeof(w) != TYPE_DICTIONARY:
			continue
		var c: Variant = w.get("from_cell", {})
		if typeof(c) == TYPE_DICTIONARY and int(c.get("x", -1)) == cell.x and int(c.get("y", -1)) == cell.y:
			continue
		next_w.append(w)
	doc.warps = next_w
	doc.dirty = true


func _strip(arr: Array, key: String) -> void:
	var next: Array = []
	for item in arr:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var c: Variant = item.get(key, {})
		if typeof(c) == TYPE_DICTIONARY and int(c.get("x", -1)) == cell.x and int(c.get("y", -1)) == cell.y:
			continue
		next.append(item)
	arr.clear()
	for n in next:
		arr.append(n)


func _first_text(pages: Variant) -> String:
	if typeof(pages) != TYPE_ARRAY or (pages as Array).is_empty():
		return ""
	var p0: Variant = (pages as Array)[0]
	if typeof(p0) != TYPE_DICTIONARY:
		return ""
	var cmds: Variant = p0.get("commands", [])
	if typeof(cmds) != TYPE_ARRAY:
		return ""
	for c in cmds:
		if typeof(c) == TYPE_DICTIONARY and str(c.get("op", "")) == "text":
			return str(c.get("text", ""))
	return ""


func _add(text: String) -> void:
	var l := Label.new()
	l.text = text
	add_child(l)


func _add_to(parent: Node, text: String) -> void:
	var l := Label.new()
	l.text = text
	parent.add_child(l)


func _btn(parent: Node, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	parent.add_child(b)
