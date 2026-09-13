extends RefCounted
## One map inside a content pack: MV 6-slot data + ext layers + events/npcs.

const MapExt = preload("res://scripts/map/map_ext.gd")

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
var dirty: bool = false

var _undo: Array = []
var _redo: Array = []
var _batching: bool = false
var _batch: Array = []
const UNDO_MAX := 80


func setup_blank(p_id: String, p_name: String, w: int, h: int, ts: int = 48) -> void:
	map_id = p_id
	display_name = p_name
	width = maxi(w, 1)
	height = maxi(h, 1)
	tile_size = ts
	data.resize(width * height * 6)
	data.fill(0)
	ext_layers.clear()
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
	new_w = maxi(new_w, 1)
	new_h = maxi(new_h, 1)
	if new_w == width and new_h == height:
		return false
	var old_w := width
	var old_h := height
	var old_data := data.duplicate()
	var old_ext: Dictionary = {}
	for id in ext_layers.keys():
		old_ext[id] = (ext_layers[id] as PackedInt32Array).duplicate()
	width = new_w
	height = new_h
	data = PackedInt32Array()
	data.resize(width * height * 6)
	data.fill(0)
	var copy_w := mini(old_w, width)
	var copy_h := mini(old_h, height)
	for z in range(6):
		for y in range(copy_h):
			for x in range(copy_w):
				var src: int = (z * old_h + y) * old_w + x
				var dst: int = (z * height + y) * width + x
				if src >= 0 and src < old_data.size():
					data[dst] = old_data[src]
	ext_layers.clear()
	for id in MapExt.LAYER_IDS:
		var buf := PackedInt32Array()
		buf.resize(width * height)
		buf.fill(0)
		var src_buf: PackedInt32Array = old_ext.get(id, PackedInt32Array())
		for y2 in range(copy_h):
			for x2 in range(copy_w):
				var s2: int = y2 * old_w + x2
				if s2 >= 0 and s2 < src_buf.size():
					buf[y2 * width + x2] = src_buf[s2]
		ext_layers[id] = buf
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
	var ext = MapExt.load_file("%s/map.ext.json" % dir, width, height)
	ext_layers.clear()
	for id in MapExt.LAYER_IDS:
		var buf := PackedInt32Array()
		buf.resize(width * height)
		buf.fill(0)
		if ext != null and ext.has_method("tile"):
			for y in range(height):
				for x in range(width):
					buf[y * width + x] = int(ext.tile(id, x, y))
		ext_layers[id] = buf
	var sx := int(map_data.get("startX", 2))
	var sy := int(map_data.get("startY", 2))
	start_cell = Vector2i(clampi(sx, 0, width - 1), clampi(sy, 0, height - 1))
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
	dirty = false
	_undo.clear()
	_redo.clear()
	return true


func save_dir(dir: String) -> bool:
	dir = dir.rstrip("/").rstrip("\\")
	if not _ensure_dir(dir):
		return false
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
		"dataEncoding": "bin32",
		"events": [null],
		"note": "",
	}
	if not _write_json("%s/map.json" % dir, map_obj):
		return false
	if not _save_data_bin("%s/map.data.bin" % dir):
		return false
	var layers: Array = []
	for id in MapExt.LAYER_IDS:
		var buf: PackedInt32Array = ext_layers.get(id, PackedInt32Array())
		var cells: Array = []
		for y in range(height):
			for x in range(width):
				var idx := y * width + x
				if idx >= buf.size():
					continue
				var v := int(buf[idx])
				if v != 0:
					cells.append([x, y, v])
		if cells.is_empty():
			continue
		layers.append({"id": id, "encoding": "sparse", "cells": cells})
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
	var idx: int = (z * height + y) * width + x
	if idx < 0 or idx >= data.size():
		return 0
	return int(data[idx])


func set_tile(x: int, y: int, z: int, id: int, record_undo: bool = true) -> void:
	if x < 0 or y < 0 or x >= width or y >= height or z < 0 or z > 5:
		return
	var idx: int = (z * height + y) * width + x
	if idx < 0 or idx >= data.size():
		return
	var old := int(data[idx])
	if old == id:
		return
	if record_undo:
		_push_undo({"t": "tile", "x": x, "y": y, "z": z, "old": old, "new": id})
	data[idx] = id
	dirty = true


func ext_tile(layer_id: String, x: int, y: int) -> int:
	if not ext_layers.has(layer_id):
		return 0
	if x < 0 or y < 0 or x >= width or y >= height:
		return 0
	var buf: PackedInt32Array = ext_layers[layer_id]
	var idx := y * width + x
	if idx < 0 or idx >= buf.size():
		return 0
	return int(buf[idx])


func set_ext_tile(layer_id: String, x: int, y: int, id: int, record_undo: bool = true) -> void:
	if not ext_layers.has(layer_id):
		return
	if x < 0 or y < 0 or x >= width or y >= height:
		return
	var buf: PackedInt32Array = ext_layers[layer_id]
	var idx := y * width + x
	if idx < 0 or idx >= buf.size():
		return
	var old := int(buf[idx])
	if old == id:
		return
	if record_undo:
		_push_undo({"t": "ext", "id": layer_id, "x": x, "y": y, "old": old, "new": id})
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
	d.data = data.duplicate()
	d.ext_layers = {}
	for k in ext_layers.keys():
		d.ext_layers[k] = (ext_layers[k] as PackedInt32Array).duplicate()
	d.events = events.duplicate(true)
	d.npcs = npcs.duplicate(true)
	d.warps = warps.duplicate(true)
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
