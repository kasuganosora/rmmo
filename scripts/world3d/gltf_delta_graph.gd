extends RefCounted
## Pure JSON graph edits. All rejection paths precede publication. This checks
## reference safety, not binary buffer contents or the entire glTF schema.
## Index semantics: https://registry.khronos.org/glTF/specs/2.0/glTF-2.0.html
## Supported extensions are deliberately explicit. In particular meshopt, LOD,
## material variants and animation pointers require a separate audited adapter.
## extras are opaque metadata except the known instance UUID / streetlamp group.
const ARRAYS := ["nodes", "meshes", "materials", "textures", "images", "samplers", "accessors", "bufferViews", "buffers", "skins", "animations", "cameras"]
const MATERIAL_EXTENSIONS := {
	"KHR_materials_unlit": [], "KHR_materials_ior": [],
	"KHR_materials_emissive_strength": [], "KHR_materials_dispersion": [],
	"KHR_materials_pbrSpecularGlossiness": ["diffuseTexture", "specularGlossinessTexture"],
	"KHR_materials_clearcoat": ["clearcoatTexture", "clearcoatRoughnessTexture", "clearcoatNormalTexture"],
	"KHR_materials_transmission": ["transmissionTexture"], "KHR_materials_volume": ["thicknessTexture"],
	"KHR_materials_specular": ["specularTexture", "specularColorTexture"],
	"KHR_materials_sheen": ["sheenColorTexture", "sheenRoughnessTexture"],
	"KHR_materials_iridescence": ["iridescenceTexture", "iridescenceThicknessTexture"],
	"KHR_materials_anisotropy": ["anisotropyTexture"]
}
const OTHER_EXTENSIONS := ["GODOT_single_root", "KHR_mesh_quantization", "KHR_lights_punctual", "EXT_mesh_gpu_instancing", "KHR_draco_mesh_compression", "KHR_texture_basisu", "EXT_texture_webp", "EXT_texture_avif", "KHR_texture_transform"]

