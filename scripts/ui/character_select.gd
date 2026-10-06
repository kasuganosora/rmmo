extends Control
const Net = preload("res://scripts/net/net.gd")
const LookCatalog = preload("res://scripts/char/look_catalog.gd")
const MV = preload("res://scripts/char/mv_generator.gd")
const CharacterView3D = preload("res://scripts/char/character_view_3d.gd")
const Style = preload("res://scripts/ui/entry_style.gd")
var list: ItemList
var status_label: Label
var enter_btn: Button
var create_btn: Button
var back_btn: Button
var _chars: Array = []
var _entering := false
var _sidebar: VBoxContainer
var _scroll: ScrollContainer
var _stage: Control
var _portrait: TextureRect
var _identity: Label
var _details: Label
var _view: Node2D
var _turn := 0
var _turn_left: Button
var _turn_right: Button
var _account: Label
var _shadow: TextureRect

func _ready() -> void:
	Style.apply(self)
	_stage = Control.new(); _stage.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(_stage)
	_shadow = TextureRect.new(); _shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var shadow_gradient := Gradient.new()
	shadow_gradient.colors = PackedColorArray([Color(0, 0, 0, .65), Color(0, 0, 0, 0)])
	var shadow_texture := GradientTexture2D.new(); shadow_texture.gradient = shadow_gradient
	shadow_texture.fill = GradientTexture2D.FILL_RADIAL; shadow_texture.width = 256; shadow_texture.height = 64
	shadow_texture.fill_from = Vector2(.5, .5); shadow_texture.fill_to = Vector2(1, .5)
	_shadow.texture = shadow_texture; _stage.add_child(_shadow)
	_portrait = TextureRect.new(); _portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; _portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.add_child(_portrait); _portrait.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_identity = Style.label("", 30); _identity.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; add_child(_identity)
	_details = Style.label("", 16, Style.GOLD); _details.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; add_child(_details)
	_turn_left = Style.button("‹"); _turn_left.tooltip_text = "向左旋转角色"; _turn_left.flat = true; add_child(_turn_left)
	_turn_right = Style.button("›"); _turn_right.tooltip_text = "向右旋转角色"; _turn_right.flat = true; add_child(_turn_right)
	for button in [_turn_left, _turn_right]: button.add_theme_font_size_override("font_size", 28)
	_turn_left.pressed.connect(func(): _rotate(-1)); _turn_right.pressed.connect(func(): _rotate(1))
	_scroll = ScrollContainer.new(); _scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; add_child(_scroll)
	_sidebar = Style.column(_scroll, 16); _sidebar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sidebar.add_child(Style.label("选择角色", 30))
	_account = Style.label("账号 · " + Net.session().username, 14, Style.MUTED)
	_account.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS; _sidebar.add_child(_account)
	Style.divider(_sidebar)
	list = ItemList.new(); list.custom_minimum_size = Vector2(0, 230); list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list.allow_reselect = true; list.item_selected.connect(_show_character)
	list.item_activated.connect(func(_index: int): _on_enter()); _sidebar.add_child(list)
	status_label = Style.label("正在加载角色…", 14, Style.MUTED)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; status_label.custom_minimum_size.y = 36; _sidebar.add_child(status_label)
	enter_btn = Style.button("进入世界", true); enter_btn.disabled = true; _sidebar.add_child(enter_btn)
	create_btn = Style.button("创建角色"); _sidebar.add_child(create_btn)
	back_btn = Style.button("返回登录"); back_btn.flat = true; _sidebar.add_child(back_btn)
	enter_btn.pressed.connect(_on_enter)
	create_btn.pressed.connect(func(): Net.session().go_character_create())
	back_btn.pressed.connect(func(): Net.session().go_login())
	Net.server().characters_ready.connect(_on_chars)
	resized.connect(_layout); _layout()
	_refresh()

func _layout() -> void:
	if _scroll == null: return
	var narrow := size.x < 840
	var width := minf(340, size.x * .46) if narrow else 340.0
	_scroll.position = Vector2(size.x - width - (24 if narrow else 72), 32 if size.y < 650 else 64)
	_scroll.size = Vector2(width, maxf(120, size.y - _scroll.position.y - 24))
	_stage.position = Vector2(12, 32)
	_stage.size = Vector2(maxf(100, _scroll.position.x - 28), maxf(120, size.y - 180))
	var preview_size := minf(_stage.size.x, _stage.size.y)
	_shadow.size = Vector2(preview_size * .3, preview_size * .07)
	_shadow.position = Vector2((_stage.size.x - _shadow.size.x) / 2, (_stage.size.y - preview_size) / 2 + preview_size * .905)
	_identity.position = Vector2(12, size.y - 140); _identity.size = Vector2(_stage.size.x, 42)
	_identity.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_details.position = Vector2(12, size.y - 98); _details.size = Vector2(_stage.size.x, 30)
	_turn_left.position = Vector2(_stage.size.x / 2 - 52, size.y - 56); _turn_left.size = Vector2(48, 44)
	_turn_right.position = Vector2(_stage.size.x / 2 + 28, size.y - 56); _turn_right.size = Vector2(48, 44)
	list.custom_minimum_size.y = 170 if size.y < 650 else 230

