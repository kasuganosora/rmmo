extends RefCounted
## Isolated experiment: immutable texture closure + private native scene graphs.
## No production cache/map is written. Build on main; Pool reads may be parallel.
## The caller must finish all reads/instances before disposing the pool on main.
const Paths = preload("res://scripts/world3d/map_paths.gd")
const Compiled = preload("res://scripts/world3d/compiled_asset_cache.gd")
const SCRIPT_PATH = "res://tools/shared_texture_cook_candidate.gd"
const EXPERIMENT_ROOT = "D:/code/rmmo_runtime/review_artifacts/shared_resource_20261010/cook"
const VERSION = 1
const BINDINGS = &"_shared_texture_cook_bindings_v1"
const MAX_FILE_BYTES = 1024 * 1024 * 1024
const MAX_MANIFEST_BYTES = 4 * 1024 * 1024
const MAX_TEXTURES = 4096
const MAX_TOTAL_BYTES = 8 * 1024 * 1024 * 1024

static func generator() -> String:
	return JSON.stringify([VERSION, Engine.get_version_info(), Compiled.generator(), FileAccess.get_sha256(SCRIPT_PATH)]).sha256_text()

static func _failure(reason: String, code: int = ERR_INVALID_DATA) -> Dictionary:
	return {"error": code, "reason": reason}

static func _normalize(path: String) -> String:
	return path.replace("\\", "/").simplify_path()

static func _experimental(path: String) -> bool:
	return path.is_absolute_path() and Paths.allowed(_normalize(path), EXPERIMENT_ROOT)

static func _sha(value: Variant) -> bool:
	return Compiled._sha(value)

static func _integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) == float(int(value)) and value >= low and value <= high

static func _keys(value: Dictionary, expected: Array) -> bool:
	if value.size() != expected.size(): return false
	for key in expected:
		if not value.has(key): return false
	return true

static func _read_json(path: String, limit: int) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return _failure("json_open")
	if file.get_length() <= 0 or file.get_length() > limit:
		file.close(); return _failure("json_size")
	var value: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not value is Dictionary: return _failure("json_schema")
	return {"error": OK, "value": value}

static func _record_valid(record: Variant, suffix: String, semantic_id: String = "") -> bool:
	if not record is Dictionary or not _keys(record, ["file", "sha", "bytes"]): return false
	if not _sha(record.sha) or not _integer(record.bytes, 1, MAX_FILE_BYTES): return false
	var expected := (str(record.sha) if semantic_id.is_empty() else semantic_id) + suffix
	return record.file is String and record.file == expected

static func _verify_file(path: String, record: Dictionary, root_path: String, closed: bool = true) -> Dictionary:
	if not Paths.allowed(path, root_path): return _failure("file_outside_root")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return _failure("file_missing")
	var length := file.get_length(); file.close()
	if length != int(record.bytes): return _failure("file_size")
	if FileAccess.get_sha256(path) != record.sha: return _failure("file_sha")
	if closed and not ResourceLoader.get_dependencies(path).is_empty(): return _failure("external_dependency")
	return {"error": OK}

## Canonicalize metadata without converting numeric/packed-array value types.
## Reject resource/object metadata instead of silently dropping its semantics.
static func _canonical(value: Variant, depth: int = 0) -> Dictionary:
	if depth > 32: return _failure("metadata_depth")
	var kind := typeof(value)
	if kind in [TYPE_OBJECT, TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID]: return _failure("unsupported_metadata")
	if value is Dictionary:
		var key_script: Variant = value.get_typed_key_script()
		var value_script: Variant = value.get_typed_value_script()
		if key_script != null or value_script != null: return _failure("scripted_dictionary_metadata")
		var key_type := [value.get_typed_key_builtin(), value.get_typed_key_class_name(), key_script]
		var value_type := [value.get_typed_value_builtin(), value.get_typed_value_class_name(), value_script]
		var pairs: Array = []
		for key in value:
			var ck := _canonical(key, depth + 1)
			var cv := _canonical(value[key], depth + 1)
			if ck.error != OK or cv.error != OK: return _failure("unsupported_dictionary_metadata")
			pairs.append([var_to_bytes(ck.value).hex_encode(), ck.value, cv.value])
		pairs.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
		return {"error": OK, "value": [kind, key_type, value_type, pairs]}
	if value is Array:
		if value.get_typed_script() != null: return _failure("scripted_array_metadata")
		var items: Array = []
		for item in value:
			var child := _canonical(item, depth + 1)
			if child.error != OK: return child
			items.append(child.value)
		return {"error": OK, "value": [kind, value.get_typed_builtin(), value.get_typed_class_name(), items]}
	return {"error": OK, "value": [kind, value]}

