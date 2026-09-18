extends PanelContainer
const IconPreview = preload("res://scripts/ui/icon_preview.gd")
## One skills-window grid cell: letter avatar + owned CD clock chrome.
## Drag source for hotbar ({kind:"skill", skill_id}).

signal activated(skill_id: String)

const CdChrome = preload("res://scripts/ui/cd_chrome.gd")

var skill_id: String = ""
var display_name: String = ""
var category: String = ""
var slot_index: int = -1
var icon_index: int = -1
var icon_ref: String = ""
## False = not yet learned (gray / lock overlay).
var known: bool = true
var _lock_label: Label
## Alias so HUD can match by bound_id like hotbar.
var bound_id: String:
	get:
		return skill_id

var _avatar_label: Label
var _icon_rect: TextureRect
var _empty_sb: StyleBoxFlat
var _filled_sb: StyleBoxFlat
var _passive_sb: StyleBoxFlat
var _cd: Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	if custom_minimum_size.x < 1.0 or custom_minimum_size.y < 1.0:
		custom_minimum_size = Vector2(42, 42)
	_ensure_styles()
	_ensure_children()
	_apply_visual()


func setup(p_skill_id: String, p_display_name: String, p_category: String = "", p_index: int = -1, p_icon_index: int = -1, p_icon_ref: String = "") -> void:
	skill_id = p_skill_id.strip_edges()
	display_name = p_display_name.strip_edges()
	if display_name.is_empty():
		display_name = skill_id
	category = p_category.strip_edges()
	slot_index = p_index
	icon_index = p_icon_index
	icon_ref = p_icon_ref.strip_edges()
	_ensure_styles()
	_ensure_children()
	_apply_visual()


func set_icon_index(p_index: int) -> void:
	icon_index = p_index
	_apply_icon_visual()


func set_known(p_known: bool) -> void:
	known = p_known
	_apply_visual()


func set_icon_ref(ref: String) -> void:
	icon_ref = ref.strip_edges()
	_apply_icon_visual()


func clear_slot() -> void:
	skill_id = ""
	display_name = ""
	category = ""
	icon_index = -1
	icon_ref = ""
	_ensure_styles()
	_ensure_children()
	_apply_visual()
	clear_cooldown()
	set_cast_progress(-1.0)


func _ensure_styles() -> void:
	if _empty_sb == null:
		_empty_sb = StyleBoxFlat.new()
		_empty_sb.bg_color = Color(0.08, 0.08, 0.10, 0.92)
		_empty_sb.border_color = Color(0.22, 0.22, 0.26, 0.9)
		_empty_sb.set_border_width_all(1)
		_empty_sb.set_corner_radius_all(3)
		_empty_sb.content_margin_left = 3
		_empty_sb.content_margin_right = 3
		_empty_sb.content_margin_top = 3
		_empty_sb.content_margin_bottom = 3
	if _filled_sb == null:
		_filled_sb = StyleBoxFlat.new()
		_filled_sb.bg_color = Color(0.14, 0.15, 0.18, 0.95)
		_filled_sb.border_color = Color(0.40, 0.55, 0.75, 0.85)
		_filled_sb.set_border_width_all(1)
		_filled_sb.set_corner_radius_all(3)
		_filled_sb.content_margin_left = 3
		_filled_sb.content_margin_right = 3
		_filled_sb.content_margin_top = 3
		_filled_sb.content_margin_bottom = 3
	if _passive_sb == null:
		_passive_sb = StyleBoxFlat.new()
		_passive_sb.bg_color = Color(0.14, 0.16, 0.14, 0.95)
		_passive_sb.border_color = Color(0.45, 0.65, 0.40, 0.85)
		_passive_sb.set_border_width_all(1)
		_passive_sb.set_corner_radius_all(3)
		_passive_sb.content_margin_left = 3
		_passive_sb.content_margin_right = 3
		_passive_sb.content_margin_top = 3
		_passive_sb.content_margin_bottom = 3


