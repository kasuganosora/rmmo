extends Control
## World map: prebaked overview if present, otherwise JIT chunk bake.
## Drag pans; newly visible chunks stream in.

const CHUNK := 16
const ZOOM_MIN_CELLS := 32.0
const STREAM_PER_FRAME := 4
const STREAM_TEX_MAX := 48

var _map_field: Node2D = null
var _player: Node2D = null
var _map_id: String = ""
var _fit_rect: Rect2 = Rect2()
var _content_px: Rect2 = Rect2()
var _last_cell: Vector2i = Vector2i(2147483647, 2147483647)
var _last_yaw: float = 1.0e9
var _last_pos: Vector2 = Vector2(1.0e9, 1.0e9)

var _pan_cell: Vector2 = Vector2.ZERO
var _cells_across: float = 0.0
var _dragging: bool = false
var _drag_last: Vector2 = Vector2.ZERO
var _chunk_tex: Dictionary = {}
var _stream_q: Array[Vector2i] = []
var _stream_seen: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	resized.connect(_on_resized)
	set_process(true)
	gui_input.connect(_on_gui_input)
	visibility_changed.connect(_on_vis)
	queue_redraw()


func _on_resized() -> void:
	_queue_visible_chunks()
	queue_redraw()


func _on_vis() -> void:
	if is_visible_in_tree():
		_kick()


func bind(map_field: Node2D, player: Node2D, map_id: String = "") -> void:
	_map_field = map_field
	_player = player
	_map_id = map_id
	_last_cell = Vector2i(2147483647, 2147483647)
	_last_yaw = 1.0e9
	_last_pos = Vector2(1.0e9, 1.0e9)
	_chunk_tex.clear()
	_stream_q.clear()
	_stream_seen.clear()
	_cells_across = 0.0
	var cell := _player_cell()
	_pan_cell = Vector2(cell)
	_kick()
	queue_redraw()


func hint_line() -> String:
	var mid := _map_id
	if mid.is_empty() and _map_field != null and "pack_path" in _map_field:
		mid = str(_map_field.pack_path).get_file()
	if mid.is_empty():
		mid = "map"
	var cell := _player_cell()
	var extra := ""
	if _map_field != null and _map_field.has_method("world_map_complete") and not bool(_map_field.world_map_complete()):
		var p := 0.0
		if _map_field.has_method("world_map_progress"):
			p = float(_map_field.world_map_progress())
		extra = "  渲染中 %d%%" % int(p * 100.0)
	return "%s  (%d, %d)%s" % [mid, cell.x, cell.y, extra]


func set_pan_cell(cell: Vector2) -> void:
	_pan_cell = cell
	_clamp_pan()
	_stream_q.clear()
	_queue_visible_chunks()
	queue_redraw()


func set_cells_across(n: float) -> void:
	_cells_across = n
	_clamp_zoom()
	_stream_q.clear()
	_queue_visible_chunks()
	queue_redraw()


func has_stream_chunk(cx: int, cy: int) -> bool:
	return _chunk_tex.has("%d,%d" % [cx, cy])


func visible_chunk_count() -> int:
	return _chunk_tex.size()


func step_live(n: int = 4) -> void:
	_kick()
	var ch := Vector2i(int(floor(_pan_cell.x / float(CHUNK))), int(floor(_pan_cell.y / float(CHUNK))))
	var key := "%d,%d" % [ch.x, ch.y]
	if not _chunk_tex.has(key):
		for i in range(_stream_q.size()):
			if _stream_q[i] == ch:
				_stream_q.remove_at(i)
				break
		_stream_q.insert(0, ch)
		_stream_seen[key] = true
	if _map_field != null and _map_field.has_method("world_map_step"):
		_map_field.world_map_step(n)
	_step_stream(n)
	queue_redraw()


func _kick() -> void:
	if _map_field != null and _map_field.has_method("ensure_world_map"):
		_map_field.ensure_world_map()
	_queue_visible_chunks()


func _player_cell() -> Vector2i:
	if _player != null and "cell" in _player:
		return _player.cell
	if _map_field != null and _player != null and _map_field.has_method("world_to_cell"):
		return _map_field.world_to_cell(_player.global_position)
	return Vector2i.ZERO


func _grid() -> Vector2i:
	if _map_field == null:
		return Vector2i.ONE
	return Vector2i(
		maxi(int(_map_field.grid_width), 1),
		maxi(int(_map_field.grid_height), 1)
	)


func _view_cells() -> Vector2:
	var g := _grid()
	var across: float = _cells_across
	if across <= 1.0:
		across = float(maxi(g.x, g.y))
	var aspect := size.y / maxf(size.x, 1.0)
	if aspect < 0.05:
		aspect = 0.75
	return Vector2(across, across * aspect)


