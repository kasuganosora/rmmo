extends RefCounted
## Daylight × weather compose. Tint/energy multiply the map light_preset, they do not replace it.

const MapExt = preload("res://scripts/map/map_ext.gd")
const JsonUtil = preload("res://scripts/util/json_util.gd")

const PATH := "map/weather.json"
const KINDS := ["clear", "rain", "storm", "snow", "fog"]
## Viewport stack: world (0) < atmosphere (weather + day/night veil) < HUD.
const CANVAS_ATMOSPHERE := 5
const CANVAS_HUD := 20
const TRANSITION_SEC := 5.0

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


static func transition_sec() -> float:
	_ensure()
	var v: Variant = _cache.get("transition_sec", TRANSITION_SEC)
	return maxf(float(v), 0.4)


static func mix_weight(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func _as_color(v: Variant, fallback: Color = Color.WHITE) -> Color:
	if typeof(v) == TYPE_COLOR:
		return v
	if typeof(v) == TYPE_ARRAY and (v as Array).size() >= 3:
		var a: Array = v
		return Color(float(a[0]), float(a[1]), float(a[2]), 1.0)
	return fallback


static func particle_weight(atm: Dictionary, kind: String) -> float:
	var k := str(atm.get("kind", "")).strip_edges()
	var p := str(atm.get("particles", "")).strip_edges()
	var amt := maxf(float(atm.get("particle_amount", 0.0)), 0.0)
	match kind:
		"rain":
			return amt if p == "rain" and k != "storm" else 0.0
		"storm":
			return amt if k == "storm" else 0.0
		"snow":
			return amt if p == "snow" else 0.0
		"fog":
			return maxf(float(atm.get("fog", 0.0)), 0.0)
		_:
			return 0.0


static func blend(from_atm: Dictionary, to_atm: Dictionary, t: float) -> Dictionary:
	if from_atm.is_empty():
		return to_atm.duplicate(true)
	if to_atm.is_empty():
		return from_atm.duplicate(true)
	t = mix_weight(t)
	var ma := _as_color(from_atm.get("modulate", Color.WHITE))
	var mb := _as_color(to_atm.get("modulate", Color.WHITE))
	var fca := _as_color(from_atm.get("fog_color", ma), ma)
	var fcb := _as_color(to_atm.get("fog_color", mb), mb)
	var pick: Dictionary = to_atm if t >= 0.5 else from_atm
	var out: Dictionary = pick.duplicate(true)
	out["modulate"] = ma.lerp(mb, t)
	out["fog"] = lerpf(float(from_atm.get("fog", 0.0)), float(to_atm.get("fog", 0.0)), t)
	out["fog_color"] = fca.lerp(fcb, t)
	out["intensity"] = lerpf(float(from_atm.get("intensity", 0.0)), float(to_atm.get("intensity", 0.0)), t)
	out["rain_weight"] = lerpf(particle_weight(from_atm, "rain"), particle_weight(to_atm, "rain"), t)
	out["storm_weight"] = lerpf(particle_weight(from_atm, "storm"), particle_weight(to_atm, "storm"), t)
	out["snow_weight"] = lerpf(particle_weight(from_atm, "snow"), particle_weight(to_atm, "snow"), t)
	out["fog_weight"] = lerpf(particle_weight(from_atm, "fog"), particle_weight(to_atm, "fog"), t)
	out["sfx_from"] = str(from_atm.get("sfx", ""))
	out["sfx_to"] = str(to_atm.get("sfx", ""))
	out["sfx_t"] = t
	out["lightning"] = bool(to_atm.get("lightning", false)) and t > 0.4
	return out


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
	var parsed: Variant = JsonUtil.parse_data(PATH)
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