func _ensure_children() -> void:
	if _avatar_label != null and is_instance_valid(_avatar_label) and _icon_rect != null and is_instance_valid(_icon_rect):
		return
	var root := Control.new()
	root.name = "Inner"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	_icon_rect = TextureRect.new()
	_icon_rect.name = "Icon"
	_icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_icon_rect.visible = false
	root.add_child(_icon_rect)
	_avatar_label = Label.new()
	_avatar_label.name = "Avatar"
	_avatar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_avatar_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_avatar_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_avatar_label.add_theme_font_size_override("font_size", 26)
	_avatar_label.add_theme_color_override("font_color", Color(0.88, 0.92, 0.98))
	_avatar_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_avatar_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_avatar_label.offset_bottom = -2
	root.add_child(_avatar_label)
	_ensure_cd()


func _ensure_lock_label() -> void:
	_ensure_children()
	if _lock_label != null and is_instance_valid(_lock_label):
		return
	_lock_label = Label.new()
	_lock_label.name = "Lock"
	_lock_label.text = "锁"
	_lock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_lock_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_lock_label.add_theme_font_size_override("font_size", 10)
	_lock_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	_lock_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lock_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_lock_label.offset_right = -2
	_lock_label.offset_bottom = -1
	_lock_label.z_index = 6
	add_child(_lock_label)


func _ensure_cd() -> void:
	if _cd != null and is_instance_valid(_cd):
		return
	_cd = CdChrome.new()
	_cd.name = "CdChrome"
	_cd.z_index = 8
	add_child(_cd)


func set_cooldown(remaining: float, total: float) -> void:
	_ensure_children()
	_ensure_cd()
	if _cd != null and _cd.has_method("set_cooldown"):
		_cd.set_cooldown(remaining, total)


func clear_cooldown() -> void:
	_ensure_children()
	_ensure_cd()
	if _cd != null and _cd.has_method("clear_cooldown"):
		_cd.clear_cooldown()


func set_cast_progress(frac: float) -> void:
	_ensure_children()
	_ensure_cd()
	if _cd != null and _cd.has_method("set_cast_progress"):
		_cd.set_cast_progress(frac)


func tick_cooldown(delta: float) -> void:
	if _cd != null and _cd.has_method("tick_cooldown"):
		_cd.tick_cooldown(delta)


func _apply_visual() -> void:
	_ensure_styles()
	_ensure_children()
	var occupied := not skill_id.is_empty()
	if occupied:
		if category == "passive":
			add_theme_stylebox_override("panel", _passive_sb)
		else:
			add_theme_stylebox_override("panel", _filled_sb)
		var tip := "%s\n%s" % [display_name, skill_id]
		if category == "passive":
			tip += "\n（被动）"
		if not known:
			tip += "\n（未学会）"
			modulate = Color(0.45, 0.45, 0.5, 0.95)
		else:
			modulate = Color(1, 1, 1, 1)
		tooltip_text = tip
		_apply_icon_visual()
		_ensure_lock_label()
		_lock_label.visible = not known
	else:
		add_theme_stylebox_override("panel", _empty_sb)
		_avatar_label.text = ""
		_avatar_label.visible = true
		if _icon_rect != null:
			_icon_rect.texture = null
			_icon_rect.visible = false
		tooltip_text = ""
		modulate = Color(1, 1, 1, 1)
		if _lock_label != null:
			_lock_label.visible = false



func _apply_icon_visual() -> void:
	_ensure_children()
	var tex: Texture2D = _resolve_icon_texture()
	if tex != null:
		_icon_rect.texture = tex
		_icon_rect.visible = true
		_avatar_label.text = ""
		_avatar_label.visible = false
	else:
		_icon_rect.texture = null
		_icon_rect.visible = false
		_avatar_label.visible = true
		if not skill_id.is_empty():
			_avatar_label.text = first_grapheme(display_name)
		else:
			_avatar_label.text = ""


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


static func first_grapheme(full: String) -> String:
	full = full.strip_edges()
	if full.is_empty():
		return "?"
	return full.substr(0, 1)


func _get_drag_data(_at_position: Vector2) -> Variant:
	if skill_id.is_empty():
		return null
	var data := {"kind": "skill", "skill_id": skill_id}
	set_drag_preview(IconPreview.make_drag_preview(display_name, icon_index, icon_ref))
	return data


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			if not skill_id.is_empty() and not get_viewport().gui_is_dragging():
				activated.emit(skill_id)
				accept_event()