func _clamp_zoom() -> void:
	var g := _grid()
	var max_across := float(maxi(g.x, g.y))
	if _cells_across <= 1.0:
		return
	_cells_across = clampf(_cells_across, ZOOM_MIN_CELLS, max_across)


func _clamp_pan() -> void:
	var g := _grid()
	var half := _view_cells() * 0.5
	_pan_cell.x = clampf(_pan_cell.x, half.x, float(g.x) - half.x)
	_pan_cell.y = clampf(_pan_cell.y, half.y, float(g.y) - half.y)
	if g.x <= int(ceil(_view_cells().x)):
		_pan_cell.x = float(g.x) * 0.5
	if g.y <= int(ceil(_view_cells().y)):
		_pan_cell.y = float(g.y) * 0.5


func _view_cell_rect() -> Rect2:
	var half := _view_cells() * 0.5
	return Rect2(_pan_cell - half, _view_cells())


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_dragging = mb.pressed
			_drag_last = mb.position
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(mb.position, 1.0 / 1.2)
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(mb.position, 1.2)
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		var vc := _view_cells()
		var dx: float = (mm.position.x - _drag_last.x) / maxf(size.x, 1.0) * vc.x
		var dy: float = (mm.position.y - _drag_last.y) / maxf(size.y, 1.0) * vc.y
		_pan_cell -= Vector2(dx, dy)
		_drag_last = mm.position
		_clamp_pan()
		_queue_visible_chunks()
		queue_redraw()
		accept_event()


func _zoom_at(local: Vector2, factor: float) -> void:
	var g := _grid()
	var old := _view_cells()
	if _cells_across <= 1.0:
		_cells_across = float(maxi(g.x, g.y))
	var u := clampf(local.x / maxf(size.x, 1.0), 0.0, 1.0)
	var v := clampf(local.y / maxf(size.y, 1.0), 0.0, 1.0)
	var focus := Vector2(_pan_cell.x - old.x * 0.5 + old.x * u, _pan_cell.y - old.y * 0.5 + old.y * v)
	_cells_across *= factor
	_clamp_zoom()
	var nw := _view_cells()
	_pan_cell = Vector2(focus.x - nw.x * (u - 0.5), focus.y - nw.y * (v - 0.5))
	_clamp_pan()
	_queue_visible_chunks()
	queue_redraw()


func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	if _map_field != null and _map_field.has_method("world_map_step") and _map_field.has_method("world_map_complete"):
		if not bool(_map_field.world_map_complete()):
			_map_field.world_map_step(3)
	_step_stream(STREAM_PER_FRAME)
	if _player == null:
		queue_redraw()
		return
	var cell := _player_cell()
	var yaw := PI * 0.5
	if _player.has_method("facing_angle"):
		yaw = float(_player.facing_angle())
	var pos: Vector2 = _player.global_position
	if cell != _last_cell or absf(yaw - _last_yaw) > 0.001 or pos.distance_squared_to(_last_pos) > 0.25:
		_last_cell = cell
		_last_yaw = yaw
		_last_pos = pos
		queue_redraw()


func _queue_visible_chunks() -> void:
	if _map_field == null or not _map_field.has_method("sample_world_chunk"):
		return
	var vr := _view_cell_rect()
	var sx := maxf(size.x, 256.0)
	var chunk_px := sx / maxf(vr.size.x, 1.0) * float(CHUNK)
	if chunk_px < 12.0:
		return
	var g := _grid()
	var max_cx := int(ceil(float(g.x) / float(CHUNK))) - 1
	var max_cy := int(ceil(float(g.y) / float(CHUNK))) - 1
	var x0 := clampi(int(floor(vr.position.x / float(CHUNK))), 0, max_cx)
	var y0 := clampi(int(floor(vr.position.y / float(CHUNK))), 0, max_cy)
	var x1 := clampi(int(floor((vr.position.x + vr.size.x) / float(CHUNK))), 0, max_cx)
	var y1 := clampi(int(floor((vr.position.y + vr.size.y) / float(CHUNK))), 0, max_cy)
	if (x1 - x0 + 1) * (y1 - y0 + 1) > 64:
		return
	for cy in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			var key := "%d,%d" % [cx, cy]
			if _chunk_tex.has(key) or _stream_seen.has(key):
				continue
			_stream_seen[key] = true
			_stream_q.append(Vector2i(cx, cy))


