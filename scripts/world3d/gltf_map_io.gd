extends RefCounted
## Read and write one map glTF with GLTFDocument. The scene tree is a view, not the document.

static func save_scene(root: Node, gltf_path: String) -> Error:
	if root == null or gltf_path.is_empty():
		return ERR_INVALID_PARAMETER
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_scene(root, state)
	if err != OK:
		return err
	# GLTF export does not copy per-instance morph weights into GLTFMesh defaults.
	# Give each morph instance its own mesh record to retain distinct initial poses.
	var meshes := state.meshes
	for i in state.nodes.size():
		var imported: GLTFNode = state.nodes[i]
		var visual := state.get_scene_node(i) as MeshInstance3D
		if visual == null or not visual.mesh is ArrayMesh or visual.mesh.get_blend_shape_count() == 0 or imported.mesh < 0: continue
		var copy: GLTFMesh = meshes[imported.mesh].duplicate()
		var weights := PackedFloat32Array()
		for blend in visual.mesh.get_blend_shape_count(): weights.append(visual.get_blend_shape_value(blend))
		copy.blend_weights = weights
		imported.mesh = meshes.size()
		meshes.append(copy)
	state.meshes = meshes
	DirAccess.make_dir_recursive_absolute(gltf_path.get_base_dir())
	return doc.write_to_filesystem(state, gltf_path)


# Test-only interruption hook; production leaves it empty.
static var save_fault: Callable

static func save_scene_atomic(root: Node, gltf_path: String, expected_signature: Variant = null) -> Error:
	if root == null or gltf_path.is_empty(): return ERR_INVALID_PARAMETER
	gltf_path = ProjectSettings.globalize_path(gltf_path).simplify_path()
	var err := DirAccess.make_dir_recursive_absolute(gltf_path.get_base_dir())
	if err != OK: return err
	err = _acquire_save_lock(gltf_path)
	if err != OK: return err
	if expected_signature != null and FileAccess.get_sha256(gltf_path) != str(expected_signature):
		err = ERR_BUSY
	else:
		err = _save_version(root, gltf_path)
	_remove_tree(gltf_path + ".save-lock")
	return err

static func _acquire_save_lock(path: String) -> Error:
	var lock := path + ".save-lock"
	if DirAccess.dir_exists_absolute(lock):
		var owner_path := lock.path_join("owner")
		if not FileAccess.file_exists(owner_path): return ERR_BUSY
		var owner := int(FileAccess.get_file_as_string(owner_path))
		if owner <= 0 or OS.is_process_running(owner): return ERR_BUSY
		_remove_tree(lock)
	var err := DirAccess.make_dir_absolute(lock)
	if err != OK: return ERR_BUSY
	var owner_file := FileAccess.open(lock.path_join("owner"), FileAccess.WRITE)
	if owner_file == null:
		err = FileAccess.get_open_error()
		_remove_tree(lock)
		return err
	owner_file.store_string(str(OS.get_process_id()))
	owner_file.flush()
	err = owner_file.get_error()
	owner_file.close()
	if err != OK: _remove_tree(lock)
	return err

static func restore_previous(path: String) -> Error:
	path = ProjectSettings.globalize_path(path).simplify_path()
	if not FileAccess.file_exists(path + ".previous"): return ERR_FILE_NOT_FOUND
	var err := _acquire_save_lock(path)
	if err != OK: return err
	var staged := path.get_basename() + ".recover." + path.get_extension()
	err = DirAccess.copy_absolute(path + ".previous", staged)
	if err == OK:
		var scene := load_scene(staged)
		if scene == null: err = ERR_FILE_CORRUPT
		else: scene.free()
	if err == OK: err = preload("res://scripts/world3d/atomic_file.gd").publish(staged, path)
	_remove_file(staged)
	_remove_tree(path + ".save-lock")
	return err

static func _save_version(root: Node, gltf_path: String) -> Error:
	var dir := gltf_path.get_base_dir()
	var file_name := gltf_path.get_file()
	var version := "%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var relative := file_name + ".versions/" + version
	var staging := dir.path_join(relative)
	var err := DirAccess.make_dir_recursive_absolute(staging)
	if err != OK: return err
	var staged := staging.path_join(file_name)
	err = save_scene(root, staged)
	if err != OK:
		_remove_tree(staging)
		return err
	if save_fault.is_valid() and save_fault.call("resources_ready"): return ERR_FILE_CANT_WRITE
	if gltf_path.get_extension().to_lower() == "gltf":
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(staged))
		if not parsed is Dictionary: return ERR_FILE_CORRUPT
		for section in ["buffers", "images"]:
			for item in parsed.get(section, []):
				var uri := str(item.get("uri", ""))
				if uri.is_empty() or uri.begins_with("data:"): continue
				if uri.is_absolute_path() or uri.contains(":") or ".." in uri.split("/"): return ERR_INVALID_DATA
				if not FileAccess.file_exists(staging.path_join(uri)): return ERR_FILE_NOT_FOUND
				item["uri"] = relative + "/" + uri
		var file := FileAccess.open(staged, FileAccess.WRITE)
		if file == null: return FileAccess.get_open_error()
		file.store_string(JSON.stringify(parsed))
		file.flush()
		err = file.get_error()
		file.close()
		if err != OK: return err
	if save_fault.is_valid() and save_fault.call("before_publish"): return ERR_FILE_CANT_WRITE
	# Dependencies are immutable and remain available to the current/previous map.
	# A crash anywhere above leaves the currently published map untouched.
	root.set_meta("published_signature", FileAccess.get_sha256(staged))
	return preload("res://scripts/world3d/atomic_file.gd").publish(staged, gltf_path)


