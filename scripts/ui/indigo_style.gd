extends RefCounted
## Pack white button + Imagine hover (209x68, real alpha). Titles nudged for CJK vertical center.

const ROOT := "res://assets/ui/indigo"
const CUSTOM := "res://assets/ui/indigo/custom"

const COL_INK := Color(0.22, 0.15, 0.10, 1)
const COL_INK_MUTED := Color(0.42, 0.34, 0.26, 1)
const COL_PARCHMENT := Color(0.91, 0.80, 0.64, 1)
const COL_PARCHMENT_DEEP := Color(0.84, 0.72, 0.54, 1)
const COL_BORDER := Color(0.40, 0.26, 0.14, 1)
const COL_GOLD := Color(0.78, 0.58, 0.22, 1)
const COL_PANEL_EDGE := Color(0.32, 0.20, 0.10, 1)

static func tex(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		push_warning("IndigoStyle missing: %s" % path)
		return null
	return load(path) as Texture2D

static func style_box(path: String, ml: float, mt: float, mr: float, mb: float, content_h := 8.0, content_v_top := 10.0, content_v_bottom := 6.0) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = tex(path)
	sb.texture_margin_left = ml
	sb.texture_margin_top = mt
	sb.texture_margin_right = mr
	sb.texture_margin_bottom = mb
	sb.content_margin_left = content_h
	sb.content_margin_right = content_h
	# CJK glyphs sit high in the em-box — more top padding centers them visually.
	sb.content_margin_top = content_v_top
	sb.content_margin_bottom = content_v_bottom
	return sb

static func flat_box(bg: Color, border: Color, border_w: int = 2, content: float = 10.0, radius: int = 4) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = content
	sb.content_margin_right = content
	sb.content_margin_top = content + 2.0
	sb.content_margin_bottom = content - 2.0
	return sb

static func build_theme() -> Theme:
	var t := Theme.new()

	var panel := flat_box(COL_PARCHMENT, COL_PANEL_EDGE, 3, 18, 6)
	panel.shadow_color = Color(0, 0, 0, 0.25)
	panel.shadow_size = 4
	panel.shadow_offset = Vector2(2, 3)
	t.set_stylebox("panel", "PanelContainer", panel)

	var white_path := "%s/button/UI_Dialogue_Button_White.png" % ROOT
	var hover_path := "%s/btn_menu_hover.png" % CUSTOM
	var btn_n: StyleBox = style_box(white_path, 18, 10, 18, 10, 8, 11, 5)
	var btn_h: StyleBox = style_box(hover_path, 18, 10, 18, 10, 8, 11, 5)
	var btn_p: StyleBox = style_box(white_path, 18, 10, 18, 10, 8, 12, 4)
	var btn_d: StyleBox = style_box(white_path, 18, 10, 18, 10, 8, 11, 5)
	if (btn_h as StyleBoxTexture).texture == null:
		btn_h = flat_box(Color(0.95, 0.86, 0.68, 1), Color(0.90, 0.72, 0.28, 1), 3, 10, 4)

	for kind in ["Button", "OptionButton"]:
		t.set_stylebox("normal", kind, btn_n)
		t.set_stylebox("hover", kind, btn_h)
		t.set_stylebox("pressed", kind, btn_p)
		t.set_stylebox("disabled", kind, btn_d)
		t.set_stylebox("focus", kind, btn_h)
		t.set_color("font_color", kind, COL_INK)
		t.set_color("font_hover_color", kind, COL_INK)
		t.set_color("font_pressed_color", kind, COL_INK)
		t.set_color("font_disabled_color", kind, COL_INK_MUTED)
		t.set_color("font_focus_color", kind, COL_INK)
		t.set_font_size("font_size", kind, 18)

	t.set_constant("arrow_margin", "OptionButton", 10)
	t.set_constant("h_separation", "OptionButton", 6)

	var field := flat_box(COL_PARCHMENT, COL_BORDER, 2, 12, 4)
	var field_focus := flat_box(COL_PARCHMENT, COL_GOLD, 3, 12, 4)
	t.set_stylebox("normal", "LineEdit", field)
	t.set_stylebox("focus", "LineEdit", field_focus)
	t.set_stylebox("read_only", "LineEdit", field)
	t.set_color("font_color", "LineEdit", COL_INK)
	t.set_color("font_uneditable_color", "LineEdit", COL_INK_MUTED)
	t.set_color("font_placeholder_color", "LineEdit", COL_INK_MUTED)
	t.set_color("caret_color", "LineEdit", COL_INK)
	t.set_color("selection_color", "LineEdit", Color(0.78, 0.58, 0.22, 0.35))
	t.set_color("font_selected_color", "LineEdit", COL_INK)
	t.set_font_size("font_size", "LineEdit", 16)

	t.set_color("font_color", "Label", COL_INK)
	t.set_font_size("font_size", "Label", 16)

	var list_bg := flat_box(COL_PARCHMENT_DEEP, COL_BORDER, 2, 8, 4)
	var list_sel := flat_box(Color(0.93, 0.84, 0.58, 1), COL_GOLD, 3, 6, 4)
	t.set_stylebox("panel", "ItemList", list_bg)
	t.set_stylebox("focus", "ItemList", list_bg)
	t.set_stylebox("hovered", "ItemList", flat_box(Color(0.88, 0.76, 0.58, 1), COL_BORDER, 2, 6, 4))
	t.set_stylebox("hovered_selected", "ItemList", list_sel)
	t.set_stylebox("hovered_selected_focus", "ItemList", list_sel)
	t.set_stylebox("selected", "ItemList", list_sel)
	t.set_stylebox("selected_focus", "ItemList", list_sel)
	t.set_stylebox("cursor", "ItemList", list_sel)
	t.set_stylebox("cursor_unfocused", "ItemList", list_sel)
	t.set_color("font_color", "ItemList", COL_INK)
	t.set_color("font_hovered_color", "ItemList", COL_INK)
	t.set_color("font_selected_color", "ItemList", COL_INK)
	t.set_font_size("font_size", "ItemList", 14)
	t.set_constant("v_separation", "ItemList", 6)
	t.set_constant("h_separation", "ItemList", 6)

	t.set_stylebox("background", "ProgressBar", flat_box(COL_PARCHMENT_DEEP, COL_BORDER, 2, 2, 3))
	t.set_stylebox("fill", "ProgressBar", flat_box(Color(0.72, 0.48, 0.22, 1), COL_GOLD, 1, 2, 3))
	return t


static func nudge_title_label(label: Label) -> void:
	## Center title text with a nested CenterContainer (avoids full-rect font metric drift).
	if label == null or label.get_parent() == null:
		return
	var box: Control = label.get_parent() as Control
	if box == null:
		return
	# Ensure ribbon behind uses keep-aspect-centered
	var ribbon := box.get_node_or_null("Ribbon") as TextureRect
	if ribbon:
		ribbon.set_anchors_preset(Control.PRESET_FULL_RECT)
		ribbon.offset_left = 0.0
		ribbon.offset_top = 0.0
		ribbon.offset_right = 0.0
		ribbon.offset_bottom = 0.0
		ribbon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ribbon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# Wrap label in CenterContainer if not already
	if not (box.get_node_or_null("TextCenter") is CenterContainer):
		var holder := CenterContainer.new()
		holder.name = "TextCenter"
		holder.set_anchors_preset(Control.PRESET_FULL_RECT)
		holder.offset_left = 0.0
		holder.offset_top = 0.0
		holder.offset_right = 0.0
		holder.offset_bottom = 0.0
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(holder)
		label.reparent(holder)
	label.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	# Reset any old full-rect offsets
	label.anchor_left = 0.0
	label.anchor_top = 0.0
	label.anchor_right = 0.0
	label.anchor_bottom = 0.0
	label.offset_left = 0.0
	label.offset_top = 0.0
	label.offset_right = 0.0
	label.offset_bottom = 0.0
	label.custom_minimum_size = Vector2.ZERO
