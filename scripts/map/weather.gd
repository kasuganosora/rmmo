extends RefCounted
## Daylight × weather compose. Tint/energy multiply the map light_preset, they do not replace it.

const MapExt = preload("res://scripts/map/map_ext.gd")

const PATH := "res://data/map/weather.json"
const KINDS := ["clear", "rain", "storm", "snow", "fog"]
## Viewport stack: world (0) < atmosphere (weather + day/night veil) < HUD.
const CANVAS_ATMOSPHERE := 5
const CANVAS_HUD := 20

static var _cache: Dictionary = {}


static func normalize(kind: String) -> String:
	match kind.strip_edges().to_lower():
		"rain", "raining", "雨":
			return "rain"
		"storm", "thunder", "雷", "雷暴":
			return "storm"
		"snow", "snowing", "雪":
			return "snow"
		"fog", "mist", "雾":
			return "fog"
		_:
			return "clear"


static func label_of(kind: String) -> String:
	var d: Dictionary = kind_def(kind)
	return str(d.get("name", kind))


static func kind_def(kind: String) -> Dictionary:
	_ensure()
	var key := normalize(kind)
	var kinds: Dictionary = _cache.get("kinds", {})
	var raw: Variant = kinds.get(key, {})
	return raw if typeof(raw) == TYPE_DICTIONARY else {}


static func cycle_list() -> Array:
	_ensure()
	var v: Variant = _cache.get("cycle", KINDS)
	return v if typeof(v) == TYPE_ARRAY else KINDS.duplicate()


static func duration_range() -> Vector2:
	_ensure()
	var v: Variant = _cache.get("duration_sec", [45, 80])
	if typeof(v) == TYPE_ARRAY and (v as Array).size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	return Vector2(45, 80)


static func compose(light_id: int, kind: String, intensity: float, map_indoor: bool) -> Dictionary:
	var vis_kind := "clear" if map_indoor else normalize(kind)
	var vis_i := 0.0 if map_indoor else clampf(intensity, 0.0, 1.0)
	var def: Dictionary = kind_def(vis_kind)
	var light: Color = MapExt.light_modulate(light_id)
	var tint: Color = _tint_of(def)
	var energy := float(def.get("energy", 1.0))
	var mul := Color(
		lerpf(1.0, tint.r * energy, vis_i),
		lerpf(1.0, tint.g * energy, vis_i),
		lerpf(1.0, tint.b * energy, vis_i),
		1.0
	)
	var modulate := Color(light.r * mul.r, light.g * mul.g, light.b * mul.b, 1.0)
	var fog_a := float(def.get("fog", 0.0)) * vis_i
	var amount := float(def.get("particle_amount", 1.0)) * vis_i
	return {
		"kind": vis_kind,
		"logical_kind": normalize(kind),
		"intensity": vis_i,
		"map_indoor": map_indoor,
		"modulate": modulate,
		"particles": str(def.get("particles", "")),
		"particle_amount": amount,
		"fog": fog_a,
		"fog_color": modulate,
		"lightning": bool(def.get("lightning", false)) and vis_i > 0.25 and not map_indoor,
		"sfx": str(def.get("sfx", "")),
		"label": str(def.get("name", vis_kind)),
	}


static func _tint_of(def: Dictionary) -> Color:
	var c: Variant = def.get("tint", [1, 1, 1])
	if typeof(c) == TYPE_ARRAY and (c as Array).size() >= 3:
		return Color(float(c[0]), float(c[1]), float(c[2]), 1.0)
	return Color(1, 1, 1, 1)


static func _ensure() -> void:
	if not _cache.is_empty():
		return
	if FileAccess.file_exists(PATH):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if typeof(parsed) == TYPE_DICTIONARY:
			_cache = parsed
			return
	_cache = {
		"kinds": {
			"clear": {"name": "晴", "tint": [1, 1, 1], "energy": 1.0},
		},
		"cycle": ["clear"],
		"duration_sec": [45, 80],
	}