static func _buffer_uris(gltf_path: String) -> PackedStringArray:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(gltf_path))
	var uris := PackedStringArray()
	if not parsed is Dictionary:
		return uris
	# Only resource dependencies are files. An extras field named uri is data.
	for section in ["buffers", "images"]:
		for item in parsed.get(section, []):
			var uri := str(item.get("uri", ""))
			if uri.is_empty() or uri.begins_with("data:") or uri.contains("://"):
				continue
			if not uris.has(uri):
				uris.append(uri)
	return uris


static func _move_aside(path: String, backups: Array) -> Error:
	if not FileAccess.file_exists(path):
		return OK
	var backup := path + ".bak_%d" % Time.get_ticks_usec()
	var err := DirAccess.rename_absolute(path, backup)
	if err == OK:
		backups.append([backup, path])
	return err


static func _restore(backups: Array) -> void:
	for pair in backups:
		var backup := str(pair[0])
		var live := str(pair[1])
		if FileAccess.file_exists(live):
			_remove_file(live)
		DirAccess.rename_absolute(backup, live)


static func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var child := path.path_join(entry)
			if dir.current_is_dir():
				_remove_tree(child)
			else:
				_remove_file(child)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)


static func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


static func load_scene(gltf_path: String) -> Node:
	if gltf_path.is_empty() or not FileAccess.file_exists(gltf_path):
		push_error("World glTF is missing: %s" % gltf_path)
		return null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(gltf_path, state, 0, gltf_path.get_base_dir())
	if err != OK:
		var bytes := FileAccess.get_file_as_bytes(gltf_path)
		err = doc.append_from_buffer(bytes, gltf_path.get_base_dir(), state)
	if err != OK:
		push_error("World glTF failed to load (%s): %s" % [error_string(err), gltf_path])
		return null
	return generate_scene(doc, state)


static func find_named(node: Node, wanted: String) -> Node:
	if node == null:
		return null
	if str(node.name) == wanted:
		return node
	for child in node.get_children():
		var found := find_named(child, wanted)
		if found != null:
			return found
	return null


static func extras_of(node: Node) -> Dictionary:
	if node == null or not node.has_meta("extras"):
		return {}
	var raw: Variant = node.get_meta("extras")
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	return raw


static func generate_scene(document: GLTFDocument, state: GLTFState) -> Node:
	var scene := document.generate_scene(state)
	if scene == null: return null
	var raw_nodes: Array = state.json.get("nodes", [])
	for i in state.nodes.size():
		var gltf_node: GLTFNode = state.nodes[i]
		if gltf_node.mesh < 0: continue
		var weights: Variant = state.meshes[gltf_node.mesh].blend_weights
		if i < raw_nodes.size() and raw_nodes[i].has("weights"): weights = raw_nodes[i].weights
		if weights.is_empty(): continue
		var mapped: Node = state.get_scene_node(i)
		var visual: MeshInstance3D
		if is_instance_valid(mapped): visual = mapped as MeshInstance3D
		else:
			visual = find_named(scene, gltf_node.resource_name) as MeshInstance3D
		if visual == null or not visual.mesh is ArrayMesh: continue
		for blend in mini(visual.mesh.get_blend_shape_count(), weights.size()):
			visual.set_blend_shape_value(blend, float(weights[blend]))
	return scene


static func preserve_node_morph_defaults(state: GLTFState) -> void:
	var raw_nodes: Array = state.json.get("nodes", [])
	var meshes := state.meshes
	for i in mini(raw_nodes.size(), state.nodes.size()):
		if not raw_nodes[i].has("weights") or state.nodes[i].mesh < 0: continue
		var copy: GLTFMesh = meshes[state.nodes[i].mesh].duplicate()
		copy.blend_weights = PackedFloat32Array(raw_nodes[i].weights)
		state.nodes[i].mesh = meshes.size()
		meshes.append(copy)
	state.meshes = meshes
