extends SceneTree
## Offline readback audit; private-desktop GPU only. Never saves/instantiates
## products or invokes the global grass pool. One private model at a time.
const Compiled = preload("res://scripts/world3d/compiled_asset_cache.gd")
const Reader = preload("res://scripts/world3d/compiled_asset_preparation.gd")
const Footprint = preload("res://scripts/world3d/compiled_asset_footprint.gd")
const Paths = preload("res://scripts/world3d/map_paths.gd")
const Drainer = preload("res://scripts/world3d/asset_worker_drainer.gd")
var output := ""
var input := ""
var content_root := ""
var report: Dictionary = {"version":1, "failures":0, "checks":[], "models":[], "scope":"Offline exact native-resource content audit, not an entry benchmark or permission to merge materials/geometry."}
var groups: Dictionary = {"textures":{}, "meshes":{}}

func _initialize() -> void: run.call_deferred()

func check(ok: bool, label_: String) -> bool:
	report.checks.append({"ok":ok, "label":label_})
	print("PASS " if ok else "FAIL ", label_)
	if not ok: report.failures += 1
	return ok

static func digest(bytes: PackedByteArray) -> String:
	var hash_ := HashingContext.new()
	hash_.start(HashingContext.HASH_SHA256); hash_.update(bytes)
	return hash_.finish().hex_encode()

static func packed_bytes(value: Variant) -> int:
	match typeof(value):
		TYPE_PACKED_BYTE_ARRAY: return value.size()
		TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_FLOAT32_ARRAY: return value.size() * 4
		TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT64_ARRAY: return value.size() * 8
		TYPE_PACKED_VECTOR2_ARRAY: return value.size() * 8
		TYPE_PACKED_VECTOR3_ARRAY: return value.size() * 12
		TYPE_PACKED_VECTOR4_ARRAY, TYPE_PACKED_COLOR_ARRAY: return value.size() * 16
	return 0

static func arrays_fingerprint(arrays: Array) -> Dictionary:
	var channels: Array = []; var size := 0
	for index in arrays.size():
		var value: Variant = arrays[index]
		var count: int = packed_bytes(value)
		size += count
		channels.append({"slot":index, "type":typeof(value), "bytes":count, "sha256":digest(var_to_bytes(value))})
	return {"channels":channels, "bytes":size, "sha256":digest(var_to_bytes(channels))}

func image_fingerprint(image: Image) -> Dictionary:
	if image == null or image.is_empty(): return {}
	var pixels := image.get_data()
	var pixel_sha := digest(pixels)
	var layout: Array = [image.get_width(), image.get_height(), image.get_format(), image.has_mipmaps(), image.get_mipmap_count()]
	var mips: Array = []
	for mip in image.get_mipmap_count() + 1:
		var begin := image.get_mipmap_offset(mip)
		var end: int = image.get_mipmap_offset(mip + 1) if mip < image.get_mipmap_count() else pixels.size()
		mips.append({"level":mip, "offset":begin, "bytes":end - begin, "sha256":digest(pixels.slice(begin, end))})
	return {"key":digest(var_to_bytes([layout, pixel_sha])), "width":image.get_width(), "height":image.get_height(), "format":image.get_format(), "mipmaps":image.has_mipmaps(), "mipmap_count":image.get_mipmap_count(), "bytes":pixels.size(), "pixels_sha256":pixel_sha, "mips":mips}

