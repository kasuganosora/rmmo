extends VBoxContainer
## Place/edit map events (pages + EventRuntime commands), NPCs, and warps.

const EventCommands = preload("res://scripts/editor/domain/event_commands.gd")
const ItemCatalog = preload("res://scripts/net/combat/item_catalog.gd")
const ShopCatalog = preload("res://scripts/net/combat/shop_catalog.gd")
const SelectorsModule = preload("res://scripts/editor/interface/inspector/selectors_module.gd")
const NpcModule = preload("res://scripts/editor/interface/inspector/npc_module.gd")
var _npc_module_logic: NpcModule = NpcModule.new(self)
var _selectors_module_logic: SelectorsModule = SelectorsModule.new(self)

signal changed
signal jump_requested(cell: Vector2i)

var pack: RefCounted
var doc: RefCounted
var cell: Vector2i = Vector2i.ZERO

var _loading: bool = false
var _pages: Array = []
var _page_idx: int = 0
var _event_trigger: String = "action"

var _list: ItemList
var _kind: OptionButton
var _info: Label

var _ev_box: VBoxContainer
var _id: LineEdit
var _trigger: OptionButton
var _through: CheckBox
var _page_opt: OptionButton
var _self_sw: OptionButton
var _switch_id: LineEdit
var _item_when: OptionButton
var _g_charset_opt: OptionButton
var _g_charset: LineEdit
var _g_index: SpinBox
var _g_dir: OptionButton
var _cmds: ItemList
var _add_op: OptionButton
var _param_box: VBoxContainer

var _npc_box: VBoxContainer
var _name: LineEdit
var _charset: LineEdit
var _charset_opt: OptionButton
var _dir: OptionButton
var _char_index: SpinBox
var _wander: CheckBox
var _npc_through: CheckBox
var _npc_kind: OptionButton
var _hostile: CheckBox
var _aggressive: CheckBox
var _level: SpinBox
var _wander_r: SpinBox
var _text: LineEdit
var clip: Dictionary = {}

var _warp_box: VBoxContainer
var _to_map: LineEdit
var _to_map_opt: OptionButton
var _to_x: SpinBox
var _to_y: SpinBox
var _facing: OptionButton
var _warp_msg: LineEdit

var _items: Array = []
var _shops: Array = []
var _p_text: TextEdit
var _p_item: OptionButton
var _p_qty: SpinBox
var _p_amount: SpinBox
var _p_switch: LineEdit
var _p_letter: OptionButton
var _p_on: CheckBox
var _p_shop: OptionButton
var _p_map: LineEdit
var _p_map_opt: OptionButton
var _p_cx: SpinBox
var _p_cy: SpinBox
var _p_audio: LineEdit
var _p_audio_opt: OptionButton
var _p_face_opt: OptionButton
var _p_face_index: SpinBox
var _p_switch_opt: OptionButton
var _switch_opt: OptionButton
var _p_wait: SpinBox
var _p_choices: TextEdit
var _choices_lbl: Label
var _opt_box: VBoxContainer
var _opt_list: ItemList
var _opt_name: LineEdit
var _branch_cmds: ItemList
var _param_src: String = "page"


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	_load_catalogs()
	_add(self, "本图实体")
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0, 80)
	_list.item_selected.connect(_on_list)
	add_child(_list)
	var kind_row := HBoxContainer.new()
	add_child(kind_row)
	_add(kind_row, "类型")
	_kind = OptionButton.new()
	_kind.add_item("事件", 0)
	_kind.add_item("NPC", 1)
	_kind.add_item("传送", 2)
	_kind.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_kind.item_selected.connect(func(_i): _sync_kind())
	kind_row.add_child(_kind)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var form := VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation", 4)
	scroll.add_child(form)
	_build_event(form)
	_build_npc(form)
	_build_warp(form)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 6)
	add_child(btns)
	_btn(btns, "写入此格", _apply)
	_btn(btns, "删除此格", _delete)
	_btn(btns, "宝箱模板", _apply_chest)
	_btn(btns, "复制", copy_current)
	_btn(btns, "粘贴", paste_current)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_info)
	_show_params("")
	_sync_kind()


func bind_pack(p: RefCounted) -> void:
	pack = p
	_fill_charset_opt()
	_fill_map_opt()
	_fill_face_opt()
	_fill_switch_opts()
	_reload_list()


func load_cell(p_doc: RefCounted, p_cell: Vector2i) -> void:
	doc = p_doc
	cell = p_cell
	_loading = true
	_info.text = "格子 %d,%d" % [cell.x, cell.y]
	_clear_fields()
	_reload_list()
	if doc == null or not doc.has_method("entity_at"):
		_loading = false
		_sync_kind()
		return
	var hit: Dictionary = doc.entity_at(cell)
	if hit.is_empty():
		_pages = [EventCommands.default_page()]
		_page_idx = 0
		_event_trigger = "action"
		_reload_pages()
		_loading = false
		_sync_kind()
		return
	var data: Dictionary = hit.get("data", {})
	match str(hit.get("kind", "")):
		"event":
			_kind.select(0)
			_id.text = str(data.get("id", ""))
			_event_trigger = str(data.get("trigger", "action"))
			_through.button_pressed = bool(data.get("through", true))
			_pages = EventCommands.ensure_pages(data).duplicate(true)
			_page_idx = 0
			_reload_pages()
		"npc":
			_kind.select(1)
			_name.text = str(data.get("name", ""))
			_charset.text = str(data.get("charset", ""))
			_select_charset_opt(_charset.text)
			_select_dir(_dir, int(data.get("direction", 2)))
			_char_index.value = int(data.get("index", 0))
			_wander.button_pressed = bool(data.get("wander", false))
			_npc_through.button_pressed = bool(data.get("through", false))
			_select_npc_kind(str(data.get("kind", "")))
			if _hostile:
				_hostile.button_pressed = bool(data.get("hostile", false))
			if _aggressive:
				_aggressive.button_pressed = bool(data.get("aggressive", false))
			if _level:
				_level.value = maxi(int(data.get("level", 1)), 1)
			if _wander_r:
				_wander_r.value = maxi(int(data.get("wander_radius", 0)), 0)
			_text.text = str(data.get("interact_text", ""))
			_sync_npc_combat()
		"warp":
			_kind.select(2)
			_to_map.text = str(data.get("to_map", data.get("to_map_id", "")))
			_select_map_opt(_to_map.text)
			var tc: Variant = data.get("to_cell", {})
			if typeof(tc) == TYPE_DICTIONARY:
				_to_x.value = int(tc.get("x", 0))
				_to_y.value = int(tc.get("y", 0))
			_select_dir(_facing, int(data.get("facing", 2)))
			_warp_msg.text = str(data.get("message", ""))
	_loading = false
	_sync_kind()
	_highlight_list_cell()


