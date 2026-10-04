extends RefCounted
## Compact Lineage 2–inspired skin shared by game windows and HUD.
## Content icons remain in the external UI pack; chrome uses native UI geometry.

const Chrome = preload("res://scripts/ui/l2_chrome.gd")
const UiPack = preload("res://scripts/ui/ui_pack.gd")

const COL_TITLE := Color("ede5d2")
const COL_TEXT := Color("d2d3d7")
const COL_MUTED := Color("9b9da7")
const COL_GOLD := Color("cbb587")
const COL_VALUE := Color("f0ece3")
const COL_ON_GOLD := Color("f3e7c9")
const COL_PANEL := Color("202228")
const COL_BORDER := Color("50525b")
const COL_LINK := Color("a1bdd6")
const TITLE_HEIGHT := 28
const TAB_HEIGHT := 24

static var _tex_cache: Dictionary = {}
static var _box_cache: Dictionary = {}
static var _theme: Theme


static func focus_box() -> StyleBoxFlat:
	var style := _flat(Color.TRANSPARENT, COL_GOLD, 1, 0)
	style.draw_center = false
	return style


static func hud_theme() -> Theme:
	if _theme != null: return _theme
	var theme := Theme.new()
	theme.default_font_size = 12
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC", "sans-serif"])
	# Pixel-sized HUD text uses the native glyph cache. Generating 64px MSDFs
	# for hundreds of Chinese UI glyphs stalls every fresh process for seconds.
	font.multichannel_signed_distance_field = false
	font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	font.disable_embedded_bitmaps = true
	theme.default_font = font
	for type in ["Label", "Button", "OptionButton", "CheckBox", "CheckButton", "LineEdit", "TextEdit", "PopupMenu", "Tree", "ItemList"]:
		theme.set_color("font_color", type, COL_TEXT)
		theme.set_color("font_hover_color", type, COL_VALUE)
		theme.set_color("font_pressed_color", type, COL_TITLE)
		theme.set_color("font_focus_color", type, COL_VALUE)
		theme.set_color("font_disabled_color", type, Color("787b86"))
		theme.set_color("font_selected_color", type, COL_VALUE)
	theme.set_color("default_color", "RichTextLabel", COL_TEXT)
	theme.set_font_size("normal_font_size", "RichTextLabel", 12)
	theme.set_stylebox("panel", "PanelContainer", panel_box())
	for type in ["Button", "OptionButton"]:
		for pair in [["normal", "button"], ["hover", "hover"], ["pressed", "pressed"], ["hover_pressed", "selected"], ["disabled", "disabled"]]:
			theme.set_stylebox(pair[0], type, button_box(pair[1]))
		theme.set_stylebox("focus", type, focus_box())
	for type in ["CheckBox", "CheckButton"]:
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]: theme.set_stylebox(state, type, _flat(Color.TRANSPARENT, Color.TRANSPARENT, 0, 2))
		theme.set_stylebox("focus", type, focus_box())
		for state in ["checked", "checked_disabled", "radio_checked", "radio_checked_disabled"]: theme.set_icon(state, type, check_icon(true))
		for state in ["unchecked", "unchecked_disabled", "radio_unchecked", "radio_unchecked_disabled"]: theme.set_icon(state, type, check_icon(false))
	for type in ["LineEdit", "TextEdit"]:
		theme.set_stylebox("normal", type, Chrome.box("input", 5, 3))
		theme.set_stylebox("read_only", type, Chrome.box("disabled", 5, 3))
		theme.set_stylebox("focus", type, focus_box())
		theme.set_color("caret_color", type, COL_TITLE)
		theme.set_color("selection_color", type, Color("504a3e"))
		theme.set_color("font_placeholder_color", type, COL_MUTED)
	theme.set_icon("arrow", "OptionButton", Chrome.glyph("arrow", COL_MUTED))
	theme.set_stylebox("panel", "PopupMenu", panel_box())
	theme.set_stylebox("hover", "PopupMenu", row_box(true))
	theme.set_constant("v_separation", "PopupMenu", 6)
	theme.set_stylebox("panel", "TooltipPanel", panel_box())
	theme.set_color("font_color", "TooltipLabel", COL_VALUE)
	theme.set_font_size("font_size", "TooltipLabel", 12)
	for type in ["Tree", "ItemList"]:
		theme.set_stylebox("panel", type, Chrome.box("input", 4, 4))
		theme.set_stylebox("selected", type, row_box(true))
		theme.set_stylebox("selected_focus", type, row_box(true))
	for type in ["VScrollBar", "HScrollBar"]:
		theme.set_stylebox("scroll", type, _flat(Color(0.06, 0.065, 0.08, 0.3), Color.TRANSPARENT, 0, 3))
		theme.set_stylebox("grabber", type, _flat(Color("595b65"), Color.TRANSPARENT, 0, 3))
		theme.set_stylebox("grabber_highlight", type, _flat(Color("8d8573"), Color.TRANSPARENT, 0, 3))
		theme.set_stylebox("grabber_pressed", type, _flat(COL_GOLD, Color.TRANSPARENT, 0, 3))
		var empty := ImageTexture.create_from_image(Image.create_empty(1, 1, false, Image.FORMAT_RGBA8))
		for state in ["increment", "decrement", "increment_highlight", "decrement_highlight", "increment_pressed", "decrement_pressed"]: theme.set_icon(state, type, empty)
	theme.set_stylebox("background", "ProgressBar", Chrome.box("input", 1, 1))
	theme.set_stylebox("fill", "ProgressBar", Chrome.bar_fill(Color("7c9274")))
	_theme = theme
	return theme


