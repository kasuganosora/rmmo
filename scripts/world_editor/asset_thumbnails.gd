extends Node
## Visible thumbnail IO is bounded. Missing imported thumbnails are repaired
## one at a time after input settles, and persisted for subsequent visits.
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
var _render_serial := 0
var _output := ""
var placeholder: Texture2D
var model_load_count := 0
var disk_load_count := 0
var _missing := {}
var _attempted := {}
var _errors := {}
var _idle := 0.
var _preparation:Node
var _request:=0
var _prepare_serial:=0
var _active_idle:=false
var _streamed_observer=preload("res://scripts/world_editor/streamed_preview_observer.gd").new()
var _readiness=preload("res://scripts/world_editor/streamed_preview_readiness.gd").new()

static func thumbnail_path(entry: Dictionary) -> String:
	var paths=preload("res://scripts/world3d/map_paths.gd")
	var path: String=str(entry.get("thumbnail_path",""))
	if path.is_empty(): path=paths.cache_directory("asset_thumbnails").path_join(key_for(entry).sha256_text()+".png")
	return path if paths.allowed(path) else ""

func state(entry: Dictionary) -> Dictionary:
	var key:=key_for(entry); var path:=thumbnail_path(entry)
	var status:="ready" if not path.is_empty() and FileAccess.file_exists(path) else "missing"
	if (_busy and key==_key) or _imports.any(func(item):return key_for(item)==key) or _missing.has(key): status="pending"
	if _errors.has(key): status="failed"
	return {"status":status,"path":path,"error":_errors.get(key,"")}

static func key_for(entry: Dictionary) -> String:
	return str(entry.get("prefab_path", entry.get("asset_path", entry.get("id", ""))))

func lookup(entry: Dictionary) -> Texture2D:
	var key := key_for(entry)
	if not cache.has(key): return placeholder
	_lru.erase(key)
	_lru.append(key)
	return cache[key] if cache[key] != null else placeholder

func set_visible_entries(entries: Array) -> void:
	_wanted.clear()
	_pending.clear()
	_missing.clear()
	for entry in entries:
		var key := key_for(entry)
		_wanted[key] = true
		if not cache.has(key) and (not _busy or key != _key): _pending.append(entry)
		if (entry.has("asset_path") or entry.has("prefab_path")) and not _attempted.has(key):
			var path:=thumbnail_path(entry)
			if not path.is_empty() and not FileAccess.file_exists(path): _missing[key]=entry
	# No deferred callback per asset, and scrolling replaces obsolete queued work.
	_imports=_imports.filter(func(entry):return not entry.get("_thumbnail_idle",false) or _wanted.has(key_for(entry)))
	if _busy and _active_idle and not _wanted.has(_key):
		_attempted.erase(_key);_cancel_active()

func queue_import(entry: Dictionary,idle_request:bool=false) -> void:
	var key:=key_for(entry)
	if _busy and key==_key:
		if not idle_request:_active_idle=false
		return
	for queued:Dictionary in _imports:
		if key_for(queued)==key:
			if not idle_request:queued._thumbnail_idle=false
			return
	_errors.erase(key); _missing.erase(key)
	var job:=entry.duplicate(); job.thumbnail_path=thumbnail_path(entry)
	job._thumbnail_idle=idle_request
	_imports.append(job)

func _input(_event: InputEvent) -> void:
	_idle=0

func _remember(key: String, texture: Texture2D) -> void:
	cache[key] = texture
	_lru.erase(key)
	_lru.append(key)
	while _lru.size() > MAX_CACHE:
		cache.erase(_lru.pop_front())
	if _wanted.has(key): available.emit(key, texture if texture != null else placeholder)

func _process(_delta: float) -> void:
	_idle+=_delta
	_readiness.pump()
	if get_parent().has_method("saving") and get_parent().saving(): return
	if not _busy and _imports.is_empty() and _pending.is_empty() and _idle>=.4 and not _missing.is_empty():
		var key: String=_missing.keys()[0]
		var entry: Dictionary=_missing[key]; _missing.erase(key)
		if _wanted.has(key):
			_attempted[key]=true
			var source:=key_for(entry)
			var available:bool=(preload("res://scripts/world3d/map_paths.gd").allowed(source) and FileAccess.file_exists(source)) if entry.has("prefab_path") else preload("res://scripts/world_editor/asset_library.gd").native_available(source)
			if available:queue_import(entry,true)
			else:_errors[key]="缩略图资源缺失或缺少原生产物，请重新导入"
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
	preload("res://scripts/world_editor/asset_preview_environment.gd").apply_reflections(environment)
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
	if (entry.has("asset_path") or entry.has("prefab_path")) and not importing:
		# Existing PNGs never instantiate models; missing files use the idle queue.
		var path := thumbnail_path(entry)
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
		if importing:
			_errors[key]="无图形渲染器，需在图形编辑器生成缩略图"
			import_finished.emit(key, _output, ERR_UNAVAILABLE)
		return
	_busy = true
	_active_idle=entry.get("_thumbnail_idle",false)
	var model: Node3D
	if entry.has("prefab_path") or entry.has("asset_path"):
		model_load_count += 1
		_prepare_entry(entry,importing)
		return
	else:
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = entry.get("size", Vector3.ONE)
		mesh.mesh = box
		mesh.rotation_degrees = entry.get("rotation", Vector3.ZERO)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("72966a") if entry.get("category") == "地面" else Color("ab9680")
		mesh.material_override = material
		if entry.has("auto_family"):
			mesh.mesh = preload("res://scripts/world3d/auto_tile_mesh.gd").build({"family": entry.auto_family, "mask": 3, "neighbors": []})
			mesh.scale = entry.get("size", Vector3.ONE)
			mesh.material_override = null
		model = mesh
	_present_model(model,key,importing)