func mesh_fingerprint(mesh: ArrayMesh) -> Dictionary:
	var surfaces: Array = []; var size := 0; var names: Array = []
	# Mesh.surface_get_lods is not script-bound. Native _surfaces preserves each
	# distance and its complete index byte array, with no Resource in the hash.
	var stored_surfaces: Array = mesh.get("_surfaces")
	for index in mesh.get_blend_shape_count(): names.append(str(mesh.get_blend_shape_name(index)))
	for surface in mesh.get_surface_count():
		var arrays: Dictionary = arrays_fingerprint(mesh.surface_get_arrays(surface))
		var blends: Array = []
		for blend: Array in mesh.surface_get_blend_shape_arrays(surface):
			var item: Dictionary = arrays_fingerprint(blend); blends.append(item); size += int(item.bytes)
		var lods: Array = []
		var source_lods: Array = stored_surfaces[surface].get("lods", [])
		for level in range(0, source_lods.size(), 2):
			var indices: Variant = source_lods[level + 1]
			var count := packed_bytes(indices); size += count
			lods.append({"distance":float(source_lods[level]), "type":typeof(indices), "bytes":count, "sha256":digest(var_to_bytes(indices))})
		size += int(arrays.bytes)
		surfaces.append({"primitive":mesh.surface_get_primitive_type(surface), "format":int(mesh.surface_get_format(surface)), "arrays":arrays, "blend_shapes":blends, "lods":lods})
	return {"key":digest(var_to_bytes([int(mesh.blend_shape_mode), names, surfaces])), "bytes":size, "surfaces":surfaces, "blend_shape_names":names, "blend_shape_mode":int(mesh.blend_shape_mode), "material_excluded":true}

func walk(value: Variant, model: Dictionary, state: Dictionary, depth: int = 0) -> void:
	state.visits += 1
	if depth > 32 or state.visits > 2000000:
		state.valid = false; return
	if value is Resource:
		var id: int = value.get_instance_id()
		if state.seen.has(id): return
		state.seen[id] = true
		state.weak.append({"ref":weakref(value), "class":value.get_class()})
		var local_id: String = "r%d" % state.seen.size()
		if value is ImageTexture or value is Image:
			var image: Image = value.get_image() if value is ImageTexture else value
			var texture: Dictionary = image_fingerprint(image)
			if texture.is_empty(): state.valid = false; return
			texture.local_id = local_id; texture.resource_class = value.get_class(); texture.resource_name = str(value.resource_name)
			if value is ImageTexture:
				texture.texture_width = value.get_width(); texture.texture_height = value.get_height(); texture.declared_format = value.get_format()
			model.textures.append(texture); state.texture_ids[id] = texture
			# An ImageTexture's image property would request another GPU readback
			# copy, not a second stored allocation. Count this texture only once.
			return
		if value is ArrayMesh:
			var geometry: Dictionary = mesh_fingerprint(value)
			geometry.local_id = local_id; geometry.resource_name = str(value.resource_name)
			model.meshes.append(geometry)
		elif value is StandardMaterial3D:
			var material: Dictionary = {"local_id":local_id, "resource_name":str(value.resource_name), "texture_slots":[]}
			for property: Dictionary in value.get_property_list():
				if int(property.usage) & PROPERTY_USAGE_STORAGE == 0: continue
				var slot: Variant = value.get(property.name)
				if slot is Texture2D:
					walk(slot, model, state, depth + 1)
					var texture: Dictionary = state.texture_ids.get(slot.get_instance_id(), {})
					if texture.is_empty(): state.valid = false; continue
					material.texture_slots.append({"slot":str(property.name), "texture_id":texture.local_id, "texture_key":texture.key})
			model.materials.append(material)
		else: state.valid = false; return
		for property: Dictionary in value.get_property_list():
			if int(property.usage) & PROPERTY_USAGE_STORAGE: walk(value.get(property.name), model, state, depth + 1)
	elif value is Dictionary:
		for key in value:
			walk(key, model, state, depth + 1); walk(value[key], model, state, depth + 1)
	elif value is Array:
		for child in value: walk(child, model, state, depth + 1)
	elif value is Object or value is Callable or value is Signal or value is RID: state.valid = false

func collect(packed: PackedScene, model: Dictionary) -> Array:
	var state: Dictionary = {"seen":{}, "texture_ids":{}, "weak":[], "visits":0, "valid":true}
	var scene := packed.get_state()
	model.nodes = scene.get_node_count()
	for node in scene.get_node_count():
		for property in scene.get_node_property_count(node): walk(scene.get_node_property_value(node, property), model, state)
	check(state.valid, model.path + ": supported complete resource graph")
	model.resource_count = state.seen.size(); model.graph_valid = state.valid
	return state.weak

