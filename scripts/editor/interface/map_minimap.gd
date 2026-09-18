extends PanelContainer
## Left-dock map thumbnail: whole map, view rect, click to jump.

signal jump_to_world(world: Vector2)

const MAX_SIDE := 192

var map_w: int = 1
var map_h: int = 1
var tile_size: int = 48
var cell_px: int = 2
var view_world: Rect2 = Rect2()
var chunk_world: Rect2 = Rect2()

var _tex: Texture2D
var _host: Control
var _dragging: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.05, 0.06, 0.08, 1)
	st.border_color = Color(0.22, 0.24, 0.28, 1)
	st.set_border_width_all(1)
	st.content_margin_left = 3
	st.content_margin_right = 3
	st.content_margin_top = 3
	st.content_margin_bottom = 3
	add_theme_stylebox_override("panel", st)
	_host = Control.new()
	_host.mouse_filter = Control.MOUSE_FILTER_STOP
	_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_host)
	_host.draw.connect(_draw_host)
	_host.gui_input.connect(_on_input)
	resized.connect(func(): _host.queue_redraw())


func rebuild(field: Node2D, doc: RefCounted) -> void:
	if doc == null:
		_tex = null
		if _host:
			_host.queue_redraw()
		return
	map_w = maxi(int(doc.width), 1)
	map_h = maxi(int(doc.height), 1)
	tile_size = maxi(int(doc.tile_size), 1)
	cell_px = clampi(int(floor(float(MAX_SIDE) / float(maxi(map_w, map_h)))), 1, 3)
	if field == null:
		_tex = null
		if _host:
			_host.queue_redraw()
		return
	var img: Image = null
	if field.has_method("ensure_world_map"):
		field.ensure_world_map()
	if field.has_method("get_lofi_image"):
		img = field.get_lofi_image()
	if img == null and field.has_method("render_preview") and map_w * map_h <= 65536:
		img = field.render_preview(0, 0, map_w, map_h, cell_px)
	if img != null:
		var longest: int = maxi(img.get_width(), img.get_height())
		if longest > MAX_SIDE:
			var sc := float(MAX_SIDE) / float(longest)
			img = img.duplicate()
			img.resize(maxi(1, int(img.get_width() * sc)), maxi(1, int(img.get_height() * sc)), Image.INTERPOLATE_NEAREST)
		elif img.get_width() == map_w and cell_px > 1 and map_w * cell_px <= MAX_SIDE * 2:
			img = img.duplicate()
			img.resize(maxi(1, map_w * cell_px), maxi(1, map_h * cell_px), Image.INTERPOLATE_NEAREST)
	if img == null or img.get_width() <= 0:
		_tex = null
		if _host:
			_host.queue_redraw()
		return
	var longest: int = maxi(img.get_width(), img.get_height())
	if longest > MAX_SIDE:
		var sc := float(MAX_SIDE) / float(longest)
		img.resize(maxi(1, int(img.get_width() * sc)), maxi(1, int(img.get_height() * sc)), Image.INTERPOLATE_NEAREST)
	if _tex is ImageTexture and _tex.get_width() == img.get_width() and _tex.get_height() == img.get_height():
		(_tex as ImageTexture).update(img)
	else:
		_tex = ImageTexture.create_from_image(img)
	if _host:
		_host.queue_redraw()


func patch_cells(field: Node2D, cells: Array) -> void:
	if _tex == null or field == null or cells.is_empty():
		rebuild(field, field.edit_doc if field else null)
		return
	if cells.size() > 80:
		rebuild(field, field.edit_doc if field else null)
		return
	var img: Image = _tex.get_image() if _tex is ImageTexture else null
	if img == null:
		rebuild(field, field.edit_doc if field else null)
		return
	var lofi: Image = field.get_lofi_image() if field.has_method("get_lofi_image") else null
	for item in cells:
		var c: Vector2i = item
		if c.x < 0 or c.y < 0 or c.x >= map_w or c.y >= map_h:
			continue
		if lofi != null and c.x < lofi.get_width() and c.y < lofi.get_height():
			var col: Color = lofi.get_pixel(c.x, c.y)
			for py in range(cell_px):
				for px in range(cell_px):
					img.set_pixel(c.x * cell_px + px, c.y * cell_px + py, col)
			continue
		if not field.has_method("render_preview"):
			continue
		var chip: Image = field.render_preview(c.x, c.y, 1, 1, cell_px)
		if chip == null:
			continue
		if chip.get_width() != cell_px or chip.get_height() != cell_px:
			chip.resize(cell_px, cell_px, Image.INTERPOLATE_NEAREST)
		img.blit_rect(chip, Rect2i(0, 0, cell_px, cell_px), Vector2i(c.x * cell_px, c.y * cell_px))
	(_tex as ImageTexture).update(img)
	_host.queue_redraw()


