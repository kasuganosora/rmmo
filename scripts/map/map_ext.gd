extends RefCounted
## Extra map layers beside RPG Maker MV MapXXX.json (z0–z5).
## File: MapXXX.ext.json / map.ext.json. Missing file = empty (legacy pack).

const JsonUtil = preload("res://scripts/util/json_util.gd")

const FORMAT := "map_ext_v1"
const EXT_Z_BASE := 6

## Visual / logic ids in paint order (not including MV 0–3).
const LAYER_IDS := [
	"far", "water", "ground_fx", "props_low", "props_high",
	"roof", "sky", "light", "meta", "settings",
]

const LAYER_LABELS := {
	"far": "远景",
	"water": "水面",
	"ground_fx": "地面特效",
	"props_low": "低物",
	"props_high": "高物",
	"roof": "屋顶",
	"sky": "天空",
	"light": "光效",
	"meta": "格子标记",
	"settings": "氛围",
}

const VISUAL_EXT := ["far", "water", "ground_fx", "props_low", "props_high", "roof", "sky", "light"]
const SPEC_EXT := ["meta", "settings"]


static func layer_label(id: String) -> String:
	if LAYER_LABELS.has(id):
		return str(LAYER_LABELS[id])
	return id

const META_INDOOR := 0x01
const META_WATER := 0x02
const META_FORCE_BLOCK := 0x04
const META_FORCE_PASS := 0x08
const META_NO_DASH := 0x10

const ENV_OUTDOOR := "outdoor"
const ENV_INDOOR := "indoor"


static func normalize_environment(v: Variant) -> String:
	if typeof(v) == TYPE_BOOL:
		return ENV_INDOOR if bool(v) else ENV_OUTDOOR
	var s := str(v).strip_edges().to_lower()
	match s:
		"indoor", "inside", "interior", "室内", "1", "true":
			return ENV_INDOOR
		_:
			return ENV_OUTDOOR


static func environment_label(env: String) -> String:
	return "室内" if normalize_environment(env) == ENV_INDOOR else "室外"

var width: int = 0
var height: int = 0
var valid: bool = false
## id -> PackedInt32Array (width*height), 0 = empty. Unused when _sparse.
var _layers: Dictionary = {}
## Large maps: id -> Dictionary(idx -> value). Never allocates width*height.
var _sparse: Dictionary = {}
## id -> true if any non-zero
var _has_tiles: Dictionary = {}
var far_scroll: Vector2 = Vector2.ZERO
var light_color: Color = Color(1, 1, 1, 1)
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
	_sparse.clear()
	_has_tiles.clear()
	far_scroll = Vector2.ZERO
	light_color = Color(1, 1, 1, 1)
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
	if id == "light":
		light_color = parse_color(layer.get("color", [1, 1, 1, 1]), Color(1, 1, 1, 1))
	var n := width * height
	var use_sparse := n > 65536
	var encoding := str(layer.get("encoding", "sparse")).strip_edges().to_lower()
	var filled := 0
	if use_sparse:
		var spar: Dictionary = {}
		if encoding == "dense":
			var data_v: Variant = layer.get("data", [])
			if typeof(data_v) == TYPE_ARRAY:
				var arr: Array = data_v
				var lim := mini(arr.size(), n)
				for i in range(lim):
					var v := int(arr[i])
					if v != 0:
						spar[i] = v
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
					if tid == 0:
						continue
					spar[cy * width + cx] = tid
					filled += 1
		_sparse[id] = spar
		_has_tiles[id] = filled > 0
		return
	var buf := PackedInt32Array()
	buf.resize(n)
	if encoding == "dense":
		var data_v2: Variant = layer.get("data", [])
		if typeof(data_v2) == TYPE_ARRAY:
			var arr2: Array = data_v2
			var lim2 := mini(arr2.size(), n)
			for i2 in range(lim2):
				var v2 := int(arr2[i2])
				buf[i2] = v2
				if v2 != 0:
					filled += 1
	else:
		var cells_v2: Variant = layer.get("cells", [])
		if typeof(cells_v2) == TYPE_ARRAY:
			for cell2 in cells_v2:
				if typeof(cell2) != TYPE_ARRAY or (cell2 as Array).size() < 3:
					continue
				var cx2 := int(cell2[0])
				var cy2 := int(cell2[1])
				if cx2 < 0 or cy2 < 0 or cx2 >= width or cy2 >= height:
					continue
				var tid2 := int(cell2[2])
				buf[cy2 * width + cx2] = tid2
				if tid2 != 0:
					filled += 1
	_layers[id] = buf
	_has_tiles[id] = filled > 0