func _build_event(parent: Node) -> void:
	_ev_box = VBoxContainer.new()
	_ev_box.add_theme_constant_override("separation", 4)
	parent.add_child(_ev_box)
	_add(_ev_box, "事件 id")
	_id = LineEdit.new()
	_ev_box.add_child(_id)
	var tr := HBoxContainer.new()
	_ev_box.add_child(tr)
	_add(tr, "触发")
	_trigger = OptionButton.new()
	EventCommands.fill_trigger_option(_trigger)
	_trigger.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_trigger.item_selected.connect(func(_i): _store_when())
	tr.add_child(_trigger)
	_through = CheckBox.new()
	_through.text = "穿透"
	_ev_box.add_child(_through)
	var pr := HBoxContainer.new()
	_ev_box.add_child(pr)
	_add(pr, "页")
	_page_opt = OptionButton.new()
	_page_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_opt.item_selected.connect(_on_page)
	pr.add_child(_page_opt)
	_btn(pr, "+", _add_page)
	_btn(pr, "−", _del_page)
	var cond := HBoxContainer.new()
	_ev_box.add_child(cond)
	_add(cond, "条件")
	_self_sw = OptionButton.new()
	for s in ["无", "A", "B", "C", "D"]:
		_self_sw.add_item(s)
	_self_sw.item_selected.connect(func(_i): _store_when())
	cond.add_child(_self_sw)
	_switch_opt = OptionButton.new()
	_switch_opt.item_selected.connect(_on_when_switch_opt)
	cond.add_child(_switch_opt)
	_switch_id = LineEdit.new()
	_switch_id.placeholder_text = "开关 id"
	_switch_id.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_switch_id.text_changed.connect(func(_t): _store_when())
	cond.add_child(_switch_id)
	var item_row := HBoxContainer.new()
	_ev_box.add_child(item_row)
	_add(item_row, "持有")
	_item_when = OptionButton.new()
	_item_when.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fill_item_opt(_item_when, true)
	_item_when.item_selected.connect(func(_i): _store_when())
	item_row.add_child(_item_when)
	var gr := HBoxContainer.new()
	_ev_box.add_child(gr)
	_add(gr, "图形")
	_g_charset_opt = OptionButton.new()
	_g_charset_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_g_charset_opt.item_selected.connect(_on_g_charset_opt)
	gr.add_child(_g_charset_opt)
	_g_charset = LineEdit.new()
	_g_charset.placeholder_text = "!Chest 或行走图 id"
	_g_charset.text_changed.connect(func(_t): _store_graphic())
	_ev_box.add_child(_g_charset)
	var gi := HBoxContainer.new()
	_ev_box.add_child(gi)
	_add(gi, "编号")
	_g_index = SpinBox.new()
	_g_index.max_value = 7
	_g_index.value_changed.connect(func(_v): _store_graphic())
	gi.add_child(_g_index)
	_add(gi, "朝向")
	_g_dir = OptionButton.new()
	_fill_dir(_g_dir)
	_g_dir.item_selected.connect(func(_i): _store_graphic())
	gi.add_child(_g_dir)
	_add(_ev_box, "指令")
	_cmds = ItemList.new()
	_cmds.custom_minimum_size = Vector2(0, 88)
	_cmds.item_selected.connect(_on_cmd)
	_ev_box.add_child(_cmds)
	_param_box = VBoxContainer.new()
	_param_box.add_theme_constant_override("separation", 4)
	_ev_box.add_child(_param_box)
	_build_params()
	var cmd_row := HBoxContainer.new()
	_ev_box.add_child(cmd_row)
	_add_op = OptionButton.new()
	for row in EventCommands.OPS:
		_add_op.add_item(str(row["label"]))
		_add_op.set_item_metadata(_add_op.item_count - 1, str(row["id"]))
	_add_op.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cmd_row.add_child(_add_op)
	_btn(cmd_row, "添加", _add_cmd)
	_btn(cmd_row, "↑", func(): _move_cmd(-1))
	_btn(cmd_row, "↓", func(): _move_cmd(1))
	_btn(cmd_row, "删", _del_cmd)


