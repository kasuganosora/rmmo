extends SceneTree
const Helper = preload("res://scripts/world_editor/asset_preview_environment.gd")
const Preview = preload("res://scripts/world_editor/asset_preview.gd")
const Thumbnails = preload("res://scripts/world_editor/asset_thumbnails.gd")
const OUT = "D:/code/rmmo/review_artifacts/axel_market_realism_20261016/pottery_scroll/preview_environment_cpu.json"
var checks: Array = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks.append({"ok": ok, "label": message})
	if not ok: push_error(message)

func recipe(environment: Environment, label: String) -> void:
	check(environment.sky != null, label + " has radiance sky")
	check(environment.reflected_light_source == Environment.REFLECTION_SOURCE_SKY, label + " reflection source independent of background")
	if environment.sky == null: return
	check(environment.sky.radiance_size == Sky.RADIANCE_SIZE_64, label + " bounded 64 radiance")
	check(environment.sky.process_mode == Sky.PROCESS_MODE_QUALITY, label + " complete static update")
	check(environment.sky.get_meta("asset_preview_environment_version", 0) == Helper.RECIPE_VERSION, label + " shared recipe identity")
	var material := environment.sky.sky_material as ProceduralSkyMaterial
	check(material != null, label + " procedural sky")
	if material == null: return
	check(material.sky_top_color == Color(.58, .58, .58) and material.sky_horizon_color == Color(.82, .82, .82), label + " neutral upper hemisphere")
	check(material.ground_bottom_color == Color(.18, .18, .18) and material.ground_horizon_color == Color(.55, .55, .55), label + " neutral lower hemisphere contrast")
	check(not material.use_debanding, label + " deterministic reflection recipe")

func run() -> void:
	check(DisplayServer.get_name() == "headless", "CPU only execution")
	var map_environment := Environment.new()
	map_environment.background_color = Color(.12, .27, .39)
	map_environment.ambient_light_energy = .19
	map_environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	var map_world := WorldEnvironment.new()
	map_world.environment = map_environment
	root.add_child(map_world)
	var map_snapshot := var_to_str([map_environment.background_color, map_environment.ambient_light_energy, map_environment.reflected_light_source, map_environment.sky])
	var custom := Environment.new()
	custom.background_mode = Environment.BG_COLOR
	custom.background_color = Color(.31, .17, .23)
	custom.background_energy_multiplier = .72
	custom.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	custom.ambient_light_energy = .43
	custom.ambient_light_color = Color(.8, .9, .7)
	custom.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	custom.tonemap_exposure = 1.17
	custom.fog_enabled = true
	var preserved := {}
	for property: Dictionary in custom.get_property_list():
		var property_name := str(property.name)
		if property.usage & PROPERTY_USAGE_STORAGE and property_name not in ["sky", "reflected_light_source"]:
			preserved[property_name] = custom.get(property_name)
	Helper.apply_reflections(custom)
	recipe(custom, "direct review API")
	check(preserved.keys().all(func(key): return custom.get(key) == preserved[key]), "helper preserves every other stored Environment property")
	Helper.apply_reflections(null)
	var preview := Preview.new()
	var thumbnails := Thumbnails.new()
	root.add_child(preview)
	root.add_child(thumbnails)
	await process_frame
	recipe(preview.camera.environment, "preview UI")
	recipe(thumbnails._camera.environment, "thumbnail UI/MCP import queue")
	check(preview.camera.environment.background_mode == Environment.BG_COLOR and preview.camera.environment.background_color == Color("252c35"), "preview background unchanged")
	check(preview.camera.environment.ambient_light_source == Environment.AMBIENT_SOURCE_COLOR and is_equal_approx(preview.camera.environment.ambient_light_energy, .7), "preview ambient unchanged")
	check(thumbnails._camera.environment.background_mode == Environment.BG_COLOR and thumbnails._camera.environment.background_color == Color("303139"), "thumbnail background unchanged")
	check(thumbnails._camera.environment.ambient_light_source == Environment.AMBIENT_SOURCE_COLOR and is_equal_approx(thumbnails._camera.environment.ambient_light_energy, .65), "thumbnail ambient unchanged")
	check(preview.viewport_.own_world_3d and thumbnails._viewport.own_world_3d, "both UI viewports use private worlds")
	check(preview.camera.get_world_3d() != thumbnails._camera.get_world_3d() and preview.camera.get_world_3d() != root.find_world_3d(), "preview worlds isolated from map and each other")
	check(preview.camera.environment != thumbnails._camera.environment and preview.camera.environment.sky != thumbnails._camera.environment.sky, "per viewport resources independent")
	for viewport: SubViewport in [preview.viewport_, thumbnails._viewport]:
		var lights := viewport.find_children("*", "DirectionalLight3D", true, false)
		check(lights.size() == 1, "existing key light count preserved")
		if not lights.is_empty():
			check(lights[0].rotation_degrees.is_equal_approx(Vector3(-50,-30,0)) and is_equal_approx(lights[0].light_energy, 1.), "existing key direction and energy preserved")
	check(map_snapshot == var_to_str([map_environment.background_color, map_environment.ambient_light_energy, map_environment.reflected_light_source, map_environment.sky]), "map Environment untouched")
	check(map_world.environment == map_environment, "map Environment resource identity preserved")
	check(thumbnails._pending.is_empty() and thumbnails._imports.is_empty() and not thumbnails._busy, "helper performs no model load or thumbnail writes")
	var fingerprints := {}
	for path: String in ["res://scripts/world_editor/asset_preview_environment.gd", "res://scripts/world_editor/asset_preview.gd", "res://scripts/world_editor/asset_thumbnails.gd"]:
		fingerprints[path] = FileAccess.get_sha256(path)
	var failures := checks.filter(func(item): return not item.ok)
	var file := FileAccess.open(OUT, FileAccess.WRITE)
	file.store_string(JSON.stringify({"version":1,"passed":failures.is_empty(),"checks":checks,"failures":failures,"source_sha256":fingerprints,"gpu_executed":false,"visual_accepted":false,"map_writes":false,"thumbnail_writes":false},"\t"))
	file.close()
	preview.queue_free()
	thumbnails.queue_free()
	map_world.queue_free()
	await process_frame
	print("PREVIEW_ENVIRONMENT_CPU ", checks.size(), " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
