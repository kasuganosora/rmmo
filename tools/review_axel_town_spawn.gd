extends SceneTree
## Read-only map review. Run through run_godot_background.py, never a foreground window.
## Uses the production loading scene and metadata spawn; no map, config or character save.
const Document = preload("res://scripts/world3d/world_document.gd")
const Paths = preload("res://scripts/world3d/map_paths.gd")
const CANDIDATE := "D:/code/rmmo_runtime/cache/world3d/axel_town_terrain_20261014/map.gltf"
var map_path := CANDIDATE
var output := "D:/code/rmmo_runtime/review_artifacts/axel_town_terrain_20261014/spawn_review"
var expected_feet := Vector3(156, 7.5, 209)
var skip_walk := false
var require_startup_config := false
var world: Node
var failures := 0
var finished := false
var started_ms := 0
var report := {"scope":"native loading, authored spawn, standing capsule, 8m outdoor walk",
	"not_tested":["interiors", "full-town performance", "west gate/market/bridge3 complete routes", "startup configuration persistence"],
	"checks":[], "screenshots":[]}


func _initialize() -> void:
	call_deferred("run")


func check(passed: bool, label: String, details: Dictionary = {}) -> bool:
	report.checks.append({"name":label, "passed":passed, "details":details})
	if not passed: failures += 1
	print("PASS " if passed else "FAIL ", label)
	return passed


func xyz(point: Vector3) -> Array:
	return [point.x, point.y, point.z]


func canonical_path(value: String) -> String:
	var normalized := value.replace("\\", "/").simplify_path().trim_suffix("/")
	return normalized.to_lower() if OS.get_name() == "Windows" else normalized


func feet() -> Vector3:
	return world._player.global_position - Vector3.UP * .9


func support(point: Vector3, reach: float = .5, rise: float = .2) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * rise, point - Vector3.UP * reach)
	query.exclude = [world._player.get_rid()]
	query.collision_mask = world._player.collision_mask
	var hit: Dictionary = world._player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return {"ok":false, "reason":"no_support"}
	var gap: float = point.y - hit.position.y
	return {"ok":hit.normal.y >= cos(deg_to_rad(45.0)) and absf(gap) <= .12,
		"point":xyz(hit.position), "normal":xyz(hit.normal), "feet_gap_m":gap}