func _build_params() -> void:
	_add(_param_box, "选中指令")
	_p_text = TextEdit.new()
	_p_text.custom_minimum_size = Vector2(0, 52)
	_p_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_p_text.text_changed.connect(_store_params)
	_param_box.add_child(_p_text)
	var ir := HBoxContainer.new()
	_param_box.add_child(ir)
	_add(ir, "物品")
	_p_item = OptionButton.new()
	_p_item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fill_item_opt(_p_item)
	_p_item.item_selected.connect(func(_i): _store_params())
	ir.add_child(_p_item)
	_p_qty = SpinBox.new()
	_p_qty.min_value = 1
	_p_qty.max_value = 99
	_p_qty.value = 1
	_p_qty.value_changed.connect(func(_v): _store_params())
	ir.add_child(_p_qty)
	var ar := HBoxContainer.new()
	_param_box.add_child(ar)
	_add(ar, "数量/金币")
	_p_amount = SpinBox.new()
	_p_amount.min_value = 0
	_p_amount.max_value = 999999
	_p_amount.value = 10
	_p_amount.value_changed.connect(func(_v): _store_params())
	ar.add_child(_p_amount)
	var sr := HBoxContainer.new()
	_param_box.add_child(sr)
	_add(sr, "开关")
	_p_switch_opt = OptionButton.new()
	_p_switch_opt.item_selected.connect(_on_cmd_switch_opt)
	sr.add_child(_p_switch_opt)
	_p_switch = LineEdit.new()
	_p_switch.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_p_switch.text_changed.connect(func(_t): _store_params())
	sr.add_child(_p_switch)
	_p_letter = OptionButton.new()
	for L in ["A", "B", "C", "D"]:
		_p_letter.add_item(L)
	_p_letter.item_selected.connect(func(_i): _store_params())
	sr.add_child(_p_letter)
	_p_on = CheckBox.new()
	_p_on.text = "开"
	_p_on.button_pressed = true
	_p_on.toggled.connect(func(_v): _store_params())
	sr.add_child(_p_on)
	var shopr := HBoxContainer.new()
	_param_box.add_child(shopr)
	_add(shopr, "商店")
	_p_shop = OptionButton.new()
	_p_shop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fill_shop_opt(_p_shop)
	_p_shop.item_selected.connect(func(_i): _store_params())
	shopr.add_child(_p_shop)
	var tr := HBoxContainer.new()
	_param_box.add_child(tr)
	_add(tr, "传送")
	_p_map_opt = OptionButton.new()
	_p_map_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_p_map_opt.item_selected.connect(_on_cmd_map_opt)
	tr.add_child(_p_map_opt)
	_p_map = LineEdit.new()
	_p_map.placeholder_text = "地图 id"
	_p_map.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_p_map.text_changed.connect(func(_t): _store_params())
	tr.add_child(_p_map)
	_p_cx = SpinBox.new()
	_p_cx.max_value = 1000
	_p_cx.value_changed.connect(func(_v): _store_params())
	tr.add_child(_p_cx)
	_p_cy = SpinBox.new()
	_p_cy.max_value = 1000
	_p_cy.value_changed.connect(func(_v): _store_params())
	tr.add_child(_p_cy)
	var wr := HBoxContainer.new()
	_param_box.add_child(wr)
	_add(wr, "等待(秒)")
	_p_wait = SpinBox.new()
	_p_wait.min_value = 0.05
	_p_wait.max_value = 60.0
	_p_wait.step = 0.05
	_p_wait.value = 0.5
	_p_wait.value_changed.connect(func(_v): _store_params())
	wr.add_child(_p_wait)
	var aud := HBoxContainer.new()
	_param_box.add_child(aud)
	_add(aud, "音频")
	_p_audio_opt = OptionButton.new()
	_p_audio_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_p_audio_opt.item_selected.connect(_on_audio_opt)
	aud.add_child(_p_audio_opt)
	_p_audio = LineEdit.new()
	_p_audio.placeholder_text = "文件名（不含扩展名）"
	_p_audio.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_p_audio.text_changed.connect(func(_t): _store_params())
	aud.add_child(_p_audio)
	var fr := HBoxContainer.new()
	_param_box.add_child(fr)
	_add(fr, "脸图")
	_p_face_opt = OptionButton.new()
	_p_face_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_p_face_opt.item_selected.connect(_on_face_opt)
	fr.add_child(_p_face_opt)
	_p_face_index = SpinBox.new()
	_p_face_index.max_value = 7
	_p_face_index.value_changed.connect(func(_v): _store_params())
	fr.add_child(_p_face_index)
	_choices_lbl = Label.new()
	_choices_lbl.text = "选项（每行一个）"
	_choices_lbl.visible = false
	_param_box.add_child(_choices_lbl)
	_p_choices = TextEdit.new()
	_p_choices.custom_minimum_size = Vector2(0, 48)
	_p_choices.visible = false
	_p_choices.text_changed.connect(_store_params)
	_param_box.add_child(_p_choices)
	_opt_box = VBoxContainer.new()
	_opt_box.add_theme_constant_override("separation", 4)
	_param_box.add_child(_opt_box)
	_add(_opt_box, "选项")
	_opt_list = ItemList.new()
	_opt_list.custom_minimum_size = Vector2(0, 64)
	_opt_list.item_selected.connect(_on_opt)
	_opt_box.add_child(_opt_list)
	var orow := HBoxContainer.new()
	_opt_box.add_child(orow)
	_opt_name = LineEdit.new()
	_opt_name.placeholder_text = "选项文案"
	_opt_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_opt_name.text_changed.connect(func(_t): _rename_opt())
	orow.add_child(_opt_name)
	_btn(orow, "+", _add_opt)
	_btn(orow, "−", _del_opt)
	_add(_opt_box, "此选项的指令")
	_branch_cmds = ItemList.new()
	_branch_cmds.custom_minimum_size = Vector2(0, 64)
	_branch_cmds.item_selected.connect(_on_branch_cmd)
	_opt_box.add_child(_branch_cmds)
	var brow := HBoxContainer.new()
	_opt_box.add_child(brow)
	_btn(brow, "添加指令", _add_branch_cmd)
	_btn(brow, "↑", func(): _move_branch_cmd(-1))
	_btn(brow, "↓", func(): _move_branch_cmd(1))
	_btn(brow, "删", _del_branch_cmd)


func _build_npc(parent: Node) -> void:
	_npc_box = VBoxContainer.new()
	_npc_box.add_theme_constant_override("separation", 4)
	parent.add_child(_npc_box)
	_add(_npc_box, "名称")
	_name = LineEdit.new()
	_npc_box.add_child(_name)
	_add(_npc_box, "行走图")
	_charset_opt = OptionButton.new()
	_charset_opt.item_selected.connect(_on_charset_opt)
	_npc_box.add_child(_charset_opt)
	_charset = LineEdit.new()
	_charset.placeholder_text = "Actor1 或导入的 id"
	_npc_box.add_child(_charset)
	var nr := HBoxContainer.new()
	_npc_box.add_child(nr)
	_add(nr, "朝向")
	_dir = OptionButton.new()
	_fill_dir(_dir)
	nr.add_child(_dir)
	_add(nr, "编号")
	_char_index = SpinBox.new()
	_char_index.max_value = 7
	nr.add_child(_char_index)
	_wander = CheckBox.new()
	_wander.text = "徘徊"
	_npc_box.add_child(_wander)
	_npc_through = CheckBox.new()
	_npc_through.text = "穿透"
	_npc_box.add_child(_npc_through)
	var kr := HBoxContainer.new()
	_npc_box.add_child(kr)
	_add(kr, "类型")
	_npc_kind = OptionButton.new()
	_npc_kind.add_item("路人", 0)
	_npc_kind.set_item_metadata(0, "normal")
	_npc_kind.add_item("怪物", 1)
	_npc_kind.set_item_metadata(1, "monster")
	_npc_kind.add_item("物件", 2)
	_npc_kind.set_item_metadata(2, "object")
	_npc_kind.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_npc_kind.item_selected.connect(func(_i): _on_npc_kind())
	kr.add_child(_npc_kind)
	var cr := HBoxContainer.new()
	_npc_box.add_child(cr)
	_hostile = CheckBox.new()
	_hostile.text = "敌对"
	_hostile.toggled.connect(func(_on): _sync_npc_combat())
	cr.add_child(_hostile)
	_aggressive = CheckBox.new()
	_aggressive.text = "主动"
	cr.add_child(_aggressive)
	var lr := HBoxContainer.new()
	_npc_box.add_child(lr)
	_add(lr, "等级")
	_level = SpinBox.new()
	_level.min_value = 1
	_level.max_value = 99
	_level.value = 1
	lr.add_child(_level)
	_add(lr, "徘徊半径")
	_wander_r = SpinBox.new()
	_wander_r.min_value = 0
	_wander_r.max_value = 20
	_wander_r.value = 0
	lr.add_child(_wander_r)
	_add(_npc_box, "对话")
	_text = LineEdit.new()
	_npc_box.add_child(_text)