static func _resource_semantics(resource: Resource, skip: Array) -> Dictionary:
	var properties: Dictionary = {}
	for info in resource.get_property_list():
		var name := str(info.name)
		if (int(info.usage) & PROPERTY_USAGE_STORAGE) == 0 or name in skip: continue
		var converted := _canonical(resource.get(info.name))
		if converted.error != OK: return _failure("property_semantics:" + name)
		properties[name] = converted.value
	# Keep these explicit even if an engine version changes their usage flags.
	properties["resource_name"] = [TYPE_STRING, resource.resource_name]
	properties["resource_local_to_scene"] = [TYPE_BOOL, resource.resource_local_to_scene]
	var metadata: Dictionary = {}
	for key in resource.get_meta_list():
		var converted := _canonical(resource.get_meta(key))
		if converted.error != OK: return _failure("metadata_semantics:" + str(key))
		metadata[str(key)] = converted.value
	return _canonical([properties, metadata])

## The identity covers every mip byte, pixel layout, actual texture dimensions,
## all non-transient storage properties, resource name/locality and metadata.
## get_image/readback is OFFLINE ONLY, never performed by Pool.read().
static func _texture_identity(texture: ImageTexture) -> Dictionary:
	if texture.get_script() != null: return _failure("texture_script")
	var image := texture.get_image()
	if image == null or image.is_empty(): return _failure("empty_texture")
	var transient := ["resource_path", "resource_scene_unique_id", "scene_unique_id"]
	var texture_semantics := _resource_semantics(texture, transient + ["image"])
	var image_semantics := _resource_semantics(image, transient + ["data"])
	if texture_semantics.error != OK: return texture_semantics
	if image_semantics.error != OK: return image_semantics
	var pixels := image.get_data()
	if pixels.is_empty() or pixels.size() > MAX_FILE_BYTES: return _failure("pixel_size")
	var layout := [image.get_width(), image.get_height(), image.get_format(), image.has_mipmaps(), image.get_mipmap_count(), texture.get_width(), texture.get_height(), pixels.size()]
	var offsets: Array = []
	for level in range(image.get_mipmap_count() + 1): offsets.append(image.get_mipmap_offset(level))
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(var_to_bytes([VERSION, layout, offsets, texture_semantics.value, image_semantics.value]))
	context.update(pixels)
	return {"error": OK, "identity": context.finish().hex_encode(), "pixel_bytes": pixels.size()}

static func _walk(value: Variant, seen: Dictionary, graph: Dictionary, depth: int = 0) -> void:
	if graph.error != OK: return
	if depth > 32: graph.error = ERR_INVALID_DATA; return
	if value is Resource:
		var id: int = value.get_instance_id()
		if seen.has(id): return
		seen[id] = true
		if value is ImageTexture:
			graph.textures.append(value); return
		if value is Image:
			graph.standalone_images += 1; return
		if value is StandardMaterial3D: graph.materials.append(value)
		for info in value.get_property_list():
			if int(info.usage) & PROPERTY_USAGE_STORAGE: _walk(value.get(info.name), seen, graph, depth + 1)
	elif value is Array:
		for item in value: _walk(item, seen, graph, depth + 1)
	elif value is Dictionary:
		for key in value:
			_walk(key, seen, graph, depth + 1); _walk(value[key], seen, graph, depth + 1)