static func tex(name: String) -> Texture2D:
	name = name.strip_edges()
	if name.is_empty():
		return null
	if _tex_cache.has(name):
		return _tex_cache[name] as Texture2D
	var t: Texture2D = UiPack.tex("l2/%s" % name)
	_tex_cache[name] = t
	return t


static func has_kit() -> bool:
	return tex("panel.png") != null


static func stretch_box(name: String, content := 6.0) -> StyleBox:
	var key := "s:%s:%.1f" % [name, content]
	if _box_cache.has(key):
		return _box_cache[key] as StyleBox
	var t := tex(name)
	if t == null:
		return null
	var sb := StyleBoxTexture.new()
	sb.texture = t
	sb.texture_margin_left = 0
	sb.texture_margin_top = 0
	sb.texture_margin_right = 0
	sb.texture_margin_bottom = 0
	sb.content_margin_left = content
	sb.content_margin_right = content
	sb.content_margin_top = maxf(content - 2.0, 2.0)
	sb.content_margin_bottom = maxf(content - 2.0, 2.0)
	_box_cache[key] = sb
	return sb


static func slice_box(name: String, margin: float, content: float) -> StyleBox:
	var key := "9:%s:%.1f:%.1f" % [name, margin, content]
	if _box_cache.has(key):
		return _box_cache[key] as StyleBox
	var t := tex(name)
	if t == null:
		return null
	var sb := StyleBoxTexture.new()
	sb.texture = t
	sb.texture_margin_left = margin
	sb.texture_margin_top = margin
	sb.texture_margin_right = margin
	sb.texture_margin_bottom = margin
	sb.content_margin_left = content
	sb.content_margin_right = content
	sb.content_margin_top = content
	sb.content_margin_bottom = content
	_box_cache[key] = sb
	return sb


static func panel_box() -> StyleBox:
	return Chrome.box("settings_panel", 5, 5)


static func title_box() -> StyleBox:
	var space := StyleBoxEmpty.new()
	space.content_margin_left = 2
	space.content_margin_right = 0
	space.content_margin_top = 2
	space.content_margin_bottom = 2
	return space


static func slot_box(filled: bool) -> StyleBox:
	return Chrome.box("slot_filled" if filled else "slot", 3, 3)


static func tab_box(selected: bool) -> StyleBox:
	var style := _flat(Color(1, 1, 1, 0.04 if selected else 0.0), COL_GOLD if selected else Color.TRANSPARENT, 0, 4)
	style.border_width_bottom = 2
	style.content_margin_left = 8
	style.content_margin_right = 8
	return style


static func row_box(selected: bool) -> StyleBox:
	var style := _flat(Color(0.64, 0.65, 0.52, 0.12) if selected else Color(1, 1, 1, 0.015), COL_GOLD if selected else Color(0.40, 0.48, 0.49, 0.22), 0, 4)
	style.border_width_left = 2 if selected else 0
	style.border_width_bottom = 0 if selected else 1
	style.content_margin_left = 7
	style.content_margin_right = 7
	return style


static func inner_box() -> StyleBox:
	var style := _flat(Color(0.045, 0.05, 0.065, 0.25), Color.TRANSPARENT, 0, 4)
	style.set_corner_radius_all(4)
	return style