func _build_warp(parent: Node) -> void:
	_warp_box = VBoxContainer.new()
	_warp_box.add_theme_constant_override("separation", 4)
	parent.add_child(_warp_box)
	_add(_warp_box, "目标地图")
	_to_map_opt = OptionButton.new()
	_to_map_opt.item_selected.connect(_on_map_opt)
	_warp_box.add_child(_to_map_opt)
	_to_map = LineEdit.new()
	_to_map.placeholder_text = "包内 map id"
	_warp_box.add_child(_to_map)
	var row := HBoxContainer.new()
	_warp_box.add_child(row)
	_add(row, "X")
	_to_x = SpinBox.new()
	_to_x.max_value = 1000
	row.add_child(_to_x)
	_add(row, "Y")
	_to_y = SpinBox.new()
	_to_y.max_value = 1000
	row.add_child(_to_y)
	var fr := HBoxContainer.new()
	_warp_box.add_child(fr)
	_add(fr, "朝向")
	_facing = OptionButton.new()
	_fill_dir(_facing)
	fr.add_child(_facing)
	_add(_warp_box, "提示")
	_warp_msg = LineEdit.new()
	_warp_box.add_child(_warp_msg)


func _apply() -> void:
	if doc == null:
		return
	if doc.has_method("remove_entity_at"):
		doc.remove_entity_at(cell)
	else:
		_delete_silent()
	var k := _kind.get_selected_id()
	match k:
		0:
			_store_when()
			_store_params()
			var eid := _id.text.strip_edges()
			if eid == "":
				eid = "ev_%d_%d" % [cell.x, cell.y]
			var ev := {
				"id": eid,
				"cell": {"x": cell.x, "y": cell.y},
				"trigger": EventCommands.trigger_id_of(_trigger),
				"through": _through.button_pressed,
				"pages": _pages.duplicate(true),
			}
			doc.events.append(ev)
		1:
			var cs := _charset.text.strip_edges()
			if cs == "":
				cs = "Actor1"
			var n: Dictionary = doc.add_npc(cell, cs, _name.text if _name.text != "" else "NPC")
			n["interact_text"] = _text.text
			n["direction"] = _dir_value(_dir)
			n["index"] = int(_char_index.value)
			n["through"] = _npc_through.button_pressed
			n["hostile"] = _hostile.button_pressed if _hostile else false
			n["aggressive"] = bool(n["hostile"]) and (_aggressive.button_pressed if _aggressive else false)
			n["kind"] = _npc_kind_id()
			n["level"] = int(_level.value) if _level else 1
			n["wander_radius"] = int(_wander_r.value) if _wander_r else 0
			n["wander"] = (_wander.button_pressed if _wander else false) or int(n["wander_radius"]) > 0
		2:
			var tm := _to_map.text.strip_edges()
			if tm == "":
				tm = "Map002"
			var w: Dictionary = doc.add_warp(cell, tm, Vector2i(int(_to_x.value), int(_to_y.value)), _dir_value(_facing))
			w["message"] = _warp_msg.text
	doc.dirty = true
	changed.emit()
	_info.text = "已写入 %d,%d" % [cell.x, cell.y]
	_reload_list()


func _apply_chest() -> void:
	if doc == null:
		return
	if doc.has_method("remove_entity_at"):
		doc.remove_entity_at(cell)
	var ev: Dictionary = EventCommands.make_chest(cell)
	doc.events.append(ev)
	doc.dirty = true
	changed.emit()
	load_cell(doc, cell)
	_info.text = "已放宝箱 %d,%d" % [cell.x, cell.y]


func _delete() -> void:
	if doc == null:
		return
	if doc.has_method("remove_entity_at"):
		doc.remove_entity_at(cell)
	else:
		_delete_silent()
	changed.emit()
	_info.text = "已清除 %d,%d" % [cell.x, cell.y]
	_reload_list()


func _delete_silent() -> void:
	if doc == null:
		return
	if doc.has_method("remove_entity_at"):
		doc.remove_entity_at(cell)
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


func _reload_list() -> void:
	if _list == null:
		return
	_list.clear()
	if doc == null:
		return
	for ev in doc.events:
		if typeof(ev) != TYPE_DICTIONARY:
			continue
		var c: Variant = ev.get("cell", {})
		var x := int(c.get("x", 0)) if typeof(c) == TYPE_DICTIONARY else 0
		var y := int(c.get("y", 0)) if typeof(c) == TYPE_DICTIONARY else 0
		var idx := _list.add_item("事件 %s  (%d,%d)" % [str(ev.get("id", "")), x, y])
		_list.set_item_metadata(idx, {"kind": "event", "x": x, "y": y})
	for n in doc.npcs:
		if typeof(n) != TYPE_DICTIONARY:
			continue
		var c2: Variant = n.get("cell", {})
		var x2 := int(c2.get("x", 0)) if typeof(c2) == TYPE_DICTIONARY else 0
		var y2 := int(c2.get("y", 0)) if typeof(c2) == TYPE_DICTIONARY else 0
		var idx2 := _list.add_item("NPC %s  (%d,%d)" % [str(n.get("name", n.get("id", ""))), x2, y2])
		_list.set_item_metadata(idx2, {"kind": "npc", "x": x2, "y": y2})
	for w in doc.warps:
		if typeof(w) != TYPE_DICTIONARY:
			continue
		var c3: Variant = w.get("from_cell", {})
		var x3 := int(c3.get("x", 0)) if typeof(c3) == TYPE_DICTIONARY else 0
		var y3 := int(c3.get("y", 0)) if typeof(c3) == TYPE_DICTIONARY else 0
		var idx3 := _list.add_item("传送 → %s  (%d,%d)" % [str(w.get("to_map", w.get("to_map_id", ""))), x3, y3])
		_list.set_item_metadata(idx3, {"kind": "warp", "x": x3, "y": y3})