static func _graph(packed: PackedScene) -> Dictionary:
	var result := {"error": OK, "materials": [], "textures": [], "standalone_images": 0}
	if not Compiled._valid_packed(packed): return _failure("unsupported_scene")
	var seen: Dictionary = {}; var state := packed.get_state()
	for node in state.get_node_count():
		for property in state.get_node_property_count(node):
			_walk(state.get_node_property_value(node, property), seen, result)
	return result

static func _texture_slots(material: StandardMaterial3D) -> Dictionary:
	var result: Dictionary = {}
	for info in material.get_property_list():
		if (int(info.usage) & PROPERTY_USAGE_STORAGE) != 0 and int(info.type) == TYPE_OBJECT and "Texture" in str(info.get("hint_string", "")):
			result[str(info.name)] = true
	return result

static func _remove_own(path: String) -> void:
	if _experimental(path) and FileAccess.file_exists(path): DirAccess.remove_absolute(path)

static func _temporary(folder: String, suffix: String) -> String:
	return folder.path_join("staged_%d_%d_%d%s" % [OS.get_process_id(), OS.get_thread_caller_id(), Time.get_ticks_usec(), suffix])

static func _publish_staged(staged: String, folder: String, suffix: String, identity: String = "") -> Dictionary:
	if not _experimental(staged) or not _experimental(folder): return _failure("publish_root")
	var file := FileAccess.open(staged, FileAccess.READ)
	if file == null: _remove_own(staged); return _failure("staged_open")
	var size := file.get_length(); file.close()
	if size <= 0 or size > MAX_FILE_BYTES: _remove_own(staged); return _failure("staged_size")
	var digest := FileAccess.get_sha256(staged)
	if not _sha(digest): _remove_own(staged); return _failure("staged_sha")
	var record := {"file": (digest if identity.is_empty() else identity) + suffix, "sha": digest, "bytes": size}
	var destination := folder.path_join(record.file)
	if FileAccess.file_exists(destination):
		var existing := _verify_file(destination, record, folder, suffix != ".json")
		_remove_own(staged)
		if existing.error != OK: return _failure("immutable_product_conflict")
	else:
		var error := DirAccess.rename_absolute(staged, destination)
		if error != OK:
			_remove_own(staged)
			if _verify_file(destination, record, folder, suffix != ".json").error != OK: return _failure("publish_failed", error)
	return {"error": OK, "record": record, "path": destination}

static func _save_resource(resource: Resource, folder: String, suffix: String, identity: String = "") -> Dictionary:
	var staged := _temporary(folder, suffix)
	var error := ResourceSaver.save(resource, staged, ResourceSaver.FLAG_BUNDLE_RESOURCES | ResourceSaver.FLAG_COMPRESS)
	if error != OK: _remove_own(staged); return _failure("resource_save", error)
	if not ResourceLoader.get_dependencies(staged).is_empty(): _remove_own(staged); return _failure("saved_external_dependency")
	return _publish_staged(staged, folder, suffix, identity)