static func button_box(state: String) -> StyleBoxFlat:
	var bg := Color("32343b")
	var edge := Color("53555f")
	match state:
		"hover": bg = Color("40424b"); edge = Color("aaa08a")
		"pressed", "selected": bg = Color("24262c"); edge = COL_GOLD
		"disabled": bg = Color("26282e"); edge = Color("393b43")
	var style := _flat(bg, edge, 1, 3)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.set_corner_radius_all(4)
	return style


static func style_primary_button(btn: Button) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := button_box("button" if state == "normal" else state)
		if state != "disabled":
			style.bg_color = Color("494237") if state == "normal" else Color("5b5040") if state == "hover" else Color("332e26")
			style.border_color = Color("a59066") if state == "normal" else COL_GOLD
		btn.add_theme_stylebox_override(state, style)
	btn.add_theme_color_override("font_color", COL_ON_GOLD)
	btn.add_theme_color_override("font_hover_color", COL_VALUE)
	btn.add_theme_color_override("font_pressed_color", COL_ON_GOLD)
	btn.add_theme_stylebox_override("focus", focus_box())


static func slot_outline(selected: bool) -> StyleBoxFlat:
	var key := "slot_outline:" + str(selected)
	if _box_cache.has(key): return _box_cache[key]
	var style := _flat(Color.TRANSPARENT, COL_GOLD if selected else Color("aaa89f"), 1, 0)
	style.draw_center = false
	style.set_corner_radius_all(3)
	_box_cache[key] = style
	return style


static func compact_box() -> StyleBox:
	return button_box("button")


static func style_gold_amount(label: Label) -> void:
	if label == null:
		return
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", COL_GOLD)
	label.add_theme_constant_override("outline_size", 0)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))


static func style_compact_button(btn: Button) -> void:
	if btn == null:
		return
	var sb := compact_box()
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", button_box("hover"))
	btn.add_theme_stylebox_override("pressed", button_box("pressed"))
	btn.add_theme_stylebox_override("focus", focus_box())
	btn.add_theme_color_override("font_color", COL_TEXT)
	btn.add_theme_color_override("font_hover_color", COL_ON_GOLD)
	btn.add_theme_color_override("font_pressed_color", COL_ON_GOLD)
	btn.add_theme_font_size_override("font_size", 12)
	btn.modulate = Color(1, 1, 1, 1)


static func style_body_rtl(rtl: RichTextLabel) -> void:
	if rtl == null:
		return
	rtl.add_theme_font_size_override("normal_font_size", 13)
	rtl.add_theme_color_override("default_color", COL_TEXT)
	rtl.add_theme_color_override("font_url_color", COL_LINK)


static func hairline() -> ColorRect:
	var r := ColorRect.new()
	r.custom_minimum_size = Vector2(0, 1)
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.color = Color(0.64, 0.61, 0.54, 0.20)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func apply_panel(panel: PanelContainer) -> void:
	if panel == null:
		return
	panel.add_theme_stylebox_override("panel", panel_box())


static func style_title(label: Label) -> void:
	if label == null:
		return
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", COL_TITLE)
	label.add_theme_constant_override("outline_size", 0)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


static func style_close(btn: Button) -> void:
	if btn == null: return
	btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	btn.add_theme_stylebox_override("hover", _flat(Color(1, 1, 1, 0.08), Color.TRANSPARENT, 0, 1))
	btn.add_theme_stylebox_override("pressed", _flat(Color(1, 1, 1, 0.14), Color.TRANSPARENT, 0, 1))
	btn.add_theme_stylebox_override("focus", focus_box())
	btn.flat = false
	btn.text = ""
	btn.icon = Chrome.glyph("close", COL_TITLE)
	btn.expand_icon = true
	btn.add_theme_constant_override("icon_max_width", 18)
	btn.custom_minimum_size = Vector2(26, 24)
	btn.tooltip_text = "关闭"
	btn.focus_mode = Control.FOCUS_NONE