func _highlight_list_cell() -> void:
	if _list == null:
		return
	for i in range(_list.item_count):
		var meta: Variant = _list.get_item_metadata(i)
		if typeof(meta) == TYPE_DICTIONARY and int(meta.get("x", -1)) == cell.x and int(meta.get("y", -1)) == cell.y:
			_list.select(i)
			_list.ensure_current_is_visible()
			return


func _on_list(idx: int) -> void:
	var meta: Variant = _list.get_item_metadata(idx)
	if typeof(meta) != TYPE_DICTIONARY:
		return
	var c := Vector2i(int(meta.get("x", 0)), int(meta.get("y", 0)))
	if c != cell and doc:
		load_cell(doc, c)
	jump_requested.emit(c)


func _sync_kind() -> void:
	var k := _kind.get_selected_id() if _kind else 0
	if _ev_box:
		_ev_box.visible = k == 0
	if _npc_box:
		_npc_box.visible = k == 1
	if _warp_box:
		_warp_box.visible = k == 2


func _reload_pages() -> void:
	if _pages.is_empty():
		_pages = [EventCommands.default_page()]
	_page_idx = clampi(_page_idx, 0, _pages.size() - 1)
	if _page_opt:
		_page_opt.clear()
		for i in range(_pages.size()):
			var p: Dictionary = _pages[i] if typeof(_pages[i]) == TYPE_DICTIONARY else {}
			_page_opt.add_item("%d · %s" % [i + 1, EventCommands.page_when_label(p)])
		_page_opt.select(_page_idx)
	_load_when()
	_reload_cmds()


func _on_page(idx: int) -> void:
	if _loading:
		return
	_store_when()
	_store_params()
	_page_idx = idx
	_load_when()
	_reload_cmds()


func _add_page() -> void:
	_store_when()
	_pages.append(EventCommands.default_page())
	_page_idx = _pages.size() - 1
	_reload_pages()


func _del_page() -> void:
	if _pages.size() <= 1:
		return
	_pages.remove_at(_page_idx)
	_page_idx = mini(_page_idx, _pages.size() - 1)
	_reload_pages()


func _load_when() -> void:
	var page := _current_page()
	var when_v: Variant = page.get("when", {})
	var when: Dictionary = when_v if typeof(when_v) == TYPE_DICTIONARY else {}
	var ss := str(when.get("self_switch", "")).strip_edges()
	if _self_sw:
		var sel := 0
		for i in range(_self_sw.item_count):
			if _self_sw.get_item_text(i) == ss:
				sel = i
				break
		_self_sw.select(sel)
	if _switch_id:
		_switch_id.text = str(when.get("switch", when.get("switch_id", "")))
	_select_switch_opt(_switch_opt, str(when.get("switch", when.get("switch_id", ""))))
	var item_id := ""
	if when.has("item"):
		var iv: Variant = when.get("item")
		if typeof(iv) == TYPE_DICTIONARY:
			item_id = str(iv.get("item_id", iv.get("id", "")))
		else:
			item_id = str(iv)
	if item_id == "":
		item_id = str(when.get("item_id", "")).strip_edges()
	if _item_when:
		var picked := 0
		for i in range(_item_when.item_count):
			if str(_item_when.get_item_metadata(i)) == item_id:
				picked = i
				break
		_item_when.select(picked)
	var trig := str(page.get("trigger", "")).strip_edges()
	if trig == "":
		trig = _event_trigger
	_select_trigger(trig)
	_load_graphic()


func _store_when() -> void:
	if _loading:
		return
	var page := _current_page()
	var ss := _self_sw.get_item_text(_self_sw.selected) if _self_sw else "无"
	var iid := ""
	if _item_when and _item_when.item_count > 0:
		iid = str(_item_when.get_item_metadata(_item_when.selected))
	EventCommands.set_page_when(page, ss, _switch_id.text if _switch_id else "", iid)
	page["trigger"] = EventCommands.trigger_id_of(_trigger)
	_event_trigger = str(page["trigger"])
	if _page_opt and _page_idx >= 0 and _page_idx < _page_opt.item_count:
		_page_opt.set_item_text(_page_idx, "%d · %s" % [_page_idx + 1, EventCommands.page_when_label(page)])


func _load_graphic() -> void:
	var page := _current_page()
	var g: Dictionary = EventCommands.page_graphic(page)
	var was := _loading
	_loading = true
	if _g_charset:
		_g_charset.text = str(g.get("charset", ""))
	_select_g_charset_opt(str(g.get("charset", "")))
	if _g_index:
		_g_index.value = int(g.get("index", 0))
	if _g_dir:
		_select_dir(_g_dir, int(g.get("direction", 2)))
	_loading = was


func _store_graphic() -> void:
	if _loading:
		return
	var page := _current_page()
	var cs := _g_charset.text.strip_edges() if _g_charset else ""
	var idx := int(_g_index.value) if _g_index else 0
	var d := _dir_value(_g_dir) if _g_dir else 2
	EventCommands.set_page_graphic(page, cs, idx, d)


func _select_g_charset_opt(id: String) -> void:
	_selectors_module_logic._select_g_charset_opt(id)
func _on_g_charset_opt(idx: int) -> void:
	_selectors_module_logic._on_g_charset_opt(idx)
func _current_page() -> Dictionary:
	if _page_idx < 0 or _page_idx >= _pages.size():
		_pages = [EventCommands.default_page()]
		_page_idx = 0
	if typeof(_pages[_page_idx]) != TYPE_DICTIONARY:
		_pages[_page_idx] = EventCommands.default_page()
	return _pages[_page_idx]


func _page_commands() -> Array:
	var page := _current_page()
	var cv: Variant = page.get("commands", [])
	if typeof(cv) != TYPE_ARRAY:
		cv = []
		page["commands"] = cv
	return cv


func _reload_cmds() -> void:
	if _cmds == null:
		return
	_cmds.clear()
	var cmds := _page_commands()
	for c in cmds:
		if typeof(c) == TYPE_DICTIONARY:
			_cmds.add_item(EventCommands.summarize(c))
	if not cmds.is_empty():
		_cmds.select(mini(_cmds.item_count - 1, 0))
		_on_cmd(0)
	else:
		_show_params("")


