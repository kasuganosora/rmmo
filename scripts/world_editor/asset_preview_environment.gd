extends RefCounted
## Private asset previews need directional radiance even with a flat background.
## This is not a world/weather preset: callers keep their background, ambient,
## exposure and lights. Review tools use this same entry point for parity.
const RECIPE_VERSION := 1

static func apply_reflections(environment: Environment) -> void:
	if environment == null:
		return
	var material := ProceduralSkyMaterial.new()
	# Neutral luminance contrast reveals dielectric edges without tinting goods.
	material.sky_top_color = Color(.58, .58, .58)
	material.sky_horizon_color = Color(.82, .82, .82)
	material.sky_curve = .25
	material.ground_horizon_color = Color(.55, .55, .55)
	material.ground_bottom_color = Color(.18, .18, .18)
	material.ground_curve = .25
	material.sky_energy_multiplier = 1.
	material.ground_energy_multiplier = 1.
	material.sun_angle_max = 5.
	material.sun_curve = .05
	material.use_debanding = false
	var sky := Sky.new()
	sky.sky_material = material
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	# Fixed preview lighting; generate the small radiance map in one update.
	sky.process_mode = Sky.PROCESS_MODE_QUALITY
	sky.set_meta("asset_preview_environment_version", RECIPE_VERSION)
	environment.sky = sky
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