static func style_tab_button(btn: Button, selected: bool) -> void:
	if btn == null:
		return
	btn.add_theme_stylebox_override("normal", tab_box(selected))
	var hover := tab_box(selected).duplicate()
	hover.bg_color = Color(1, 1, 1, 0.08)
	btn.add_theme_stylebox_override("hover", hover)
	var pressed := tab_box(selected).duplicate()
	pressed.bg_color = Color(1, 1, 1, 0.13)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", focus_box())
	var ink := COL_ON_GOLD if selected else COL_TEXT
	btn.add_theme_color_override("font_color", ink)
	btn.add_theme_color_override("font_hover_color", COL_ON_GOLD)
	btn.add_theme_color_override("font_pressed_color", COL_ON_GOLD)
	btn.add_theme_font_size_override("font_size", 12)
	btn.modulate = Color(1, 1, 1, 1)


static func style_action_button(btn: Button) -> void:
	if btn == null:
		return
	style_compact_button(btn)
	btn.custom_minimum_size = Vector2(92, 24)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN


static func style_icon_button(btn: Button, icon_name: String, size: float = 40.0) -> void:
	if btn == null:
		return
	var sb := slot_box(false)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", slot_box(true) if slot_box(true) != null else sb)
	btn.add_theme_stylebox_override("pressed", Chrome.box("pressed", 3, 3))
	btn.add_theme_stylebox_override("focus", focus_box())
	btn.flat = false
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(size, size)
	btn.expand_icon = true
	btn.add_theme_constant_override("icon_max_width", 18 if icon_name == "icon_menu.png" else int(size) - 8)
	var glyph_name := icon_name.trim_prefix("icon_").trim_suffix(".png")
	var t := Chrome.glyph(glyph_name, COL_TITLE) if glyph_name in ["menu", "character", "inventory", "skills", "quest", "party", "map", "system"] else tex(icon_name)
	if t != null:
		btn.icon = t
		btn.text = ""
	btn.add_theme_color_override("font_color", COL_TEXT)
	btn.modulate = Color(1, 1, 1, 1)


static func style_slider(sl: HSlider) -> void:
	if sl == null:
		return
	var track := _flat(Color("191b20"), Color("444650"), 1, 2)
	var fill := _flat(Color("9e8b65"), Color("bdaa81"), 1, 2)
	sl.add_theme_stylebox_override("slider", track)
	sl.add_theme_stylebox_override("grabber_area", fill)
	sl.add_theme_stylebox_override("grabber_area_highlight", fill)
	sl.custom_minimum_size = Vector2(160, 18)


static func check_icon(on: bool) -> Texture2D:
	return Chrome.glyph("check" if on else "empty_check", COL_GOLD if on else COL_MUTED)


static func style_check(box: CheckBox) -> void:
	if box == null:
		return
	box.add_theme_color_override("font_color", COL_TEXT)
	box.add_theme_color_override("font_hover_color", COL_TITLE)
	box.add_theme_color_override("font_pressed_color", COL_GOLD)
	box.add_theme_font_size_override("font_size", 13)
	box.focus_mode = Control.FOCUS_NONE
	var on_tex := check_icon(true)
	var off_tex := check_icon(false)
	box.add_theme_icon_override("checked", on_tex)
	box.add_theme_icon_override("unchecked", off_tex)
	box.add_theme_icon_override("checked_disabled", on_tex)
	box.add_theme_icon_override("unchecked_disabled", off_tex)


static func style_option(opt: OptionButton) -> void:
	if opt == null:
		return
	style_compact_button(opt)
	opt.custom_minimum_size = Vector2(160, 24)
	opt.fit_to_longest_item = false
	opt.focus_mode = Control.FOCUS_NONE


static func style_row_button(btn: Button, selected: bool) -> void:
	if btn == null:
		return
	btn.add_theme_stylebox_override("normal", row_box(selected))
	btn.add_theme_stylebox_override("hover", row_box(true))
	btn.add_theme_stylebox_override("pressed", Chrome.box("pressed", 7, 4))
	btn.add_theme_stylebox_override("focus", focus_box())
	var ink := COL_ON_GOLD if selected else COL_TEXT
	btn.add_theme_color_override("font_color", ink)
	btn.add_theme_color_override("font_hover_color", COL_ON_GOLD)
	btn.add_theme_color_override("font_pressed_color", COL_ON_GOLD)
	btn.add_theme_font_size_override("font_size", 12)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.clip_text = true
	btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	btn.modulate = Color(1, 1, 1, 1)


static func _flat(bg: Color, border: Color, border_w: int, content: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(0)
	sb.content_margin_left = content
	sb.content_margin_right = content
	sb.content_margin_top = content
	sb.content_margin_bottom = content
	return sb
