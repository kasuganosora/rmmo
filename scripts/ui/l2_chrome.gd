extends RefCounted
## Game-only charcoal surfaces: a single fine edge and restrained reflected light.
## SVG is UI geometry, rasterized once and cached; nine-slicing keeps edges crisp.
static var _textures := {}
static var _boxes := {}

static func texture(kind: String) -> Texture2D:
	if _textures.has(kind): return _textures[kind]
	var top := "#292b30"
	var bottom := "#1c1e23"
	var edge := "#66635a"
	var shine := "#ddd0aa"
	var opacity := "1.0"
	var radius := 5
	match kind:
		"settings_panel": opacity = "1.0"
		"title": top = "#292b30"; bottom = "#25272c"
		"button": top = "#34363c"; bottom = "#2b2d32"; edge = "#57595e"
		"hover": top = "#42434a"; bottom = "#35363d"; edge = "#b4a27d"
		"selected": top = "#494335"; bottom = "#34312b"; edge = "#baa477"
		"pressed": top = "#222328"; bottom = "#28292e"; edge = "#b4a27d"
		"row": top = "#292b30"; bottom = "#26282d"; edge = "#383a40"
		"slot": top = "#191b20"; bottom = "#22242a"; edge = "#3c3f47"; shine = "#25272e"; radius = 3
		"slot_filled": top = "#24262c"; bottom = "#2b2d34"; edge = "#66665e"; shine = "#8c8778"; radius = 3
		"slot_passive": top = "#232b28"; bottom = "#2a322e"; edge = "#66796c"; radius = 3
		"input": top = "#1a1c21"; bottom = "#1f2127"; edge = "#4c4e57"; shine = "#292b32"; radius = 3
		"disabled": top = "#1d1f24"; bottom = "#1d1f24"; edge = "#2b2d34"; shine = "#23252b"; radius = 3
	var source := '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64"><defs><linearGradient id="plate" x1="0" y1="0" x2="0" y2="1"><stop stop-color="%s"/><stop offset="1" stop-color="%s"/></linearGradient><linearGradient id="glint"><stop stop-color="%s" stop-opacity="0"/><stop offset="0.5" stop-color="%s" stop-opacity="0.26"/><stop offset="1" stop-color="%s" stop-opacity="0"/></linearGradient></defs><rect x="0.5" y="0.5" width="63" height="63" rx="%d" fill="url(#plate)" fill-opacity="%s" stroke="%s"/><path d="M7 1.5h50" fill="none" stroke="url(#glint)"/></svg>' % [top, bottom, shine, shine, shine, radius, opacity, edge]
	var image := Image.new()
	image.load_svg_from_string(source)
	var result := ImageTexture.create_from_image(image)
	_textures[kind] = result
	return result

static func box(kind: String, horizontal: float = 6.0, vertical: float = 3.0) -> StyleBoxTexture:
	var key := "%s:%s:%s" % [kind, horizontal, vertical]
	if _boxes.has(key): return _boxes[key]
	var style := StyleBoxTexture.new()
	style.texture = texture(kind)
	style.set_texture_margin_all(6)
	style.content_margin_left = horizontal
	style.content_margin_right = horizontal
	style.content_margin_top = vertical
	style.content_margin_bottom = vertical
	_boxes[key] = style
	return style

static func glyph(kind: String, color: Color) -> Texture2D:
	var key := kind + color.to_html()
	if _textures.has(key): return _textures[key]
	var shape: String = {
		"close": '<path d="m5 5 8 8M13 5l-8 8"/>',
		"arrow": '<path d="m5 7 4 4 4-4"/>',
		"check": '<rect x="3" y="3" width="12" height="12"/><path d="m5 9 3 3 5-6"/>',
		"empty_check": '<rect x="3" y="3" width="12" height="12"/>',
		"menu": '<path d="M4 5h10M4 9h10M4 13h10"/>',
		"lock": '<rect x="4.5" y="8" width="9" height="7" rx="1"/><path d="M6 8V5a3 3 0 0 1 6 0v3M9 10v3"/>',
		"unlock": '<rect x="4.5" y="8" width="9" height="7" rx="1"/><path d="M6 8V5a3 3 0 0 1 6 0M9 10v3"/>',
		"character": '<circle cx="9" cy="5" r="2.5"/><path d="M3.5 15v-2a5.5 5.5 0 0 1 11 0v2Z"/>',
		"inventory": '<rect x="3.5" y="6" width="11" height="9" rx="2"/><path d="M6 6V4a3 3 0 0 1 6 0v2M7 10h4"/>',
		"skills": '<path d="m10 2-6 8h5l-1 6 6-9H9Z"/>',
		"quest": '<path d="M4 2.5h10V15H4ZM6.5 6h5M6.5 9h5M6.5 12h3"/>',
		"party": '<circle cx="6" cy="5" r="2"/><circle cx="13" cy="6" r="1.7"/><path d="M2 15v-2a4 4 0 0 1 8 0v2ZM11 10a3.5 3.5 0 0 1 5 3v2h-3"/>',
		"map": '<path d="m2.5 4 4-2 5 2 4-2v12l-4 2-5-2-4 2ZM6.5 2v12M11.5 4v12"/>',
		"system": '<circle cx="9" cy="9" r="4.5"/><circle cx="9" cy="9" r="1.5"/><path d="M9 2v2M9 14v2M2 9h2M14 9h2M4 4l1.5 1.5M12.5 12.5 14 14M14 4l-1.5 1.5M5.5 12.5 4 14"/>',
	}.get(kind, "")
	var source := '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18"><g fill="none" stroke="#%s" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round">%s</g></svg>' % [color.to_html(false), shape]
	var image := Image.new()
	image.load_svg_from_string(source)
	var result := ImageTexture.create_from_image(image)
	_textures[key] = result
	return result

static func bar_fill(color: Color) -> StyleBoxTexture:
	var key := "bar:" + color.to_html()
	if _boxes.has(key): return _boxes[key]
	var gradient := Gradient.new()
	gradient.set_color(0, color.lightened(0.10))
	gradient.set_color(1, color.darkened(0.15))
	gradient.add_point(0.35, color)
	var fill := GradientTexture2D.new()
	fill.gradient = gradient
	fill.width = 2
	fill.height = 16
	fill.fill_from = Vector2(0, 0)
	fill.fill_to = Vector2(0, 1)
	var style := StyleBoxTexture.new()
	style.texture = fill
	style.set_content_margin_all(0)
	_boxes[key] = style
	return style
