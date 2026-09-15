extends Window
## Create / duplicate / rename / delete pack tilesets.

signal catalog_changed
signal apply_requested(tileset_id: String)

var pack: RefCounted
var _list: ItemList
var _name_edit: LineEdit
var _info: Label
var _ask: ConfirmationDialog
var _pending_del: String = ""


func _ready() -> void:
	title = "图块套"
	size = Vector2i(520, 420)
	unresizable = false
	visible = false
	close_requested.connect(hide)
	var root_m := MarginContainer.new()
	root_m.set_anchors_preset(Control.PRESET_FULL_RECT)
	for m in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		root_m.add_theme_constant_override(m, 8)
	add_child(root_m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	root_m.add_child(v)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_selected.connect(_on_sel)
	_list.item_activated.connect(func(i): _apply_current(i))
	v.add_child(_list)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6)
	v.add_child(name_row)
	var nl := Label.new()
	nl.text = "显示名"
	name_row.add_child(nl)
	_name_edit = LineEdit.new()
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text_submitted.connect(func(_t): _rename())
	name_row.add_child(_name_edit)
	var nb := Button.new()
	nb.text = "改名"
	nb.pressed.connect(_rename)
	name_row.add_child(nb)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.text = "空白套无图块；复制 RTP 套可改通行和槽位。"
	v.add_child(_info)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	v.add_child(bar)
	_mk(bar, "新建空白", _create_blank)
	_mk(bar, "复制", _duplicate)
	_mk(bar, "用于当前地图", _apply_sel)
	_mk(bar, "删除", _ask_delete)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	_mk(bar, "关闭", hide)
	_ask = ConfirmationDialog.new()
	_ask.title = "删除图块套"
	_ask.ok_button_text = "删除"
	_ask.cancel_button_text = "取消"
	_ask.confirmed.connect(_do_delete)
	add_child(_ask)


func bind_pack(p: RefCounted) -> void:
	pack = p
	_reload()


func _mk(parent: Node, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	parent.add_child(b)


func _reload(select_id: String = "") -> void:
	if _list == null:
		return
	var keep := select_id
	if keep == "":
		keep = _selected_id()
	_list.clear()
	if pack == null:
		return
	var keys: Array = pack.tilesets.keys()
	keys.sort()
	var pick := 0
	var i := 0
	for k in keys:
		var sid := str(k)
		var label: String = pack.tileset_label(sid) if pack.has_method("tileset_label") else sid
		var maps: PackedStringArray = pack.maps_using_tileset(sid) if pack.has_method("maps_using_tileset") else PackedStringArray()
		var extra := " · %d 张图" % maps.size() if maps.size() > 0 else ""
		_list.add_item("%s  (%s)%s" % [label, sid, extra])
		_list.set_item_metadata(i, sid)
		if sid == keep:
			pick = i
		i += 1
	if _list.item_count > 0:
		_list.select(pick)
		_on_sel(pick)


func _selected_id() -> String:
	if _list == null or _list.get_selected_items().is_empty():
		return ""
	return str(_list.get_item_metadata(_list.get_selected_items()[0]))


func _on_sel(_idx: int) -> void:
	var sid := _selected_id()
	if pack == null or sid == "" or not pack.tilesets.has(sid):
		_name_edit.text = ""
		_info.text = ""
		return
	_name_edit.text = pack.tileset_label(sid)
	var ts: Dictionary = pack.tilesets[sid]
	var names_v: Variant = ts.get("tilesetNames", [])
	var filled := 0
	if typeof(names_v) == TYPE_ARRAY:
		for n in names_v:
			if str(n).strip_edges() != "":
				filled += 1
	var used: PackedStringArray = pack.maps_using_tileset(sid)
	_info.text = "槽位 %d/9 已指定 · 被 %d 张地图使用" % [filled, used.size()]


func _create_blank() -> void:
	if pack == null or not pack.has_method("create_tileset"):
		return
	var tid: String = pack.create_tileset("", _name_edit.text.strip_edges())
	if tid == "":
		return
	catalog_changed.emit()
	_reload(tid)


func _duplicate() -> void:
	if pack == null or not pack.has_method("duplicate_tileset"):
		return
	var src := _selected_id()
	if src == "":
		return
	var tid: String = pack.duplicate_tileset(src)
	if tid == "":
		return
	catalog_changed.emit()
	_reload(tid)


func _rename() -> void:
	if pack == null or not pack.has_method("rename_tileset"):
		return
	var sid := _selected_id()
	if sid == "":
		return
	if pack.rename_tileset(sid, _name_edit.text):
		catalog_changed.emit()
		_reload(sid)


func _apply_sel() -> void:
	_apply_current(-1)


func _apply_current(idx: int) -> void:
	var sid := ""
	if idx >= 0 and idx < _list.item_count:
		sid = str(_list.get_item_metadata(idx))
	else:
		sid = _selected_id()
	if sid == "":
		return
	apply_requested.emit(sid)


func _ask_delete() -> void:
	var sid := _selected_id()
	if sid == "" or pack == null:
		return
	if pack.tilesets.size() <= 1:
		_info.text = "至少保留一套图块。"
		return
	_pending_del = sid
	var used: PackedStringArray = pack.maps_using_tileset(sid)
	var extra := ""
	if used.size() > 0:
		extra = "\n%d 张地图会改用另一套。" % used.size()
	_ask.dialog_text = "删除图块套「%s」？%s" % [pack.tileset_label(sid), extra]
	_ask.popup_centered()


func _do_delete() -> void:
	if pack == null or _pending_del == "":
		return
	if pack.delete_tileset(_pending_del):
		catalog_changed.emit()
		_reload()
	_pending_del = ""
