extends RefCounted
## CPU blit of tile IDs onto Image targets (48px grid, half-tile quarters).

const TileId = preload("res://scripts/map/tile_id.gd")
const JsonUtil = preload("res://scripts/util/json_util.gd")

const TABLES_PATH := "res://scripts/map/autotile_tables.json"

static var _tables_loaded: bool = false
static var _floor_table: Array = []
static var _wall_table: Array = []
static var _waterfall_table: Array = []
static var _color_cache: Dictionary = {}
static var _sample_tmp: Image = null


static func ensure_tables() -> void:
	if _tables_loaded:
		return
	_tables_loaded = true
	var parsed: Variant = JsonUtil.parse_file(TABLES_PATH)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("tile_blit: missing or bad autotile_tables.json")
		return
	var d: Dictionary = parsed
	_floor_table = d.get("FLOOR", [])
	_wall_table = d.get("WALL", [])
	_waterfall_table = d.get("WATERFALL", [])


static func sample_color(tile_id: int, sheets: Array, flags: PackedInt32Array = PackedInt32Array()) -> Color:
	if not TileId.is_visible(tile_id):
		return Color(0, 0, 0, 0)
	ensure_tables()
	## A2 edge shapes mix dirt seams; sample the filled face for minimap.
	var sample_id: int = tile_id
	if TileId.is_tile_a2(tile_id):
		sample_id = TileId.make_autotile_id(TileId.autotile_kind(tile_id), 47)
	if _color_cache.has(sample_id):
		return _color_cache[sample_id]
	## Always blit at native 48px. Sampling at 4px treats the sheet as 4px tiles and
	## reads autotile corners (dirt seams) instead of grass / water / brick faces.
	const PX := 48
	if _sample_tmp == null or _sample_tmp.get_width() != PX:
		_sample_tmp = Image.create(PX, PX, false, Image.FORMAT_RGBA8)
	_sample_tmp.fill(Color(0, 0, 0, 0))
	blit_tile(_sample_tmp, sample_id, 0, 0, sheets, PX, PX, flags, 0)
	var col := _average_opaque(_sample_tmp, 12, 12, 36, 36)
	if col.a < 0.2:
		col = _average_opaque(_sample_tmp, 0, 0, PX, PX)
	_color_cache[sample_id] = col
	return col


static func _average_opaque(img: Image, x0: int, y0: int, x1: int, y1: int) -> Color:
	if img == null:
		return Color(0, 0, 0, 0)
	var r := 0.0
	var g := 0.0
	var b := 0.0
	var n := 0
	var step := 2
	for y in range(y0, y1, step):
		for x in range(x0, x1, step):
			var c: Color = img.get_pixel(x, y)
			if c.a < 0.2:
				continue
			r += c.r
			g += c.g
			b += c.b
			n += 1
	if n <= 0:
		return Color(0, 0, 0, 0)
	return Color(r / float(n), g / float(n), b / float(n), 1)


static func blit_tile(
	dest: Image,
	tile_id: int,
	dx: int,
	dy: int,
	sheets: Array,
	tile_w: int = 48,
	tile_h: int = 48,
	flags: PackedInt32Array = PackedInt32Array(),
	anim_frame: int = 0
) -> void:
	if dest == null or not TileId.is_visible(tile_id):
		return
	if TileId.is_autotile(tile_id):
		_blit_autotile(dest, tile_id, dx, dy, sheets, tile_w, tile_h, flags, anim_frame)
	else:
		_blit_normal(dest, tile_id, dx, dy, sheets, tile_w, tile_h)