func register_model(model: Dictionary, model_index: int) -> void:
	model.content_summary = {}
	for kind in ["textures", "meshes"]:
		var seen: Dictionary = {}; var total := 0; var unique := 0
		for resource: Dictionary in model[kind]:
			var key: String = resource.key; var size: int = resource.bytes
			total += size
			if not seen.has(key): seen[key] = true; unique += size
			if not groups[kind].has(key): groups[kind][key] = {"key":key, "bytes":size, "occurrences":[], "models":{}}
			var group: Dictionary = groups[kind][key]
			group.occurrences.append({"model":model_index, "path":model.path, "resource_id":resource.local_id})
			group.models[model_index] = true
		model.content_summary[kind] = {"resource_objects":model[kind].size(), "distinct_contents":seen.size(), "logical_bytes":total, "unique_content_bytes":unique, "within_model_duplicate_bytes":total - unique}

func summarize() -> void:
	var summary: Dictionary = {}; var repeated: Dictionary = {}; var pairs: Dictionary = {}
	for kind in ["textures", "meshes"]:
		var total := 0; var within := 0; var cross := 0; var unique := 0
		var duplicates: Array = []
		for key: String in groups[kind]:
			var group: Dictionary = groups[kind][key]
			var count: int = group.occurrences.size(); var model_count: int = group.models.size(); var size: int = group.bytes
			total += count * size; unique += size
			within += (count - model_count) * size; cross += (model_count - 1) * size
			if count > 1: duplicates.append({"key":key, "bytes":size, "resource_objects":count, "model_count":model_count, "occurrences":group.occurrences})
			var models: Array = group.models.keys(); models.sort()
			for left in models.size():
				for right in range(left + 1, models.size()):
					var pair_key: String = "%d:%d" % [models[left], models[right]]
					if not pairs.has(pair_key): pairs[pair_key] = {"left":models[left], "right":models[right], "shared_texture_bytes":0, "shared_mesh_bytes":0, "texture_keys":[], "mesh_keys":[]}
					var pair: Dictionary = pairs[pair_key]
					pair["shared_texture_bytes" if kind == "textures" else "shared_mesh_bytes"] += size
					pair["texture_keys" if kind == "textures" else "mesh_keys"].append(key)
		duplicates.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.bytes) * int(a.model_count) > int(b.bytes) * int(b.model_count))
		repeated[kind] = duplicates
		summary[kind] = {"resource_object_bytes":total, "globally_unique_content_bytes":unique, "within_model_duplicate_bytes":within, "cross_model_duplicate_bytes_after_within_dedup":cross, "total_duplicate_bytes":within + cross, "distinct_contents":groups[kind].size()}
	var ranked: Array = pairs.values()
	ranked.sort_custom(func(a: Dictionary, b: Dictionary): return a.shared_texture_bytes > b.shared_texture_bytes)
	for pair: Dictionary in ranked:
		pair.left_path = report.models[int(pair.left)].path; pair.right_path = report.models[int(pair.right)].path
	report.summary = summary; report.duplicate_groups = repeated; report.model_pairs = ranked
	report.byte_semantics = "Texture bytes are exact native GPU-readback Image bytes including every mip, grouped by format/dimensions/mips/full SHA. Mesh bytes sum complete unpacked surface/blend arrays plus native LOD index bytes; materials/transforms are excluded. Logical duplication is not measured RSS/VRAM or guaranteed Cook savings. Existing aliases within one model count once."

