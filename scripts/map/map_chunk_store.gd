extends RefCounted
## On-disk 16×16 tile chunks. Missing file = empty (void). Sparse continents stay cheap.

const TileBlit = preload("res://scripts/map/tile_blit.gd")
const TileId = preload("res://scripts/map/tile_id.gd")

const MAGIC := "RMCH"
const PACK_MAGIC := "RMCP"
const IDX_MAGIC := "RMCI"
const VERSION := 1
const CHUNK_CELLS := 16
const LAYERS := 6
const PAYLOAD_INTS := 1536 ## 16*16*6
const PAYLOAD_BYTES := 6144
const OVERVIEW_MAX_SIDE := 1024
## map_dir abs -> { "cx,cy": offset }
static var _idx_cache: Dictionary = {}
static var _pack_read: Dictionary = {}
## Dense RAM is fine up to 256×256. Bigger maps must stream.
const DENSE_MAX_CELLS := 65536
const MAX_SIDE := 16384


static func should_chunk(w: int, h: int) -> bool:
	return maxi(w, 0) * maxi(h, 0) > DENSE_MAX_CELLS


static func clamp_side(n: int) -> int:
	return clampi(int(n), 1, MAX_SIDE)


static func key(cx: int, cy: int) -> String:
	return "%d,%d" % [cx, cy]


static func cell_to_chunk(cell: Vector2i) -> Vector2i:
	return Vector2i(
		int(floor(float(cell.x) / float(CHUNK_CELLS))),
		int(floor(float(cell.y) / float(CHUNK_CELLS)))
	)


static func chunk_origin(cx: int, cy: int) -> Vector2i:
	return Vector2i(cx * CHUNK_CELLS, cy * CHUNK_CELLS)


static func chunk_counts(width: int, height: int) -> Vector2i:
	return Vector2i(
		int(ceil(float(maxi(width, 1)) / float(CHUNK_CELLS))),
		int(ceil(float(maxi(height, 1)) / float(CHUNK_CELLS)))
	)


static func local_index(lx: int, ly: int, z: int, cw: int = CHUNK_CELLS, ch: int = CHUNK_CELLS) -> int:
	return (z * ch + ly) * cw + lx


static func empty_buf(cw: int = CHUNK_CELLS, ch: int = CHUNK_CELLS) -> PackedInt32Array:
	var buf := PackedInt32Array()
	buf.resize(cw * ch * LAYERS)
	buf.fill(0)
	return buf


static func is_empty_buf(buf: PackedInt32Array) -> bool:
	for v in buf:
		if int(v) != 0:
			return false
	return true


static func chunks_dir(map_dir: String) -> String:
	return "%s/chunks" % map_dir.rstrip("/").rstrip("\\")


static func chunk_path(map_dir: String, cx: int, cy: int) -> String:
	return "%s/c_%d_%d.bin" % [chunks_dir(map_dir), cx, cy]


static func overview_path(map_dir: String) -> String:
	return "%s/overview.png" % map_dir.rstrip("/").rstrip("\\")


static func pack_path(map_dir: String) -> String:
	return "%s/world.pack" % chunks_dir(map_dir)


static func idx_path(map_dir: String) -> String:
	return "%s/world.idx" % chunks_dir(map_dir)


