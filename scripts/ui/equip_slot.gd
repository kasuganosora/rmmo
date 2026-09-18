extends PanelContainer
const IconPreview = preload("res://scripts/ui/icon_preview.gd")
const L2Style = preload("res://scripts/ui/l2_style.gd")
## Paperdoll equipment cell: L2 slot chrome + letter-avatar like InvSlot.
## Drop {kind:"item", item_id} to equip; drag filled slot to world to drop;
## left/right click filled → unequip to bag (no right-click drop).

signal equip_requested(item_id: String, slot_id: String)
signal unequip_requested(slot_id: String)

var slot_id: String = ""
var item_id: String = ""
var display_name: String = ""
var hint_label: String = ""
var icon_index: int = -1
var icon_ref: String = ""
var durability: int = -1
var durability_max: int = -1

var _avatar_label: Label
var _icon_rect: TextureRect
var _hint_label: Label
var _dur_label: Label
var _empty_sb: StyleBox
var _filled_sb: StyleBox


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	if custom_minimum_size.x < 1.0 or custom_minimum_size.y < 1.0:
		custom_minimum_size = Vector2(42, 42)
	_ensure_styles()
	_ensure_children()
	_apply_visual()


func setup(p_slot_id: String, p_item_id: String = "", p_display_name: String = "", p_hint: String = "", p_icon_index: int = -1, p_icon_ref: String = "", p_durability: int = -1, p_durability_max: int = -1) -> void:
	slot_id = p_slot_id.strip_edges()
	item_id = p_item_id.strip_edges()
	display_name = p_display_name.strip_edges()
	hint_label = p_hint.strip_edges()
	icon_index = p_icon_index
	icon_ref = p_icon_ref.strip_edges()
	durability = int(p_durability)
	durability_max = int(p_durability_max)
	if display_name.is_empty() and not item_id.is_empty():
		display_name = item_id
	_ensure_styles()
	_ensure_children()
	_apply_visual()


func set_icon_index(p_index: int) -> void:
	icon_index = p_index
	_apply_icon_visual()


func set_icon_ref(ref: String) -> void:
	icon_ref = ref.strip_edges()
	_apply_icon_visual()


func set_item(p_item_id: String, p_display_name: String = "", p_icon_index: int = -1, p_icon_ref: String = "", p_durability: int = -1, p_durability_max: int = -1) -> void:
	item_id = p_item_id.strip_edges()
	display_name = p_display_name.strip_edges()
	icon_index = p_icon_index
	icon_ref = p_icon_ref.strip_edges()
	durability = int(p_durability)
	durability_max = int(p_durability_max)
	if display_name.is_empty() and not item_id.is_empty():
		display_name = item_id
	_apply_visual()


func clear_item() -> void:
	item_id = ""
	display_name = ""
	icon_index = -1
	icon_ref = ""
	durability = -1
	durability_max = -1
	_apply_visual()


func _ensure_styles() -> void:
	if _empty_sb == null:
		_empty_sb = L2Style.slot_box(false)
	if _filled_sb == null:
		_filled_sb = L2Style.slot_box(true)


func _ensure_children() -> void:
	if (
		_avatar_label != null and is_instance_valid(_avatar_label)
		and _icon_rect != null and is_instance_valid(_icon_rect)
		and _dur_label != null and is_instance_valid(_dur_label)
	):
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
	_avatar_label.add_theme_font_size_override("font_size", 22)
	_avatar_label.add_theme_color_override("font_color", Color(0.95, 0.90, 0.72))
	_avatar_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_avatar_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_avatar_label.offset_bottom = -2
	root.add_child(_avatar_label)
	_hint_label = Label.new()
	_hint_label.name = "Hint"
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", 10)
	_hint_label.add_theme_color_override("font_color", Color(0.78, 0.68, 0.42, 0.95))
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_hint_label)
	_dur_label = Label.new()
	_dur_label.name = "Dur"
	_dur_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_dur_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_dur_label.add_theme_font_size_override("font_size", 9)
	_dur_label.add_theme_color_override("font_color", Color(0.85, 0.92, 0.70, 0.95))
	_dur_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dur_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dur_label.offset_right = -2
	_dur_label.offset_bottom = -1
	_dur_label.visible = false
	root.add_child(_dur_label)


func _apply_visual() -> void:
	_ensure_styles()
	_ensure_children()
	var occupied := not item_id.is_empty()
	add_theme_stylebox_override("panel", _filled_sb if occupied else _empty_sb)
	if occupied:
		_hint_label.text = ""
		var tip := "%s\n%s · %s" % [display_name, item_id, slot_id]
		if durability_max > 0:
			tip += "\n耐久 %d/%d" % [maxi(durability, 0), durability_max]
			if durability <= 0:
				tip += "（损坏）"
		tip += "\n点击卸下"
		tooltip_text = tip
		if _dur_label != null:
			if durability_max > 0:
				_dur_label.text = str(maxi(durability, 0))
				_dur_label.visible = true
				if durability <= 0:
					_dur_label.add_theme_color_override("font_color", Color(0.95, 0.45, 0.40, 0.95))
				elif durability * 2 <= durability_max:
					_dur_label.add_theme_color_override("font_color", Color(0.95, 0.80, 0.40, 0.95))
				else:
					_dur_label.add_theme_color_override("font_color", Color(0.85, 0.92, 0.70, 0.95))
			else:
				_dur_label.text = ""
				_dur_label.visible = false
		_apply_icon_visual()
	else:
		_avatar_label.text = ""
		_avatar_label.visible = true
		if _icon_rect != null:
			_icon_rect.texture = null
			_icon_rect.visible = false
		_hint_label.text = hint_label
		tooltip_text = hint_label if not hint_label.is_empty() else slot_id
		if _dur_label != null:
			_dur_label.text = ""
			_dur_label.visible = false



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
		if not item_id.is_empty():
			_avatar_label.text = _first_grapheme(display_name)
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


static func _first_grapheme(full: String) -> String:
	full = full.strip_edges()
	if full.is_empty():
		return "?"
	return full.substr(0, 1)


func _get_drag_data(_at_position: Vector2) -> Variant:
	if item_id.is_empty() or slot_id.is_empty():
		return null
	var data := {"kind": "equipped", "slot_id": slot_id, "item_id": item_id}
	set_drag_preview(IconPreview.make_drag_preview(display_name, icon_index, icon_ref))
	return data


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	var d: Dictionary = data
	if str(d.get("kind", "")) != "item":
		return false
	return not str(d.get("item_id", "")).strip_edges().is_empty()


func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if typeof(data) != TYPE_DICTIONARY:
		return
	var d: Dictionary = data
	if str(d.get("kind", "")) != "item":
		return
	var iid := str(d.get("item_id", "")).strip_edges()
	if iid.is_empty() or slot_id.is_empty():
		return
	equip_requested.emit(iid, slot_id)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		# Right-click → unequip to bag (never drop; drop is drag-to-world).
		if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			if not item_id.is_empty() and not slot_id.is_empty():
				unequip_requested.emit(slot_id)
				accept_event()
			return
		# Left release on filled slot (no drag) → unequip to bag.
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			if not item_id.is_empty() and not slot_id.is_empty() and not get_viewport().gui_is_dragging():
				unequip_requested.emit(slot_id)
				accept_event()
