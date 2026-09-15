extends RefCounted
## One map inside a content pack: MV 6-slot data + ext layers + events/npcs.

const MapExt = preload("res://scripts/map/map_ext.gd")
const EventCommands = preload("res://scripts/editor/event_commands.gd")
const MapChunkStore = preload("res://scripts/map/map_chunk_store.gd")

var map_id: String = "Map001"
var display_name: String = "地图"
var parent_id: String = ""
var tileset_id: String = "default"
var width: int = 20
var height: int = 15
var tile_size: int = 48
var data: PackedInt32Array = PackedInt32Array()
var ext_layers: Dictionary = {} ## id -> PackedInt32Array
var events: Array = []
var npcs: Array = []
var warps: Array = []
var start_cell: Vector2i = Vector2i(2, 2)
var far_scroll: Vector2 = Vector2.ZERO
var water_through: bool = false
var bgm: String = ""
var light_preset: int = 0
var light_fx_color: Color = Color(1, 1, 1, 1)
## outdoor | indoor — map-wide, for weather (distinct from per-cell META_INDOOR).
var environment: String = MapExt.ENV_OUTDOOR
var dirty: bool = false
var bookmarks: Array = []
var regions: Array = []

var _undo: Array = []
var _redo: Array = []
var _batching: bool = false
var _batch: Array = []
const UNDO_MAX := 80
const MAX_SIDE := 16384
const DENSE_MAX_CELLS := 65536
const CHUNK_CACHE_MAX := 192


static func clamp_side(n: int) -> int:
	return MapChunkStore.clamp_side(n)


var chunked: bool = false
var _chunk_cache: Dictionary = {}
var _dirty_chunks: Dictionary = {}
var _ext_sparse: Dictionary = {}
var _store_dir: String = ""


func uses_chunks() -> bool:
	return chunked


func cached_chunk_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not chunked:
		return out
	for k in _chunk_cache.keys():
		var parts: PackedStringArray = str(k).split(",")
		if parts.size() < 2:
			continue
		var origin: Vector2i = MapChunkStore.chunk_origin(int(parts[0]), int(parts[1]))
		for ly in range(MapChunkStore.CHUNK_CELLS):
			for lx in range(MapChunkStore.CHUNK_CELLS):
				var c := Vector2i(origin.x + lx, origin.y + ly)
				if c.x >= 0 and c.y >= 0 and c.x < width and c.y < height:
					out.append(c)
	return out


func setup_blank(p_id: String, p_name: String, w: int, h: int, ts: int = 48) -> void:
	map_id = p_id
	display_name = p_name
	width = clamp_side(w)
	height = clamp_side(h)
	tile_size = ts
	chunked = MapChunkStore.should_chunk(width, height)
	_chunk_cache.clear()
	_dirty_chunks.clear()
	_ext_sparse.clear()
	_store_dir = ""
	data = PackedInt32Array()
	ext_layers.clear()
	if not chunked:
		data.resize(width * height * 6)
		data.fill(0)
		for id in MapExt.LAYER_IDS:
			var buf := PackedInt32Array()
			buf.resize(width * height)
			buf.fill(0)
			ext_layers[id] = buf
	events = []
	npcs = []
	warps = []
	start_cell = Vector2i(mini(2, width - 1), mini(2, height - 1))
	dirty = true
	_undo.clear()
	_redo.clear()