class References:
	extends RefCounted
	var data: Dictionary
	var offsets: Dictionary
	var error := ""
	static func _integer(value: Variant) -> bool:
		return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_finite(value) and value == floor(value))
	static func _supported(name: String) -> bool:
		return MATERIAL_EXTENSIONS.has(name) or name in OTHER_EXTENSIONS
	func fail(message: String) -> void:
		if error.is_empty(): error = message
	func ref(obj: Dictionary, key: String, domain: String, required := false, local_limit := -1) -> void:
		if not obj.has(key):
			if required: fail("Missing %s reference" % key)
			return
		var value: Variant = obj[key]
		var limit: int = local_limit if local_limit >= 0 else data.get(domain, []).size()
		if not _integer(value) or value < 0 or value >= limit:
			fail("Invalid %s.%s index: %s" % [domain, key, str(value)])
			return
		if not offsets.is_empty() and local_limit < 0: obj[key] = int(value) + int(offsets.get(domain, 0))
	func refs(obj: Dictionary, key: String, domain: String, required := false) -> void:
		if not obj.has(key):
			if required: fail("Missing %s" % key)
			return
		if not obj[key] is Array:
			fail("%s must be an array" % key); return
		for i in obj[key].size():
			var holder := {"index": obj[key][i]}
			ref(holder, "index", domain, true)
			if not offsets.is_empty(): obj[key][i] = holder.index
	func attributes(obj: Variant) -> void:
		if not obj is Dictionary:
			fail("Attributes must be an object"); return
		for key in obj: ref(obj, key, "accessors", true)
	func texture(obj: Dictionary, key: String) -> void:
		if not obj.has(key): return
		if not obj[key] is Dictionary: fail("Invalid texture info"); return
		ref(obj[key], "index", "textures", true)
	func dictionary(obj: Dictionary, key: String) -> Dictionary:
		if not obj.get(key, {}) is Dictionary:
			fail("%s must be an object" % key); return {}
		return obj.get(key, {})
	func objects(obj: Dictionary, key: String, required := false) -> Array:
		if required and not obj.has(key): fail("Missing %s" % key)
		if not obj.get(key, []) is Array:
			fail("%s must be an array" % key); return []
		for value in obj.get(key, []):
			if not value is Dictionary: fail("%s contains non-object" % key); return []
		return obj.get(key, [])
	func run() -> void:
		for key in ARRAYS + ["scenes"]: objects(data, key)
		if not error.is_empty(): return
		ref(data, "scene", "scenes")
		for scene in data.get("scenes", []): refs(scene, "nodes", "nodes")
		for node in data.get("nodes", []):
			refs(node, "children", "nodes")
			for key in ["mesh", "skin", "camera"]: ref(node, key, {"mesh":"meshes", "skin":"skins", "camera":"cameras"}[key])
		for mesh in data.get("meshes", []):
			for primitive in objects(mesh, "primitives", true):
				attributes(dictionary(primitive, "attributes"))
				ref(primitive, "indices", "accessors"); ref(primitive, "material", "materials")
				for target in objects(primitive, "targets"): attributes(target)
		for material in data.get("materials", []):
			var pbr := dictionary(material, "pbrMetallicRoughness")
			for key in ["baseColorTexture", "metallicRoughnessTexture"]: texture(pbr, key)
			for key in ["normalTexture", "occlusionTexture", "emissiveTexture"]: texture(material, key)
		for tex in data.get("textures", []):
			ref(tex, "sampler", "samplers"); ref(tex, "source", "images")
		for img in data.get("images", []): ref(img, "bufferView", "bufferViews")
		for accessor in data.get("accessors", []):
			ref(accessor, "bufferView", "bufferViews")
			if accessor.has("sparse"):
				var sparse := dictionary(accessor, "sparse")
				ref(dictionary(sparse, "indices"), "bufferView", "bufferViews", true)
				ref(dictionary(sparse, "values"), "bufferView", "bufferViews", true)
		for view in data.get("bufferViews", []): ref(view, "buffer", "buffers", true)
		for skin in data.get("skins", []):
			ref(skin, "inverseBindMatrices", "accessors"); ref(skin, "skeleton", "nodes")
			refs(skin, "joints", "nodes", true)
			if not error.is_empty(): return
			if skin.get("joints", []).is_empty(): fail("Empty skin joints")
		for animation in data.get("animations", []):
			var samplers := objects(animation, "samplers", true)
			var channels := objects(animation, "channels", true)
			if samplers.is_empty() or channels.is_empty(): fail("Empty animation")
			for sampler in samplers:
				ref(sampler, "input", "accessors", true); ref(sampler, "output", "accessors", true)
			for channel in channels:
				ref(channel, "sampler", "", true, samplers.size())
				var target := dictionary(channel, "target")
				ref(target, "node", "nodes", true)
				if not target.get("path", "") in ["translation", "rotation", "scale", "weights"]: fail("Unsupported animation target")
		for key in ["extensionsUsed", "extensionsRequired"]:
			if not data.get(key, []) is Array: fail("Invalid extension declarations"); return
			for ext in data.get(key, []):
				if not ext is String or not _supported(ext): fail("Unsupported extension: %s" % str(ext))
		_scan(data, [])
	func _scan(value: Variant, path: Array) -> void:
		if value is Array:
			for i in value.size(): _scan(value[i], path + [str(i)])
		elif value is Dictionary:
			if value.has("extensions"):
				var extensions := dictionary(value, "extensions")
				for name in extensions:
					if not _supported(name) or not extensions[name] is Dictionary:
						fail("Unsupported extension: %s" % name); continue
					_extension(name, extensions[name], path)
			for key in value:
				if key != "extras": _scan(value[key], path + [str(key)])
	func _extension(name: String, payload: Dictionary, path: Array) -> void:
		var top: String = str(path[0]) if not path.is_empty() else ""
		var direct := path.size() == 2
		if MATERIAL_EXTENSIONS.has(name) and top == "materials" and direct:
			for key in MATERIAL_EXTENSIONS[name]: texture(payload, key)
		elif name == "KHR_lights_punctual" and path.is_empty():
			objects(payload, "lights", true)
		elif name == "KHR_lights_punctual" and top == "nodes" and direct:
			var root_extensions := dictionary(data, "extensions")
			var root_lights := dictionary(root_extensions, "KHR_lights_punctual")
			var lights: Variant = root_lights.get("lights", [])
			if not lights is Array: fail("Invalid lights array"); return
			ref(payload, "light", "", true, lights.size())
			if not offsets.is_empty() and payload.has("light"): payload.light = int(payload.light) + int(offsets.get("lights", 0))
		elif name == "EXT_mesh_gpu_instancing" and top == "nodes" and direct:
			attributes(dictionary(payload, "attributes"))
		elif name == "KHR_draco_mesh_compression" and top == "meshes" and path.size() == 4 and path[2] == "primitives":
			ref(payload, "bufferView", "bufferViews", true)
			var attrs := dictionary(payload, "attributes")
			for attribute in attrs.values():
				if not _integer(attribute) or attribute < 0: fail("Invalid Draco attribute ID")
		elif name in ["KHR_texture_basisu", "EXT_texture_webp", "EXT_texture_avif"] and top == "textures" and direct:
			ref(payload, "source", "images", true)
		elif name == "KHR_texture_transform" and top == "materials" and not path.is_empty() and str(path[-1]).ends_with("Texture"):
			pass
		else: fail("Unsupported extension placement: %s at %s" % [name, "/".join(path)])

