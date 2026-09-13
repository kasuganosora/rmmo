extends Button
## Hotbar cell: drag bind, right-click clear. CD clock chrome is owned by the skill cell.

signal item_dropped(page: int, slot: int, item_id: String)
signal skill_dropped(page: int, slot: int, skill_id: String)
signal binding_cleared(page: int, slot: int)

const CdChrome = preload("res://scripts/ui/cd_chrome.gd")

var page: int = 0
var slot_num: int = 0

var _avatar: Label
var _icon_rect: TextureRect
var _qty: Label
var _key: Label
var _cd: Control

var icon_index: int = -1
var icon_ref: String = ""

## Bound skill/item id for CD matching.
var bound_kind: String = ""
var bound_id: String = ""


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP
	_ensure_badges()


func configure(p_page: int, p_slot: int) -> void:
	page = p_page
	slot_num = p_slot


func _ensure_badges() -> void:
	if _avatar != null and is_instance_valid(_avatar):
		_ensure_cd()
		return
	_icon_rect = TextureRect.new()
	_icon_rect.name = "Icon"
	_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_icon_rect.offset_left = 2
	_icon_rect.offset_top = 2
	_icon_rect.offset_right = -2
	_icon_rect.offset_bottom = -2
	_icon_rect.visible = false
	add_child(_icon_rect)
	_avatar = Label.new()
	_avatar.name = "Avatar"
	_avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_avatar.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_avatar.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_avatar.add_theme_font_size_override("font_size", 18)
	_avatar.add_theme_color_override("font_color", Color(0.96, 0.92, 0.75))
	_avatar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_avatar.offset_bottom = -2
	add_child(_avatar)
	_qty = Label.new()
	_qty.name = "QtyBadge"
	_qty.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_qty.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_qty.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_qty.add_theme_font_size_override("font_size", 10)
	_qty.add_theme_color_override("font_color", Color(0.98, 0.94, 0.55))
	_qty.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_qty.anchor_left = 1.0
	_qty.anchor_top = 1.0
	_qty.anchor_right = 1.0
	_qty.anchor_bottom = 1.0
	_qty.offset_left = -28
	_qty.offset_top = -14
	_qty.offset_right = -2
	_qty.offset_bottom = 0
	add_child(_qty)
	_key = Label.new()
	_key.name = "KeyHint"
	_key.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_key.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_key.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_key.add_theme_font_size_override("font_size", 9)
	_key.add_theme_color_override("font_color", Color(0.75, 0.78, 0.88, 0.95))
	_key.add_theme_constant_override("outline_size", 2)
	_key.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	_key.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_key.anchor_left = 0.0
	_key.anchor_top = 1.0
	_key.anchor_right = 0.0
	_key.anchor_bottom = 1.0
	_key.offset_left = 2
	_key.offset_top = -12
	_key.offset_right = 28
	_key.offset_bottom = -1
	add_child(_key)
	_ensure_cd()


func _ensure_cd() -> void:
	if _cd != null and is_instance_valid(_cd):
		return
	_cd = CdChrome.new()
	_cd.name = "CdChrome"
	_cd.z_index = 8
	add_child(_cd)


func set_key_hint(label: String) -> void:
	_ensure_badges()
	_key.text = label
	_key.visible = not label.is_empty()


func set_binding_visual(kind: String, letter: String, qty: int, tip: String, p_icon_index: int = -1, p_icon_ref: String = "") -> void:
	_ensure_badges()
	tooltip_text = tip
	bound_kind = kind.strip_edges()
	icon_index = p_icon_index
	icon_ref = p_icon_ref.strip_edges()
	if kind == "item" or kind == "skill":
		text = ""
		if kind == "item" and qty > 1:
			_qty.text = str(qty)
			_qty.visible = true
		else:
			_qty.text = ""
			_qty.visible = false
		_apply_icon_visual(letter)
	elif kind == "default_num":
		bound_kind = ""
		bound_id = ""
		icon_index = -1
		icon_ref = ""
		_avatar.text = ""
		_avatar.visible = false
		if _icon_rect != null:
			_icon_rect.texture = null
			_icon_rect.visible = false
		_qty.visible = false
		text = letter
	else:
		bound_kind = ""
		bound_id = ""
		icon_index = -1
		icon_ref = ""
		_avatar.text = ""
		_avatar.visible = false
		if _icon_rect != null:
			_icon_rect.texture = null
			_icon_rect.visible = false
		_qty.visible = false
		text = ""


func set_icon_index(p_index: int) -> void:
	icon_index = p_index
	_apply_icon_visual(_avatar.text if _avatar != null else "")


func set_icon_ref(ref: String) -> void:
	icon_ref = ref.strip_edges()
	_apply_icon_visual(_avatar.text if _avatar != null else "")


func _apply_icon_visual(letter_fallback: String = "") -> void:
	_ensure_badges()
	var tex: Texture2D = _resolve_icon_texture()
	if tex != null:
		_icon_rect.texture = tex
		_icon_rect.visible = true
		_avatar.text = ""
		_avatar.visible = false
	else:
		_icon_rect.texture = null
		_icon_rect.visible = false
		_avatar.visible = true
		_avatar.text = letter_fallback if not letter_fallback.is_empty() else "?"


func _resolve_icon_texture() -> Texture2D:
	var am: Node = get_node_or_null("/root/AssetManager")
	if am == null:
		return null
	if am.has_method("resolve_slot_icon_texture"):
		return am.resolve_slot_icon_texture(icon_index, icon_ref)
	if icon_index >= 0 and am.has_method("load_mv_icon_texture"):
		var t: ImageTexture = am.load_mv_icon_texture(icon_index)
		if t != null:
			return t
	var ref := icon_ref.strip_edges()
	if ref.is_empty():
		return null
	if not ref.begins_with("content:"):
		ref = "content://icon/%s" % ref
	if am.has_method("load_image"):
		var img: Image = am.load_image(ref)
		if img != null:
			return ImageTexture.create_from_image(img)
	return null


func set_bound_id(id: String) -> void:
	bound_id = id.strip_edges()


func set_cooldown(remaining: float, total: float) -> void:
	_ensure_badges()
	if _cd != null and _cd.has_method("set_cooldown"):
		_cd.set_cooldown(remaining, total)


func clear_cooldown() -> void:
	_ensure_badges()
	if _cd != null and _cd.has_method("clear_cooldown"):
		_cd.clear_cooldown()


func set_cast_progress(frac: float) -> void:
	_ensure_badges()
	if _cd != null and _cd.has_method("set_cast_progress"):
		_cd.set_cast_progress(frac)


func tick_cooldown(delta: float) -> void:
	if _cd != null and _cd.has_method("tick_cooldown"):
		_cd.tick_cooldown(delta)


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var kind := str((data as Dictionary).get("kind", ""))
	return kind == "item" or kind == "skill"


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if typeof(data) != TYPE_DICTIONARY:
		return
	var d: Dictionary = data
	var kind := str(d.get("kind", ""))
	if kind == "item":
		var iid := str(d.get("item_id", "")).strip_edges()
		if not iid.is_empty():
			item_dropped.emit(page, slot_num, iid)
	elif kind == "skill":
		var sid := str(d.get("skill_id", d.get("id", ""))).strip_edges()
		if not sid.is_empty():
			skill_dropped.emit(page, slot_num, sid)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			binding_cleared.emit(page, slot_num)
			accept_event()
