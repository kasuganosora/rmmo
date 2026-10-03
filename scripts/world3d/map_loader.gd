extends Node
## Parse external glTF off the scene thread. Generate nodes only on the main thread.
signal finished(scene: Node, path: String, error: String)
signal progress(stage: String, done: int, total: int)
var _record_meta := {}
var _asset_states := {}
var _building := false
var _prepared: Node
var _thread: Thread
var _document: GLTFDocument
var _state: GLTFState
var _error := OK
var _path := ""
var _content_root := ""
var _cancelled := false


static func resolve_path(requested: String) -> String:
	if not requested.is_empty():
		return requested
	var Paths = preload("res://scripts/world3d/map_paths.gd")
	var yard := Paths.cache_directory("p4_yard")
	var inn := Paths.cache_directory("p4_inn")
	if yard.is_empty() or inn.is_empty():
		return ""
	var path := yard.path_join("map.gltf")
	var inn_path := inn.path_join("map.gltf")
	var Document = preload("res://scripts/world3d/world_document.gd")
	if not FileAccess.file_exists(path) and Document.sample_yard(inn_path).save(path) != OK:
		return ""
	if not FileAccess.file_exists(inn_path) and Document.make_inn(path).save(inn_path) != OK:
		return ""
	return path


func start(path: String) -> void:
	_path = path
	# Snapshot the configured root on the main thread; parsing must not read autoload nodes.
	_content_root = preload("res://scripts/world3d/map_paths.gd").external_root()
	_thread = Thread.new()
	_error = _thread.start(_parse)
	if _error != OK:
		_thread = null
		call_deferred("_finish_error", "无法启动地图读取")


func cancel() -> void:
	_cancelled = true


func _parse() -> void:
	# Our editor records are the authoritative document; avoid importing their
	# duplicate glTF mesh export and constructing thousands of temporary nodes.
	if _path.get_extension().to_lower() == "gltf":
		var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(_path))
		if data is Dictionary:
			var nodes: Array = data.get("nodes", [])
			var scenes: Array = data.get("scenes", [])
			var scene_index := int(data.get("scene", 0))
			if scene_index >= 0 and scene_index < scenes.size():
				var roots: Array = scenes[scene_index].get("nodes", [])
				if roots.size() == 1 and int(roots[0]) >= 0 and int(roots[0]) < nodes.size():
					var root: Dictionary = nodes[int(roots[0])]
					var extra: Dictionary = root.get("extras", {})
					if extra.get("rmmo_format") == "rmmo_gltf_map" and not _valid_records(extra):
						_error = ERR_INVALID_DATA
						return
					if not root.has("matrix") and not root.has("translation") and not root.has("rotation") and not root.has("scale") and _valid_records(extra):
						_record_meta = extra
						for record in extra.rmmo_records:
							if record.get("kind") != "asset": continue
							var asset_path := str(record.get("asset_path", ""))
							if _asset_states.has(asset_path): continue
							if not FileAccess.file_exists(asset_path):
								_error = ERR_FILE_NOT_FOUND
								return
							var asset_document := GLTFDocument.new()
							var asset_state := GLTFState.new()
							_error = asset_document.append_from_file(asset_path, asset_state, 0, asset_path.get_base_dir())
							if _error != OK: return
							_asset_states[asset_path] = [asset_document, asset_state]
						return
	_document = GLTFDocument.new()
	_state = GLTFState.new()
	_error = _document.append_from_file(_path, _state, 0, _path.get_base_dir())


func _process(_delta: float) -> void:
	if _building or _thread == null or _thread.is_alive():
		return
	_thread.wait_to_finish()
	_thread = null
	if _cancelled:
		queue_free()
		return
	if _error != OK:
		_finish_error("地图读取失败：%s" % error_string(_error))
		return
	if not _record_meta.is_empty():
		_building = true
		_build_records()
		return
	if _can_stream_static():
		_building = true
		_build_static()
		return
	var scene := preload("res://scripts/world3d/gltf_map_io.gd").generate_scene(_document, _state)
	finished.emit(scene, _path, "" if scene != null else "地图场景生成失败")
	queue_free()


func _finish_error(message: String) -> void:
	if not _cancelled:
		finished.emit(null, _path, message)
	queue_free()


