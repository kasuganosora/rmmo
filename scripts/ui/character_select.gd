extends Control
const Net = preload("res://scripts/net/net.gd")
const LookCatalog = preload("res://scripts/char/look_catalog.gd")
const MV = preload("res://scripts/char/mv_generator.gd")

@onready var list: ItemList = %CharList
@onready var status_label: Label = %Status
@onready var enter_btn: Button = %EnterButton
@onready var create_btn: Button = %CreateButton
@onready var back_btn: Button = %BackButton

var _chars: Array = []

func _ready() -> void:
	enter_btn.pressed.connect(_on_enter)
	create_btn.pressed.connect(func(): Net.session().go_character_create())
	back_btn.pressed.connect(func(): Net.session().go_login())
	Net.server().characters_ready.connect(_on_chars)
	status_label.text = "账号 %s @ %s" % [Net.session().username, Net.session().server_address]
	_refresh()
	call_deferred("_warmup_create")


func _warmup_create() -> void:
	MV.warmup(LookCatalog.GENDER_FEMALE)

func _refresh() -> void:
	list.clear()
	status_label.text = "正在加载角色…"
	Net.server().fetch_characters()

func _on_chars(chars: Array) -> void:
	_chars = chars
	Net.session().characters = chars
	list.clear()
	for c in chars:
		var label := "%s  Lv.%s  [%s]  %s" % [
			c.get("name", "?"),
			c.get("level", 1),
			_class_label(str(c.get("class_id", ""))),
			_gender_label(str(c.get("gender", LookCatalog.GENDER_FEMALE))),
		]
		var idx := list.add_item(label)
		var look := str(c.get("look_id", "1"))
		var gender := LookCatalog.normalize_gender(str(c.get("gender", LookCatalog.GENDER_FEMALE)))
		var tex: Texture2D = null
		var cust: Dictionary = c.get("customization", {}) if typeof(c.get("customization")) == TYPE_DICTIONARY else {}
		var sheet := str(cust.get("mv_sheet", ""))
		if sheet != "":
			tex = MV.load_sheet_texture(sheet)
		if tex == null:
			tex = LookCatalog.load_idle(look, "Front", gender)
		if tex:
			list.set_item_icon(idx, tex)
	if chars.is_empty():
		status_label.text = "还没有角色，点「创建角色」开始"
		enter_btn.disabled = true
	else:
		status_label.text = "已有 %d 个角色 · 选一个进入，或创建新角色" % chars.size()
		enter_btn.disabled = false
		_select_preferred(chars)

func _select_preferred(chars: Array) -> void:
	var prefer := int(Net.session().pending_select_id)
	if prefer < 0 and not Net.session().selected_character.is_empty():
		prefer = int(Net.session().selected_character.get("id", -1))
	var pick := 0
	if prefer >= 0:
		for i in range(chars.size()):
			if int(chars[i].get("id", -1)) == prefer:
				pick = i
				break
	list.select(pick)
	Net.session().pending_select_id = -1

func _class_label(class_id: String) -> String:
	match class_id:
		"mage":
			return "法师"
		"warrior":
			return "战士"
		_:
			return "冒险者"

func _gender_label(gender: String) -> String:
	if LookCatalog.normalize_gender(gender) == LookCatalog.GENDER_MALE:
		return "男"
	return "女"

func _on_enter() -> void:
	var sel := list.get_selected_items()
	if sel.is_empty():
		status_label.text = "请先选择一个角色"
		return
	var raw: Variant = _chars[sel[0]]
	if typeof(raw) != TYPE_DICTIONARY:
		status_label.text = "角色数据无效，请重新选择"
		return
	var ch: Dictionary = (raw as Dictionary).duplicate(true)
	Net.session().selected_character = ch
	Net.session().spawn_data = {}
	Net.session().loading_mode = ""
	Net.session().go_loading()