func save_report() -> void:
	report.failures = failures
	report.elapsed_ms = Time.get_ticks_msec() - started_ms
	var file := FileAccess.open(output.path_join("result.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
		file.close()


func finish(code: int = -1) -> void:
	if finished: return
	finished = true
	if is_instance_valid(world) and is_instance_valid(world.get("_player")):
		world._player.click_target = null
		world._player._route.clear()
		report.final_feet = xyz(feet())
	report.status = "passed" if failures == 0 and code != 2 else "failed"
	save_report()
	print("AXEL_TOWN_SPAWN_REVIEW ", output.path_join("result.json"), " failures=", failures)
	quit(code if code >= 0 else (1 if failures else 0))


func run() -> void:
	started_ms = Time.get_ticks_msec()
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--map="): map_path = arg.trim_prefix("--map=").replace("\\", "/").simplify_path()
		elif arg.begins_with("--out="): output = arg.trim_prefix("--out=").replace("\\", "/").simplify_path()
		elif arg == "--skip-walk": skip_walk = true
		elif arg == "--require-startup-config": require_startup_config = true
	if not Paths.allowed(output):
		push_error("Review output must be inside the external content root")
		quit(1)
		return
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		push_error("Unable to create review output directory: " + output)
		quit(1)
		return
	report.map_path = map_path
	report.expected_feet = xyz(expected_feet)
	report.startup_configuration = {"required":require_startup_config,"status":"pending" if require_startup_config else "not_requested"}
	report.phase = "metadata"
	create_timer(240).timeout.connect(func():
		if not finished:
			var status := current_scene.get_node_or_null("%Status") if is_instance_valid(current_scene) else null
			check(false, "review timeout", {"phase":report.phase, "loading_status":status.text if status is Label else ""})
			finish(2))
	if not check(DisplayServer.get_name() != "headless", "real graphics renderer required"):
		finish()
		return
	if not check(Paths.allowed(map_path) and FileAccess.file_exists(map_path), "map exists in content root"):
		finish()
		return
	if require_startup_config:
		report.not_tested.erase("startup configuration persistence")
		var configured := str(ProjectSettings.get_setting("rmmo/world3d_start_map", ""))
		var profile := str(ProjectSettings.get_setting("rmmo/startup_profile", ""))
		var matching := not configured.is_empty() and Paths.allowed(configured) and canonical_path(configured) == canonical_path(map_path)
		var map_ok := check(matching, "effective startup map matches requested map", {"configured":configured,"requested":map_path,"canonical_configured":canonical_path(configured),"canonical_requested":canonical_path(map_path)})
		var profile_ok := check(profile == "world3d", "effective startup profile is world3d", {"profile":profile})
		report.startup_configuration.merge({"status":"passed" if map_ok and profile_ok else "failed","map":configured,"profile":profile,"source":"effective ProjectSettings loaded by this process","runtime_loading":"pending"},true)
		if not map_ok or not profile_ok:
			finish()
			return
	report.map_sha256 = FileAccess.get_sha256(map_path)
	var authored: Dictionary = Document.authoritative_extras(map_path, null, true)
	if not check(authored.has("extras"), "native map metadata readable", {"error":authored.get("error", "")}):
		finish()
		return
	var meta: Dictionary = authored.extras
	report.map_ref = meta.get("map_ref", "")
	report.authored_spawn_center = meta.get("spawn", [])
	report.editor_spawn_feet = meta.get("editor_view", {}).get("spawn", [])
	var raw: Variant = meta.get("spawn", [])
	if not check(raw is Array and raw.size() == 3, "formal spawn metadata exists"):
		finish()
		return
	var authored_center := Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
	check(authored_center.distance_to(expected_feet + Vector3.UP * .9) < .01, "authored spawn matches planned center")
	Engine.max_fps = 60
	root.size = Vector2i(1280, 800)
	preload("res://tools/world3d_test_character.gd").ensure(self)
	var session = root.get_node("GameSession")
	session.spawn_data = {"character":session.selected_character.duplicate(true), "equipment":[], "world_mode":"world3d"}
	session.world3d_requested = true
	session.loading_mode = "world3d_preview"
	# Required mode exercises LoadingScene's normal ProjectSettings fallback;
	# candidate review continues to use the explicit session-only map override.
	session.world3d_map_path = "" if require_startup_config else map_path
	report.loading_path_source = "ProjectSettings rmmo/world3d_start_map" if require_startup_config else "session review override"
	# Leave the normal sentinel intact: world_3d must read root extras.spawn itself.
	session.world3d_spawn = Vector3(0, .9, 4)
	session.prepared_world3d = null
	report.phase = "native_loading"
	save_report()
	var entry_started := Time.get_ticks_msec()
	if not check(change_scene_to_file("res://scenes/loading.tscn") == OK, "enter production LoadingScene"):
		finish()
		return
	while not finished:
		await process_frame
		world = current_scene
		if world == null: continue
		if world.has_meta("entry_loading_error"):
			check(false, "runtime entry readiness", {"error":world.get_meta("entry_loading_error")})
			finish()
			return
		if world.has_method("is_world_ready") and world.is_world_ready() and not session._world_transition_active: break
	if finished: return
	report.entry_ms = Time.get_ticks_msec() - entry_started
	if not check(is_instance_valid(world.get("_map_root")) and is_instance_valid(world.get("_player")), "native map and actual player created"):
		finish()
		return
	var loaded_map_ok := check(canonical_path(world._map_path) == canonical_path(map_path), "runtime loaded requested map")
	var loaded_spawn_ok := check(session.world3d_spawn.distance_to(authored_center) < .01, "runtime used formal metadata spawn")
	var player_ready := check(not world._player.input_locked and not world._player.geometry_blocked, "entry released actual player")
	if require_startup_config:
		var runtime_passed := loaded_map_ok and loaded_spawn_ok and player_ready
		report.startup_configuration.runtime_loading = "passed" if runtime_passed else "failed"
		report.startup_configuration.configuration_and_runtime_passed = report.startup_configuration.status == "passed" and runtime_passed
	report.navigation_ready_for_queries = world._navigation.ready_for_queries
	report.phase = "standing"
	var initial: Vector3 = feet()
	var minimum_y := initial.y
	var maximum_drift := 0.0
	for tick in 180:
		await physics_frame
		var point := feet()
		minimum_y = minf(minimum_y, point.y)
		maximum_drift = maxf(maximum_drift, Vector2(point.x - initial.x, point.z - initial.z).length())
	report.standing = {"start":xyz(initial), "end":xyz(feet()), "minimum_y":minimum_y, "max_horizontal_drift_m":maximum_drift}
	check(initial.distance_to(expected_feet) < .2, "spawn capsule starts at planned feet")
	check(minimum_y >= expected_feet.y - .15 and absf(feet().y - expected_feet.y) <= .15 and maximum_drift < .15, "capsule remains stable for 180 physics ticks", report.standing)
	check(bool(support(feet()).ok), "standing feet have walkable support", support(feet()))
	var collider := world._player.get_node("CollisionShape3D") as CollisionShape3D
	check(not collider.disabled and collider.shape is CapsuleShape3D, "real character capsule remains enabled")
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collider.shape
	query.transform = collider.global_transform
	query.transform.origin += Vector3.UP * .03
	query.collision_mask = world._player.collision_mask
	query.exclude = [world._player.get_rid()]
	query.margin = .001
	var overlaps: Array = world._player.get_world_3d().direct_space_state.intersect_shape(query, 8)
	check(overlaps.is_empty(), "standing capsule has clear space above support", {"overlap_count":overlaps.size()})
	await capture("spawn", feet() + Vector3(-8, 5, 12), feet() + Vector3(0, .8, -6))
	if not skip_walk and failures == 0:
		await short_walk()
	else:
		report.walk = {"status":"skipped", "reason":"requested" if skip_walk else "entry checks failed"}
	check(FileAccess.get_sha256(map_path) == report.map_sha256, "source map unchanged")
	report.phase = "complete"
	finish()


func short_walk() -> void:
	report.phase = "short_outdoor_walk"
	# The approved route starts south across the future guild square, before its turn.
	var sample := support(Vector3(expected_feet.x, expected_feet.y, expected_feet.z + 8), 20.0, 20.0)
	if not check(sample.has("point") and float(sample.get("normal", [0, 0, 0])[1]) >= cos(deg_to_rad(45.0)), "nearby walk target has walkable collision support", sample): return
	var target := Vector3(sample.point[0], sample.point[1], sample.point[2])
	var start := feet()
	var request: Dictionary = world._player.set_click_target(target, "ground")
	var began := Time.get_ticks_msec()
	var unsupported_ticks := 0
	var max_unsupported_ticks := 0
	while Time.get_ticks_msec() - began < 45000:
		await physics_frame
		var ground := support(feet())
		unsupported_ticks = 0 if ground.ok else unsupported_ticks + 1
		max_unsupported_ticks = maxi(max_unsupported_ticks, unsupported_ticks)
		if unsupported_ticks > 30: break
		if feet().distance_to(target) < .3: break
		if not world._player.path_status.get("ok", false) and world._player.path_status.get("reason") != "pending": break
	var remaining := feet().distance_to(target)
	report.walk = {"status":"passed" if remaining < .3 and max_unsupported_ticks <= 30 else "failed",
		"start":xyz(start), "target":xyz(target), "end":xyz(feet()), "remaining_m":remaining,
		"elapsed_ms":Time.get_ticks_msec() - began, "max_unsupported_ticks":max_unsupported_ticks,
		"initial_request_reason":request.get("reason", ""), "final_path_reason":world._player.path_status.get("reason", "")}
	world._player.click_target = null
	world._player._route.clear()
	check(remaining < .3 and max_unsupported_ticks <= 30, "actual player walks 8m without falling", report.walk)
	await capture("short_walk", feet() + Vector3(-9, 5, 10), expected_feet + Vector3(0, 1, -8))


func capture(label: String, eye: Vector3, target: Vector3) -> void:
	# Only rendering is hidden. Collision, physics, readiness and measurements remain intact.
	var model := world._player.get_node("CharacterModel3D") as Node3D
	var visible_before := model.visible
	var processing_before: bool = world.is_processing()
	var camera: Camera3D = world._camera.camera
	var camera_before := camera.global_transform
	var layers: Array = []
	for child in world.get_children():
		if child is CanvasLayer:
			layers.append([child, child.visible])
			child.hide()
	model.hide()
	world.set_process(false)
	camera.global_position = eye
	camera.look_at(target)
	for frame in 8: await process_frame
	await RenderingServer.frame_post_draw
	var frame_image := root.get_texture().get_image()
	var path := output.path_join(label + ".webp")
	var error := frame_image.save_webp(path, true, .92)
	camera.global_transform = camera_before
	world.set_process(processing_before)
	model.visible = visible_before
	for entry: Array in layers: entry[0].visible = entry[1]
	check(error == OK, "direct WebP capture " + label)
	check(model.visible == visible_before and not world._player.get_node("CollisionShape3D").disabled, "actor rendering restored after " + label)
	if error == OK:
		report.screenshots.append({"path":path, "sha256":FileAccess.get_sha256(path),
			"width":frame_image.get_width(), "height":frame_image.get_height(), "eye":xyz(eye), "target":xyz(target), "mime":"image/webp"})
