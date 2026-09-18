extends RefCounted
## Lineage 2–inspired chrome for character / quest windows.
## Textures live under res://assets/ui/l2 (png gitignored; load_from_file fallback).

const ROOT := "res://assets/ui/l2"

const COL_TITLE := Color(0.93, 0.82, 0.38, 1.0)
const COL_TEXT := Color(0.90, 0.86, 0.74, 1.0)
const COL_MUTED := Color(0.62, 0.56, 0.42, 1.0)
const COL_GOLD := Color(0.95, 0.82, 0.28, 1.0)
const COL_VALUE := Color(0.95, 0.92, 0.82, 1.0)
const COL_ON_GOLD := Color(0.16, 0.10, 0.04, 1.0)
const COL_PANEL := Color(0.08, 0.07, 0.06, 0.96)
const COL_BORDER := Color(0.62, 0.50, 0.28, 0.95)
const COL_LINK := Color(0.42, 0.62, 1.0, 1.0)

static var _tex_cache: Dictionary = {}
static var _box_cache: Dictionary = {}


static func tex(name: String) -> Texture2D:
	name = name.strip_edges()
	if name.is_empty():
		return null
	if _tex_cache.has(name):
		return _tex_cache[name] as Texture2D
	var path := "%s/%s" % [ROOT, name]
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		var loaded: Variant = load(path)
		if loaded is Texture2D:
			t = loaded
	if t == null and FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img != null and not img.is_empty():
			t = ImageTexture.create_from_image(img)
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
	## Corners ~56px of 512 atlas. Content inset must clear filigree so labels
	## / bottom buttons do not sit on the gold ornament.
	var key := "panel:v2"
	if _box_cache.has(key):
		return _box_cache[key] as StyleBox
	var t := tex("panel.png")
	if t == null:
		return _flat(COL_PANEL, COL_BORDER, 2, 8)
	var sb := StyleBoxTexture.new()
	sb.texture = t
	sb.texture_margin_left = 56
	sb.texture_margin_top = 56
	sb.texture_margin_right = 56
	sb.texture_margin_bottom = 56
	sb.content_margin_left = 26
	sb.content_margin_right = 26
	sb.content_margin_top = 20
	sb.content_margin_bottom = 40
	_box_cache[key] = sb
	return sb


static func title_box() -> StyleBox:
	var t := tex("title_bar.png")
	if t != null:
		var key := "title_bar:pad"
		if _box_cache.has(key):
			return _box_cache[key] as StyleBox
		var sb := StyleBoxTexture.new()
		sb.texture = t
		sb.content_margin_left = 10
		sb.content_margin_right = 8
		sb.content_margin_top = 5
		sb.content_margin_bottom = 5
		_box_cache[key] = sb
		return sb
	return _flat(Color(0.10, 0.09, 0.08, 0.98), COL_GOLD, 1, 4)


static func slot_box(filled: bool) -> StyleBox:
	var sb := stretch_box("slot_filled.png" if filled else "slot_empty.png", 4.0)
	if sb != null:
		return sb
	if filled:
		return _flat(Color(0.12, 0.28, 0.26, 0.98), COL_GOLD, 2, 3)
	return _flat(Color(0.06, 0.06, 0.08, 0.98), Color(0.20, 0.20, 0.24, 0.95), 1, 3)


static func tab_box(selected: bool) -> StyleBox:
	var name := "tab_on.png" if selected else "tab_idle.png"
	var key := "tab:%s" % name
	if _box_cache.has(key):
		return _box_cache[key] as StyleBox
	var t := tex(name)
	if t != null:
		var sb := StyleBoxTexture.new()
		sb.texture = t
		## Keep glyphs in the dark plate, clear of wing / serpent caps.
		sb.content_margin_left = 32
		sb.content_margin_right = 32
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		_box_cache[key] = sb
		return sb
	if selected:
		return _flat(Color(0.42, 0.32, 0.12, 0.96), COL_GOLD, 1, 6)
	return _flat(Color(0.14, 0.12, 0.10, 0.96), Color(0.40, 0.32, 0.18, 0.8), 1, 6)


static func row_box(selected: bool) -> StyleBox:
	var name := "row_on.png" if selected else "row_idle.png"
	var key := "row:%s" % name
	if _box_cache.has(key):
		return _box_cache[key] as StyleBox
	var t := tex(name)
	if t != null:
		var sb := StyleBoxTexture.new()
		sb.texture = t
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		sb.content_margin_top = 5
		sb.content_margin_bottom = 5
		_box_cache[key] = sb
		return sb
	if selected:
		return _flat(Color(0.36, 0.28, 0.10, 0.95), COL_GOLD, 1, 6)
	return _flat(Color(0.10, 0.09, 0.08, 0.92), Color(0.38, 0.30, 0.16, 0.7), 1, 6)


static func inner_box() -> StyleBox:
	return _flat(Color(0.04, 0.03, 0.03, 0.35), Color(0.42, 0.34, 0.18, 0.0), 0, 4)


static func compact_box() -> StyleBox:
	return _flat(Color(0.14, 0.11, 0.07, 0.96), COL_GOLD, 1, 4)


static func style_gold_amount(label: Label) -> void:
	if label == null:
		return
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", COL_GOLD)
	label.add_theme_constant_override("outline_size", 2)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))


static func style_compact_button(btn: Button) -> void:
	if btn == null:
		return
	var sb := compact_box()
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", tab_box(true) if tab_box(true) != null else sb)
	btn.add_theme_stylebox_override("pressed", sb)
	btn.add_theme_stylebox_override("focus", sb)
	btn.add_theme_color_override("font_color", COL_TITLE)
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
	r.color = Color(0.55, 0.42, 0.18, 0.65)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