static func blit_shadow(dest: Image, shadow_bits: int, dx: int, dy: int, tile_w: int = 48, tile_h: int = 48) -> void:
	# Corner shadows must be blended into the ground bitmap (not a sprite above it),
	# otherwise transparent rug fringes show a hard grey rectangle behind them.
	if dest == null or shadow_bits <= 0 or shadow_bits > 15:
		return
	var w1: int = tile_w / 2
	var h1: int = tile_h / 2
	var a: float = 0.5
	for i in range(4):
		if (shadow_bits & (1 << i)) == 0:
			continue
		var x0: int = dx + (i % 2) * w1
		var y0: int = dy + int(i / 2) * h1
		for py in range(h1):
			for px in range(w1):
				var x: int = x0 + px
				var y: int = y0 + py
				if x < 0 or y < 0 or x >= dest.get_width() or y >= dest.get_height():
					continue
				var src: Color = dest.get_pixel(x, y)
				# Darken existing ground; keep destination alpha (don't punch grey into holes).
				if src.a <= 0.001:
					continue
				src.r = src.r * (1.0 - a)
				src.g = src.g * (1.0 - a)
				src.b = src.b * (1.0 - a)
				dest.set_pixel(x, y, src)


static func _sheet(sheets: Array, set_number: int) -> Image:
	if set_number < 0 or set_number >= sheets.size():
		return null
	var v: Variant = sheets[set_number]
	if v == null:
		return null
	return _ensure_rgba8(v as Image)


static func _ensure_rgba8(img: Image) -> Image:
	if img == null:
		return null
	if img.get_format() == Image.FORMAT_RGBA8:
		return img
	if img.is_compressed():
		img.decompress()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	return img


static func _blit_normal(
	dest: Image,
	tile_id: int,
	dx: int,
	dy: int,
	sheets: Array,
	tile_w: int,
	tile_h: int
) -> void:
	var set_number: int
	if TileId.is_tile_a5(tile_id):
		set_number = 4
	else:
		set_number = 5 + int(floor(float(tile_id) / 256.0))
	var source: Image = _sheet(sheets, set_number)
	if source == null:
		return
	var sx: int = (int(floor(float(tile_id) / 128.0)) % 2 * 8 + tile_id % 8) * tile_w
	var sy: int = (int(floor(float(tile_id % 256) / 8.0)) % 16) * tile_h
	_safe_blit(dest, source, sx, sy, tile_w, tile_h, dx, dy)


static func _blit_autotile(
	dest: Image,
	tile_id: int,
	dx: int,
	dy: int,
	sheets: Array,
	tile_w: int,
	tile_h: int,
	flags: PackedInt32Array,
	anim_frame: int
) -> void:
	ensure_tables()
	var autotile_table: Array = _floor_table
	var kind: int = TileId.autotile_kind(tile_id)
	var shape: int = TileId.autotile_shape(tile_id)
	var tx: int = kind % 8
	var ty: int = int(floor(float(kind) / 8.0))
	var bx: int = 0
	var by: int = 0
	var set_number: int = 0
	var is_table: bool = false
	var water_surface_index: int = [0, 1, 2, 1][anim_frame % 4]

	if TileId.is_tile_a1(tile_id):
		set_number = 0
		if kind == 0:
			bx = water_surface_index * 2
			by = 0
		elif kind == 1:
			bx = water_surface_index * 2
			by = 3
		elif kind == 2:
			bx = 6
			by = 0
		elif kind == 3:
			bx = 6
			by = 3
		else:
			bx = int(floor(float(tx) / 4.0)) * 8
			by = ty * 6 + int(floor(float(tx) / 2.0)) % 2 * 3
			if kind % 2 == 0:
				bx += water_surface_index * 2
			else:
				bx += 6
				autotile_table = _waterfall_table
				by += anim_frame % 3
	elif TileId.is_tile_a2(tile_id):
		set_number = 1
		bx = tx * 2
		by = (ty - 2) * 3
		is_table = _is_table_tile(tile_id, flags)
	elif TileId.is_tile_a3(tile_id):
		set_number = 2
		bx = tx * 2
		by = (ty - 6) * 2
		autotile_table = _wall_table
	elif TileId.is_tile_a4(tile_id):
		set_number = 3
		bx = tx * 2
		by = int(floor(float(ty - 10) * 2.5 + (0.5 if ty % 2 == 1 else 0.0)))
		if ty % 2 == 1:
			autotile_table = _wall_table
	else:
		return

	if shape < 0 or shape >= autotile_table.size():
		return
	var table: Variant = autotile_table[shape]
	if typeof(table) != TYPE_ARRAY:
		return
	var source: Image = _sheet(sheets, set_number)
	if source == null:
		return

	var w1: int = tile_w / 2
	var h1: int = tile_h / 2
	var quarters: Array = table
	for i in range(mini(4, quarters.size())):
		var q: Variant = quarters[i]
		if typeof(q) != TYPE_ARRAY or (q as Array).size() < 2:
			continue
		var qsx: int = int((q as Array)[0])
		var qsy: int = int((q as Array)[1])
		var sx1: int = (bx * 2 + qsx) * w1
		var sy1: int = (by * 2 + qsy) * h1
		var dx1: int = dx + (i % 2) * w1
		var dy1: int = dy + int(i / 2) * h1
		if is_table and (qsy == 1 or qsy == 5):
			var qsx2: int = qsx
			var qsy2: int = 3
			if qsy == 1:
				qsx2 = [0, 3, 2, 1][qsx]
			var sx2: int = (bx * 2 + qsx2) * w1
			var sy2: int = (by * 2 + qsy2) * h1
			_safe_blit(dest, source, sx2, sy2, w1, h1, dx1, dy1)
			dy1 += h1 / 2
			_safe_blit(dest, source, sx1, sy1, w1, h1 / 2, dx1, dy1)
		else:
			_safe_blit(dest, source, sx1, sy1, w1, h1, dx1, dy1)