func _exit_tree() -> void:
	if is_instance_valid(_prepared): _prepared.free()
	if _thread != null:
		_thread.wait_to_finish()


func _valid_records(extra: Dictionary) -> bool:
	if not preload("res://scripts/world3d/building_blueprint.gd").valid_meta(extra): return false
	if extra.get("rmmo_format", "") != "rmmo_gltf_map" or int(extra.get("rmmo_version", 0)) != 1: return false
	if not preload("res://scripts/world3d/environment_settings.gd").valid(extra): return false
	if not preload("res://scripts/world3d/editor_view_settings.gd").valid(extra): return false
	var records: Variant = extra.get("rmmo_records")
	if not records is Array: return false
	if not preload("res://scripts/world3d/building_blueprint.gd").valid_ownership(extra,records): return false
	var ids := {}
	for record in records:
		if not record is Dictionary or str(record.get("uuid", "")).is_empty() or ids.has(record.uuid): return false
		if not preload("res://scripts/world3d/building_blueprint.gd").valid_record(record): return false
		if not preload("res://scripts/world3d/wind_response.gd").valid(record): return false
		if not preload("res://scripts/world3d/terrain_surface.gd").valid(record): return false
		if not preload("res://scripts/world3d/river_material_data.gd").valid(record): return false
		if not preload("res://scripts/world3d/surface_materials.gd").valid(record,false,_content_root): return false
		for definition in preload("res://scripts/world3d/surface_materials.gd").definitions(record):
			if not preload("res://scripts/world3d/surface_materials.gd").material_valid(definition,false,_content_root): return false
			for field in preload("res://scripts/world3d/surface_materials.gd").MAP_FIELDS:
				var path: String=definition.get(field, "")
				if not path.is_empty() and (not preload("res://scripts/world3d/map_paths.gd").allowed(path,_content_root) or not FileAccess.file_exists(path)): return false
		if not preload("res://scripts/world3d/auto_tile_rules.gd").valid(record, false, _content_root): return false
		if not preload("res://scripts/world3d/event_templates.gd").valid_record(record, _content_root): return false
		ids[record.uuid] = true
		for field in ["position", "rotation", "size"]:
			var values: Variant = record.get(field)
			if not values is Array or values.size() != 3: return false
			for value in values:
				if not (value is int or value is float) or not is_finite(float(value)): return false
	return true


func _build_records() -> void:
	var root := Node3D.new()
	_prepared = root
	root.name = "rmmo_world"
	root.set_meta("extras", _record_meta)
	var library: Array = []
	var index := {}
	var by_id := {}
	var known := {}
	var records: Array = _record_meta.rmmo_records
	var doc = preload("res://scripts/world3d/world_document.gd").new()
	doc.records=records
	doc.terrain_neighbors.update(records)
	var Stream = preload("res://scripts/world3d/world_stream.gd")
	var cursor := 0
	while cursor < records.size():
		var start := Time.get_ticks_usec()
		while cursor < records.size() and Time.get_ticks_usec() - start < 3000:
			if records[cursor].get("kind") == "asset":
				if not FileAccess.file_exists(str(records[cursor].get("asset_path", ""))):
					root.free()
					_prepared = null
					_finish_error("地图素材缺失：" + str(records[cursor].get("asset_path", "")))
					return
				var asset_path: String = records[cursor].asset_path
				if _asset_states.has(asset_path):
					var imported: Node = preload("res://scripts/world3d/gltf_map_io.gd").generate_scene(_asset_states[asset_path][0], _asset_states[asset_path][1])
					if imported == null or not preload("res://scripts/world_editor/asset_library.gd").cache_scene(asset_path, imported):
						root.free()
						_prepared = null
						_finish_error("地图素材无法实例化：" + asset_path)
						return
					_asset_states.erase(asset_path)
				root.add_child(doc._asset(records[cursor]))
				cursor += 1
				continue
			var visual: MeshInstance3D = doc._mesh(records[cursor])
			if visual.has_meta("tile_error") or visual.has_meta("paint_error"):
				visual.free(); root.free(); _prepared = null
				_finish_error("自动拼接套件模型缺失或无效")
				return
			var spec: Dictionary = Stream._spec(visual)
			visual.free()
			var id: String = spec.uuid
			library.append(spec)
			by_id[id] = spec
			known[id] = true
			for z in range(spec.chunk_min.y, spec.chunk_max.y + 1):
				for x in range(spec.chunk_min.x, spec.chunk_max.x + 1):
					var key := Vector2i(x, z)
					if not index.has(key): index[key] = []
					index[key].append(id)
			cursor += 1
		progress.emit("建立地图索引", cursor, records.size())
		await get_tree().process_frame
		if _cancelled:
			root.free()
			_prepared = null
			queue_free()
			return
	root.set_meta("stream_library", library)
	root.set_meta("stream_index", index)
	root.set_meta("stream_by_id", by_id)
	root.set_meta("stream_known", known)
	root.set_meta("stream_children", -1 if root.get_child_count() > 0 else 0)
	root.set_meta("record_stream_load", true)
	_prepared = null
	finished.emit(root, _path, "")
	queue_free()