static func apply_panel(panel: PanelContainer) -> void:
	if panel == null:
		return
	panel.add_theme_stylebox_override("panel", panel_box())


static func style_title(label: Label) -> void:
	if label == null:
		return
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", COL_TITLE)
	label.add_theme_constant_override("outline_size", 3)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


static func style_close(btn: Button) -> void:
	if btn == null:
		return
	var idle := tex("close.png")
	var hover := tex("close_hover.png")
	var empty := StyleBoxEmpty.new()
	btn.add_theme_stylebox_override("normal", empty)
	btn.add_theme_stylebox_override("hover", empty)
	btn.add_theme_stylebox_override("pressed", empty)
	btn.add_theme_stylebox_override("focus", empty)
	btn.flat = true
	btn.text = ""
	btn.custom_minimum_size = Vector2(22, 22)
	btn.focus_mode = Control.FOCUS_NONE
	if idle != null:
		btn.icon = idle
		btn.expand_icon = true
		btn.add_theme_constant_override("icon_max_width", 22)
	else:
		btn.text = "×"
		btn.add_theme_color_override("font_color", COL_TITLE)
		btn.add_theme_color_override("font_hover_color", Color(1.0, 0.92, 0.55))
	if not btn.has_meta("_l2_close"):
		btn.set_meta("_l2_close", true)
		if hover != null:
			btn.mouse_entered.connect(func():
				if is_instance_valid(btn):
					btn.icon = hover
			)
			btn.mouse_exited.connect(func():
				if is_instance_valid(btn):
					btn.icon = idle
			)


static func style_tab_button(btn: Button, selected: bool) -> void:
	if btn == null:
		return
	btn.add_theme_stylebox_override("normal", tab_box(selected))
	btn.add_theme_stylebox_override("hover", tab_box(true))
	btn.add_theme_stylebox_override("pressed", tab_box(true))
	btn.add_theme_stylebox_override("focus", tab_box(selected))
	var ink := COL_ON_GOLD if selected else COL_TEXT
	btn.add_theme_color_override("font_color", ink)
	btn.add_theme_color_override("font_hover_color", COL_ON_GOLD)
	btn.add_theme_color_override("font_pressed_color", COL_ON_GOLD)
	btn.add_theme_font_size_override("font_size", 12)
	btn.modulate = Color(1, 1, 1, 1)


static func style_action_button(btn: Button) -> void:
	if btn == null:
		return
	style_tab_button(btn, false)
	btn.custom_minimum_size = Vector2(120, 28)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN


static func style_icon_button(btn: Button, icon_name: String, size: float = 40.0) -> void:
	if btn == null:
		return
	var sb := slot_box(false)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", slot_box(true) if slot_box(true) != null else sb)
	btn.add_theme_stylebox_override("pressed", sb)
	btn.add_theme_stylebox_override("focus", sb)
	btn.flat = false
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(size, size)
	btn.expand_icon = true
	btn.add_theme_constant_override("icon_max_width", int(size) - 8)
	var t := tex(icon_name)
	if t != null:
		btn.icon = t
		btn.text = ""
	btn.add_theme_color_override("font_color", COL_TITLE)
	btn.modulate = Color(1, 1, 1, 1)


static func style_slider(sl: HSlider) -> void:
	if sl == null:
		return
	var track := _flat(Color(0.08, 0.07, 0.06, 0.95), COL_BORDER, 1, 2)
	var fill := _flat(Color(0.55, 0.42, 0.14, 0.95), COL_GOLD, 1, 2)
	sl.add_theme_stylebox_override("slider", track)
	sl.add_theme_stylebox_override("grabber_area", fill)
	sl.add_theme_stylebox_override("grabber_area_highlight", fill)
	sl.custom_minimum_size = Vector2(160, 18)


static func check_icon(on: bool) -> Texture2D:
	var key := "check_on" if on else "check_off"
	if _tex_cache.has(key):
		return _tex_cache[key] as Texture2D
	var n := 16
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var bg := Color(0.10, 0.09, 0.07, 1)
	var border := COL_GOLD
	var fill := Color(0.95, 0.82, 0.28, 1)
	for y in range(n):
		for x in range(n):
			var edge := x == 0 or y == 0 or x == n - 1 or y == n - 1
			if edge:
				img.set_pixel(x, y, border)
			elif on and x >= 4 and y >= 4 and x <= n - 5 and y <= n - 5:
				img.set_pixel(x, y, fill)
			else:
				img.set_pixel(x, y, bg)
	var t := ImageTexture.create_from_image(img)
	_tex_cache[key] = t
	return t


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
	opt.custom_minimum_size = Vector2(180, 28)
	opt.fit_to_longest_item = false
	opt.focus_mode = Control.FOCUS_NONE


static func style_row_button(btn: Button, selected: bool) -> void:
	if btn == null:
		return
	btn.add_theme_stylebox_override("normal", row_box(selected))
	btn.add_theme_stylebox_override("hover", row_box(true))
	btn.add_theme_stylebox_override("pressed", row_box(true))
	btn.add_theme_stylebox_override("focus", row_box(selected))
	var ink := COL_ON_GOLD if selected else COL_TEXT
	btn.add_theme_color_override("font_color", ink)
	btn.add_theme_color_override("font_hover_color", COL_ON_GOLD)
	btn.add_theme_color_override("font_pressed_color", COL_ON_GOLD)
	btn.add_theme_font_size_override("font_size", 12)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.modulate = Color(1, 1, 1, 1)


static func _flat(bg: Color, border: Color, border_w: int, content: float) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(2)
	sb.content_margin_left = content
	sb.content_margin_right = content
	sb.content_margin_top = content
	sb.content_margin_bottom = content
	return sb