static func _integer(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_finite(value) and value == floor(value))

static func _supported(name: String) -> bool:
	return MATERIAL_EXTENSIONS.has(name) or name in OTHER_EXTENSIONS

static func _bad(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}

static func _single_root_valid(data: Dictionary) -> bool:
	# This declaration contains no payload or index to remap. Its constraints
	# apply to the document scene, including unused/orphan nodes being allowed.
	# https://github.com/KhronosGroup/glTF/tree/main/extensions/2.0/Vendor/GODOT_single_root
	if data.get("scenes", []).size() != 1 or not _integer(data.get("scene")) or int(data.scene) != 0:
		return false
	var roots: Array = data.scenes[0].get("nodes", [])
	# JSON.parse represents numbers as floats; Array equality is type-sensitive.
	if roots.size() != 1 or not _integer(roots[0]) or int(roots[0]) != 0 or data.get("nodes", []).is_empty(): return false
	var defaults := {"translation":[0,0,0], "rotation":[0,0,0,1], "scale":[1,1,1], "matrix":[1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1]}
	for field in defaults:
		if not data.nodes[0].has(field): continue
		var values: Variant = data.nodes[0][field]
		if not values is Array or values.size() != defaults[field].size(): return false
		for index in values.size():
			if typeof(values[index]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(values[index])) or float(values[index]) != float(defaults[field][index]): return false
	return true

static func validate(data: Dictionary) -> Dictionary:
	var walker := References.new()
	walker.data = data
	walker.run()
	if not walker.error.is_empty(): return _bad(walker.error)
	if "GODOT_single_root" in data.get("extensionsUsed", []) or "GODOT_single_root" in data.get("extensionsRequired", []):
		if not _single_root_valid(data): return _bad("Invalid GODOT_single_root scene or root transform")
	var nodes: Array = data.get("nodes", [])
	var parents := {}
	for i in nodes.size():
		for child in nodes[i].get("children", []):
			if parents.has(int(child)): return _bad("Node has multiple parents or duplicate child")
			parents[int(child)] = i
	# A strict forest has exactly one visit per node starting from all parentless nodes.
	var todo: Array = []
	for i in nodes.size():
		if not parents.has(i): todo.append(i)
	var visited := 0
	while not todo.is_empty():
		var i: int = todo.pop_back()
		visited += 1
		todo.append_array(nodes[i].get("children", []))
	if visited != nodes.size(): return _bad("Node hierarchy contains a cycle")
	for scene in data.get("scenes", []):
		var seen := {}
		for root in scene.get("nodes", []):
			if parents.has(int(root)) or seen.has(int(root)): return _bad("Scene root is a child or duplicated")
			seen[int(root)] = true
	return {"ok": true, "reason": ""}

static func _subtree(data: Dictionary, root: int) -> Dictionary:
	var result := {}
	var pending := [root]
	while not pending.is_empty():
		var index: int = pending.pop_back()
		result[index] = true
		pending.append_array(data.nodes[index].get("children", []))
	return result

static func _scene_nodes(data: Dictionary) -> Dictionary:
	# Deleted subtrees intentionally retain indices. Their names/UUID metadata
	# must not prevent undo or later insertion of the same authored instance.
	# All scenes count, not only the currently selected scene.
	var result := {}
	if not data.has("scenes"):
		for index in data.get("nodes", []).size(): result[index] = true
		return result
	for scene in data.scenes:
		for root in scene.get("nodes", []): result.merge(_subtree(data, int(root)))
	return result

static func _tombstone_names(data: Dictionary, selected: Dictionary, reserved: Dictionary = {}) -> void:
	# Godot reserves node names across the entire imported array, even for
	# unreachable nodes. Keep indices/resources, but relinquish authored names.
	var names := reserved.duplicate()
	for node in data.get("nodes", []):
		if node.has("name"): names[str(node.name)] = true
	for index in selected:
		if not data.nodes[index].has("name"): continue
		var stem := "__rmmo_deleted_node_%d" % int(index)
		var name := stem
		var serial := 0
		while names.has(name):
			serial += 1
			name = stem + "_%d" % serial
		data.nodes[index].name = name
		names[name] = true