func _on_cmd(idx: int) -> void:
	_param_src = "page"
	var cmds := _page_commands()
	if idx < 0 or idx >= cmds.size() or typeof(cmds[idx]) != TYPE_DICTIONARY:
		_show_params("")
		return
	_load_params(cmds[idx])
	if _is_choices_op(str(cmds[idx].get("op", ""))):
		_reload_options(cmds[idx])


func _add_cmd() -> void:
	var op := "text"
	if _add_op and _add_op.selected >= 0:
		op = str(_add_op.get_item_metadata(_add_op.selected))
	var cmds := _page_commands()
	cmds.append(EventCommands.default_command(op))
	_reload_cmds()
	if _cmds.item_count > 0:
		_cmds.select(_cmds.item_count - 1)
		_on_cmd(_cmds.item_count - 1)


func _del_cmd() -> void:
	var sel := _cmds.get_selected_items()
	if sel.is_empty():
		return
	var cmds := _page_commands()
	if sel[0] >= 0 and sel[0] < cmds.size():
		cmds.remove_at(sel[0])
	_reload_cmds()


func _move_cmd(delta: int) -> void:
	var sel := _cmds.get_selected_items()
	if sel.is_empty():
		return
	var cmds := _page_commands()
	var i: int = sel[0]
	var j := i + delta
	if j < 0 or j >= cmds.size():
		return
	var tmp = cmds[i]
	cmds[i] = cmds[j]
	cmds[j] = tmp
	_reload_cmds()
	_cmds.select(j)
	_on_cmd(j)


func _show_params(op: String) -> void:
	var key := op.strip_edges().to_lower()
	var is_ch := key in ["choices", "choice", "show_choices"]
	var page_ch := _page_cmd_is_choices()
	var is_text := key in ["text", "show_text", "show_npc_dialogue", "system", "message", "system_message"] or (is_ch and _param_src == "page")
	_p_text.visible = is_text
	_p_item.get_parent().visible = key in ["give_item", "take_item"]
	_p_amount.get_parent().visible = key in ["give_gold", "take_gold"]
	var sw := key in ["set_switch", "set_self_switch"]
	_p_switch.get_parent().visible = sw
	if sw:
		_p_switch.visible = key == "set_switch"
		if _p_switch_opt:
			_p_switch_opt.visible = key == "set_switch"
		_p_letter.visible = key == "set_self_switch"
	_p_shop.get_parent().visible = key == "open_shop"
	_p_map.get_parent().visible = key == "transfer"
	if _p_wait:
		_p_wait.get_parent().visible = key == "wait"
	if _p_audio:
		_p_audio.get_parent().visible = key in ["play_bgm", "play_bgs", "play_me", "play_se", "se"]
	if _p_face_opt:
		_p_face_opt.get_parent().visible = key in ["text", "show_text", "show_npc_dialogue", "choices", "choice", "show_choices"]
	if _p_choices:
		_p_choices.visible = false
	if _choices_lbl:
		_choices_lbl.visible = false
	if _opt_box:
		_opt_box.visible = page_ch


func _load_params(cmd: Dictionary) -> void:
	_loading = true
	var op := str(cmd.get("op", cmd.get("type", ""))).strip_edges().to_lower()
	_show_params(op)
	_p_text.text = str(cmd.get("text", cmd.get("body", cmd.get("message", ""))))
	_select_item_opt(str(cmd.get("item_id", "")))
	_p_qty.value = maxi(int(cmd.get("qty", 1)), 1)
	_p_amount.value = int(cmd.get("amount", cmd.get("gold", 0)))
	_p_switch.text = str(cmd.get("id", cmd.get("switch", "")))
	var letter := str(cmd.get("letter", cmd.get("self_switch", "A")))
	for i in range(_p_letter.item_count):
		if _p_letter.get_item_text(i) == letter:
			_p_letter.select(i)
			break
	_p_on.button_pressed = bool(cmd.get("value", true))
	_select_shop_opt(str(cmd.get("shop_id", cmd.get("id", ""))))
	if _p_audio:
		_p_audio.text = str(cmd.get("id", cmd.get("name", cmd.get("file", ""))))
	_fill_audio_opt(op, str(cmd.get("id", cmd.get("name", cmd.get("file", "")))))
	if _p_wait:
		_p_wait.value = EventCommands.wait_duration(cmd)
	_p_map.text = str(cmd.get("to_map", cmd.get("map_id", "")))
	_select_cmd_map_opt(str(cmd.get("to_map", cmd.get("map_id", ""))))
	_select_switch_opt(_p_switch_opt, str(cmd.get("id", cmd.get("switch", ""))))
	var face: Dictionary = EventCommands.cmd_face(cmd)
	_select_face_opt(str(face.get("id", "")))
	if _p_face_index:
		_p_face_index.value = int(face.get("index", 0))
	var tc: Variant = cmd.get("to_cell", {})
	if typeof(tc) == TYPE_DICTIONARY:
		_p_cx.value = int(tc.get("x", 0))
		_p_cy.value = int(tc.get("y", 0))
	_p_choices.text = "\n".join(EventCommands.choice_labels(cmd))
	if _is_choices_op(op) and _param_src == "page":
		_reload_options(cmd)
	_loading = false


func _store_params() -> void:
	if _loading or _cmds == null:
		return
	var cmd := _active_cmd()
	if cmd.is_empty():
		return
	var op := str(cmd.get("op", "")).strip_edges().to_lower()
	match op:
		"text", "show_text", "show_npc_dialogue", "system", "message", "system_message":
			cmd["text"] = _p_text.text
			EventCommands.set_cmd_face(cmd, _face_id_of(), int(_p_face_index.value) if _p_face_index else 0)
		"give_item", "take_item":
			cmd["item_id"] = _item_id_of(_p_item)
			cmd["qty"] = int(_p_qty.value)
		"give_gold", "take_gold":
			cmd["amount"] = int(_p_amount.value)
		"set_switch":
			cmd["id"] = _p_switch.text.strip_edges()
			cmd["value"] = _p_on.button_pressed
		"set_self_switch":
			cmd["letter"] = _p_letter.get_item_text(_p_letter.selected)
			cmd["value"] = _p_on.button_pressed
		"open_shop":
			cmd["shop_id"] = _shop_id_of(_p_shop)
		"transfer":
			cmd["to_map"] = _p_map.text.strip_edges()
			cmd["to_cell"] = {"x": int(_p_cx.value), "y": int(_p_cy.value)}
		"play_bgm", "play_bgs", "play_me", "play_se", "se":
			if _p_audio:
				cmd["id"] = _p_audio.text.strip_edges()
		"wait":
			if _p_wait:
				cmd["duration"] = float(_p_wait.value)
		"choices", "choice", "show_choices":
			cmd["text"] = _p_text.text
			EventCommands.set_cmd_face(cmd, _face_id_of(), int(_p_face_index.value) if _p_face_index else 0)
	_refresh_cmd_label()


