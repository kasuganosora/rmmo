extends Control
## Read-only presentation of an existing default-pack map. No world/session logic.
const Paths = preload("res://scripts/world3d/map_paths.gd")
const Loader = preload("res://scripts/ui/entry_map_loader.gd")
const Lighting = preload("res://scripts/world3d/environment_settings.gd")
signal background_ready
var viewport: SubViewport
var camera: Camera3D
var map_path := ""
var load_error := ""
var loaded := false
var _loader: Node
var _world: Node3D
var _environment: Environment
var _sun: DirectionalLight3D
static var _cached_scene: PackedScene
static var _cached_key := ""
static var _cached_lighting := {}
static var _cached_bounds := AABB()
var _load_started := 0
var _render_frames := 0

static func resolve_map() -> String:
	var pack := str(ProjectSettings.get_setting("rmmo/default_pack", "default"))
	var map_id := str(ProjectSettings.get_setting("rmmo/entry_map", "medieval_material_house"))
	var folder := Paths.map_directory(pack, map_id)
	if folder.is_empty(): return ""
	var candidate := folder.path_join("map.gltf")
	if Paths.allowed(candidate) and FileAccess.file_exists(candidate): return candidate
	# A different default pack may not contain the showcase map. Use its first
	# existing 3D map, without creating the world's sample map as a side effect.
	var maps := folder.get_base_dir()
	if not DirAccess.dir_exists_absolute(maps): return ""
	var names := DirAccess.get_directories_at(maps)
	names.sort()
	for id in names:
		candidate = maps.path_join(id).path_join("map.gltf")
		if Paths.allowed(candidate) and FileAccess.file_exists(candidate): return candidate
	return ""

func _ready() -> void:
	set_process(false)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var fallback := ColorRect.new()
	fallback.color = Color("182126")
	fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(fallback); fallback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.gui_disable_input = true
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.use_taa = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	var picture := TextureRect.new()
	picture.texture = viewport.get_texture()
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_SCALE
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(picture); picture.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_world = Node3D.new(); viewport.add_child(_world)
	var environment_node := WorldEnvironment.new()
	_environment = Environment.new(); environment_node.environment = _environment
	_world.add_child(environment_node)
	_sun = DirectionalLight3D.new(); _world.add_child(_sun)
	Lighting.apply(Lighting.defaults(), _sun, _environment)
	camera = Camera3D.new(); camera.fov = 42; camera.far = 600
	_world.add_child(camera); camera.current = true
	resized.connect(_resize); _resize()
	map_path = resolve_map()
	if map_path.is_empty():
		load_error = "默认资源包没有可用的入口地图"
		return
	_load_started = Time.get_ticks_msec()
	if _cached_scene != null and _cached_key == _map_key():
		call_deferred("_on_map", _cached_scene.instantiate(), map_path, "")
		return
	_loader = Loader.new(); add_child(_loader)
	_loader.finished.connect(_on_map)
	_loader.start(map_path)

func _resize() -> void:
	if viewport == null: return
	var scale_factor := minf(1.0, 1600.0 / maxf(size.x, 1.0))
	viewport.size = Vector2i(maxi(2, int(size.x * scale_factor)), maxi(2, int(size.y * scale_factor)))
	if loaded: _refresh_render()

func _on_map(scene: Node, _path: String, error: String) -> void:
	_loader = null
	if scene == null:
		load_error = error
		return
	scene.process_mode = Node.PROCESS_MODE_DISABLED
	_world.add_child(scene)
	var from_cache := _cached_scene != null and _cached_key == _map_key()
	var lighting: Dictionary = _cached_lighting if from_cache else Lighting.resolve(scene.get_meta("extras", {}))
	Lighting.apply(lighting, _sun, _environment)
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color("4e687a")
	sky_material.sky_horizon_color = _environment.background_color
	sky_material.ground_horizon_color = _environment.background_color
	sky_material.ground_bottom_color = _environment.background_color.darkened(.15)
	sky.sky_material = sky_material; _environment.sky = sky
	_environment.background_mode = Environment.BG_SKY
	var bounds := _cached_bounds if from_cache else _mesh_bounds(scene)
	if not from_cache:
		# Keep only the presentation nodes/resources; editor record indexes and
		# gameplay metadata are unnecessary in this in-memory entry cache.
		for key in scene.get_meta_list(): scene.remove_meta(key)
		_own_children(scene, scene)
		var packed := PackedScene.new()
		if packed.pack(scene) == OK:
			_cached_scene = packed; _cached_key = _map_key()
			_cached_lighting = lighting; _cached_bounds = bounds
	var center := bounds.get_center()
	var extent := maxf(8.0, maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z)))
	var target := center + Vector3(extent * .16, 0, 0)
	camera.position = center + Vector3(extent * .95, extent * .08, extent * 1.22)
	camera.look_at(target)
	if ProjectSettings.has_setting("rmmo/entry_camera_position") and ProjectSettings.has_setting("rmmo/entry_camera_target"):
		camera.position = ProjectSettings.get_setting("rmmo/entry_camera_position")
		camera.look_at(ProjectSettings.get_setting("rmmo/entry_camera_target"))
	camera.make_current()
	_refresh_render()
	print("Entry map ready in %d ms (%s)" % [Time.get_ticks_msec() - _load_started, "cached" if from_cache else "loaded"])

func _refresh_render() -> void:
	# Let temporal antialiasing settle, then retain the static camera frame.
	_render_frames = 12
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	set_process(true)

func _process(_delta: float) -> void:
	_render_frames -= 1
	if _render_frames > 0: return
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	set_process(false)
	if not loaded:
		loaded = true
		background_ready.emit()

func _map_key() -> String:
	return map_path + ":" + str(FileAccess.get_modified_time(map_path))

func _own_children(node: Node, scene: Node) -> void:
	for child in node.get_children():
		child.owner = scene
		_own_children(child, scene)

func _mesh_bounds(scene: Node) -> AABB:
	var bounds := AABB()
	var have_bounds := false
	for child in scene.find_children("*", "MeshInstance3D", true, false):
		if child.mesh == null: continue
		var box: AABB = child.global_transform * child.mesh.get_aabb()
		if box.size.y <= .5 or box.size.length() >= 80: continue
		bounds = bounds.merge(box) if have_bounds else box
		have_bounds = true
	return bounds if have_bounds else AABB(Vector3(-4, 0, -4), Vector3(8, 6, 8))

func _exit_tree() -> void:
	if is_instance_valid(_loader): _loader.cancel()