static func _release_orphan_root_names(data: Dictionary, root_names: Dictionary) -> void:
	# Also handle files saved by an earlier version that retained deleted names.
	# Only incoming authored root names matter here; batch clones may still be
	# unattached, so do not rename unrelated pending descendants.
	var live := _scene_nodes(data)
	var selected := {}
	for index in data.get("nodes", []).size():
		if not live.has(index) and root_names.has(str(data.nodes[index].get("name", ""))): selected[index] = true
	_tombstone_names(data, selected, root_names)

static func _rig_check(data: Dictionary, selected: Dictionary) -> Dictionary:
	var used := {}
	for index in selected:
		if data.nodes[index].has("skin"): used[int(data.nodes[index].skin)] = true
	for i in data.get("skins", []).size():
		var skin: Dictionary = data.skins[i]
		var refs: Array = skin.joints.duplicate()
		if skin.has("skeleton"): refs.append(skin.skeleton)
		var inside := false
		var outside := false
		for node in refs:
			if selected.has(int(node)): inside = true
			else: outside = true
		if (used.has(i) and outside) or (inside and not used.has(i)):
			return _bad("Cross-instance or externally owned skeleton")
	for i in data.nodes.size():
		if not selected.has(i) and data.nodes[i].has("skin") and used.has(int(data.nodes[i].skin)):
			return _bad("Skin is shared with a node outside the instance")
	return {"ok": true, "skins": used}

static func clone_instance(data: Dictionary, root_index: int, uuid: String) -> Dictionary:
	var checked := validate(data)
	if not checked.ok: return checked
	if root_index < 0 or root_index >= data.get("nodes", []).size() or uuid.is_empty(): return _bad("Invalid clone root or UUID")
	if data.nodes[root_index].get("name", "") == "rmmo_world": return _bad("Cannot clone the document wrapper")
	# Returned roots are unattached. The caller must reserve batch UUIDs and
	# attach accepted roots; orphan names are not global glTF identifiers.
	for index in _scene_nodes(data):
		var node: Dictionary = data.nodes[index]
		var extras: Dictionary = node.extras if node.get("extras") is Dictionary else {}
		if str(node.get("name", "")) == uuid or str(extras.get("uuid", "")) == uuid: return _bad("UUID already exists")
	var selected := _subtree(data, root_index)
	var rig := _rig_check(data, selected)
	if not rig.ok: return rig
	var mapping := {}
	var node_count: int = data.nodes.size()
	for index in selected: mapping[index] = node_count + mapping.size()
	var skin_mapping := {}
	var new_skins: Array = []
	for index in rig.skins:
		var skin: Dictionary = data.skins[index].duplicate(true)
		skin_mapping[index] = data.get("skins", []).size() + new_skins.size()
		for i in skin.joints.size(): skin.joints[i] = mapping[int(skin.joints[i])]
		if skin.has("skeleton"): skin.skeleton = mapping[int(skin.skeleton)]
		new_skins.append(skin)
	var old_uuid: String = str(data.nodes[root_index].get("name", ""))
	var new_nodes: Array = []
	for index in selected:
		var node: Dictionary = data.nodes[index].duplicate(true)
		for i in node.get("children", []).size(): node.children[i] = mapping[int(node.children[i])]
		if node.has("skin"): node.skin = skin_mapping[int(node.skin)]
		if node.get("extras", {}) is Dictionary and node.get("extras", {}).has("uuid"):
			node.extras.uuid = _replace_uuid(str(node.extras.uuid), old_uuid, uuid)
		if node.get("extras", {}) is Dictionary and node.get("extras", {}).get("rmmo_streetlamp_instance") == old_uuid:
			# stream_index uses this explicit authoring identity to keep the lamp
			# parts resident together. A clone must not join its source's group.
			node.extras.rmmo_streetlamp_instance = uuid
		if index == root_index: node.name = uuid
		new_nodes.append(node)
	var new_animations: Array = []
	for original in data.get("animations", []):
		var channels: Array = []
		for channel in original.channels:
			if selected.has(int(channel.target.node)):
				var copy: Dictionary = channel.duplicate(true)
				copy.target.node = mapping[int(copy.target.node)]
				channels.append(copy)
		if not channels.is_empty():
			var animation: Dictionary = original.duplicate(true)
			animation.channels = channels
			new_animations.append(animation)
	_release_orphan_root_names(data, {uuid:true})
	data.nodes.append_array(new_nodes)
	if not new_skins.is_empty(): data.skins.append_array(new_skins)
	if not new_animations.is_empty(): data.animations.append_array(new_animations)
	return {"ok": true, "root": mapping[root_index]}

