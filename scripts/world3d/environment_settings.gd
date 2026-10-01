extends RefCounted
const Schema = preload("res://scripts/world3d/document_schema.gd")
const PRESETS = {
	"day": {"sun_rotation": [-48, 32, 0], "sun_color": [1, .97, .9], "sun_energy": 1.15, "ambient_color": [.72, .76, .82], "ambient_energy": .42, "background_color": [.55, .68, .78]},
	"sunset": {"sun_rotation": [-12, -65, 0], "sun_color": [1, .55, .3], "sun_energy": .8, "ambient_color": [.5, .4, .5], "ambient_energy": .3, "background_color": [.52, .29, .28]},
	"night": {"sun_rotation": [-40, 32, 0], "sun_color": [.45, .55, .82], "sun_energy": .04, "ambient_color": [.25, .32, .5], "ambient_energy": .03, "background_color": [.02, .03, .07]},
}

static func schema() -> Dictionary:
	var fields := {"preset": {"type": "string", "enum": PRESETS.keys()}, "sun_rotation": Schema.vector(-360, 360), "sun_energy": Schema.number(0, 8), "ambient_energy": Schema.number(0, 4), "fog_enabled": {"type": "boolean"}, "fog_density": Schema.number(0, .2), "outline_enabled": {"type": "boolean"}, "outline_width": Schema.number(1, 6)}
	for key in ["sun_color", "ambient_color", "background_color", "fog_color", "outline_color"]: fields[key] = Schema.vector(0, 1)
	return {"type": "object", "properties": fields, "additionalProperties": false}

static func defaults() -> Dictionary:
	var result := {"preset": "day", "fog_enabled": false, "fog_density": .01, "fog_color": [.65, .72, .8], "outline_enabled": true, "outline_color": [1, .78, .25], "outline_width": 2.0}
	result.merge(PRESETS.day.duplicate(true))
	return result

static func resolve(meta: Dictionary) -> Dictionary:
	var value := defaults()
	var saved: Variant = meta.get("environment", {})
	if saved is Dictionary and Schema.validate(saved, schema()).is_empty():
		if saved.has("preset"): value.merge(PRESETS[saved.preset], true)
		value.merge(saved, true)
	return value

static func valid(meta: Dictionary) -> bool:
	return not meta.has("environment") or Schema.validate(meta.environment, schema()).is_empty()

static func updated(meta: Dictionary, changes: Dictionary) -> Dictionary:
	var value := resolve(meta)
	if changes.has("preset"): value.merge(PRESETS[changes.preset].duplicate(true), true)
	value.merge(changes, true)
	return value

static func color(values: Array) -> Color:
	return Color(values[0], values[1], values[2])

static func apply(values: Dictionary, sun: DirectionalLight3D, environment: Environment) -> void:
	if sun != null:
		sun.rotation_degrees = Vector3(values.sun_rotation[0], values.sun_rotation[1], values.sun_rotation[2])
		sun.light_color = color(values.sun_color); sun.light_energy = values.sun_energy
	if environment != null:
		environment.background_mode = Environment.BG_COLOR
		environment.background_color = color(values.background_color)
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_color = color(values.ambient_color); environment.ambient_light_energy = values.ambient_energy
		environment.fog_enabled = values.fog_enabled; environment.fog_density = values.fog_density; environment.fog_light_color = color(values.fog_color)