func set_view_world(r: Rect2) -> void:
	view_world = r
	if _host:
		_host.queue_redraw()


func set_chunk_world(r: Rect2) -> void:
	chunk_world = r
	if _host:
		_host.queue_redraw()


func map_draw_rect() -> Rect2:
	var inner := Rect2(Vector2.ZERO, _host.size) if _host else Rect2(Vector2.ZERO, size)
	if inner.size.x < 2.0 or inner.size.y < 2.0:
		return inner
	var aspect := float(map_w) / float(map_h)
	var box := inner.size
	var w := box.x
	var h := w / maxf(aspect, 0.001)
	if h > box.y:
		h = box.y
		w = h * aspect
	var pos := inner.position + (box - Vector2(w, h)) * 0.5
	return Rect2(pos, Vector2(w, h))


func _draw_host() -> void:
	var r := map_draw_rect()
	if _tex != null:
		_host.draw_texture_rect(_tex, r, false)
	else:
		_host.draw_rect(r, Color(0.08, 0.09, 0.11, 1), true)
	_host.draw_rect(r, Color(0.35, 0.38, 0.42, 0.9), false, 1.0)
	var map_px := Vector2(float(map_w * tile_size), float(map_h * tile_size))
	if map_px.x < 1.0 or map_px.y < 1.0:
		return
	if chunk_world.size.x > 1.0 and chunk_world.size.y > 1.0:
		var cr := Rect2(
			r.position + Vector2(chunk_world.position.x / map_px.x, chunk_world.position.y / map_px.y) * r.size,
			Vector2(chunk_world.size.x / map_px.x, chunk_world.size.y / map_px.y) * r.size
		)
		cr = cr.intersection(r)
		if cr.size.x >= 1.0 and cr.size.y >= 1.0:
			_host.draw_rect(cr, Color(0.35, 0.85, 1.0, 0.16), true)
			_host.draw_rect(cr, Color(0.45, 0.9, 1.0, 0.95), false, 1.5)
	if view_world.size.x <= 1.0 or view_world.size.y <= 1.0:
		return
	var vr := Rect2(
		r.position + Vector2(view_world.position.x / map_px.x, view_world.position.y / map_px.y) * r.size,
		Vector2(view_world.size.x / map_px.x, view_world.size.y / map_px.y) * r.size
	)
	vr = vr.intersection(r)
	if vr.size.x < 2.0:
		vr.size.x = 2.0
	if vr.size.y < 2.0:
		vr.size.y = 2.0
	_host.draw_rect(vr, Color(1.0, 0.85, 0.2, 0.18), true)
	_host.draw_rect(vr, Color(1.0, 0.82, 0.15, 0.95), false, 1.5)


func _on_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		_dragging = mb.pressed
		if mb.pressed:
			_emit_jump(mb.position)
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_emit_jump((event as InputEventMouseMotion).position)
		accept_event()


func _emit_jump(local: Vector2) -> void:
	var r := map_draw_rect()
	if r.size.x < 1.0 or r.size.y < 1.0:
		return
	var u := clampf((local.x - r.position.x) / r.size.x, 0.0, 1.0)
	var v := clampf((local.y - r.position.y) / r.size.y, 0.0, 1.0)
	jump_to_world.emit(Vector2(u * float(map_w * tile_size), v * float(map_h * tile_size)))