func _step_stream(n: int) -> void:
	if _map_field == null or not _map_field.has_method("sample_world_chunk"):
		return
	var i := 0
	while i < n and not _stream_q.is_empty():
		var ch: Vector2i = _stream_q.pop_front()
		var img: Image = _map_field.sample_world_chunk(ch.x, ch.y)
		if img != null:
			_chunk_tex["%d,%d" % [ch.x, ch.y]] = ImageTexture.create_from_image(img)
			if _chunk_tex.size() > STREAM_TEX_MAX:
				var keys: Array = _chunk_tex.keys()
				_chunk_tex.erase(keys[0])
		i += 1


func _resolve_content_px(gw: int, gh: int, ts: int) -> Rect2:
	if _map_field != null and _map_field.has_method("get_content_pixel_rect"):
		var r: Rect2 = _map_field.get_content_pixel_rect()
		if r.size.x > 0.0 and r.size.y > 0.0:
			return r
	return Rect2(0.0, 0.0, float(gw * ts), float(gh * ts))


func _cell_to_screen(cell: Vector2) -> Vector2:
	var vr := _view_cell_rect()
	if vr.size.x <= 0.001 or vr.size.y <= 0.001:
		return size * 0.5
	var u := (cell.x - vr.position.x) / vr.size.x
	var v := (cell.y - vr.position.y) / vr.size.y
	return Vector2(u * size.x, v * size.y)


func _draw() -> void:
	if _map_field == null:
		draw_string(
			ThemeDB.fallback_font,
			Vector2(12, 28),
			"无地图数据",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			13,
			Color(0.7, 0.7, 0.72)
		)
		return

	var gw: int = int(_map_field.grid_width) if "grid_width" in _map_field else 0
	var gh: int = int(_map_field.grid_height) if "grid_height" in _map_field else 0
	var ts: int = int(_map_field.tile_size) if "tile_size" in _map_field else 48
	if gw <= 0 or gh <= 0 or ts <= 0:
		return

	if _pan_cell == Vector2.ZERO and _cells_across <= 1.0:
		_pan_cell = Vector2(_player_cell())
		_clamp_pan()

	_content_px = _resolve_content_px(gw, gh, ts)
	var vr := _view_cell_rect()
	_fit_rect = Rect2(Vector2.ZERO, size)

	var lofi: Texture2D = null
	if _map_field.has_method("get_lofi_texture"):
		lofi = _map_field.get_lofi_texture()
	if lofi != null:
		var src := Rect2(
			Vector2(vr.position.x / float(gw) * float(lofi.get_width()), vr.position.y / float(gh) * float(lofi.get_height())),
			Vector2(vr.size.x / float(gw) * float(lofi.get_width()), vr.size.y / float(gh) * float(lofi.get_height()))
		)
		draw_texture_rect_region(lofi, _fit_rect, src)
	else:
		draw_rect(_fit_rect, Color(0.06, 0.07, 0.07, 1), true)

	var chunk_px := size.x / maxf(vr.size.x, 1.0) * float(CHUNK)
	if chunk_px >= 12.0:
		for key in _chunk_tex.keys():
			var parts: PackedStringArray = str(key).split(",")
			if parts.size() < 2:
				continue
			var cx := int(parts[0])
			var cy := int(parts[1])
			var origin := Vector2(float(cx * CHUNK), float(cy * CHUNK))
			var dest := Rect2(_cell_to_screen(origin), Vector2(chunk_px, chunk_px))
			if dest.intersects(_fit_rect):
				draw_texture_rect(_chunk_tex[key], dest, false)

	if _map_field.has_method("world_map_complete") and not bool(_map_field.world_map_complete()):
		var p := 0.0
		if _map_field.has_method("world_map_progress"):
			p = float(_map_field.world_map_progress())
		draw_rect(Rect2(8, size.y - 18, (size.x - 16) * p, 6), Color(0.95, 0.78, 0.2, 0.85), true)

	if _player == null:
		return
	var pcell := Vector2(_player_cell()) + Vector2(0.5, 0.5)
	var pos := _cell_to_screen(pcell)
	var yaw := PI * 0.5
	if _player.has_method("facing_angle"):
		yaw = float(_player.facing_angle())
	var tip := pos + Vector2(cos(yaw), sin(yaw)) * 10.0
	var left := pos + Vector2(cos(yaw + 2.45), sin(yaw + 2.45)) * 7.0
	var right := pos + Vector2(cos(yaw - 2.45), sin(yaw - 2.45)) * 7.0
	draw_circle(pos, 3.0, Color(0.15, 0.12, 0.05, 0.85))
	draw_colored_polygon(PackedVector2Array([tip, left, right]), Color(0.95, 0.78, 0.2))