func _can_stream_static() -> bool:
	if not _state.animations.is_empty() or not _state.skins.is_empty() or not _state.cameras.is_empty() or not _state.lights.is_empty(): return false
	for extension in _state.json.get("extensionsUsed", []):
		if str(extension) != "GODOT_single_root": return false
	for node in _state.nodes:
		if node.skin >= 0 or node.skeleton >= 0 or not node.visible: return false
	for imported in _state.meshes:
		if not imported.blend_weights.is_empty(): return false
	return true


func _build_static() -> void:
	var root := Node3D.new()
	_prepared = root
	root.name = "rmmo_world"
	var raw_nodes: Array = _state.json.get("nodes", [])
	if _state.root_nodes.size() == 1:
		root.set_meta("extras", raw_nodes[_state.root_nodes[0]].get("extras", {}))
	var stack: Array = []
	for id in _state.root_nodes: stack.append({"id": id, "parent": Transform3D.IDENTITY})
	var library: Array = []
	var by_id := {}
	var index := {}
	var known := {}
	var meshes := {}
	var visited := {}
	var Stream = preload("res://scripts/world3d/world_stream.gd")
	while not stack.is_empty():
		var start := Time.get_ticks_usec()
		while not stack.is_empty() and Time.get_ticks_usec() - start < 3000:
			var entry: Dictionary = stack.pop_back()
			var id: int = entry.id
			if visited.has(id): continue
			visited[id] = true
			var node: GLTFNode = _state.nodes[id]
			var transform: Transform3D = entry.parent * node.xform
			for child in node.children: stack.append({"id": child, "parent": transform})
			if node.mesh < 0: continue
			if not meshes.has(node.mesh):
				var imported: GLTFMesh = _state.meshes[node.mesh]
				var resource: ArrayMesh = imported.mesh.get_mesh()
				if not imported.instance_materials.is_empty():
					resource = resource.duplicate()
					for surface in mini(resource.get_surface_count(), imported.instance_materials.size()):
						if imported.instance_materials[surface] != null: resource.surface_set_material(surface, imported.instance_materials[surface])
				meshes[node.mesh] = resource
			var visual := MeshInstance3D.new()
			visual.name = "gltf_node_%d" % id
			visual.mesh = meshes[node.mesh]
			visual.transform = transform
			visual.set_meta("extras", raw_nodes[id].get("extras", {}))
			var spec: Dictionary = Stream._spec(visual)
			visual.free()
			var uuid := str(spec.extras.get("uuid", spec.uuid))
			if known.has(uuid):
				_finish_error("地图物件 ID 重复：" + uuid)
				return
			spec.uuid = uuid
			known[uuid] = true
			by_id[uuid] = spec
			library.append(spec)
			for z in range(spec.chunk_min.y, spec.chunk_max.y + 1):
				for x in range(spec.chunk_min.x, spec.chunk_max.x + 1):
					var key := Vector2i(x, z)
					if not index.has(key): index[key] = []
					index[key].append(uuid)
		progress.emit("准备静态地图", visited.size(), _state.nodes.size())
		await get_tree().process_frame
		if _cancelled:
			queue_free()
			return
	root.set_meta("stream_library", library)
	root.set_meta("stream_by_id", by_id)
	root.set_meta("stream_known", known)
	root.set_meta("stream_index", index)
	root.set_meta("stream_children", -1 if root.get_child_count() > 0 else 0)
	root.set_meta("static_stream_load", true)
	_prepared = null
	finished.emit(root, _path, "")
	queue_free()