func _prepare_entry(entry:Dictionary,importing:bool)->void:
	_prepare_serial+=1
	var prefab:Dictionary={};var paths:Array=[]
	if entry.has("prefab_path"):
		var library=preload("res://scripts/world_editor/prefab_library.gd")
		prefab=library.read(entry)
		if not prefab.get("ok",false):_present_model(null,key_for(entry),importing);return
		paths=library.preview_dependencies(prefab)
	else:paths=[str(entry.asset_path)]
	_preparation=preload("res://scripts/world_editor/editor_asset_preparation.gd").for_consumer(self)
	if _preparation==null:_present_model(null,key_for(entry),importing);return
	_request=_preparation.request_many(paths,self,_model_prepared.bind(_prepare_serial,entry,prefab,importing))
	if _request==0:_present_model(null,key_for(entry),importing)

func _model_prepared(id:int,result:Dictionary,serial:int,entry:Dictionary,prefab:Dictionary,importing:bool)->void:
	if serial!=_prepare_serial or id!=_request or not is_inside_tree():return
	_request=0
	var model:Node3D
	if result.get("ok",false):
		if prefab.is_empty():
			var handle:Variant=result.handles.get(str(entry.asset_path).replace("\\","/").simplify_path())
			if handle!=null:model=handle.instantiate()
		else:
			var templates:Dictionary={};var current:=true
			for path:String in result.handles:
				if not result.handles[path].current():current=false;break
				templates[path]=result.handles[path].packed
			if current:model=preload("res://scripts/world_editor/prefab_library.gd").preview_prepared(prefab,templates)
	_present_model(model,key_for(entry),importing)

func _present_model(model:Node3D,key:String,importing:bool)->void:
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
		_streamed_observer.capture(model)
		# Bound signal callbacks disconnect automatically when the editor closes.
		get_tree().process_frame.connect(_render, CONNECT_ONE_SHOT)
		return
	_busy = false
	if importing:
		_errors[key]="无法加载缩略图模型"
		import_finished.emit(key, _output, ERR_CANT_OPEN)

func _render() -> void:
	if not is_inside_tree() or not is_instance_valid(_model):return
	_render_serial += 1
	_readiness.start(_viewport,self,_streamed_observer,_render_completed.bind(_render_serial))

func _render_completed(result:Dictionary,serial:int)->void:
	if serial!=_render_serial or not is_inside_tree() or not is_instance_valid(_model):return
	if result.ok:_finish(serial);return
	_errors[_key]=str(result.error)
	if not _output.is_empty():import_finished.emit(_key,_output,int(result.error_code))
	_dispose_model();_busy=false

func _finish(serial: int) -> void:
	if serial != _render_serial or not is_inside_tree() or not is_instance_valid(_model):return
	var image := _viewport.get_texture().get_image()
	var texture := ImageTexture.create_from_image(image)
	if not _output.is_empty():
		DirAccess.make_dir_recursive_absolute(_output.get_base_dir())
		var error := image.save_png(_output + ".tmp")
		if error == OK: error = preload("res://scripts/world3d/atomic_file.gd").publish(_output + ".tmp", _output)
		if error!=OK: _errors[_key]=error_string(error)
		import_finished.emit(_key, _output, error)
	_remember(_key, texture)
	_dispose_model()
	_busy = false

func _dispose_model()->void:
	_readiness.cancel();_streamed_observer.clear()
	var owned:=_model;_model=null
	if not is_instance_valid(owned):return
	if owned.get_parent()!=null:
		if owned.get_parent()!=_viewport:return
		_viewport.remove_child(owned)
	preload("res://scripts/world3d/asset_worker_drainer.gd").dispose_scene(owned)

func _cancel_active()->void:
	_prepare_serial+=1
	if _request!=0 and is_instance_valid(_preparation):_preparation.cancel(_request)
	_request=0
	if get_tree().process_frame.is_connected(_render):get_tree().process_frame.disconnect(_render)
	_render_serial+=1;_dispose_model();_busy=false

func _exit_tree()->void:
	# Stop delayed draws before the retirement sync can deliver renderer events.
	_cancel_active()
