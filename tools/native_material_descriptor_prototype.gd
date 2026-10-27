extends RefCounted
## Offline research prototype only. It deliberately supports a narrow, explicit
## subset; no runtime, editor product, or texture cooking integration.

static func _plain(value: Variant, depth := 0) -> bool:
	# Avoid concealing Resources inside container-valued material properties.
	if depth > 32 or value is Object or typeof(value) in [TYPE_RID, TYPE_CALLABLE, TYPE_SIGNAL]:
		return false
	if value is Array:
		for item in value:
			if not _plain(item, depth + 1): return false
	if value is Dictionary:
		for key in value:
			if not _plain(key, depth + 1) or not _plain(value[key], depth + 1): return false
	return true

static func _material_id(material: Material, state: Dictionary) -> int:
	if material == null:
		return -1
	var identity := material.get_instance_id()
	if state.material_ids.has(identity):
		return state.material_ids[identity]
	if not material is StandardMaterial3D:
		state.error = "unsupported material type: " + material.get_class()
		return -1
	if material.resource_local_to_scene or material.get_script() != null or not material.get_meta_list().is_empty():
		state.error = "unsupported material local, script or metadata"
		return -1
	var id: int = state.materials.size()
	state.material_ids[identity] = id
	state.materials.append({})
	var properties := {}
	for property: Dictionary in material.get_property_list():
		if (int(property.usage) & PROPERTY_USAGE_STORAGE) == 0:
			continue
		var name_: String = property.name
		if name_ in ["script", "resource_path", "resource_scene_unique_id"]:
			continue
		var value: Variant = material.get(name_)
		if value is Texture2D:
			var texture_id := _texture_id(value, state)
			properties[name_] = {"kind": "texture", "id": texture_id}
		elif value is Material:
			properties[name_] = {"kind": "material", "id": _material_id(value, state)}
		elif value is Object:
			state.error = "unsupported material resource: " + name_
			return -1
		elif _plain(value):
			properties[name_] = {"kind": "value", "value": value}
		else:
			state.error = "unsupported nested material resource: " + name_
			return -1
	state.materials[id] = properties
	return id

static func _texture_id(texture: Texture2D, state: Dictionary) -> int:
	var identity := texture.get_instance_id()
	if state.texture_ids.has(identity):
		return state.texture_ids[identity]
	if not texture is ImageTexture:
		state.error = "unsupported texture type: " + texture.get_class()
		return -1
	if texture.resource_local_to_scene or texture.get_script() != null or not texture.get_meta_list().is_empty():
		state.error = "unsupported texture local, script or metadata"
		return -1
	var image := texture.get_image()
	if image == null or image.is_empty():
		state.error = "texture image is unavailable"
		return -1
	if texture.get_size() != Vector2(image.get_width(), image.get_height()):
		state.error = "unsupported texture size override"
		return -1
	var id: int = state.textures.size()
	state.texture_ids[identity] = id
	state.textures.append({"width": image.get_width(), "height": image.get_height(),
		"mipmaps": image.has_mipmaps(), "format": image.get_format(), "data": image.get_data()})
	return id

