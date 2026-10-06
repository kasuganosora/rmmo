extends RefCounted
## Share identical scanned grass textures across separate immutable GLBs.
## Hash decoded pixels and image layout, never names or untrusted family tags.
static var _textures:Dictionary={}
static var _mutex:=Mutex.new()
static func apply(root:Node)->void:
	var seen:Dictionary={}
	var colored_materials:Dictionary={}
	for mesh in preload("res://scripts/world3d/surface_materials.gd").meshes(root):
		var extras:Variant=mesh.get_meta("extras",{})
		if not extras is Dictionary or extras.get("rmmo_grass")!=true:continue
		for slot in mesh.mesh.get_surface_count():
			var mat=mesh.get_active_material(slot) as StandardMaterial3D
			if mat==null:continue
			var arrays:Array=mesh.mesh.surface_get_arrays(slot)
			var colors:Variant=arrays[Mesh.ARRAY_COLOR]
			if colors is PackedColorArray and colors.size()==arrays[Mesh.ARRAY_VERTEX].size() and not colors.is_empty() and not mat.vertex_color_use_as_albedo:
				# glTF imports can retain COLOR_0 while disabling it on the material.
				# Keep uncolored surfaces and other users of the source material intact.
				var source_id:int=mat.get_instance_id()
				if not colored_materials.has(source_id):
					var colored:StandardMaterial3D=mat.duplicate();colored.vertex_color_use_as_albedo=true
					colored_materials[source_id]=colored
				if mesh.material_override!=null:
					var override:Material=mesh.material_override;mesh.material_override=null
					for surface in mesh.mesh.get_surface_count():mesh.set_surface_override_material(surface,override)
				mat=colored_materials[source_id];mesh.set_surface_override_material(slot,mat)
			if seen.has(mat.get_instance_id()):continue
			seen[mat.get_instance_id()]=true
			for field in ["albedo_texture","normal_texture","roughness_texture","metallic_texture","ao_texture"]:
				var tex=mat.get(field) as Texture2D
				if tex==null:continue
				if not seen.has(tex.get_instance_id()):seen[tex.get_instance_id()]=shared(tex)
				mat.set(field,seen[tex.get_instance_id()])
static func shared(texture:Texture2D)->Texture2D:
	var image:=texture.get_image()
	if image==null:return texture
	var hash_=HashingContext.new();hash_.start(HashingContext.HASH_SHA256)
	hash_.update(var_to_bytes([image.get_width(),image.get_height(),image.get_format(),image.has_mipmaps()]));hash_.update(image.get_data())
	var key=hash_.finish().hex_encode()
	_mutex.lock()
	var result:Texture2D=_textures[key].get_ref() if _textures.has(key) else null
	if result==null:
		result=texture
		if _textures.size()>=32:_textures.erase(_textures.keys()[0])
		_textures[key]=weakref(texture)
	_mutex.unlock()
	return result