func resize(new_w: int, new_h: int) -> bool:
	new_w = clamp_side(new_w)
	new_h = clamp_side(new_h)
	if new_w == width and new_h == height:
		return false
	var old_w := width
	var old_h := height
	var copy_w := mini(old_w, new_w)
	var copy_h := mini(old_h, new_h)
	var become_chunked := MapChunkStore.should_chunk(new_w, new_h)
	if chunked or become_chunked:
		var saved: Array = []
		for y in range(copy_h):
			for x in range(copy_w):
				var stack: Array = []
				for z in range(6):
					stack.append(tile(x, y, z))
				var ext_hit := {}
				for id in MapExt.LAYER_IDS:
					var ev: int = ext_tile(id, x, y)
					if ev != 0:
						ext_hit[id] = ev
				var any := false
				for v in stack:
					if int(v) != 0:
						any = true
						break
				if any or not ext_hit.is_empty():
					saved.append({"x": x, "y": y, "z": stack, "ext": ext_hit})
		width = new_w
		height = new_h
		chunked = become_chunked
		_chunk_cache.clear()
		_dirty_chunks.clear()
		_ext_sparse.clear()
		data = PackedInt32Array()
		ext_layers.clear()
		if not chunked:
			data.resize(width * height * 6)
			data.fill(0)
			for id2 in MapExt.LAYER_IDS:
				var buf := PackedInt32Array()
				buf.resize(width * height)
				buf.fill(0)
				ext_layers[id2] = buf
		for item in saved:
			var ix: int = int(item["x"])
			var iy: int = int(item["y"])
			var stack2: Array = item["z"]
			for z2 in range(mini(6, stack2.size())):
				set_tile(ix, iy, z2, int(stack2[z2]), false)
			var eh: Dictionary = item["ext"]
			for id3 in eh.keys():
				set_ext_tile(str(id3), ix, iy, int(eh[id3]), false)
		dirty = true
		_undo.clear()
		_redo.clear()
		return true
	var old_data := data.duplicate()
	var old_ext: Dictionary = {}
	for id in ext_layers.keys():
		old_ext[id] = (ext_layers[id] as PackedInt32Array).duplicate()
	width = new_w
	height = new_h
	data = PackedInt32Array()
	data.resize(width * height * 6)
	data.fill(0)
	for z in range(6):
		for y in range(copy_h):
			for x in range(copy_w):
				var src: int = (z * old_h + y) * old_w + x
				var dst: int = (z * height + y) * width + x
				if src >= 0 and src < old_data.size():
					data[dst] = old_data[src]
	ext_layers.clear()
	for id in MapExt.LAYER_IDS:
		var buf2 := PackedInt32Array()
		buf2.resize(width * height)
		buf2.fill(0)
		var src_buf: PackedInt32Array = old_ext.get(id, PackedInt32Array())
		for y2 in range(copy_h):
			for x2 in range(copy_w):
				var s2: int = y2 * old_w + x2
				if s2 >= 0 and s2 < src_buf.size():
					buf2[y2 * width + x2] = src_buf[s2]
		ext_layers[id] = buf2
	dirty = true
	_undo.clear()
	_redo.clear()
	return true