static func _replace_uuid(value: String, old: String, replacement: String) -> String:
	if old.is_empty(): return value
	if value == old: return replacement
	for delimiter in ["/", ":", "_", "-", "."]:
		if value.begins_with(old + delimiter): return replacement + value.substr(old.length())
	return value

static func remove_instances(data: Dictionary, roots: Array) -> Dictionary:
	var checked := validate(data)
	if not checked.ok: return checked
	var world := -1
	for i in data.get("nodes", []).size():
		if data.nodes[i].get("name", "") == "rmmo_world":
			if world >= 0: return _bad("Ambiguous rmmo_world root")
			world = i
	if world < 0: return _bad("Missing rmmo_world root")
	var selected := {}
	var unique_roots := {}
	var direct_children := {}
	for child in data.nodes[world].get("children", []): direct_children[int(child)] = true
	for value in roots:
		if not _integer(value) or not direct_children.has(int(value)) or unique_roots.has(int(value)):
			return _bad("Removal requires unique direct rmmo_world children")
		unique_roots[int(value)] = true
		selected.merge(_subtree(data, int(value)))
	var rig := _rig_check(data, selected)
	if not rig.ok: return rig
	for scene in data.get("scenes", []):
		for root in scene.get("nodes", []):
			if selected.has(int(root)): return _bad("Removed node is still referenced by a scene")
	var children: Array = []
	for child in data.nodes[world].get("children", []):
		if not unique_roots.has(int(child)): children.append(child)
	var animations: Array = []
	var removed := 0
	for original in data.get("animations", []):
		var channels: Array = []
		for channel in original.channels:
			if not selected.has(int(channel.target.node)): channels.append(channel)
		if channels.is_empty(): removed += 1
		elif channels.size() == original.channels.size(): animations.append(original)
		else:
			var animation: Dictionary = original.duplicate()
			animation.channels = channels
			animations.append(animation)
	_tombstone_names(data, selected)
	data.nodes[world].children = children
	if data.has("animations"):
		if animations.is_empty(): data.erase("animations")
		else: data.animations = animations
	return {"ok": true, "removed_animation_count": removed}

static func append_fragment(target: Dictionary, fragment: Dictionary, roots: Array) -> Dictionary:
	for document in [target, fragment]:
		var checked := validate(document)
		if not checked.ok: return checked
	var parented := {}
	for node in fragment.get("nodes", []):
		for child in node.get("children", []): parented[int(child)] = true
	var unique := {}
	for root in roots:
		if not _integer(root) or root < 0 or root >= fragment.get("nodes", []).size() or parented.has(int(root)) or unique.has(int(root)):
			return _bad("Fragment roots must be unique parentless nodes")
		unique[int(root)] = true
	var selected := {}
	for root in roots: selected.merge(_subtree(fragment, int(root)))
	var rig := _rig_check(fragment, selected)
	if not rig.ok: return rig
	var staged := fragment.duplicate(true)
	# Scene roots belong to the fragment only and are not published into target.
	staged.erase("scene"); staged.erase("scenes")
	var offsets := {}
	for key in ARRAYS: offsets[key] = target.get(key, []).size()
	var target_lights: Array = target.get("extensions", {}).get("KHR_lights_punctual", {}).get("lights", [])
	offsets.lights = target_lights.size()
	var walker := References.new()
	walker.data = staged
	walker.offsets = offsets
	walker.run()
	if not walker.error.is_empty(): return _bad(walker.error)
	var mapped: Array = []
	for root in roots: mapped.append(int(root) + int(offsets.nodes))
	var root_names := {}
	for root in roots:
		if staged.nodes[int(root)].has("name"): root_names[str(staged.nodes[int(root)].name)] = true
	_release_orphan_root_names(target, root_names)
	for key in ARRAYS:
		if not staged.get(key, []).is_empty():
			if not target.has(key): target[key] = []
			target[key].append_array(staged[key])
	if staged.get("extensions", {}).has("KHR_lights_punctual"):
		var lights: Array = target_lights.duplicate()
		lights.append_array(staged.extensions.KHR_lights_punctual.lights)
		if not target.has("extensions"): target.extensions = {}
		if not target.extensions.has("KHR_lights_punctual"): target.extensions.KHR_lights_punctual = {}
		target.extensions.KHR_lights_punctual.lights = lights
	for key in ["extensionsUsed", "extensionsRequired"]:
		for name in staged.get(key, []):
			# The fragment's scene is not merged. Keep the target's own scene flag;
			# importing a single-root fragment must not constrain another document.
			if name == "GODOT_single_root": continue
			if not target.has(key): target[key] = []
			if not name in target[key]: target[key].append(name)
	return {"ok": true, "roots": mapped}