func has_tiles(id: String) -> bool:
	return bool(_has_tiles.get(id, false))


func tile(id: String, x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= width or y >= height:
		return 0
	var idx := y * width + x
	if _sparse.has(id):
		return int((_sparse[id] as Dictionary).get(idx, 0))
	if not _layers.has(id):
		return 0
	var buf: PackedInt32Array = _layers[id]
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


static func parse_color(v: Variant, fallback: Color = Color(1, 1, 1, 1)) -> Color:
	if typeof(v) == TYPE_ARRAY and (v as Array).size() >= 3:
		var a: Array = v
		var alpha := float(a[3]) if a.size() >= 4 else 1.0
		return Color(float(a[0]), float(a[1]), float(a[2]), alpha)
	if typeof(v) == TYPE_DICTIONARY:
		var d: Dictionary = v
		return Color(
			float(d.get("r", d.get("x", 1.0))),
			float(d.get("g", d.get("y", 1.0))),
			float(d.get("b", d.get("z", 1.0))),
			float(d.get("a", 1.0))
		)
	if typeof(v) == TYPE_COLOR:
		return v
	if typeof(v) == TYPE_STRING:
		return Color.html(str(v))
	return fallback


static func color_to_array(c: Color) -> Array:
	return [snappedf(c.r, 0.001), snappedf(c.g, 0.001), snappedf(c.b, 0.001), snappedf(c.a, 0.001)]


static func pack_settings(light_preset: int, sound_preset: int, footstep: int = 0) -> int:
	return (light_preset & 0xff) | ((sound_preset & 0xff) << 8) | ((footstep & 0xff) << 16)


static func settings_light(v: int) -> int:
	return v & 0xff


static func settings_sound(v: int) -> int:
	return (v >> 8) & 0xff


static func settings_footstep(v: int) -> int:
	return (v >> 16) & 0xff


static var _light_preset_cache: Dictionary = {}


static func light_modulate(preset_id: int) -> Color:
	_ensure_light_presets()
	var p: Variant = _light_preset_cache.get(str(preset_id), {})
	if typeof(p) != TYPE_DICTIONARY or (p as Dictionary).is_empty():
		return Color(1, 1, 1, 1)
	var d: Dictionary = p
	var c: Variant = d.get("color", [1, 1, 1])
	var col := Color(1, 1, 1, 1)
	if typeof(c) == TYPE_ARRAY and (c as Array).size() >= 3:
		col = Color(float(c[0]), float(c[1]), float(c[2]), 1.0)
	var energy := float(d.get("energy", 1.0))
	return Color(col.r * energy, col.g * energy, col.b * energy, 1.0)


static func light_preset_names() -> Dictionary:
	_ensure_light_presets()
	var out := {}
	for k in _light_preset_cache.keys():
		var def: Variant = _light_preset_cache[k]
		var label := str(k)
		if typeof(def) == TYPE_DICTIONARY:
			var n := str(def.get("name", ""))
			if n != "":
				label = n
		out[int(str(k))] = label
	return out


static func _ensure_light_presets() -> void:
	if not _light_preset_cache.is_empty():
		return
	var raw: Variant = JsonUtil.parse_data("map/light_presets.json")
	if typeof(raw) == TYPE_DICTIONARY:
		var presets: Variant = (raw as Dictionary).get("presets", raw)
		if typeof(presets) == TYPE_DICTIONARY:
			_light_preset_cache = presets
			return
	_light_preset_cache = {
		"0": {"name": "日间", "color": [1, 1, 1], "energy": 1.0},
		"1": {"name": "黄昏", "color": [1.0, 0.82, 0.62], "energy": 0.88},
		"2": {"name": "夜晚", "color": [0.55, 0.62, 0.95], "energy": 0.7},
	}


func layer_index(id: String) -> int:
	return LAYER_IDS.find(id)
