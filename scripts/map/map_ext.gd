extends RefCounted
## Extra map layers beside RPG Maker MV MapXXX.json (z0–z5).
## File: MapXXX.ext.json / map.ext.json. Missing file = empty (legacy pack).

const FORMAT := "map_ext_v1"
const EXT_Z_BASE := 6

## Visual / logic ids in paint order (not including MV 0–3).
const LAYER_IDS := [
	"far", "water", "ground_fx", "props_low", "props_high",
	"roof", "sky", "light", "meta", "settings",
]

const META_INDOOR := 0x01
const META_WATER := 0x02
const META_FORCE_BLOCK := 0x04
const META_FORCE_PASS := 0x08
const META_NO_DASH := 0x10

var width: int = 0
var height: int = 0
var valid: bool = false
## id -> PackedInt32Array (width*height), 0 = empty
var _layers: Dictionary = {}
## id -> true if any non-zero
var _has_tiles: Dictionary = {}
var far_scroll: Vector2 = Vector2.ZERO
var water_through: bool = false


static func ext_path_for(map_path: String) -> String:
	if map_path.ends_with(".json"):
		return map_path.substr(0, map_path.length() - 5) + ".ext.json"
	return map_path + ".ext.json"


static func load_file(path: String, expect_w: int, expect_h: int) -> RefCounted:
	var ext := new()
	ext.width = expect_w
	ext.height = expect_h
	if path.strip_edges() == "" or expect_w <= 0 or expect_h <= 0:
		return ext
	if not FileAccess.file_exists(path):
		var abs_path := ProjectSettings.globalize_path(path)
		if abs_path == path or not FileAccess.file_exists(abs_path):
			return ext
		path = abs_path
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ext
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("map_ext: invalid JSON %s" % path)
		return ext
	ext._ingest(parsed as Dictionary, expect_w, expect_h)
	return ext


func _ingest(d: Dictionary, expect_w: int, expect_h: int) -> void:
	var fmt := str(d.get("format", "")).strip_edges()
	if fmt != "" and fmt != FORMAT:
		push_warning("map_ext: unknown format '%s'" % fmt)
	var w := int(d.get("width", expect_w))
	var h := int(d.get("height", expect_h))
	if w != expect_w or h != expect_h:
		push_warning("map_ext: size %dx%d != map %dx%d — ignored" % [w, h, expect_w, expect_h])
		return
	width = w
	height = h
	_layers.clear()
	_has_tiles.clear()
	far_scroll = Vector2.ZERO
	water_through = false
	var layers_v: Variant = d.get("layers", [])
	if typeof(layers_v) != TYPE_ARRAY:
		valid = true
		return
	for item in layers_v:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		_ingest_layer(item as Dictionary)
	valid = true


func _ingest_layer(layer: Dictionary) -> void:
	var id := str(layer.get("id", "")).strip_edges()
	if id.is_empty() or LAYER_IDS.find(id) < 0:
		if id != "":
			push_warning("map_ext: skip unknown layer id '%s'" % id)
		return
	if id == "far":
		var sc: Variant = layer.get("scroll", [0, 0])
		if typeof(sc) == TYPE_ARRAY and (sc as Array).size() >= 2:
			far_scroll = Vector2(float(sc[0]), float(sc[1]))
		elif typeof(sc) == TYPE_DICTIONARY:
			far_scroll = Vector2(float(sc.get("x", 0)), float(sc.get("y", 0)))
	if id == "water":
		water_through = bool(layer.get("through", false))
	var n := width * height
	var buf := PackedInt32Array()
	buf.resize(n)
	var encoding := str(layer.get("encoding", "sparse")).strip_edges().to_lower()
	var filled := 0
	if encoding == "dense":
		var data_v: Variant = layer.get("data", [])
		if typeof(data_v) == TYPE_ARRAY:
			var arr: Array = data_v
			var lim := mini(arr.size(), n)
			for i in range(lim):
				var v := int(arr[i])
				buf[i] = v
				if v != 0:
					filled += 1
	else:
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
				buf[cy * width + cx] = tid
				if tid != 0:
					filled += 1
	_layers[id] = buf
	_has_tiles[id] = filled > 0


func has_tiles(id: String) -> bool:
	return bool(_has_tiles.get(id, false))


func tile(id: String, x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= width or y >= height:
		return 0
	if not _layers.has(id):
		return 0
	var buf: PackedInt32Array = _layers[id]
	var idx := y * width + x
	if idx < 0 or idx >= buf.size():
		return 0
	return int(buf[idx])


func tile_z(z: int, x: int, y: int) -> int:
	var i := z - EXT_Z_BASE
	if i < 0 or i >= LAYER_IDS.size():
		return 0
	return tile(LAYER_IDS[i], x, y)


func meta_at(x: int, y: int) -> int:
	return tile("meta", x, y)


func settings_at(x: int, y: int) -> int:
	return tile("settings", x, y)


static func pack_settings(light_preset: int, sound_preset: int, footstep: int = 0) -> int:
	return (light_preset & 0xff) | ((sound_preset & 0xff) << 8) | ((footstep & 0xff) << 16)


static func settings_light(v: int) -> int:
	return v & 0xff


static func settings_sound(v: int) -> int:
	return (v >> 8) & 0xff


static func settings_footstep(v: int) -> int:
	return (v >> 16) & 0xff


func layer_index(id: String) -> int:
	return LAYER_IDS.find(id)
