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
var dirty: bool = false

var _undo: Array = []
var _redo: Array = []
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
	dirty = true
	_undo.clear()
	_redo.clear()


func load_dir(dir: String) -> bool:
	dir = dir.rstrip("/").rstrip("\\")
	var map_data: Dictionary = _read_json("%s/map.json" % dir)
	if map_data.is_empty():
		return false
	width = int(map_data.get("width", 0))
	height = int(map_data.get("height", 0))
	if width <= 0 or height <= 0:
		return false
	data = _to_i32(map_data.get("data", []))
	var need := width * height * 6
	if data.size() < need:
		data.resize(need)
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
	var evd: Dictionary = _read_json("%s/events.json" % dir)
	events = evd.get("events", []) if typeof(evd.get("events")) == TYPE_ARRAY else []
	var npd: Dictionary = _read_json("%s/npcs.json" % dir)
	npcs = npd.get("npcs", []) if typeof(npd.get("npcs")) == TYPE_ARRAY else []
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
		"data": _from_i32(data),
		"events": [null],
		"note": "",
	}
	if not _write_json("%s/map.json" % dir, map_obj):
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
	dirty = false
	return true


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


func undo() -> bool:
	if _undo.is_empty():
		return false
	var cmd: Dictionary = _undo.pop_back()
	_apply_cmd(cmd, true)
	_redo.append(cmd)
	dirty = true
	return true


func redo() -> bool:
	if _redo.is_empty():
		return false
	var cmd: Dictionary = _redo.pop_back()
	_apply_cmd(cmd, false)
	_undo.append(cmd)
	dirty = true
	return true


func _apply_cmd(cmd: Dictionary, reverse: bool) -> void:
	var v: int = int(cmd.get("old" if reverse else "new", 0))
	match str(cmd.get("t", "")):
		"tile":
			set_tile(int(cmd["x"]), int(cmd["y"]), int(cmd["z"]), v, false)
		"ext":
			set_ext_tile(str(cmd["id"]), int(cmd["x"]), int(cmd["y"]), v, false)


func _push_undo(cmd: Dictionary) -> void:
	_undo.append(cmd)
	if _undo.size() > UNDO_MAX:
		_undo.pop_front()
	_redo.clear()


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
