extends RefCounted
const Schema = preload("res://scripts/world3d/document_schema.gd")
const PRESETS = {
	"day": {"sun_rotation": [-48, 32, 0], "sun_color": [1, .97, .9], "sun_energy": 1.15, "ambient_color": [.72, .76, .82], "ambient_energy": .42, "background_color": [.55, .68, .78]},
	"sunset": {"sun_rotation": [-12, -65, 0], "sun_color": [1, .55, .3], "sun_energy": .8, "ambient_color": [.5, .4, .5], "ambient_energy": .3, "background_color": [.52, .29, .28]},
	"night": {"sun_rotation": [-40, 32, 0], "sun_color": [.68, .74, .88], "sun_energy": .16, "ambient_color": [.25, .32, .5], "ambient_energy": .03, "background_color": [.02, .03, .07]},
}

static func schema() -> Dictionary:
	var fields := {"preset": {"type": "string", "enum": PRESETS.keys()}, "sun_rotation": Schema.vector(-360, 360), "sun_energy": Schema.number(0, 8), "ambient_energy": Schema.number(0, 4), "sun_shadows": {"type": "boolean"}, "ambient_occlusion": {"type": "boolean"}, "fog_enabled": {"type": "boolean"}, "fog_density": Schema.number(0, .2), "outline_enabled": {"type": "boolean"}, "outline_width": Schema.number(1, 6), "interior_cutaway": {"type":"boolean"}, "indoor_camera_distance": Schema.number(2,5)}
	for key in ["sun_color", "ambient_color", "background_color", "fog_color", "outline_color"]: fields[key] = Schema.vector(0, 1)
	fields.merge({"weather": {"type":"string", "enum":preload("res://scripts/world3d/weather_profile.gd").KINDS}, "weather_intensity":Schema.number(0,1), "wind_speed":Schema.number(0,18), "wind_direction":Schema.number(-180,180), "weather_transition":Schema.number(0,20), "lightning_enabled":{"type":"boolean"}, "sky_enabled":{"type":"boolean"}})
	fields.merge({"star_intensity":Schema.number(0,2),"meteors_enabled":{"type":"boolean"},"meteor_frequency":Schema.number(0,12)})
	fields.merge({"time_hours":Schema.number(0,24),"time_speed":Schema.number(0,3600)})
	fields.merge({"celestial_cycle":{"type":"boolean"},"surface_wetness":{"type":"boolean"},"initial_wetness":Schema.number(0,1),"wetting_seconds":Schema.number(10,3600),"drying_seconds":Schema.number(30,7200),"puddle_strength":Schema.number(0,1),"environment_audio":{"type":"boolean"},"thunder_enabled":{"type":"boolean"},"lightning_center":Schema.vector(-100000,100000),"lightning_radius":Schema.number(50,2000)})
	fields.merge({"cloud_altitude":Schema.number(200,3000),"cloud_thickness":Schema.number(100,1800),"cloud_scale":Schema.number(400,8000),"cirrus_amount":Schema.number(0,1)})
	return {"type": "object", "properties": fields, "additionalProperties": false}

static func defaults() -> Dictionary:
	var result := {"preset": "day", "sun_shadows": true, "ambient_occlusion": true, "fog_enabled": false, "fog_density": .01, "fog_color": [.65, .72, .8], "outline_enabled": true, "outline_color": [1, .78, .25], "outline_width": 2.0, "interior_cutaway": false, "indoor_camera_distance": 3.2}
	result.merge(PRESETS.day.duplicate(true))
	result.merge({"weather":"clear", "weather_intensity":.7, "wind_speed":2.5, "wind_direction":25.0, "weather_transition":3.0, "lightning_enabled":true, "sky_enabled":true})
	result.merge({"star_intensity":1.0,"meteors_enabled":true,"meteor_frequency":3.0})
	result.merge({"time_hours":12.0,"time_speed":0.0})
	result.merge({"celestial_cycle":false,"surface_wetness":true,"initial_wetness":0.0,"wetting_seconds":90.0,"drying_seconds":300.0,"puddle_strength":.7,"environment_audio":true,"thunder_enabled":true,"lightning_center":[0.,0.,0.],"lightning_radius":800.0})
	result.merge({"cloud_altitude":1500.0,"cloud_thickness":450.0,"cloud_scale":1800.0,"cirrus_amount":.22})
	return result

static func resolve(meta: Dictionary) -> Dictionary:
	var value := defaults()
	var saved: Variant = meta.get("environment", {})
	if saved is Dictionary and Schema.validate(saved, schema()).is_empty():
		if saved.has("preset"):
			value.merge(PRESETS[saved.preset], true)
			value.time_hours = {"day":12.0,"sunset":18.0,"night":0.0}[saved.preset]
		value.merge(saved, true)
	return value

static func valid(meta: Dictionary) -> bool:
	return not meta.has("environment") or Schema.validate(meta.environment, schema()).is_empty()

static func updated(meta: Dictionary, changes: Dictionary) -> Dictionary:
	var value := resolve(meta)
	if changes.has("preset"):
		value.merge(PRESETS[changes.preset].duplicate(true), true)
		value.time_hours = {"day":12.0,"sunset":18.0,"night":0.0}[changes.preset]
	elif changes.has("time_hours"):
		value.preset = time_preset(float(changes.time_hours))
		value.merge(PRESETS[value.preset].duplicate(true),true)
	value.merge(changes, true)
	if changes.has("time_hours"): value.preset = time_preset(float(changes.time_hours))
	return value

static func time_preset(hours: float) -> String:
	hours = fposmod(hours,24.0)
	return "day" if hours >= 6 and hours < 17 else "sunset" if hours >= 17 and hours < 20 else "night"

static func color(values: Array) -> Color:
	return Color(values[0], values[1], values[2])

static func apply(values: Dictionary, sun: DirectionalLight3D, environment: Environment) -> void:
	if sun != null:
		sun.rotation_degrees = Vector3(values.sun_rotation[0], values.sun_rotation[1], values.sun_rotation[2])
		sun.light_color = color(values.sun_color); sun.light_energy = values.sun_energy
		sun.shadow_enabled = bool(values.get("sun_shadows", true))
		# Cascades retain near-wall precision without pushing eave shadows far
		# down the facade. A tiny normal bias alone causes stippled self-shadowing.
		sun.directional_shadow_mode=DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		sun.shadow_bias = .1; sun.shadow_normal_bias = .65
		sun.directional_shadow_max_distance = 120.0
	if environment != null:
		environment.background_mode = Environment.BG_COLOR
		environment.background_color = color(values.background_color)
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_color = color(values.ambient_color); environment.ambient_light_energy = values.ambient_energy
		environment.ssao_enabled = bool(values.get("ambient_occlusion", true))
		environment.ssao_radius = 1.2; environment.ssao_intensity = 1.4
		environment.fog_enabled = values.fog_enabled; environment.fog_density = values.fog_density; environment.fog_light_color = color(values.fog_color)
