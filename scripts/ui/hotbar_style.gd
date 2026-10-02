extends RefCounted
## Floating action icons. Deliberately independent of framed game windows.
static var _styles: Dictionary = {}
static var _page_icons: Dictionary = {}


static func slot(state: String) -> StyleBoxFlat:
	if _styles.has(state):
		return _styles[state]
	var style := StyleBoxFlat.new()
	style.set_content_margin_all(0)
	style.set_corner_radius_all(4)
	style.set_border_width_all(1)
	style.bg_color = Color(0.09, 0.10, 0.13, 0.28)
	style.border_color = Color(0.56, 0.57, 0.62, 0.22)
	match state:
		"filled":
			style.bg_color.a = 0.65
			style.border_color = Color(0.67, 0.63, 0.53, 0.70)
		"hover":
			style.bg_color = Color(0.85, 0.79, 0.62, 0.10)
			style.border_color = Color(0.9, 0.84, 0.69, 0.95)
		"pressed":
			style.bg_color = Color(0.02, 0.025, 0.03, 0.75)
			style.border_color = Color(0.94, 0.87, 0.67, 1)
	_styles[state] = style
	return style


static func quiet_button(button: Button) -> void:
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	button.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	button.add_theme_color_override("font_color", Color(0.72, 0.71, 0.64))
	button.add_theme_color_override("font_hover_color", Color(1, 0.95, 0.78))
	button.add_theme_color_override("font_pressed_color", Color(0.94, 0.83, 0.51))
	button.add_theme_font_size_override("font_size", 10)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND


static func page_button(button: Button, up: bool) -> void:
	quiet_button(button)
	button.text = ""
	button.custom_minimum_size = Vector2(26, 14)
	button.icon = _page_icon(up)
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_theme_color_override("icon_normal_color", Color(0.9, 0.87, 0.76))
	button.add_theme_color_override("icon_hover_color", Color(1, 0.96, 0.76))
	button.add_theme_color_override("icon_pressed_color", Color(1, 0.86, 0.53))
	for state in ["hover", "pressed"]:
		var style := StyleBoxFlat.new()
		style.set_content_margin_all(0)
		style.set_corner_radius_all(3)
		style.bg_color = Color(0.95, 0.86, 0.62, 0.12 if state == "hover" else 0.23)
		button.add_theme_stylebox_override(state, style)


static func _page_icon(up: bool) -> Texture2D:
	if _page_icons.has(up):
		return _page_icons[up]
	# A real 12px chevron, independent of the font's tiny triangle glyph.
	var path := "M2 7L7 3L12 7" if up else "M2 3L7 7L12 3"
	var source := '<svg xmlns="http://www.w3.org/2000/svg" width="14" height="10"><path d="%s" fill="none" stroke="#0b1013" stroke-opacity="0.85" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round"/><path d="%s" fill="none" stroke="#ffffff" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>' % [path, path]
	var img := Image.new()
	img.load_svg_from_string(source)
	var texture := ImageTexture.create_from_image(img)
	_page_icons[up] = texture
	return texture