func _refresh() -> void:
	list.clear(); enter_btn.disabled = true
	status_label.text = "正在加载角色…"
	Net.server().fetch_characters()

func _on_chars(chars: Array) -> void:
	if _entering: return
	_chars = []
	for character in chars:
		if character is Dictionary: _chars.append(character)
	Net.session().characters = _chars
	list.clear()
	for character in _chars:
		list.add_item("%s   ·   %s  Lv.%s" % [character.get("name", "?"), _class_label(str(character.get("class_id", ""))), character.get("level", 1)])
	enter_btn.disabled = _chars.is_empty()
	_turn_left.visible = not _chars.is_empty() and CharacterView3D.enabled()
	_turn_right.visible = _turn_left.visible
	_shadow.visible = not _chars.is_empty()
	if _chars.is_empty():
		status_label.text = "还没有角色，创建你的第一位冒险者"
		_identity.text = "旅程即将开始"; _details.text = "从创建角色开始"
		_portrait.texture = null
		if is_instance_valid(_view): _view.queue_free(); _view = null
		create_btn.grab_focus()
	else:
		status_label.text = "方向键选择角色 · 回车进入世界"
		_select_preferred(_chars)
		list.grab_focus()

func _select_preferred(chars: Array) -> void:
	var prefer := int(Net.session().pending_select_id)
	if prefer < 0 and not Net.session().selected_character.is_empty(): prefer = int(Net.session().selected_character.get("id", -1))
	var pick := 0
	for i in chars.size():
		if int(chars[i].get("id", -1)) == prefer: pick = i; break
	list.select(pick); list.ensure_current_is_visible()
	Net.session().pending_select_id = -1
	_show_character(pick)

func _show_character(index: int) -> void:
	if index < 0 or index >= _chars.size(): return
	var character: Dictionary = _chars[index]
	_identity.text = str(character.get("name", "?"))
	_details.text = "%s  ·  Lv.%s" % [_class_label(str(character.get("class_id", ""))), character.get("level", 1)]
	var gender := LookCatalog.normalize_gender(str(character.get("gender", LookCatalog.GENDER_FEMALE)))
	var custom: Dictionary = character.get("customization", {}) if character.get("customization") is Dictionary else {}
	if CharacterView3D.enabled():
		if not is_instance_valid(_view):
			_view = CharacterView3D.new(); add_child(_view); _view.display.visible = false
			_view.viewport.size = Vector2i(640, 640)
			_view.camera.size = 2.45; _view.camera.position = Vector3(0, 1.2, 6); _view.camera.look_at(Vector3(0, 1.05, 0))
		var snapshot: Array = character.get("equipment", []) if character.get("equipment", []) is Array else []
		_view.configure(gender, custom, CharacterView3D.equipment_parts(gender, snapshot, Net.server().get("item_catalog")))
		_portrait.texture = _view.viewport.get_texture()
		_turn = 0; _view.play("idle", "front")
		_fit_preview()
	else:
		var texture: Texture2D = null
		if not str(custom.get("mv_sheet", "")).is_empty(): texture = MV.load_sheet_texture(str(custom.mv_sheet))
		if texture == null: texture = LookCatalog.load_idle(str(character.get("look_id", "1")), "Front", gender)
		_portrait.texture = texture

func _fit_preview() -> void:
	var top := 2.0
	if _view.model.axis_rig != null:
		var measured: float = _view.model.axis_rig.head_top(Vector3.UP)
		if is_finite(measured): top = maxf(1.0, measured)
	var center := Vector3(0, top * .5, 0)
	_view.camera.size = maxf(2.45, top * 1.22)
	_view.camera.position = center + Vector3(0, .15, 6)
	_view.camera.look_at(center)

func _rotate(step: int) -> void:
	if not is_instance_valid(_view): return
	var directions := ["front", "front_right", "right", "back_right", "back", "back_left", "left", "front_left"]
	_turn = posmod(_turn + step, directions.size())
	_view.play("idle", directions[_turn])

func _class_label(class_id: String) -> String:
	return {"mage": "法师", "warrior": "战士"}.get(class_id, "冒险者")

func _on_enter() -> void:
	if enter_btn.disabled or _entering: return
	var sel := list.get_selected_items()
	if sel.is_empty():
		status_label.text = "请先选择一个角色"
		return
	if sel[0] >= _chars.size(): return
	var raw: Variant = _chars[sel[0]]
	if typeof(raw) != TYPE_DICTIONARY:
		status_label.text = "角色数据无效，请重新选择"
		return
	_entering = true
	enter_btn.disabled = true; create_btn.disabled = true; back_btn.disabled = true
	status_label.text = "正在进入世界…"
	var ch: Dictionary = (raw as Dictionary).duplicate(true)
	Net.session().selected_character = ch
	Net.session().spawn_data = {}
	if not Net.session().pending_world3d_playtest:
		Net.session().world3d_map_path = ""
		Net.session().world3d_spawn = Vector3(0, 0.9, 4)
		Net.session().editor_return = false
	Net.session().pending_world3d_playtest = false
	Net.session().world3d_switches.clear()
	Net.session().loading_mode = ""
	Net.session().go_loading()