func load_dir(dir: String) -> bool:
	dir = dir.rstrip("/").rstrip("\\")
	var map_data: Dictionary = _read_json("%s/map.json" % dir)
	if map_data.is_empty():
		return false
	width = int(map_data.get("width", 0))
	height = int(map_data.get("height", 0))
	if width <= 0 or height <= 0:
		return false
	display_name = str(map_data.get("displayName", map_data.get("name", map_id)))
	_store_dir = dir
	_chunk_cache.clear()
	_dirty_chunks.clear()
	_ext_sparse.clear()
	var chunks_on_disk := DirAccess.dir_exists_absolute("%s/chunks" % dir) or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path("%s/chunks" % dir))
	chunked = str(map_data.get("dataEncoding", "")) == "chunks" or chunks_on_disk
	if not chunked and MapChunkStore.should_chunk(width, height):
		chunked = not FileAccess.file_exists("%s/map.data.bin" % dir)
	var ext = MapExt.load_file("%s/map.ext.json" % dir, width, height)
	ext_layers.clear()
	if chunked:
		data = PackedInt32Array()
		_ingest_ext_sparse_from_json("%s/map.ext.json" % dir)
	else:
		for id in MapExt.LAYER_IDS:
			var buf := PackedInt32Array()
			buf.resize(width * height)
			buf.fill(0)
			if ext != null and ext.has_method("tile"):
				for y in range(height):
					for x in range(width):
						buf[y * width + x] = int(ext.tile(id, x, y))
			ext_layers[id] = buf
	if ext != null:
		far_scroll = ext.far_scroll if "far_scroll" in ext else Vector2.ZERO
		water_through = bool(ext.water_through) if "water_through" in ext else false
		if "light_color" in ext:
			light_fx_color = ext.light_color
	var sx := int(map_data.get("startX", 2))
	var sy := int(map_data.get("startY", 2))
	start_cell = Vector2i(clampi(sx, 0, width - 1), clampi(sy, 0, height - 1))
	if chunked:
		data = PackedInt32Array()
	else:
		var bin_path := "%s/map.data.bin" % dir
		if FileAccess.file_exists(bin_path):
			_load_data_bin(bin_path)
		else:
			data = _to_i32(map_data.get("data", []))
			var need := width * height * 6
			if data.size() < need:
				data.resize(need)
	var evd: Dictionary = _read_json("%s/events.json" % dir)
	events = evd.get("events", []) if typeof(evd.get("events")) == TYPE_ARRAY else []
	var npd: Dictionary = _read_json("%s/npcs.json" % dir)
	npcs = npd.get("npcs", []) if typeof(npd.get("npcs")) == TYPE_ARRAY else []
	var wrd: Dictionary = _read_json("%s/warps.json" % dir)
	warps = wrd.get("warps", []) if typeof(wrd.get("warps")) == TYPE_ARRAY else []
	bgm = str(map_data.get("bgm", "")).strip_edges()
	light_preset = int(map_data.get("light_preset", 0))
	if map_data.has("environment"):
		environment = MapExt.normalize_environment(map_data.get("environment"))
	elif map_data.has("indoor"):
		environment = MapExt.normalize_environment(map_data.get("indoor"))
	else:
		environment = MapExt.ENV_OUTDOOR
	bookmarks = map_data.get("bookmarks", []) if typeof(map_data.get("bookmarks")) == TYPE_ARRAY else []
	regions = map_data.get("regions", []) if typeof(map_data.get("regions")) == TYPE_ARRAY else []
	dirty = false
	_undo.clear()
	_redo.clear()
	return true


func save_dir(dir: String) -> bool:
	dir = dir.rstrip("/").rstrip("\\")
	if not _ensure_dir(dir):
		return false
	_store_dir = dir
	var map_obj := {
		"id": 1,
		"name": map_id,
		"displayName": display_name,
		"width": width,
		"height": height,
		"tilesetId": 1,
		"scrollType": 0,
		"startX": start_cell.x,
		"startY": start_cell.y,
		"dataEncoding": "chunks" if chunked else "bin32",
		"chunkCells": MapChunkStore.CHUNK_CELLS if chunked else 0,
		"events": [null],
		"note": "",
		"bgm": bgm,
		"light_preset": light_preset,
		"environment": environment,
		"bookmarks": bookmarks,
		"regions": regions,
	}
	if not _write_json("%s/map.json" % dir, map_obj):
		return false
	if chunked:
		if not _flush_chunks(dir):
			return false
	elif not _save_data_bin("%s/map.data.bin" % dir):
		return false
	var layers: Array = []
	for id in MapExt.LAYER_IDS:
		var cells: Array = _ext_cells_for_save(id)
		var layer_obj := {"id": id, "encoding": "sparse", "cells": cells}
		if id == "far":
			layer_obj["scroll"] = [far_scroll.x, far_scroll.y]
		if id == "water":
			layer_obj["through"] = water_through
		if id == "light":
			layer_obj["color"] = MapExt.color_to_array(light_fx_color)
		var keep_empty: bool = id == "far" or id == "water" or (id == "light" and not light_fx_color.is_equal_approx(Color(1, 1, 1, 1)))
		if cells.is_empty() and not keep_empty:
			continue
		layers.append(layer_obj)
	var ext_obj := {
		"format": MapExt.FORMAT,
		"version": 1,
		"width": width,
		"height": height,
		"layers": layers,
	}
	_write_json("%s/map.ext.json" % dir, ext_obj)
	_write_json("%s/events.json" % dir, {"events": events})
	_write_json("%s/npcs.json" % dir, {"npcs": npcs})
	_write_json("%s/warps.json" % dir, {"warps": warps})
	dirty = false
	return true