func _is_choices_op(op: String) -> bool:
	return op.strip_edges().to_lower() in ["choices", "choice", "show_choices"]


func _page_cmd_is_choices() -> bool:
	var cmd := _selected_page_cmd()
	return not cmd.is_empty() and _is_choices_op(str(cmd.get("op", "")))


func _selected_page_cmd() -> Dictionary:
	if _cmds == null:
		return {}
	var sel := _cmds.get_selected_items()
	var cmds := _page_commands()
	if sel.is_empty() or sel[0] < 0 or sel[0] >= cmds.size() or typeof(cmds[sel[0]]) != TYPE_DICTIONARY:
		return {}
	return cmds[sel[0]]


func _active_cmd() -> Dictionary:
	if _param_src == "branch":
		var parent := _selected_page_cmd()
		if parent.is_empty():
			return {}
		var oi := _opt_index()
		var bcmds := EventCommands.option_commands(parent, oi)
		if _branch_cmds == null:
			return {}
		var bsel := _branch_cmds.get_selected_items()
		if bsel.is_empty() or bsel[0] < 0 or bsel[0] >= bcmds.size() or typeof(bcmds[bsel[0]]) != TYPE_DICTIONARY:
			return parent if _is_choices_op(str(parent.get("op", ""))) else {}
		return bcmds[bsel[0]]
	return _selected_page_cmd()


func _opt_index() -> int:
	if _opt_list == null:
		return 0
	var sel := _opt_list.get_selected_items()
	return sel[0] if not sel.is_empty() else 0


func _reload_options(cmd: Dictionary) -> void:
	if _opt_list == null:
		return
	var keep := _opt_index()
	_opt_list.clear()
	var opts := EventCommands.options_of(cmd)
	for opt in opts:
		if typeof(opt) == TYPE_DICTIONARY:
			_opt_list.add_item(EventCommands.summarize_option(opt))
	if _opt_list.item_count > 0:
		keep = clampi(keep, 0, _opt_list.item_count - 1)
		_opt_list.select(keep)
		_on_opt(keep)
	else:
		_reload_branch_cmds()


func _on_opt(idx: int) -> void:
	var cmd := _selected_page_cmd()
	if cmd.is_empty():
		return
	var opts := EventCommands.options_of(cmd)
	if idx < 0 or idx >= opts.size() or typeof(opts[idx]) != TYPE_DICTIONARY:
		return
	if _opt_name and not _loading:
		var was := _loading
		_loading = true
		_opt_name.text = str(opts[idx].get("label", ""))
		_loading = was
	elif _opt_name:
		_opt_name.text = str(opts[idx].get("label", ""))
	_reload_branch_cmds()


func _add_opt() -> void:
	var cmd := _selected_page_cmd()
	if cmd.is_empty() or not _is_choices_op(str(cmd.get("op", ""))):
		return
	EventCommands.add_option(cmd, "")
	_reload_options(cmd)
	if _opt_list.item_count > 0:
		_opt_list.select(_opt_list.item_count - 1)
		_on_opt(_opt_list.item_count - 1)
	_refresh_cmd_label()


func _del_opt() -> void:
	var cmd := _selected_page_cmd()
	if cmd.is_empty():
		return
	EventCommands.remove_option(cmd, _opt_index())
	_reload_options(cmd)
	_refresh_cmd_label()


func _rename_opt() -> void:
	if _loading:
		return
	var cmd := _selected_page_cmd()
	if cmd.is_empty() or _opt_name == null:
		return
	EventCommands.set_option_label(cmd, _opt_index(), _opt_name.text)
	if _opt_list and not _opt_list.get_selected_items().is_empty():
		var i: int = _opt_list.get_selected_items()[0]
		var opts := EventCommands.options_of(cmd)
		if i >= 0 and i < opts.size() and typeof(opts[i]) == TYPE_DICTIONARY:
			_opt_list.set_item_text(i, EventCommands.summarize_option(opts[i]))


func _reload_branch_cmds() -> void:
	if _branch_cmds == null:
		return
	_branch_cmds.clear()
	var parent := _selected_page_cmd()
	var bcmds := EventCommands.option_commands(parent, _opt_index()) if not parent.is_empty() else []
	for c in bcmds:
		if typeof(c) == TYPE_DICTIONARY:
			_branch_cmds.add_item(EventCommands.summarize(c))


func _on_branch_cmd(idx: int) -> void:
	_param_src = "branch"
	var parent := _selected_page_cmd()
	var bcmds := EventCommands.option_commands(parent, _opt_index()) if not parent.is_empty() else []
	if idx < 0 or idx >= bcmds.size() or typeof(bcmds[idx]) != TYPE_DICTIONARY:
		return
	_load_params(bcmds[idx])


func _add_branch_cmd() -> void:
	var parent := _selected_page_cmd()
	if parent.is_empty() or not _is_choices_op(str(parent.get("op", ""))):
		return
	if EventCommands.options_of(parent).is_empty():
		EventCommands.add_option(parent, "选项 1")
		_reload_options(parent)
	var op := "text"
	if _add_op and _add_op.selected >= 0:
		op = str(_add_op.get_item_metadata(_add_op.selected))
	var bcmds := EventCommands.option_commands(parent, _opt_index())
	bcmds.append(EventCommands.default_command(op))
	_reload_branch_cmds()
	if _branch_cmds.item_count > 0:
		_branch_cmds.select(_branch_cmds.item_count - 1)
		_on_branch_cmd(_branch_cmds.item_count - 1)
	_reload_options(parent)


func _del_branch_cmd() -> void:
	var parent := _selected_page_cmd()
	if parent.is_empty() or _branch_cmds == null:
		return
	var sel := _branch_cmds.get_selected_items()
	if sel.is_empty():
		return
	var bcmds := EventCommands.option_commands(parent, _opt_index())
	if sel[0] >= 0 and sel[0] < bcmds.size():
		bcmds.remove_at(sel[0])
	_reload_branch_cmds()
	_reload_options(parent)


