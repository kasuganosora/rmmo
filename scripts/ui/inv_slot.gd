extends PanelContainer
const IconPreview = preload("res://scripts/ui/icon_preview.gd")
## One bag grid cell: StyleBoxFlat + letter-avatar (first grapheme) + qty badge.
## Drag source for hotbar / ground drop ({kind:"item", item_id}).

signal activated(item_id: String)

var item_id: String = ""
var qty: int = 0
var display_name: String = ""
var slot_index: int = -1
## MV IconSet cell index; -1 = none (try icon_ref / letter).
var icon_index: int = -1
## Standalone content://icon/{id} or bare id.
var icon_ref: String = ""
## Locked / beyond capacity — darker than empty usable, no interact.
var disabled: bool = false

var _avatar_label: Label
var _icon_rect: TextureRect
var _qty_label: Label
var _empty_sb: StyleBoxFlat
var _filled_sb: StyleBoxFlat
var _disabled_sb: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Keep caller-computed cell size (fill-width grid); default 64 only if unset.
	if custom_minimum_size.x < 1.0 or custom_minimum_size.y < 1.0:
		custom_minimum_size = Vector2(42, 42)
	_ensure_styles()
	_ensure_children()
	_apply_visual()


func setup(p_item_id: String, p_qty: int, p_display_name: String, p_index: int = -1, p_icon_index: int = -1, p_icon_ref: String = "") -> void:
	disabled = false
	modulate = Color(1, 1, 1, 1)
	item_id = p_item_id.strip_edges()
	qty = maxi(p_qty, 0)
	display_name = p_display_name.strip_edges()
	if display_name.is_empty():
		display_name = item_id
	slot_index = p_index
	icon_index = p_icon_index
	icon_ref = p_icon_ref.strip_edges()
	_ensure_styles()
	_ensure_children()
	_apply_visual()


func set_icon_index(p_index: int) -> void:
	icon_index = p_index
	_apply_icon_visual()


func set_icon_ref(ref: String) -> void:
	icon_ref = ref.strip_edges()
	_apply_icon_visual()


func clear_slot() -> void:
	item_id = ""
	qty = 0
	display_name = ""
	icon_index = -1
	icon_ref = ""
	_ensure_styles()
	_ensure_children()
	_apply_visual()


func set_disabled(p_disabled: bool) -> void:
	disabled = p_disabled
	if disabled:
		item_id = ""
		qty = 0
		display_name = ""
		modulate = Color(1, 1, 1, 1)
	_ensure_styles()
	_ensure_children()
	_apply_visual()


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
		_filled_sb.bg_color = Color(0.16, 0.15, 0.14, 0.95)
		_filled_sb.border_color = Color(0.55, 0.45, 0.28, 0.85)
		_filled_sb.set_border_width_all(1)
		_filled_sb.set_corner_radius_all(3)
		_filled_sb.content_margin_left = 3
		_filled_sb.content_margin_right = 3
		_filled_sb.content_margin_top = 3
		_filled_sb.content_margin_bottom = 3
	if _disabled_sb == null:
		_disabled_sb = StyleBoxFlat.new()
		_disabled_sb.bg_color = Color(0.05, 0.05, 0.06, 0.7)
		_disabled_sb.border_color = Color(0.12, 0.12, 0.14, 0.75)
		_disabled_sb.set_border_width_all(1)
		_disabled_sb.set_corner_radius_all(3)
		_disabled_sb.content_margin_left = 3
		_disabled_sb.content_margin_right = 3
		_disabled_sb.content_margin_top = 3
		_disabled_sb.content_margin_bottom = 3


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
	_avatar_label.add_theme_color_override("font_color", Color(0.95, 0.90, 0.72))
	_avatar_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_avatar_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_avatar_label.offset_bottom = -2
	root.add_child(_avatar_label)
	_qty_label = Label.new()
	_qty_label.name = "Qty"
	_qty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_qty_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_qty_label.add_theme_font_size_override("font_size", 11)
	_qty_label.add_theme_color_override("font_color", Color(0.98, 0.94, 0.55))
	_qty_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_qty_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_qty_label.anchor_left = 1.0
	_qty_label.anchor_top = 1.0
	_qty_label.anchor_right = 1.0
	_qty_label.anchor_bottom = 1.0
	_qty_label.offset_left = -36
	_qty_label.offset_top = -16
	_qty_label.offset_right = -2
	_qty_label.offset_bottom = -1
	root.add_child(_qty_label)


func _apply_visual() -> void:
	_ensure_styles()
	_ensure_children()
	if disabled:
		add_theme_stylebox_override("panel", _disabled_sb)
		_avatar_label.text = ""
		_avatar_label.visible = true
		if _icon_rect != null:
			_icon_rect.texture = null
			_icon_rect.visible = false
		_qty_label.text = ""
		tooltip_text = "未解锁栏位"
		mouse_default_cursor_shape = Control.CURSOR_ARROW
		return
	var occupied := not item_id.is_empty() and qty > 0
	add_theme_stylebox_override("panel", _filled_sb if occupied else _empty_sb)
	if occupied:
		_qty_label.text = str(qty) if qty > 1 else ""
		tooltip_text = "%s\n%s" % [display_name, item_id]
		_apply_icon_visual()
	else:
		_avatar_label.text = ""
		_avatar_label.visible = true
		if _icon_rect != null:
			_icon_rect.texture = null
			_icon_rect.visible = false
		_qty_label.text = ""
		tooltip_text = ""



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
		if not item_id.is_empty() and qty > 0:
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


## First Unicode character of display name (Godot String is codepoint-aware; fine for CJK).
static func first_grapheme(full: String) -> String:
	full = full.strip_edges()
	if full.is_empty():
		return "?"
	return full.substr(0, 1)


func _get_drag_data(_at_position: Vector2) -> Variant:
	if disabled or item_id.is_empty() or qty <= 0:
		return null
	var data := {"kind": "item", "item_id": item_id}
	set_drag_preview(IconPreview.make_drag_preview(display_name, icon_index, icon_ref))
	return data


func _gui_input(event: InputEvent) -> void:
	# Double-click = use / equip toggle. Drag onto world = drop.
	# Single left click is drag-only (no activate).
	if disabled:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and mb.double_click:
			if not item_id.is_empty() and qty > 0:
				activated.emit(item_id)
				accept_event()
