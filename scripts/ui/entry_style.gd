extends RefCounted
## Game entry screens only; deliberately independent of the content editor.
const GameSkin = preload("res://scripts/ui/l2_style.gd")
const Background = preload("res://scripts/ui/entry_background.gd")
const GOLD := Color("d5c399")
const MUTED := Color("aab3b9")

static func apply(root: Control) -> void:
	# The project keeps nearest sampling for pixel art. UI font atlases need
	# linear sampling, especially MSDF text at fractional and enlarged scales.
	root.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	root.theme = GameSkin.hud_theme().duplicate()
	root.theme.default_font_size = 16
	for type in ["Button", "LineEdit", "ItemList"]:
		root.theme.set_font_size("font_size", type, 16)
	for state in ["normal", "read_only"]:
		root.theme.set_stylebox(state, "LineEdit", box(Color("172126"), Color("4a555b"), 1, 10))
	root.theme.set_stylebox("panel", "ItemList", box(Color(0.03, .06, .08, .35), Color.TRANSPARENT, 0, 8))
	root.theme.set_stylebox("selected", "ItemList", box(Color("343b3b"), GOLD, 1, 12))
	root.theme.set_stylebox("selected_focus", "ItemList", box(Color("343b3b"), GOLD, 1, 12))
	root.theme.set_stylebox("focus", "ItemList", StyleBoxEmpty.new())
	root.theme.set_constant("v_separation", "ItemList", 22)
	root.theme.set_constant("line_separation", "ItemList", 7)
	var background := Background.new(); background.name = "EntryBackground"; root.add_child(background)
	var shade := TextureRect.new()
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0, .42, .7, 1])
	gradient.colors = PackedColorArray([Color(.015,.025,.035,.2), Color(.015,.025,.035,.24), Color(.015,.025,.035,.88), Color(.015,.025,.035,.96)])
	var texture := GradientTexture2D.new(); texture.gradient = gradient; texture.width = 2048; texture.height = 8
	texture.fill_from = Vector2.ZERO; texture.fill_to = Vector2.RIGHT
	shade.texture = texture; shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(shade); shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.resized.connect(func():
		gradient.set_color(0, Color(.015,.025,.035,.72 if root.size.x < 840 else .2))
		gradient.set_color(1, Color(.015,.025,.035,.76 if root.size.x < 840 else .24))
	)

static func box(fill: Color, border: Color, width: int, padding: int) -> StyleBoxFlat:
	var result := StyleBoxFlat.new(); result.bg_color = fill
	result.border_color = border; result.set_border_width_all(width)
	result.set_corner_radius_all(3); result.content_margin_left = padding; result.content_margin_right = padding
	result.content_margin_top = 8; result.content_margin_bottom = 8
	return result

static func label(text: String, font_size: int = 16, color: Color = Color("ece8de")) -> Label:
	var result := Label.new(); result.text = text
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	return result

static func button(text: String, primary: bool = false) -> Button:
	var result := Button.new(); result.text = text; result.custom_minimum_size.y = 44
	if primary:
		for pair in [["normal", "bba778"], ["hover", "d7c392"], ["pressed", "a38d5e"]]:
			result.add_theme_stylebox_override(pair[0], box(Color(pair[1]), Color.TRANSPARENT, 0, 16))
		for key in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			result.add_theme_color_override(key, Color("171d20"))
	return result

static func field(parent: VBoxContainer, title: String, placeholder: String, secret: bool = false) -> LineEdit:
	parent.add_child(label(title, 14, MUTED))
	var result := LineEdit.new(); result.placeholder_text = placeholder; result.secret = secret
	result.custom_minimum_size.y = 44; result.clear_button_enabled = not secret
	parent.add_child(result)
	return result

static func divider(parent: Control) -> void:
	var line := ColorRect.new(); line.color = Color(.78,.7,.51,.35)
	line.custom_minimum_size.y = 1; line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)

static func column(parent: Control, separation: int = 12) -> VBoxContainer:
	var result := VBoxContainer.new(); result.add_theme_constant_override("separation", separation)
	parent.add_child(result); return result
