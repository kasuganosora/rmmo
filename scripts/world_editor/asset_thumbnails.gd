extends Node
## Visible thumbnail IO is bounded. Imported models render only in explicit import jobs.
signal available(key: String, texture: Texture2D)
signal import_finished(key: String, path: String, error: int)
const MAX_CACHE := 96
var cache := {}
var _pending: Array = []
var _imports: Array = []
var _wanted := {}
var _lru: Array[String] = []
var _busy := false
var _viewport: SubViewport
var _camera: Camera3D
var _model: Node3D
var _key := ""
var _output := ""
var placeholder: Texture2D
var model_load_count := 0
var disk_load_count := 0

static func key_for(entry: Dictionary) -> String:
	return str(entry.get("asset_path", entry.get("id", "")))

func lookup(entry: Dictionary) -> Texture2D:
	var key := key_for(entry)
	if not cache.has(key): return placeholder
	_lru.erase(key)
	_lru.append(key)
	return cache[key] if cache[key] != null else placeholder

func set_visible_entries(entries: Array) -> void:
	_wanted.clear()
	_pending.clear()
	for entry in entries:
		var key := key_for(entry)
		_wanted[key] = true
		if not cache.has(key) and (not _busy or key != _key): _pending.append(entry)
	# No deferred callback per asset, and scrolling replaces obsolete queued work.

func queue_import(entry: Dictionary) -> void:
	_imports.append(entry)

func _remember(key: String, texture: Texture2D) -> void:
	cache[key] = texture
	_lru.erase(key)
	_lru.append(key)
	while _lru.size() > MAX_CACHE:
		cache.erase(_lru.pop_front())
	if _wanted.has(key): available.emit(key, texture if texture != null else placeholder)

func _process(_delta: float) -> void:
	if not _busy: _next()

func _ready() -> void:
	var gradient := GradientTexture2D.new()
	gradient.width = 96
	gradient.height = 80
	gradient.gradient = Gradient.new()
	gradient.gradient.colors = PackedColorArray([Color("303139"), Color("424752")])
	placeholder = gradient
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(96, 80)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	_camera = Camera3D.new()
	_camera.current = true
	_viewport.add_child(_camera)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("303139")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.65
	_camera.environment = environment
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -30, 0)
	_viewport.add_child(light)

func _next() -> void:
	if _busy: return
	var importing := not _imports.is_empty()
	if not importing and _pending.is_empty(): return
	var entry: Dictionary = _imports.pop_front() if importing else _pending.pop_front()
	var key := key_for(entry)
	_key = key
	_output = str(entry.get("thumbnail_path", "")) if importing else ""
	if entry.has("asset_path") and not importing:
		# Browsing never instantiates models, including resources without a thumbnail.
		var path := str(entry.get("thumbnail_path", ""))
		var texture: Texture2D
		if not path.is_empty() and FileAccess.file_exists(path):
			var image := Image.load_from_file(path)
			if image != null and not image.is_empty():
				image.resize(96, 80, Image.INTERPOLATE_LANCZOS)
				texture = ImageTexture.create_from_image(image)
				disk_load_count += 1
		_remember(key, texture)
		return
	if DisplayServer.get_name() == "headless":
		if importing: import_finished.emit(key, _output, ERR_UNAVAILABLE)
		return
	_busy = true
	var model: Node3D
	if entry.has("asset_path"):
		model_load_count += 1
		model = preload("res://scripts/world_editor/asset_library.gd").instantiate_preview(entry.asset_path)
	else:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = entry.get("size", Vector3.ONE)
		mesh.mesh = box
		mesh.rotation_degrees = entry.get("rotation", Vector3.ZERO)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("72966a") if entry.get("category") == "地面" else Color("ab9680")
		mesh.material_override = material
		model = mesh
	if model != null:
		_viewport.add_child(model)
		for imported in model.find_children("*", "Camera3D", true, false): imported.current = false
		_camera.current = true
		var bounds := preload("res://scripts/world_editor/asset_library.gd").bounds_of(model)
		var distance := maxf(bounds.size.length() * 1.25, 1.0)
		_camera.position = bounds.get_center() + Vector3(1, 0.8, 1).normalized() * distance
		_camera.look_at(bounds.get_center())
		_camera.near = maxf(0.001, distance / 1000)
		_camera.far = maxf(100, distance * 5)
		_model = model
		_key = key
		# Bound signal callbacks disconnect automatically when the editor closes.
		get_tree().process_frame.connect(_render, CONNECT_ONE_SHOT)
		return
	_busy = false
	if importing: import_finished.emit(key, _output, ERR_CANT_OPEN)

func _render() -> void:
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	RenderingServer.frame_post_draw.connect(_finish, CONNECT_ONE_SHOT)

func _finish() -> void:
	var image := _viewport.get_texture().get_image()
	var texture := ImageTexture.create_from_image(image)
	if not _output.is_empty():
		DirAccess.make_dir_recursive_absolute(_output.get_base_dir())
		var error := image.save_png(_output + ".tmp")
		if error == OK: error = preload("res://scripts/world3d/atomic_file.gd").publish(_output + ".tmp", _output)
		import_finished.emit(_key, _output, error)
	_remember(_key, texture)
	_model.free()
	_model = null
	_busy = false