static func _nodes(root: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		if node is MeshInstance3D:
			result.append(node)
		for child in node.get_children():
			pending.append(child)
	return result

static func extract(source: PackedScene) -> Dictionary:
	var root := source.instantiate()
	var state := {"material_ids": {}, "texture_ids": {}, "materials": [], "textures": [], "error": ""}
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var current: Node = pending.pop_back()
		if current.get_class() not in ["Node3D", "MeshInstance3D"] or current.get_script() != null or not current.get_meta_list().is_empty() or not current.scene_file_path.is_empty():
			root.free()
			return {"error": "unsupported node type, script, metadata or nested scene"}
		for signal_info: Dictionary in current.get_signal_list():
			for connection: Dictionary in current.get_signal_connection_list(signal_info.name):
				if (int(connection.flags) & CONNECT_PERSIST) != 0:
					root.free()
					return {"error": "unsupported persistent signal connection"}
		for property: Dictionary in current.get_property_list():
			if (int(property.usage) & PROPERTY_USAGE_STORAGE) == 0: continue
			var property_name: String = property.name
			if current is MeshInstance3D and (property_name in ["mesh", "material_override", "material_overlay"] or property_name.begins_with("surface_material_override/")): continue
			if not _plain(current.get(property_name)):
				root.free()
				return {"error": "unsupported node resource property: " + property_name}
		for child: Node in current.get_children(): pending.append(child)
	var mesh_copies := {}
	var meshes := []
	var nodes := []
	for node: MeshInstance3D in _nodes(root):
		var mesh := node.mesh
		if not mesh is ArrayMesh:
			state.error = "only ArrayMesh supported"
			break
		if node.skin != null or mesh.get_blend_shape_count() != 0 or mesh.shadow_mesh != null or mesh.resource_local_to_scene or mesh.get_script() != null or not mesh.get_meta_list().is_empty():
			state.error = "unsupported skin, blendshape, local mesh, script or metadata"
			break
		var mesh_key := mesh.get_instance_id()
		var overrides := []
		for index in mesh.get_surface_count():
			overrides.append(_material_id(node.get_surface_override_material(index), state))
		var global_id := _material_id(node.material_override, state)
		var overlay_id := _material_id(node.material_overlay, state)
		if not mesh_copies.has(mesh_key):
			var copy := mesh.duplicate() as ArrayMesh
			var base := []
			for index in mesh.get_surface_count():
				if mesh.surface_get_primitive_type(index) != Mesh.PRIMITIVE_TRIANGLES:
					state.error = "only triangle surfaces supported"
					break
				var arrays: Array = mesh.surface_get_arrays(index)
				if arrays[Mesh.ARRAY_BONES] != null or arrays[Mesh.ARRAY_WEIGHTS] != null:
					state.error = "unsupported skinned geometry"
					break
				base.append(_material_id(mesh.surface_get_material(index), state))
			if state.error == "":
				preload("res://scripts/world3d/white_native_asset_writer.gd")._store_geometry(copy)
			var mesh_id := meshes.size()
			meshes.append({"materials": base})
			mesh_copies[mesh_key] = {"id": mesh_id, "mesh": copy}
		nodes.append({"path": str(root.get_path_to(node)), "mesh": mesh_copies[mesh_key].id,
			"overrides": overrides, "global": global_id, "overlay": overlay_id})
		node.mesh = mesh_copies[mesh_key].mesh
		for index in mesh.get_surface_count():
			node.set_surface_override_material(index, null)
		node.material_override = null
		node.material_overlay = null
		if state.error != "":
			break
	if state.error != "":
		root.free()
		return {"error": state.error}
	var packed := PackedScene.new()
	var err := packed.pack(root)
	root.free()
	if err != OK:
		return {"error": "pack failed: %d" % err}
	return {"geometry": packed, "descriptor": {"version": 1, "meshes": meshes, "nodes": nodes,
		"materials": state.materials, "textures": state.textures}}

static func _lookup(values: Array, id: int) -> Variant:
	return null if id < 0 else values[id]

static func restore(geometry: PackedScene, descriptor: Dictionary) -> Dictionary:
	if descriptor.get("version", 0) != 1:
		return {"error": "unsupported descriptor version"}
	var textures := []
	for record: Dictionary in descriptor.textures:
		var img := Image.create_from_data(record.width, record.height, record.mipmaps, record.format, record.data)
		textures.append(ImageTexture.create_from_image(img))
	var materials := []
	for record: Dictionary in descriptor.materials:
		materials.append(StandardMaterial3D.new())
	for index in materials.size():
		var material: StandardMaterial3D = materials[index]
		var properties: Dictionary = descriptor.materials[index]
		for name_: String in properties:
			var value: Dictionary = properties[name_]
			match value.kind:
				"texture": material.set(name_, _lookup(textures, value.id))
				"material": material.set(name_, _lookup(materials, value.id))
				"value": material.set(name_, value.value)
	var root := geometry.instantiate()
	var restored_meshes := {}
	for record: Dictionary in descriptor.nodes:
		var node := root.get_node_or_null(NodePath(record.path)) as MeshInstance3D
		if node == null or node.mesh == null:
			root.free()
			return {"error": "missing geometry node: " + record.path}
		if not restored_meshes.has(record.mesh):
			var mesh := node.mesh.duplicate() as ArrayMesh
			var ids: Array = descriptor.meshes[record.mesh].materials
			for index in ids.size():
				mesh.surface_set_material(index, _lookup(materials, ids[index]))
			restored_meshes[record.mesh] = mesh
		node.mesh = restored_meshes[record.mesh]
		for index in record.overrides.size():
			node.set_surface_override_material(index, _lookup(materials, record.overrides[index]))
		node.material_override = _lookup(materials, record.global)
		node.material_overlay = _lookup(materials, record.overlay)
	var packed := PackedScene.new()
	var err := packed.pack(root)
	root.free()
	if err != OK:
		return {"error": "pack failed: %d" % err}
	return {"packed": packed}