static func _abs_dir(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	return path


static func invalidate_index(map_dir: String) -> void:
	var abs_d := _abs_dir(map_dir)
	_idx_cache.erase(abs_d)
	if _pack_read.has(abs_d):
		_pack_read.erase(abs_d)


static func _pack_reader(map_dir: String) -> FileAccess:
	var abs_d := _abs_dir(map_dir)
	if _pack_read.has(abs_d):
		var held: FileAccess = _pack_read[abs_d]
		if held != null:
			return held
	var f := _open(pack_path(map_dir), FileAccess.READ)
	if f != null:
		_pack_read[abs_d] = f
	return f


static func _open(path: String, mode: int) -> FileAccess:
	var f := FileAccess.open(path, mode)
	if f != null:
		return f
	var abs_path := _abs_dir(path)
	if abs_path != path:
		return FileAccess.open(abs_path, mode)
	return null


static func _encode_buf(buf: PackedInt32Array) -> PackedByteArray:
	var bytes := PackedByteArray()
	bytes.resize(PAYLOAD_BYTES)
	var n: int = mini(buf.size(), PAYLOAD_INTS)
	for i in range(n):
		bytes.encode_s32(i * 4, int(buf[i]))
	return bytes


static func _decode_buf(bytes: PackedByteArray) -> PackedInt32Array:
	var buf := PackedInt32Array()
	buf.resize(PAYLOAD_INTS)
	var n: int = mini(int(bytes.size() / 4), PAYLOAD_INTS)
	for i in range(n):
		buf[i] = bytes.decode_s32(i * 4)
	return buf


static func _load_index(map_dir: String) -> Dictionary:
	var abs_d := _abs_dir(map_dir)
	if _idx_cache.has(abs_d):
		return _idx_cache[abs_d]
	var idx := {}
	var f := _open(idx_path(map_dir), FileAccess.READ)
	if f != null:
		var mag := f.get_buffer(4).get_string_from_utf8()
		if mag == IDX_MAGIC:
			var ver := int(f.get_16())
			if ver >= 1:
				var count := int(f.get_32())
				for i in range(count):
					var cx := int(f.get_16())
					if cx >= 32768:
						cx -= 65536
					var cy := int(f.get_16())
					if cy >= 32768:
						cy -= 65536
					var off := int(f.get_32())
					if off != 0xFFFFFFFF:
						idx[key(cx, cy)] = off
	_idx_cache[abs_d] = idx
	return idx


static func _write_index(map_dir: String, idx: Dictionary) -> bool:
	_ensure_chunks_dir(map_dir)
	var f := _open(idx_path(map_dir), FileAccess.WRITE)
	if f == null:
		return false
	f.store_buffer(IDX_MAGIC.to_utf8_buffer())
	f.store_16(VERSION)
	f.store_32(idx.size())
	for k in idx.keys():
		var parts: PackedStringArray = str(k).split(",")
		if parts.size() < 2:
			continue
		f.store_16(int(parts[0]) & 0xFFFF)
		f.store_16(int(parts[1]) & 0xFFFF)
		f.store_32(int(idx[k]))
	_idx_cache[_abs_dir(map_dir)] = idx.duplicate()
	return true


static func _ensure_chunks_dir(map_dir: String) -> void:
	var abs_dir := _abs_dir(chunks_dir(map_dir))
	if not DirAccess.dir_exists_absolute(abs_dir):
		DirAccess.make_dir_recursive_absolute(abs_dir)


static func _pack_header_bytes() -> int:
	return 6 ## magic 4 + version u16


static func load_chunk(map_dir: String, cx: int, cy: int) -> PackedInt32Array:
	var idx: Dictionary = _load_index(map_dir)
	var k := key(cx, cy)
	if idx.has(k):
		var f := _pack_reader(map_dir)
		if f != null:
			f.seek(int(idx[k]))
			var bytes: PackedByteArray = f.get_buffer(PAYLOAD_BYTES)
			if bytes.size() >= PAYLOAD_BYTES:
				return _decode_buf(bytes)
	return _load_loose_chunk(map_dir, cx, cy)


static func _load_loose_chunk(map_dir: String, cx: int, cy: int) -> PackedInt32Array:
	var path := chunk_path(map_dir, cx, cy)
	var f := _open(path, FileAccess.READ)
	if f == null:
		return PackedInt32Array()
	var mag := f.get_buffer(4).get_string_from_utf8()
	if mag != MAGIC:
		return PackedInt32Array()
	var ver := int(f.get_16())
	if ver < 1:
		return PackedInt32Array()
	var cw := int(f.get_16())
	var ch := int(f.get_16())
	var layers := int(f.get_16())
	if cw <= 0 or ch <= 0 or layers <= 0:
		return PackedInt32Array()
	var need := mini(cw * ch * layers, PAYLOAD_INTS)
	var bytes: PackedByteArray = f.get_buffer(need * 4)
	return _decode_buf(bytes)


static func save_chunk(map_dir: String, cx: int, cy: int, buf: PackedInt32Array, _cw: int = CHUNK_CELLS, _ch: int = CHUNK_CELLS) -> bool:
	var batch := {}
	batch[key(cx, cy)] = buf
	return save_chunks_batch(map_dir, batch)


static func save_chunks_batch(map_dir: String, chunks: Dictionary) -> bool:
	if chunks.is_empty():
		return true
	invalidate_index(map_dir)
	_ensure_chunks_dir(map_dir)
	var idx: Dictionary = _load_index(map_dir).duplicate()
	var pp := pack_path(map_dir)
	var pf := _open(pp, FileAccess.READ_WRITE)
	if pf == null:
		pf = _open(pp, FileAccess.WRITE_READ)
	if pf == null:
		return false
	if pf.get_length() < _pack_header_bytes():
		pf.seek(0)
		pf.store_buffer(PACK_MAGIC.to_utf8_buffer())
		pf.store_16(VERSION)
	for k in chunks.keys():
		var buf: PackedInt32Array = chunks[k]
		var parts: PackedStringArray = str(k).split(",")
		if parts.size() < 2:
			continue
		var cx := int(parts[0])
		var cy := int(parts[1])
		if is_empty_buf(buf):
			idx.erase(str(k))
			var loose := chunk_path(map_dir, cx, cy)
			if FileAccess.file_exists(loose):
				DirAccess.remove_absolute(loose)
			continue
		var bytes: PackedByteArray = _encode_buf(buf)
		var off := int(idx.get(str(k), -1))
		if off >= _pack_header_bytes():
			pf.seek(off)
			pf.store_buffer(bytes)
		else:
			pf.seek(pf.get_length())
			off = int(pf.get_position())
			pf.store_buffer(bytes)
			idx[str(k)] = off
		var loose2 := chunk_path(map_dir, cx, cy)
		if FileAccess.file_exists(loose2):
			DirAccess.remove_absolute(loose2)
		var abs_loose := _abs_dir(loose2)
		if abs_loose != loose2 and FileAccess.file_exists(abs_loose):
			DirAccess.remove_absolute(abs_loose)
	if not _write_index(map_dir, idx):
		return false
	return true


static func save_uniform_grid(map_dir: String, width: int, height: int, buf: PackedInt32Array) -> bool:
	invalidate_index(map_dir)
	_ensure_chunks_dir(map_dir)
	var bytes: PackedByteArray = _encode_buf(buf)
	var pf := _open(pack_path(map_dir), FileAccess.WRITE)
	if pf == null:
		return false
	pf.store_buffer(PACK_MAGIC.to_utf8_buffer())
	pf.store_16(VERSION)
	var idx := {}
	var counts: Vector2i = chunk_counts(width, height)
	for cy in range(counts.y):
		for cx in range(counts.x):
			var off: int = int(pf.get_position())
			pf.store_buffer(bytes)
			idx[key(cx, cy)] = off
	return _write_index(map_dir, idx)


static func list_chunk_coords(map_dir: String) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var seen := {}
	var idx: Dictionary = _load_index(map_dir)
	for k in idx.keys():
		var parts: PackedStringArray = str(k).split(",")
		if parts.size() < 2:
			continue
		var c := Vector2i(int(parts[0]), int(parts[1]))
		seen[str(k)] = true
		out.append(c)
	var abs_dir := _abs_dir(chunks_dir(map_dir))
	if DirAccess.dir_exists_absolute(abs_dir):
		var da := DirAccess.open(abs_dir)
		if da != null:
			da.list_dir_begin()
			var name := da.get_next()
			while name != "":
				if not da.current_is_dir() and name.begins_with("c_") and name.ends_with(".bin"):
					var body := name.substr(2, name.length() - 6)
					var parts2 := body.split("_")
					if parts2.size() >= 2:
						var k2 := "%s,%s" % [parts2[0], parts2[1]]
						if not seen.has(k2):
							seen[k2] = true
							out.append(Vector2i(int(parts2[0]), int(parts2[1])))
				name = da.get_next()
			da.list_dir_end()
	return out


static func sample_cell_color(buf: PackedInt32Array, lx: int, ly: int, cw: int, ch: int, sheets: Array, flags: PackedInt32Array) -> Color:
	if buf.is_empty():
		return Color(0, 0, 0, 0)
	var last_tid := 0
	for z in [3, 2, 1, 0]:
		var idx := local_index(lx, ly, z, cw, ch)
		if idx < 0 or idx >= buf.size():
			continue
		var tid: int = int(buf[idx])
		if not TileId.is_visible(tid):
			continue
		last_tid = tid
		var sc: Color = TileBlit.sample_color(tid, sheets, flags)
		if sc.a >= 0.2:
			return sc
	if last_tid > 0:
		return Color.from_hsv(fmod(absf(float(last_tid)) * 0.00781, 1.0), 0.42, 0.52, 1.0)
	return Color(0, 0, 0, 0)


static func overview_metrics(width: int, height: int, max_side: int = OVERVIEW_MAX_SIDE) -> Dictionary:
	width = maxi(width, 1)
	height = maxi(height, 1)
	max_side = maxi(max_side, 16)
	var longest: int = maxi(width, height)
	var step: int = maxi(1, int(ceil(float(longest) / float(max_side))))
	return {
		"step": step,
		"w": maxi(1, int(ceil(float(width) / float(step)))),
		"h": maxi(1, int(ceil(float(height) / float(step)))),
	}


static func put_rgb(data: PackedByteArray, iw: int, px: int, py: int, col: Color) -> void:
	if px < 0 or py < 0 or px >= iw:
		return
	var o: int = (py * iw + px) * 4
	if o < 0 or o + 3 >= data.size():
		return
	data[o] = clampi(int(col.r * 255.0), 0, 255)
	data[o + 1] = clampi(int(col.g * 255.0), 0, 255)
	data[o + 2] = clampi(int(col.b * 255.0), 0, 255)
	data[o + 3] = 255


static func stamp_overview_bytes(
	data: PackedByteArray,
	iw: int,
	ih: int,
	step: int,
	cx: int,
	cy: int,
	buf: PackedInt32Array,
	sheets: Array,
	flags: PackedInt32Array,
	map_w: int,
	map_h: int
) -> void:
	if buf.is_empty() or data.is_empty():
		return
	step = maxi(step, 1)
	var origin: Vector2i = chunk_origin(cx, cy)
	var ly := 0
	while ly < CHUNK_CELLS:
		var gy: int = origin.y + ly
		if gy >= 0 and gy < map_h:
			var lx := 0
			while lx < CHUNK_CELLS:
				var gx: int = origin.x + lx
				if gx >= 0 and gx < map_w:
					var px: int = gx / step
					var py: int = gy / step
					if px >= 0 and py >= 0 and px < iw and py < ih:
						var col: Color = sample_cell_color(buf, lx, ly, CHUNK_CELLS, CHUNK_CELLS, sheets, flags)
						if col.a >= 0.2:
							put_rgb(data, iw, px, py, col)
				lx += step
		ly += step


## Offline world map: at most OVERVIEW_MAX_SIDE on the long edge.
static func bake_overview(
	width: int,
	height: int,
	chunk_bufs: Dictionary,
	sheets: Array,
	flags: PackedInt32Array,
	max_side: int = OVERVIEW_MAX_SIDE
) -> Image:
	return bake_overview_dir("", width, height, sheets, flags, chunk_bufs, max_side)


static func bake_overview_dir(
	map_dir: String,
	width: int,
	height: int,
	sheets: Array,
	flags: PackedInt32Array,
	extra: Dictionary = {},
	max_side: int = OVERVIEW_MAX_SIDE
) -> Image:
	var m: Dictionary = overview_metrics(width, height, max_side)
	var step: int = int(m.get("step", 1))
	var iw: int = int(m.get("w", 1))
	var ih: int = int(m.get("h", 1))
	var img := Image.create(iw, ih, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.04, 0.05, 0.05, 1))
	var data: PackedByteArray = img.get_data()
	var seen := {}
	for k in extra.keys():
		var buf: PackedInt32Array = extra[k]
		var parts: PackedStringArray = str(k).split(",")
		if parts.size() < 2:
			continue
		seen[str(k)] = true
		stamp_overview_bytes(data, iw, ih, step, int(parts[0]), int(parts[1]), buf, sheets, flags, width, height)
	if map_dir != "":
		var idx: Dictionary = _load_index(map_dir)
		var pf := _pack_reader(map_dir)
		for c in list_chunk_coords(map_dir):
			var k2 := key(c.x, c.y)
			if seen.has(k2):
				continue
			var buf2 := PackedInt32Array()
			if pf != null and idx.has(k2):
				pf.seek(int(idx[k2]))
				buf2 = _decode_buf(pf.get_buffer(PAYLOAD_BYTES))
			else:
				buf2 = _load_loose_chunk(map_dir, c.x, c.y)
			stamp_overview_bytes(data, iw, ih, step, c.x, c.y, buf2, sheets, flags, width, height)
	img.set_data(iw, ih, false, Image.FORMAT_RGBA8, data)
	return img
