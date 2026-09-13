extends RefCounted
## First-party placeholder chrome (OK in res:// / generated Images — not UGC).

static func first_grapheme(full: String) -> String:
	full = full.strip_edges()
	if full.is_empty():
		return "?"
	return full.substr(0, 1)


## Solid letter-avatar texture (HSV tint from codepoint). No Godot ResourceLoader UGC path.
static func make_letter_texture(text: String, size: int = 48) -> ImageTexture:
	var letter := first_grapheme(text)
	var s: int = maxi(size, 8)
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var code: int = letter.unicode_at(0) if letter.length() > 0 else 63
	var hue: float = float(code % 360) / 360.0
	var bg := Color.from_hsv(hue, 0.28, 0.32, 1.0)
	var fg := Color.from_hsv(hue, 0.15, 0.78, 1.0)
	var border := Color.from_hsv(hue, 0.2, 0.55, 1.0)
	img.fill(bg)
	for i in s:
		img.set_pixel(i, 0, border)
		img.set_pixel(i, s - 1, border)
		img.set_pixel(0, i, border)
		img.set_pixel(s - 1, i, border)
	# Inner plate
	var m: int = maxi(s / 6, 2)
	for y in range(m, s - m):
		for x in range(m, s - m):
			img.set_pixel(x, y, fg.darkened(0.15))
	# Crude 5x7 glyph blob in the center (readable as "letter block", not a font)
	_blit_glyph_blob(img, letter, fg)
	return ImageTexture.create_from_image(img)


static func _blit_glyph_blob(img: Image, letter: String, color: Color) -> void:
	var w: int = img.get_width()
	var h: int = img.get_height()
	var cw: int = maxi(w / 5, 3)
	var ch: int = maxi(h / 3, 5)
	var ox: int = (w - cw) / 2
	var oy: int = (h - ch) / 2
	# Vertical stem
	for y in range(oy, oy + ch):
		for x in range(ox + cw / 2 - 1, ox + cw / 2 + 2):
			if x >= 0 and x < w and y >= 0 and y < h:
				img.set_pixel(x, y, color)
	# Top bar (suggests a character)
	for x in range(ox, ox + cw):
		for y in range(oy, oy + 2):
			if x >= 0 and x < w and y >= 0 and y < h:
				img.set_pixel(x, y, color)
	# Encode codepoint lightly into a bottom tick so avatars differ
	var code: int = letter.unicode_at(0) if letter.length() > 0 else 63
	var tick: int = ox + (code % maxi(cw, 1))
	for y in range(oy + ch - 2, oy + ch):
		if tick >= 0 and tick < w and y >= 0 and y < h:
			img.set_pixel(tick, y, color)


## SpriteFrames with idle/walk_* using the same letter texture (safe empty-charset fallback).
static func make_letter_sprite_frames(text: String, size: int = 48) -> SpriteFrames:
	var tex: ImageTexture = make_letter_texture(text, size)
	var frames := SpriteFrames.new()
	if frames.has_animation("default"):
		frames.remove_animation("default")
	for facing in ["front", "left", "right", "back"]:
		var idle_name := "idle_%s" % facing
		frames.add_animation(idle_name)
		frames.set_animation_speed(idle_name, 1.0)
		frames.set_animation_loop(idle_name, true)
		frames.add_frame(idle_name, tex)
		var walk_name := "walk_%s" % facing
		frames.add_animation(walk_name)
		frames.set_animation_speed(walk_name, 4.0)
		frames.set_animation_loop(walk_name, true)
		frames.add_frame(walk_name, tex)
	return frames