func add_event(cell: Vector2i, text: String = "……") -> Dictionary:
	var eid := "ev_%d_%d" % [cell.x, cell.y]
	var ev := {
		"id": eid,
		"cell": {"x": cell.x, "y": cell.y},
		"trigger": "action",
		"through": true,
		"pages": [{
			"when": {},
			"commands": [{"op": "text", "text": text}],
		}],
	}
	events.append(ev)
	dirty = true
	return ev


func add_npc(cell: Vector2i, charset: String, display: String = "NPC") -> Dictionary:
	var nid := "npc_%d_%d" % [cell.x, cell.y]
	var n := {
		"id": nid,
		"name": display,
		"cell": {"x": cell.x, "y": cell.y},
		"charset": charset,
		"index": 0,
		"direction": 2,
		"through": false,
		"wander": false,
		"wander_radius": 0,
		"hostile": false,
		"aggressive": false,
		"kind": "normal",
		"level": 1,
		"interact_text": "",
	}
	npcs.append(n)
	dirty = true
	return n


func add_warp(from_cell: Vector2i, to_map: String, to_cell: Vector2i, facing: int = 2) -> Dictionary:
	var w := {
		"from_cell": {"x": from_cell.x, "y": from_cell.y},
		"to_map": to_map,
		"to_map_id": to_map,
		"to_pack": "",
		"to_cell": {"x": to_cell.x, "y": to_cell.y},
		"facing": facing,
		"message": "",
	}
	warps.append(w)
	dirty = true
	return w


func remove_entity_at(cell: Vector2i) -> bool:
	var hit := entity_at(cell)
	if hit.is_empty():
		return false
	match str(hit.get("kind", "")):
		"event":
			_strip_cell(events, "cell", cell)
		"npc":
			_strip_cell(npcs, "cell", cell)
		"warp":
			_strip_cell(warps, "from_cell", cell)
		_:
			return false
	dirty = true
	return true


func _strip_cell(arr: Array, key: String, cell: Vector2i) -> void:
	var next: Array = []
	for item in arr:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var c: Variant = item.get(key, {})
		if typeof(c) == TYPE_DICTIONARY and int(c.get("x", -1)) == cell.x and int(c.get("y", -1)) == cell.y:
			continue
		next.append(item)
	arr.clear()
	for n in next:
		arr.append(n)


func copy_entity_at(cell: Vector2i) -> Dictionary:
	var hit := entity_at(cell)
	if hit.is_empty():
		return {}
	var data_v: Variant = hit.get("data", {})
	if typeof(data_v) != TYPE_DICTIONARY:
		return {}
	return {"kind": str(hit.get("kind", "")), "data": (data_v as Dictionary).duplicate(true)}


func paste_entity_at(clip: Dictionary, cell: Vector2i) -> bool:
	if clip.is_empty():
		return false
	var kind := str(clip.get("kind", "")).strip_edges()
	var data_v: Variant = clip.get("data", {})
	if typeof(data_v) != TYPE_DICTIONARY:
		return false
	var data: Dictionary = EventCommands.retarget_entity(kind, data_v as Dictionary, cell)
	if data.is_empty():
		return false
	remove_entity_at(cell)
	match kind:
		"event":
			events.append(data)
		"npc":
			npcs.append(data)
		"warp":
			warps.append(data)
		_:
			return false
	dirty = true
	return true