func _move_branch_cmd(delta: int) -> void:
	var parent := _selected_page_cmd()
	if parent.is_empty() or _branch_cmds == null:
		return
	var sel := _branch_cmds.get_selected_items()
	if sel.is_empty():
		return
	var bcmds := EventCommands.option_commands(parent, _opt_index())
	var i: int = sel[0]
	var j := i + delta
	if j < 0 or j >= bcmds.size():
		return
	var tmp = bcmds[i]
	bcmds[i] = bcmds[j]
	bcmds[j] = tmp
	_reload_branch_cmds()
	_branch_cmds.select(j)
	_on_branch_cmd(j)


func _refresh_cmd_label() -> void:
	if _param_src == "branch" and _branch_cmds:
		var sel := _branch_cmds.get_selected_items()
		var cmd := _active_cmd()
		if not sel.is_empty() and not cmd.is_empty():
			_branch_cmds.set_item_text(sel[0], EventCommands.summarize(cmd))
		var parent := _selected_page_cmd()
		if not parent.is_empty() and _opt_list:
			var oi := _opt_index()
			var opts := EventCommands.options_of(parent)
			if oi >= 0 and oi < opts.size() and typeof(opts[oi]) == TYPE_DICTIONARY:
				_opt_list.set_item_text(oi, EventCommands.summarize_option(opts[oi]))
		return
	if _cmds == null:
		return
	var sel2 := _cmds.get_selected_items()
	var page_cmd := _selected_page_cmd()
	if not sel2.is_empty() and not page_cmd.is_empty():
		_cmds.set_item_text(sel2[0], EventCommands.summarize(page_cmd))


func _clear_fields() -> void:
	_id.text = ""
	_name.text = ""
	_charset.text = ""
	_text.text = ""
	_to_map.text = ""
	_to_x.value = 0
	_to_y.value = 0
	_warp_msg.text = ""
	_through.button_pressed = true
	_wander.button_pressed = false
	_npc_through.button_pressed = false
	if _hostile:
		_hostile.button_pressed = false
	if _aggressive:
		_aggressive.button_pressed = false
	if _level:
		_level.value = 1
	if _wander_r:
		_wander_r.value = 0
	_select_npc_kind("normal")
	_char_index.value = 0
	_event_trigger = "action"
	_select_trigger("action")
	_pages = [EventCommands.default_page()]
	_page_idx = 0
	_reload_pages()


func _select_trigger(trig: String) -> void:
	EventCommands.select_trigger_option(_trigger, trig)


func _fill_dir(opt: OptionButton) -> void:
	_selectors_module_logic._fill_dir(opt)
func _select_dir(opt: OptionButton, d: int) -> void:
	_selectors_module_logic._select_dir(opt, d)
func _dir_value(opt: OptionButton) -> int:
	return _selectors_module_logic._dir_value(opt)
func _fill_charset_opt() -> void:
	_selectors_module_logic._fill_charset_opt()
func _fill_one_charset_opt(opt: OptionButton) -> void:
	_selectors_module_logic._fill_one_charset_opt(opt)
func _select_charset_opt(id: String) -> void:
	_selectors_module_logic._select_charset_opt(id)
func _on_charset_opt(idx: int) -> void:
	_selectors_module_logic._on_charset_opt(idx)
func _fill_map_opt() -> void:
	_selectors_module_logic._fill_map_opt()
func _fill_one_map_opt(opt: OptionButton) -> void:
	_selectors_module_logic._fill_one_map_opt(opt)
func _select_map_opt(id: String) -> void:
	_selectors_module_logic._select_map_opt(id)
func _on_map_opt(idx: int) -> void:
	_selectors_module_logic._on_map_opt(idx)
func _load_catalogs() -> void:
	_selectors_module_logic._load_catalogs()
func _fill_item_opt(opt: OptionButton, allow_empty: bool = false) -> void:
	_selectors_module_logic._fill_item_opt(opt, allow_empty)
func _select_item_opt(id: String) -> void:
	_selectors_module_logic._select_item_opt(id)
func _item_id_of(opt: OptionButton) -> String:
	return _selectors_module_logic._item_id_of(opt)
func _fill_shop_opt(opt: OptionButton) -> void:
	_selectors_module_logic._fill_shop_opt(opt)
func _select_shop_opt(id: String) -> void:
	_selectors_module_logic._select_shop_opt(id)
func _shop_id_of(opt: OptionButton) -> String:
	return _selectors_module_logic._shop_id_of(opt)
func _add(parent: Node, text: String) -> void:
	var l := Label.new()
	l.text = text
	parent.add_child(l)


func _btn(parent: Node, text: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	parent.add_child(b)


func copy_current() -> bool:
	return _npc_module_logic.copy_current()
func paste_current() -> bool:
	return _npc_module_logic.paste_current()
func _npc_kind_id() -> String:
	return _npc_module_logic._npc_kind_id()
func _select_npc_kind(kind: String) -> void:
	_npc_module_logic._select_npc_kind(kind)
func _on_npc_kind() -> void:
	_npc_module_logic._on_npc_kind()
func _sync_npc_combat() -> void:
	_npc_module_logic._sync_npc_combat()
func _fill_switch_opts() -> void:
	_selectors_module_logic._fill_switch_opts()
func _fill_id_opt(opt: OptionButton, ids: PackedStringArray) -> void:
	_selectors_module_logic._fill_id_opt(opt, ids)
func _select_switch_opt(opt: OptionButton, id: String) -> void:
	_selectors_module_logic._select_switch_opt(opt, id)
func _on_when_switch_opt(idx: int) -> void:
	_selectors_module_logic._on_when_switch_opt(idx)
func _on_cmd_switch_opt(idx: int) -> void:
	_selectors_module_logic._on_cmd_switch_opt(idx)
func _on_cmd_map_opt(idx: int) -> void:
	_selectors_module_logic._on_cmd_map_opt(idx)
func _select_cmd_map_opt(id: String) -> void:
	_selectors_module_logic._select_cmd_map_opt(id)
func _fill_audio_opt(op: String, current: String) -> void:
	_selectors_module_logic._fill_audio_opt(op, current)
func _on_audio_opt(idx: int) -> void:
	_selectors_module_logic._on_audio_opt(idx)
func _fill_face_opt() -> void:
	_selectors_module_logic._fill_face_opt()
func _select_face_opt(id: String) -> void:
	_selectors_module_logic._select_face_opt(id)
func _on_face_opt(_idx: int) -> void:
	_selectors_module_logic._on_face_opt(_idx)
func _face_id_of() -> String:
	return _selectors_module_logic._face_id_of()