static func _save_texture(texture: ImageTexture, identity: String, folder: String) -> Dictionary:
	var path := folder.path_join(identity + ".res")
	if not _experimental(path): return _failure("texture_output_path")
	if not FileAccess.file_exists(path): return _save_resource(texture, folder, ".res", identity)
	# Across independent model cooks, the canonical semantic object is immutable.
	# Verify it in full before reuse; no serialized UID/path accident changes it.
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return _failure("existing_texture_open")
	var bytes := file.get_length(); file.close()
	if bytes <= 0 or bytes > MAX_FILE_BYTES: return _failure("existing_texture_size")
	var digest := FileAccess.get_sha256(path)
	var record := {"file": identity + ".res", "sha": digest, "bytes": bytes}
	if _verify_file(path, record, folder).error != OK: return _failure("existing_texture_closure")
	var loaded: Resource = ResourceLoader.load(path, "ImageTexture", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	if not loaded is ImageTexture: return _failure("existing_texture_type")
	var actual := _texture_identity(loaded as ImageTexture)
	if actual.error != OK or actual.identity != identity or not _experimental(path) or FileAccess.get_sha256(path) != digest: return _failure("existing_texture_identity")
	return {"error": OK, "record": record, "path": path}

## source_path is a GLB with an ALREADY BUILT, verified native compiled product.
## This method never builds/updates that product or its index.
static func build(source_path: String, output_directory: String) -> Dictionary:
	var started := Time.get_ticks_usec()
	if OS.get_thread_caller_id() != OS.get_main_thread_id(): return _failure("build_requires_main")
	if DisplayServer.get_name() == "headless": return _failure("offline_readback_requires_graphics")
	var folder := _normalize(output_directory); var source := _normalize(source_path)
	var content_root := Paths.external_root()
	if not _experimental(folder) or not Paths.allowed(source, content_root): return _failure("build_paths")
	var index_path := Compiled.index_path(source, content_root)
	if not Paths.allowed(index_path, Compiled.directory(content_root)): return _failure("native_index_path")
	var index_read := _read_json(index_path, 8192)
	if index_read.error != OK: return _failure("native_index_missing")
	var index: Dictionary = index_read.value
	if index.get("version") != Compiled.VERSION or index.get("generator") != Compiled.generator() or not _sha(index.get("source_sha")) or not _sha(index.get("payload_sha")) or not _integer(index.get("bytes"), 1, MAX_FILE_BYTES): return _failure("native_index_schema")
	var index_sha := FileAccess.get_sha256(index_path)
	var source_sha := FileAccess.get_sha256(source)
	if source_sha != index.source_sha: return _failure("source_changed_before_build")
	var parent_path := Compiled.directory(content_root).path_join(str(index.payload_sha) + ".scn")
	var parent_record := {"file": parent_path.get_file(), "sha": index.payload_sha, "bytes": index.bytes}
	if _verify_file(parent_path, parent_record, Compiled.directory(content_root)).error != OK: return _failure("native_product_integrity")
	var resource: Resource = ResourceLoader.load(parent_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	if not resource is PackedScene: return _failure("native_product_type")
	var packed := resource as PackedScene
	var graph := _graph(packed)
	if graph.error != OK: return graph
	if graph.standalone_images != 0: return {"error": ERR_INVALID_DATA, "reason": "unsupported_standalone_images", "standalone_images": graph.standalone_images}
	if DirAccess.make_dir_recursive_absolute(folder) != OK or not _experimental(folder): return _failure("output_directory")
	var textures: Dictionary = {}; var seen_textures: Dictionary = {}
	var binding_count := 0; var pixel_bytes := 0; var total_bytes := 0
	for item in graph.materials:
		var material := item as StandardMaterial3D
		if material.has_meta(BINDINGS): return _failure("reserved_material_metadata")
		var bindings: Dictionary = {}
		for slot in _texture_slots(material):
			var value: Variant = material.get(slot)
			if value == null: continue
			if not value is ImageTexture: return _failure("unsupported_texture_type")
			var texture := value as ImageTexture; var id := texture.get_instance_id()
			var identity: String = str(seen_textures.get(id, ""))
			if identity.is_empty():
				var identity_result := _texture_identity(texture)
				if identity_result.error != OK: return identity_result
				identity = identity_result.identity; seen_textures[id] = identity
				if not textures.has(identity):
					if textures.size() >= MAX_TEXTURES: return _failure("texture_count")
					var saved := _save_texture(texture, identity, folder)
					if saved.error != OK: return saved
					textures[identity] = saved.record
					pixel_bytes += int(identity_result.pixel_bytes); total_bytes += int(saved.record.bytes)
					if total_bytes > MAX_TOTAL_BYTES: return _failure("closure_capacity")
			bindings[slot] = identity
			material.set(slot, null); binding_count += 1
		if not bindings.is_empty(): material.set_meta(BINDINGS, bindings)
	var stripped := _graph(packed)
	if stripped.error != OK: return stripped
	if not stripped.textures.is_empty() or stripped.standalone_images != 0: return {"error": ERR_INVALID_DATA, "reason": "unbound_image_resources_in_scene", "standalone_images": stripped.standalone_images, "unbound_textures": stripped.textures.size()}
	var scene_saved := _save_resource(packed, folder, ".scn")
	if scene_saved.error != OK: return scene_saved
	if total_bytes + int(scene_saved.record.bytes) > MAX_TOTAL_BYTES: return _failure("closure_capacity")
	# Full checks on both sides of conversion, including the original native file.
	if not Paths.allowed(source, content_root) or not Paths.allowed(parent_path, Compiled.directory(content_root)) or not Paths.allowed(index_path, Compiled.directory(content_root)) or FileAccess.get_sha256(source) != source_sha or FileAccess.get_sha256(parent_path) != index.payload_sha or FileAccess.get_sha256(index_path) != index_sha: return _failure("source_or_parent_changed_during_build")
	var document := {"version": VERSION, "generator": generator(), "root": folder, "source_path": source, "source_sha": source_sha, "parent_payload_path": parent_path, "parent_payload_sha": index.payload_sha, "parent_generator": index.generator, "scene": scene_saved.record, "textures": textures, "material_count": graph.materials.size(), "binding_count": binding_count}
	var staged := _temporary(folder, ".json")
	var file := FileAccess.open(staged, FileAccess.WRITE)
	if file == null: return _failure("manifest_write")
	file.store_string(JSON.stringify(document, "", true, true)); file.flush()
	var write_error := file.get_error(); file.close()
	if write_error != OK: _remove_own(staged); return _failure("manifest_flush", write_error)
	# Only this final immutable manifest makes a cook usable. Failed partial cooks
	# can leave verified immutable objects, but never publish a usable descriptor.
	var manifest := _publish_staged(staged, folder, ".json")
	if manifest.error != OK: return manifest
	return {"error": OK, "descriptor": {"path": manifest.path, "sha": manifest.record.sha}, "descriptor_path": manifest.path, "stats": {"elapsed_us": Time.get_ticks_usec() - started, "unique_textures": textures.size(), "texture_bindings": binding_count, "materials": graph.materials.size(), "texture_pixel_bytes": pixel_bytes, "texture_file_bytes": total_bytes, "scene_bytes": scene_saved.record.bytes}}

static func _manifest(descriptor: Dictionary, content_root: String, expected_generator: String, parent_generator: String) -> Dictionary:
	if not _keys(descriptor, ["path", "sha"]) or not descriptor.path is String or not _sha(descriptor.sha): return _failure("descriptor_schema")
	var path := _normalize(descriptor.path)
	if not _experimental(path) or path.get_file() != str(descriptor.sha) + ".json": return _failure("descriptor_path")
	if FileAccess.get_sha256(path) != descriptor.sha: return _failure("descriptor_sha")
	var parsed := _read_json(path, MAX_MANIFEST_BYTES)
	if parsed.error != OK: return parsed
	if FileAccess.get_sha256(path) != descriptor.sha: return _failure("descriptor_changed")
	var data: Dictionary = parsed.value
	if not _keys(data, ["version", "generator", "root", "source_path", "source_sha", "parent_payload_path", "parent_payload_sha", "parent_generator", "scene", "textures", "material_count", "binding_count"]): return _failure("manifest_keys")
	if data.version != VERSION or data.generator != expected_generator or data.parent_generator != parent_generator: return _failure("manifest_generator")
	if not data.root is String or _normalize(data.root) != path.get_base_dir() or not _experimental(data.root): return _failure("manifest_root")
	if not data.source_path is String or not Paths.allowed(data.source_path, content_root) or not _sha(data.source_sha) or not _sha(data.parent_payload_sha): return _failure("manifest_source")
	if data.parent_payload_path != Compiled.directory(content_root).path_join(str(data.parent_payload_sha) + ".scn"): return _failure("manifest_parent")
	if not _record_valid(data.scene, ".scn") or not data.textures is Dictionary or data.textures.size() > MAX_TEXTURES: return _failure("manifest_products")
	if not _integer(data.material_count, 0, 65536) or not _integer(data.binding_count, 0, 65536 * 32): return _failure("manifest_counts")
	var total := int(data.scene.bytes)
	for identity in data.textures:
		if not _sha(identity) or not _record_valid(data.textures[identity], ".res", identity): return _failure("manifest_texture")
		total += int(data.textures[identity].bytes)
	if total > MAX_TOTAL_BYTES: return _failure("manifest_capacity")
	return {"error": OK, "data": data}

class Pool extends RefCounted:
	# A fresh Pool is the sharing/lifetime boundary; no global resource REUSE.
	var _ops: Script
	var _root: String = ""
	var _generator: String = ""
	var _parent_generator: String = ""
	var _mutex := Mutex.new()
	var _entries: Dictionary = {}
	var _retained: Array = []
	var _active: int = 0
	var _closed: bool = false
	var _native_texture_loads: int = 0

	func _init() -> void:
		if OS.get_thread_caller_id() != OS.get_main_thread_id():
			_closed = true; return
		_ops = load("res://tools/shared_texture_cook_candidate.gd")
		_root = _ops.Paths.external_root()
		_generator = _ops.generator()
		_parent_generator = _ops.Compiled.generator()

	func _retain(resource: Resource) -> void:
		if resource == null: return
		_mutex.lock(); _retained.append(resource); _mutex.unlock()

	func read(descriptor: Dictionary) -> Dictionary:
		_mutex.lock()
		if _closed:
			_mutex.unlock(); return {"error": ERR_UNAVAILABLE, "reason": "pool_closed", "packed": null, "stats": {}}
		_active += 1; _mutex.unlock()
		var stats := {"elapsed_us": 0, "validation_us": 0, "scene_read_us": 0, "texture_read_us": 0, "texture_wait_us": 0, "texture_pool_hits": 0, "native_texture_loads": 0, "texture_bindings": 0, "unique_textures": 0}
		var started := Time.get_ticks_usec()
		var result := _read(descriptor, stats)
		stats.elapsed_us = Time.get_ticks_usec() - started
		result.stats = stats
		if not result.has("packed"): result.packed = null
		_mutex.lock(); _active -= 1; _mutex.unlock()
		return result

	func _read(descriptor: Dictionary, stats: Dictionary) -> Dictionary:
		var validation_started := Time.get_ticks_usec()
		var manifest: Dictionary = _ops._manifest(descriptor, _root, _generator, _parent_generator)
		if manifest.error != OK: return manifest
		var data: Dictionary = manifest.data
		if FileAccess.get_sha256(data.source_path) != data.source_sha: return _ops._failure("source_changed_before_read")
		var scene_path: String = data.root.path_join(data.scene.file)
		var check: Dictionary = _ops._verify_file(scene_path, data.scene, data.root)
		if check.error != OK: return check
		stats.validation_us += Time.get_ticks_usec() - validation_started
		var scene_started := Time.get_ticks_usec()
		var resource: Resource = ResourceLoader.load(scene_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
		_retain(resource) # Includes rejected products; only main dispose releases them.
		stats.scene_read_us = Time.get_ticks_usec() - scene_started
		if not resource is PackedScene: return _ops._failure("scene_type")
		var packed := resource as PackedScene
		var graph: Dictionary = _ops._graph(packed)
		if graph.error != OK: return graph
		if graph.standalone_images != 0: return {"error": ERR_INVALID_DATA, "reason": "unsupported_standalone_images", "standalone_images": graph.standalone_images}
		if not graph.textures.is_empty() or graph.materials.size() != int(data.material_count): return _ops._failure("scene_not_stripped")
		var used: Dictionary = {}; var restored := 0
		for item in graph.materials:
			var material := item as StandardMaterial3D
			if not material.has_meta(_ops.BINDINGS): continue
			var bindings: Variant = material.get_meta(_ops.BINDINGS)
			if not bindings is Dictionary or bindings.is_empty(): return _ops._failure("binding_schema")
			var slots: Dictionary = _ops._texture_slots(material)
			for slot in bindings:
				var identity: Variant = bindings[slot]
				if not slot is String or not slots.has(slot) or material.get(slot) != null or not _ops._sha(identity) or not data.textures.has(identity): return _ops._failure("binding_identity")
				var texture_result := _texture(identity, data.textures[identity], data.root, stats)
				if texture_result.error != OK: return texture_result
				material.set(slot, texture_result.texture)
				used[identity] = true; restored += 1
			material.remove_meta(_ops.BINDINGS)
		if restored != int(data.binding_count) or used.size() != data.textures.size(): return _ops._failure("closure_binding_count")
		validation_started = Time.get_ticks_usec()
		if not _ops.Paths.allowed(scene_path, data.root) or FileAccess.get_sha256(scene_path) != data.scene.sha or not _ops.Paths.allowed(data.source_path, _root) or FileAccess.get_sha256(data.source_path) != data.source_sha: return _ops._failure("source_or_scene_changed_during_read")
		if not _ops.Compiled._valid_packed(packed): return _ops._failure("restored_scene_invalid")
		stats.validation_us += Time.get_ticks_usec() - validation_started
		stats.texture_bindings = restored; stats.unique_textures = used.size()
		return {"error": OK, "packed": packed}

	func _texture(identity: String, record: Dictionary, folder: String, stats: Dictionary) -> Dictionary:
		var entry: Dictionary
		while true:
			_mutex.lock()
			if not _entries.has(identity):
				entry = {"state": 0, "record": record.duplicate(true), "waiters": [], "texture": null, "error": OK, "reason": ""}
				_entries[identity] = entry; _mutex.unlock(); break
			entry = _entries[identity]
			if entry.record != record:
				_mutex.unlock(); return _ops._failure("semantic_object_conflict")
			if int(entry.state) != 0:
				var result := {"error": entry.error, "reason": entry.reason, "texture": entry.texture}
				_mutex.unlock(); stats.texture_pool_hits += 1; return result
			var semaphore := Semaphore.new()
			entry.waiters.append(semaphore); _mutex.unlock()
			var waited := Time.get_ticks_usec()
			semaphore.wait() # Never wait while holding the pool mutex.
			stats.texture_wait_us += Time.get_ticks_usec() - waited
		var started := Time.get_ticks_usec()
		var path := folder.path_join(record.file)
		var result: Dictionary = _ops._verify_file(path, record, folder)
		var loaded: Resource = null
		if result.error == OK:
			loaded = ResourceLoader.load(path, "ImageTexture", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
			_retain(loaded)
			stats.native_texture_loads += 1
			_mutex.lock(); _native_texture_loads += 1; _mutex.unlock()
			if not loaded is ImageTexture or loaded.get_script() != null:
				result = _ops._failure("texture_type")
			elif not _ops.Paths.allowed(path, folder) or FileAccess.get_sha256(path) != record.sha:
				result = _ops._failure("texture_changed_during_read")
		stats.texture_read_us += Time.get_ticks_usec() - started
		_mutex.lock()
		entry.error = result.error; entry.reason = result.get("reason", "")
		entry.texture = loaded if result.error == OK else null
		entry.state = 1 if result.error == OK else 2
		var waiters: Array = entry.waiters; entry.waiters = []
		var completed := {"error": entry.error, "reason": entry.reason, "texture": entry.texture}
		_mutex.unlock()
		for semaphore in waiters: semaphore.post()
		return completed

	func snapshot_stats() -> Dictionary:
		_mutex.lock()
		var result := {"active_reads": _active, "texture_entries": _entries.size(), "retained_resources": _retained.size(), "native_texture_loads": _native_texture_loads, "closed": _closed}
		_mutex.unlock(); return result

	func dispose() -> Dictionary:
		if OS.get_thread_caller_id() != OS.get_main_thread_id(): return {"error": ERR_UNAVAILABLE, "reason": "dispose_requires_main"}
		_mutex.lock()
		if _active != 0:
			_mutex.unlock(); return {"error": ERR_BUSY, "reason": "active_reads"}
		_closed = true
		var retained := _retained; var entries := _entries
		_retained = []; _entries = {}; _mutex.unlock()
		RenderingServer.force_sync()
		entries.clear(); retained.clear()
		RenderingServer.force_sync()
		return {"error": OK}