func entity_at(cell: Vector2i) -> Dictionary:
	for ev in events:
		if typeof(ev) == TYPE_DICTIONARY:
			var c: Variant = ev.get("cell", {})
			if typeof(c) == TYPE_DICTIONARY and int(c.get("x", -1)) == cell.x and int(c.get("y", -1)) == cell.y:
				return {"kind": "event", "data": ev}
	for n in npcs:
		if typeof(n) == TYPE_DICTIONARY:
			var c2: Variant = n.get("cell", {})
			if typeof(c2) == TYPE_DICTIONARY and int(c2.get("x", -1)) == cell.x and int(c2.get("y", -1)) == cell.y:
				return {"kind": "npc", "data": n}
	for w in warps:
		if typeof(w) == TYPE_DICTIONARY:
			var c3: Variant = w.get("from_cell", {})
			if typeof(c3) == TYPE_DICTIONARY and int(c3.get("x", -1)) == cell.x and int(c3.get("y", -1)) == cell.y:
				return {"kind": "warp", "data": w}
	return {}


func tile(x: int, y: int, z: int) -> int:
	if x < 0 or y < 0 or x >= width or y >= height or z < 0 or z > 5:
		return 0
	if chunked:
		var buf: PackedInt32Array = _touch_chunk(MapChunkStore.cell_to_chunk(Vector2i(x, y)), false)
		if buf.is_empty():
			return 0
		var origin: Vector2i = MapChunkStore.chunk_origin(int(floor(float(x) / float(MapChunkStore.CHUNK_CELLS))), int(floor(float(y) / float(MapChunkStore.CHUNK_CELLS))))
		var idx: int = MapChunkStore.local_index(x - origin.x, y - origin.y, z)
		if idx < 0 or idx >= buf.size():
			return 0
		return int(buf[idx])
	var idx2: int = (z * height + y) * width + x
	if idx2 < 0 or idx2 >= data.size():
		return 0
	return int(data[idx2])


func set_tile(x: int, y: int, z: int, id: int, record_undo: bool = true) -> void:
	if x < 0 or y < 0 or x >= width or y >= height or z < 0 or z > 5:
		return
	if chunked:
		var ch: Vector2i = MapChunkStore.cell_to_chunk(Vector2i(x, y))
		var buf: PackedInt32Array = _touch_chunk(ch, true)
		var origin: Vector2i = MapChunkStore.chunk_origin(ch.x, ch.y)
		var idx: int = MapChunkStore.local_index(x - origin.x, y - origin.y, z)
		if idx < 0 or idx >= buf.size():
			return
		var old := int(buf[idx])
		if old == id:
			return
		if record_undo:
			_push_undo({"t": "tile", "x": x, "y": y, "z": z, "old": old, "new": id})
		buf[idx] = id
		_chunk_cache[MapChunkStore.key(ch.x, ch.y)] = buf
		_dirty_chunks[MapChunkStore.key(ch.x, ch.y)] = ch
		dirty = true
		return
	var idx2: int = (z * height + y) * width + x
	if idx2 < 0 or idx2 >= data.size():
		return
	var old2 := int(data[idx2])
	if old2 == id:
		return
	if record_undo:
		_push_undo({"t": "tile", "x": x, "y": y, "z": z, "old": old2, "new": id})
	data[idx2] = id
	dirty = true


