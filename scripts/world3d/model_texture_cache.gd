extends RefCounted
## Immutable native model images. Preparation stamps pixel/layout identity;
## main-thread publication may intern textures without renderer readback.
## This is late sharing, not a replacement for a shared on-disk dependency graph.
const PIXEL_KEY := &"compiled_model_pixel_key_v1"
const MAX_KEYS := 256
static var enabled := true # Default enabled after game/editor GPU acceptance; probes can override.
static var _textures: Dictionary = {}

static func prepare_mipmaps(root: Node) -> Dictionary:
	# Import preparation only. Keep the base pixels and authored sampler filter;
	# never read textures back during publication/inter-instance sharing.
	var prepared: Dictionary = {}
	var generated := 0
	for material: StandardMaterial3D in _materials(root):
		for info: Dictionary in material.get_property_list():
			if not (int(info.usage) & PROPERTY_USAGE_STORAGE): continue
			var value: Variant = material.get(info.name)
			if not value is Texture2D or not _plain_texture(value): continue
			var normal_map := str(info.name) in ["normal_texture", "detail_normal"]
			var key := str(value.get_instance_id()) + (":normal" if normal_map else ":color")
			if not prepared.has(key):
				var image: Image = value.get_image()
				var replacement: Texture2D = value
				if image != null and not image.is_empty() and not image.has_mipmaps() and not image.is_compressed() and maxi(image.get_width(), image.get_height()) > 1:
					image = image.duplicate()
					if image.generate_mipmaps(normal_map) == OK:
						replacement = ImageTexture.create_from_image(image)
						replacement.resource_name = value.resource_name
						generated += 1
				prepared[key] = replacement
			material.set(info.name, prepared[key])
	return {"generated": generated, "texture_usages": prepared.size()}

static func pixel_key(image: Image) -> String:
	if image == null or image.is_empty(): return ""
	var hash_ := HashingContext.new()
	hash_.start(HashingContext.HASH_SHA256)
	hash_.update(var_to_bytes([1, image.get_width(), image.get_height(), image.get_format(), image.has_mipmaps()]))
	hash_.update(image.get_data())
	return hash_.finish().hex_encode()

static func _plain_texture(texture: Texture2D) -> bool:
	# Unknown metadata can carry semantic identity; leave it independent rather
	# than silently discarding it when the pixel content happens to match.
	if not texture is ImageTexture or texture.get_script() != null or texture.resource_local_to_scene: return false
	for key: StringName in texture.get_meta_list():
		if key not in [PIXEL_KEY, &"compiled_grass_pixel_key"]: return false
	return true

static func _valid_key(value: Variant) -> bool:
	if not value is String or value.length() != 64: return false
	for character in value:
		if character not in "0123456789abcdef": return false
	return true

static func _materials(root: Node) -> Array[StandardMaterial3D]:
	var result: Array[StandardMaterial3D] = []
	var seen: Dictionary = {}
	var pending: Array[Material] = []
	for mesh: MeshInstance3D in preload("res://scripts/world3d/surface_materials.gd").meshes(root):
		pending.append(mesh.material_override)
		pending.append(mesh.material_overlay)
		for slot in mesh.mesh.get_surface_count():
			# Overrides do not release the mesh's original surface material. Both
			# remain serialized/reachable (leaf backlight is a common example).
			pending.append(mesh.mesh.surface_get_material(slot))
			pending.append(mesh.get_surface_override_material(slot))
	while not pending.is_empty():
		var material: Material = pending.pop_back()
		if material == null or seen.has(material.get_instance_id()): continue
		seen[material.get_instance_id()] = true
		pending.append(material.next_pass)
		if material is StandardMaterial3D: result.append(material)
	return result

static func stamp(root: Node) -> void:
	# Offline build only; never introduce image readback into live raw fallback.
	if OS.get_thread_caller_id() != OS.get_main_thread_id(): return
	var seen: Dictionary = {}
	for material: StandardMaterial3D in _materials(root):
		for info: Dictionary in material.get_property_list():
			if not (int(info.usage) & PROPERTY_USAGE_STORAGE): continue
			var value: Variant = material.get(info.name)
			if not value is Texture2D or seen.has(value.get_instance_id()): continue
			seen[value.get_instance_id()] = value
			if not _plain_texture(value): continue
			# Never trust an author-supplied key: recompute from the actual image.
			var key := pixel_key(value.get_image())
			if not key.is_empty(): value.set_meta(PIXEL_KEY, key)

static func apply(root: Node) -> void:
	# Replacing a texture may retire its last renderer reference. Workers keep
	# their private graph intact; main publication performs sharing and retirement.
	if not enabled or OS.get_thread_caller_id() != OS.get_main_thread_id(): return
	var seen: Dictionary = {}
	var retired: Array[Texture2D] = []
	for material: StandardMaterial3D in _materials(root):
		for info: Dictionary in material.get_property_list():
			if not (int(info.usage) & PROPERTY_USAGE_STORAGE): continue
			var value: Variant = material.get(info.name)
			if not value is Texture2D or not _plain_texture(value): continue
			var key: Variant = value.get_meta(PIXEL_KEY, "")
			if not _valid_key(key): continue
			var id: int = value.get_instance_id()
			if not seen.has(id):
				var shared := _remember(key, value)
				# Retain originals through the entire rebind, including id reuse and
				# queued material setters, before main releases replaced textures.
				seen[id] = {"original": value, "shared": shared}
			var shared: Texture2D = seen[id].shared
			if shared != value:
				retired.append(value)
				material.set(info.name, shared)
	if not retired.is_empty():
		preload("res://scripts/world3d/asset_worker_drainer.gd").synchronize_transfer()
	seen.clear()
	retired.clear()

static func _remember(key: String, texture: Texture2D) -> Texture2D:
	# Main-thread-only weak interning; the pool never owns a published allocation.
	var previous: Texture2D = _textures[key].get_ref() if _textures.has(key) else null
	if previous != null: return previous
	if _textures.size() >= MAX_KEYS:
		for old: String in _textures.keys():
			if _textures[old].get_ref() == null: _textures.erase(old)
		if _textures.size() >= MAX_KEYS: _textures.erase(_textures.keys()[0])
	_textures[key] = weakref(texture)
	return texture