static func is_table_tile(tile_id: int, flags: PackedInt32Array) -> bool:
	if not TileId.is_tile_a2(tile_id):
		return false
	if tile_id < 0 or tile_id >= flags.size():
		return false
	return (flags[tile_id] & 0x80) != 0


static func _is_table_tile(tile_id: int, flags: PackedInt32Array) -> bool:
	return is_table_tile(tile_id, flags)


## Bottom half-strip of the A2 table tile above, into the current cell (lower).
## Matches classic tilemap table-edge when flags have 0x80.
static func blit_table_edge(
	dest: Image,
	tile_id: int,
	dx: int,
	dy: int,
	sheets: Array,
	tile_w: int = 48,
	tile_h: int = 48
) -> void:
	if dest == null or not TileId.is_tile_a2(tile_id):
		return
	ensure_tables()
	var kind: int = TileId.autotile_kind(tile_id)
	var shape: int = TileId.autotile_shape(tile_id)
	var tx: int = kind % 8
	var ty: int = int(floor(float(kind) / 8.0))
	var bx: int = tx * 2
	var by: int = (ty - 2) * 3
	if shape < 0 or shape >= _floor_table.size():
		return
	var table: Variant = _floor_table[shape]
	if typeof(table) != TYPE_ARRAY:
		return
	var source: Image = _sheet(sheets, 1)
	if source == null:
		return
	var w1: int = tile_w / 2
	var h1: int = tile_h / 2
	var quarters: Array = table
	for i in range(2):
		var qi: int = 2 + i
		if qi >= quarters.size():
			continue
		var q: Variant = quarters[qi]
		if typeof(q) != TYPE_ARRAY or (q as Array).size() < 2:
			continue
		var qsx: int = int((q as Array)[0])
		var qsy: int = int((q as Array)[1])
		var sx1: int = (bx * 2 + qsx) * w1
		var sy1: int = (by * 2 + qsy) * h1 + h1 / 2
		var dx1: int = dx + (i % 2) * w1
		var dy1: int = dy + int(i / 2) * h1
		_safe_blit(dest, source, sx1, sy1, w1, h1 / 2, dx1, dy1)


static func _safe_blit(
	dest: Image,
	source: Image,
	sx: int,
	sy: int,
	w: int,
	h: int,
	dx: int,
	dy: int
) -> void:
	if w <= 0 or h <= 0:
		return
	if sx < 0 or sy < 0 or sx + w > source.get_width() or sy + h > source.get_height():
		return
	if dx < 0 or dy < 0 or dx + w > dest.get_width() or dy + h > dest.get_height():
		return
	# Alpha-blend so rug fringes keep the floor underneath (blit_rect would replace
	# floor RGB with low-alpha pixels and look like a grey box against the void).
	dest.blend_rect(source, Rect2i(sx, sy, w, h), Vector2i(dx, dy))