func ext_tile(layer_id: String, x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= width or y >= height:
		return 0
	if chunked:
		var spar: Dictionary = _ext_sparse.get(layer_id, {})
		return int(spar.get(y * width + x, 0))
	if not ext_layers.has(layer_id):
		return 0
	var buf: PackedInt32Array = ext_layers[layer_id]
	var idx := y * width + x
	if idx < 0 or idx >= buf.size():
		return 0
	return int(buf[idx])


func set_ext_tile(layer_id: String, x: int, y: int, id: int, record_undo: bool = true) -> void:
	if x < 0 or y < 0 or x >= width or y >= height:
		return
	if chunked:
		if not _ext_sparse.has(layer_id):
			_ext_sparse[layer_id] = {}
		var spar: Dictionary = _ext_sparse[layer_id]
		var k: int = y * width + x
		var old := int(spar.get(k, 0))
		if old == id:
			return
		if record_undo:
			_push_undo({"t": "ext", "id": layer_id, "x": x, "y": y, "old": old, "new": id})
		if id == 0:
			spar.erase(k)
		else:
			spar[k] = id
		_ext_sparse[layer_id] = spar
		dirty = true
		return
	if not ext_layers.has(layer_id):
		return
	var buf: PackedInt32Array = ext_layers[layer_id]
	var idx := y * width + x
	if idx < 0 or idx >= buf.size():
		return
	var old2 := int(buf[idx])
	if old2 == id:
		return
	if record_undo:
		_push_undo({"t": "ext", "id": layer_id, "x": x, "y": y, "old": old2, "new": id})
	buf[idx] = id
	ext_layers[layer_id] = buf
	dirty = true


func begin_undo_batch() -> void:
	_batching = true
	_batch = []


func end_undo_batch() -> void:
	_batching = false
	if _batch.is_empty():
		_batch = []
		return
	_undo.append({"t": "batch", "ops": _batch})
	if _undo.size() > UNDO_MAX:
		_undo.pop_front()
	_redo.clear()
	_batch = []


func undo() -> bool:
	if _undo.is_empty():
		return false
	undo_cells()
	return true


func undo_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if _undo.is_empty():
		return out
	var cmd: Dictionary = _undo.pop_back()
	out = _cmd_cells(cmd)
	_apply_cmd(cmd, true)
	_redo.append(cmd)
	dirty = true
	return out


func redo() -> bool:
	if _redo.is_empty():
		return false
	redo_cells()
	return true


func redo_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if _redo.is_empty():
		return out
	var cmd: Dictionary = _redo.pop_back()
	out = _cmd_cells(cmd)
	_apply_cmd(cmd, false)
	_undo.append(cmd)
	dirty = true
	return out


func _cmd_cells(cmd: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	match str(cmd.get("t", "")):
		"batch":
			for op in cmd.get("ops", []):
				if typeof(op) == TYPE_DICTIONARY:
					out.append_array(_cmd_cells(op))
		"tile", "ext":
			out.append(Vector2i(int(cmd.get("x", 0)), int(cmd.get("y", 0))))
	return out


func clone(new_id: String, new_name: String) -> RefCounted:
	var d = get_script().new()
	d.map_id = new_id
	d.display_name = new_name
	d.width = width
	d.height = height
	d.tile_size = tile_size
	d.tileset_id = tileset_id
	d.parent_id = parent_id
	d.start_cell = start_cell
	d.chunked = chunked
	d._store_dir = _store_dir
	d._chunk_cache = _chunk_cache.duplicate(true)
	d._dirty_chunks = _dirty_chunks.duplicate(true)
	d._ext_sparse = _ext_sparse.duplicate(true)
	d.data = data.duplicate()
	d.ext_layers = {}
	for k in ext_layers.keys():
		d.ext_layers[k] = (ext_layers[k] as PackedInt32Array).duplicate()
	d.events = events.duplicate(true)
	d.npcs = npcs.duplicate(true)
	d.warps = warps.duplicate(true)
	d.far_scroll = far_scroll
	d.water_through = water_through
	d.bgm = bgm
	d.light_preset = light_preset
	d.light_fx_color = light_fx_color
	d.environment = environment
	d.dirty = true
	return d


func _apply_cmd(cmd: Dictionary, reverse: bool) -> void:
	match str(cmd.get("t", "")):
		"batch":
			var ops: Array = cmd.get("ops", [])
			if reverse:
				var i := ops.size() - 1
				while i >= 0:
					_apply_cmd(ops[i], true)
					i -= 1
			else:
				for op in ops:
					_apply_cmd(op, false)
		"tile":
			var v: int = int(cmd.get("old" if reverse else "new", 0))
			set_tile(int(cmd["x"]), int(cmd["y"]), int(cmd["z"]), v, false)
		"ext":
			var v2: int = int(cmd.get("old" if reverse else "new", 0))
			set_ext_tile(str(cmd["id"]), int(cmd["x"]), int(cmd["y"]), v2, false)


func _push_undo(cmd: Dictionary) -> void:
	if _batching:
		_batch.append(cmd)
		_redo.clear()
		return
	_undo.append(cmd)
	if _undo.size() > UNDO_MAX:
		_undo.pop_front()
	_redo.clear()


func chunk_buffer(cx: int, cy: int) -> PackedInt32Array:
	return _touch_chunk(Vector2i(cx, cy), false)


func bake_world_map(sheets: Array, flags: PackedInt32Array, dest_dir: String = "") -> bool:
	var dir := dest_dir.strip_edges()
	if dir == "":
		dir = _store_dir
	if dir == "":
		return false
	var img: Image
	if chunked:
		img = MapChunkStore.bake_overview_dir(dir, width, height, sheets, flags, _chunk_cache)
	else:
		img = _bake_dense_overview(sheets, flags)
	if img == null or img.get_width() <= 0:
		return false
	return img.save_png(MapChunkStore.overview_path(dir)) == OK


func _touch_chunk(ch: Vector2i, create: bool) -> PackedInt32Array:
	var k := MapChunkStore.key(ch.x, ch.y)
	if _chunk_cache.has(k):
		return _chunk_cache[k]
	var buf := PackedInt32Array()
	if _store_dir != "":
		buf = MapChunkStore.load_chunk(_store_dir, ch.x, ch.y)
	if buf.is_empty() and create:
		buf = MapChunkStore.empty_buf()
	if not buf.is_empty() or create:
		_chunk_cache[k] = buf
		_evict_chunks()
	return buf


func _evict_chunks() -> void:
	if _chunk_cache.size() <= CHUNK_CACHE_MAX:
		return
	var keys: Array = _chunk_cache.keys()
	var drop_n: int = _chunk_cache.size() - CHUNK_CACHE_MAX
	for i in range(mini(drop_n, keys.size())):
		var k: String = str(keys[i])
		if _dirty_chunks.has(k):
			continue
		_chunk_cache.erase(k)


func _flush_chunks(dir: String) -> bool:
	_store_dir = dir
	var batch := {}
	for k in _dirty_chunks.keys():
		var ch: Vector2i = _dirty_chunks[k]
		batch[MapChunkStore.key(ch.x, ch.y)] = _chunk_cache.get(MapChunkStore.key(ch.x, ch.y), PackedInt32Array())
	if not MapChunkStore.save_chunks_batch(dir, batch):
		return false
	_dirty_chunks.clear()
	return true


func _all_chunk_bufs() -> Dictionary:
	var out: Dictionary = {}
	for k in _chunk_cache.keys():
		out[k] = _chunk_cache[k]
	if _store_dir == "":
		return out
	for c in MapChunkStore.list_chunk_coords(_store_dir):
		var k2 := MapChunkStore.key(c.x, c.y)
		if out.has(k2):
			continue
		out[k2] = MapChunkStore.load_chunk(_store_dir, c.x, c.y)
	return out


func _ext_cells_for_save(layer_id: String) -> Array:
	var cells: Array = []
	if chunked:
		var spar: Dictionary = _ext_sparse.get(layer_id, {})
		for idx in spar.keys():
			var v: int = int(spar[idx])
			if v == 0:
				continue
			var i: int = int(idx)
			var x: int = i % width
			var y: int = int(i / width)
			cells.append([x, y, v])
		return cells
	var buf: PackedInt32Array = ext_layers.get(layer_id, PackedInt32Array())
	for y in range(height):
		for x in range(width):
			var idx2 := y * width + x
			if idx2 >= buf.size():
				continue
			var v2 := int(buf[idx2])
			if v2 != 0:
				cells.append([x, y, v2])
	return cells


func _ingest_ext_sparse_from_json(path: String) -> void:
	_ext_sparse.clear()
	var raw: Dictionary = _read_json(path)
	var layers_v: Variant = raw.get("layers", [])
	if typeof(layers_v) != TYPE_ARRAY:
		return
	for item in layers_v:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var layer: Dictionary = item
		var id := str(layer.get("id", ""))
		if id == "":
			continue
		var spar: Dictionary = {}
		var cells_v: Variant = layer.get("cells", [])
		if typeof(cells_v) == TYPE_ARRAY:
			for cell in cells_v:
				if typeof(cell) != TYPE_ARRAY or (cell as Array).size() < 3:
					continue
				var cx := int(cell[0])
				var cy := int(cell[1])
				if cx < 0 or cy < 0 or cx >= width or cy >= height:
					continue
				var tid := int(cell[2])
				if tid == 0:
					continue
				spar[cy * width + cx] = tid
		_ext_sparse[id] = spar


func _bake_dense_overview(sheets: Array, flags: PackedInt32Array) -> Image:
	var longest: int = maxi(width, height)
	var step: int = maxi(1, int(ceil(float(longest) / float(MapChunkStore.OVERVIEW_MAX_SIDE))))
	var iw: int = maxi(1, int(ceil(float(width) / float(step))))
	var ih: int = maxi(1, int(ceil(float(height) / float(step))))
	var img := Image.create(iw, ih, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 1))
	var TileBlit = load("res://scripts/map/tile_blit.gd")
	var tmp := Image.create(48, 48, false, Image.FORMAT_RGBA8)
	var cache: Dictionary = {}
	for py in range(ih):
		for px in range(iw):
			var gx: int = mini(px * step, width - 1)
			var gy: int = mini(py * step, height - 1)
			var key := "%d:%d:%d:%d" % [tile(gx, gy, 0), tile(gx, gy, 1), tile(gx, gy, 2), tile(gx, gy, 3)]
			if cache.has(key):
				img.set_pixel(px, py, cache[key])
				continue
			tmp.fill(Color(0, 0, 0, 0))
			for z in [0, 1, 2, 3]:
				var tid: int = tile(gx, gy, z)
				if tid > 0:
					TileBlit.blit_tile(tmp, tid, 0, 0, sheets, 48, 48, flags, 0)
			var acc: Color = TileBlit._average_opaque(tmp, 8, 8, 40, 40)
			if acc.a < 0.15:
				acc = Color(0, 0, 0, 1)
			cache[key] = acc
			img.set_pixel(px, py, acc)
	return img


func _save_data_bin(path: String) -> bool:
	var need: int = width * height * 6
	if data.size() < need:
		data.resize(need)
	var any := false
	for v in data:
		if int(v) != 0:
			any = true
			break
	if not any:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
		return true
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_32(data.size())
	for v2 in data:
		f.store_32(int(v2))
	return true


func _load_data_bin(path: String) -> void:
	var need: int = width * height * 6
	data = PackedInt32Array()
	data.resize(need)
	data.fill(0)
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var n := int(f.get_32())
	var count := mini(n, need)
	for i in range(count):
		if f.eof_reached():
			break
		data[i] = f.get_32()


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		var abs_path := ProjectSettings.globalize_path(path)
		if not FileAccess.file_exists(abs_path):
			return {}
		path = abs_path
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


func _write_json(path: String, obj: Dictionary) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(obj, "\t"))
	return true


func _to_i32(v: Variant) -> PackedInt32Array:
	var out := PackedInt32Array()
	if typeof(v) != TYPE_ARRAY:
		return out
	var arr: Array = v
	out.resize(arr.size())
	for i in range(arr.size()):
		out[i] = int(arr[i])
	return out


func _from_i32(buf: PackedInt32Array) -> Array:
	var out: Array = []
	out.resize(buf.size())
	for i in range(buf.size()):
		out[i] = int(buf[i])
	return out


func _ensure_dir(path: String) -> bool:
	var abs_path := ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else path
	if DirAccess.dir_exists_absolute(abs_path):
		return true
	return DirAccess.make_dir_recursive_absolute(abs_path) == OK