func audit_one(path: String) -> Dictionary:
	var identity: Dictionary = Footprint._identity(path, content_root)
	if not check(not identity.is_empty(), path + ": current native manifest identity"): return {}
	var worker := Thread.new()
	if not check(worker.start(Reader.read.bind(path, identity, content_root)) == OK, path + ": independent native read worker"): return {}
	while worker.is_alive(): await process_frame
	var packet: Dictionary = worker.wait_to_finish()
	Drainer.synchronize_transfer()
	var model: Dictionary = {"path":path, "source_sha":identity.source_sha, "payload_sha":identity.payload_sha, "generator":identity.generator, "payload_bytes":identity.bytes, "product":identity.product, "textures":[], "meshes":[], "materials":[]}
	var weak: Array = []
	if check(packet.get("error", FAILED) == OK and packet.get("packed") is PackedScene and not packet.get("fallback_required", false), path + ": full native/source verification"):
		weak.append({"ref":weakref(packet.packed), "class":"PackedScene"})
		weak.append_array(collect(packet.packed, model))
		model.source_unchanged = FileAccess.get_sha256(path) == identity.source_sha
		model.product_unchanged = FileAccess.get_sha256(str(identity.product)) == identity.payload_sha
		check(model.source_unchanged and model.product_unchanged, path + ": full source/product hashes unchanged after readback")
	Drainer.synchronize_transfer(); packet.clear(); Drainer.synchronize_transfer()
	await process_frame; await process_frame
	var alive: Array = []
	for entry: Dictionary in weak:
		if entry.ref.get_ref() != null: alive.append(str(entry["class"]))
	model.retained_resources = alive
	check(alive.is_empty(), path + ": private PackedScene and resource graph released before next model")
	return model

func run() -> void:
	content_root = Paths.external_root()
	input = content_root.path_join("review_artifacts/native_budget_20261010/initial_paths.json")
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--input="): input = argument.trim_prefix("--input=").replace("\\", "/").simplify_path()
		elif argument.begins_with("--output="): output = argument.trim_prefix("--output=").replace("\\", "/").simplify_path()
	var reviews := content_root.path_join("review_artifacts")
	if not check(Paths.allowed(output, reviews) and output.get_extension() == "json" and output != input, "explicit output JSON stays in review artifacts"): quit(1); return
	if not check(DisplayServer.get_name() != "headless" and Paths.allowed(input, reviews), "private GPU and allowed input report"): quit(1); return
	var file := FileAccess.open(input, FileAccess.READ)
	if not check(file != null and file.get_length() <= 65536, "bounded initial-path report"): quit(1); return
	var raw: Variant = JSON.parse_string(file.get_as_text()); file.close()
	if not check(raw is Array and raw.size() == 9, "input contains exactly nine initial models"): quit(1); return
	var paths: Array[String] = []; var seen: Dictionary = {}
	for value in raw:
		if not check(value is String and Paths.allowed(value, content_root) and value.get_extension().to_lower() == "glb" and FileAccess.file_exists(value) and not seen.has(value), "unique allowed existing initial GLB"): quit(1); return
		seen[value] = true; paths.append(value)
	report.input = input; report.input_sha = FileAccess.get_sha256(input); report.engine = Engine.get_version_info()
	report.renderer = ProjectSettings.get_setting("rendering/renderer/rendering_method", ""); report.executable = OS.get_executable_path()
	Engine.max_fps = 60
	create_timer(300).timeout.connect(func(): push_error("COMPILED_RESOURCE_SHARING timeout"); quit(2))
	var started := Time.get_ticks_usec()
	for path: String in paths:
		var model: Dictionary = await audit_one(path)
		if model.is_empty(): break
		register_model(model, report.models.size()); report.models.append(model)
		print("AUDITED_NATIVE ", path, " textures=", model.textures.size(), " meshes=", model.meshes.size())
	summarize()
	check(report.models.size() == paths.size(), "all nine model inventories completed")
	check(FileAccess.get_sha256(input) == report.input_sha, "input selection report remains unchanged")
	report.elapsed_us = Time.get_ticks_usec() - started
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	file = FileAccess.open(output, FileAccess.WRITE)
	if file == null: push_error("Cannot write audit output"); quit(1); return
	file.store_string(JSON.stringify(report, "\t")); file.close()
	print("COMPILED_RESOURCE_SHARING_FINISHED failures=", report.failures, " output=", output)
	quit(0 if report.failures == 0 else 1)
