extends Control
## Full current-map overview: cropped MapField content + player marker.
## Letterbox stays transparent so the HUD window panel shows through.

var _map_field: Node2D = null
var _player: Node2D = null
var _map_id: String = ""
var _fit_rect: Rect2 = Rect2()
var _content_px: Rect2 = Rect2()
var _last_cell: Vector2i = Vector2i(2147483647, 2147483647)
var _last_yaw: float = 1.0e9
var _last_pos: Vector2 = Vector2(1.0e9, 1.0e9)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	resized.connect(_on_resized)
	set_process(true)
	queue_redraw()


func _on_resized() -> void:
	queue_redraw()


func bind(map_field: Node2D, player: Node2D, map_id: String = "") -> void:
	_map_field = map_field
	_player = player
	_map_id = map_id
	_last_cell = Vector2i(2147483647, 2147483647)
	_last_yaw = 1.0e9
	_last_pos = Vector2(1.0e9, 1.0e9)
	queue_redraw()


func hint_line() -> String:
	var mid := _map_id
	if mid.is_empty() and _map_field != null and "pack_path" in _map_field:
		mid = str(_map_field.pack_path).get_file()
	if mid.is_empty():
		mid = "map"
	var cell := _player_cell()
	return "%s  (%d, %d)" % [mid, cell.x, cell.y]


func _player_cell() -> Vector2i:
	if _player != null and "cell" in _player:
		return _player.cell
	if _map_field != null and _player != null and _map_field.has_method("world_to_cell"):
		return _map_field.world_to_cell(_player.global_position)
	return Vector2i.ZERO


func _process(_delta: float) -> void:
	if not is_visible_in_tree() or _player == null:
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


func _resolve_content_px(gw: int, gh: int, ts: int) -> Rect2:
	if _map_field != null and _map_field.has_method("get_content_pixel_rect"):
		var r: Rect2 = _map_field.get_content_pixel_rect()
		if r.size.x > 0.0 and r.size.y > 0.0:
			return r
	return Rect2(0.0, 0.0, float(gw * ts), float(gh * ts))


func _compute_fit_rect(tex_w: float, tex_h: float) -> Rect2:
	if tex_w <= 0.0 or tex_h <= 0.0:
		return Rect2(Vector2.ZERO, size)
	var pad := 4.0
	var avail := size - Vector2(pad * 2.0, pad * 2.0)
	if avail.x < 8.0 or avail.y < 8.0:
		avail = size
		pad = 0.0
	var sc := minf(avail.x / tex_w, avail.y / tex_h)
	var drawn := Vector2(tex_w * sc, tex_h * sc)
	var origin := Vector2(pad, pad) + (avail - drawn) * 0.5
	return Rect2(origin, drawn)


func _draw() -> void:
	# Transparent chrome: no yellow frame, no opaque black letterbox.
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

	_content_px = _resolve_content_px(gw, gh, ts)
	var content_w := maxf(_content_px.size.x, 1.0)
	var content_h := maxf(_content_px.size.y, 1.0)
	_fit_rect = _compute_fit_rect(content_w, content_h)

	var ground_tex: Texture2D = null
	var upper_tex: Texture2D = null
	if _map_field.has_method("get_ground_texture"):
		ground_tex = _map_field.get_ground_texture()
	elif _map_field.has_method("get_ground_image"):
		var gimg: Image = _map_field.get_ground_image()
		if gimg != null:
			ground_tex = ImageTexture.create_from_image(gimg)
	if _map_field.has_method("get_upper_texture"):
		upper_tex = _map_field.get_upper_texture()
	elif _map_field.has_method("get_upper_image"):
		var uimg: Image = _map_field.get_upper_image()
		if uimg != null:
			upper_tex = ImageTexture.create_from_image(uimg)

	var src := _content_px
	if ground_tex != null:
		draw_texture_rect_region(ground_tex, _fit_rect, src)
	if upper_tex != null:
		draw_texture_rect_region(upper_tex, _fit_rect, src)

	if _player == null:
		return

	var local: Vector2 = _map_field.to_local(_player.global_position)
	var nx := 0.5
	var ny := 0.5
	if content_w > 0.0 and content_h > 0.0:
		nx = clampf((local.x - _content_px.position.x) / content_w, 0.0, 1.0)
		ny = clampf((local.y - _content_px.position.y) / content_h, 0.0, 1.0)
	var pos := _fit_rect.position + Vector2(nx * _fit_rect.size.x, ny * _fit_rect.size.y)

	var yaw := PI * 0.5
	if _player.has_method("facing_angle"):
		yaw = float(_player.facing_angle())

	var tip := pos + Vector2(cos(yaw), sin(yaw)) * 10.0
	var left := pos + Vector2(cos(yaw + 2.45), sin(yaw + 2.45)) * 7.0
	var right := pos + Vector2(cos(yaw - 2.45), sin(yaw - 2.45)) * 7.0
	draw_circle(pos, 3.0, Color(0.15, 0.12, 0.05, 0.85))
	draw_colored_polygon(PackedVector2Array([tip, left, right]), Color(0.95, 0.78, 0.2))
