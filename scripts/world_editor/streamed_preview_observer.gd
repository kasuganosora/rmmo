extends RefCounted
## Observes the textures actually bound by this preview's materials once.
## Weak descriptors never keep a scene, material or texture allocation alive.
var _textures:Array=[]
var profile:={"scene_scans":0,"nodes":0,"materials":0}

func capture(scene:Node)->void:
	clear()
	if not is_instance_valid(scene):return
	profile.scene_scans+=1
	var nodes:Array[Node]=[scene];var pending:Array[Material]=[]
	while not nodes.is_empty():
		var node:Node=nodes.pop_back();nodes.append_array(node.get_children());profile.nodes+=1
		if node is MeshInstance3D:
			if node.mesh!=null:
				for surface:int in node.mesh.get_surface_count():pending.append(node.get_active_material(surface))
			pending.append(node.material_overlay)
		elif node is MultiMeshInstance3D and node.multimesh!=null and node.multimesh.mesh!=null:
			for surface:int in node.multimesh.mesh.get_surface_count():
				pending.append(node.material_override if node.material_override!=null else node.multimesh.mesh.surface_get_material(surface))
			pending.append(node.material_overlay)
	var materials:Dictionary={};var textures:Dictionary={}
	while not pending.is_empty():
		var material:Material=pending.pop_back()
		if material==null or materials.has(material.get_instance_id()):continue
		materials[material.get_instance_id()]=true;profile.materials+=1;pending.append(material.next_pass)
		if material is BaseMaterial3D:
			for slot:int in BaseMaterial3D.TEXTURE_MAX:_texture(material.get_texture(slot),textures)
		elif material is ShaderMaterial and material.shader!=null:
			for uniform:Dictionary in _uniforms(material.shader):
				if int(uniform.type) not in [TYPE_OBJECT,TYPE_ARRAY]:continue
				var name_:StringName=uniform.name
				var value:Variant=material.get_shader_parameter(name_)
				if value==null and int(uniform.type)==TYPE_OBJECT:value=material.shader.get_default_texture_parameter(name_)
				_value(value,textures)

func _uniforms(shader:Shader)->Array:
	# Shader.get_shader_uniform_list hides uniforms with default textures.
	return RenderingServer.get_shader_parameter_list(shader.get_rid())

func live_textures()->Array[Texture2D]:
	var result:Array[Texture2D]=[]
	for row:Dictionary in _textures:
		var texture:Texture2D=row.texture.get_ref()
		if texture!=null:result.append(texture)
	return result

func _value(value:Variant,seen:Dictionary)->void:
	if value is Texture2D:_texture(value,seen)
	elif value is Array:
		for item:Variant in value:
			if item is Texture2D:_texture(item,seen)

func _texture(texture:Texture2D,seen:Dictionary)->void:
	if texture==null or seen.has(texture.get_instance_id()):return
	seen[texture.get_instance_id()]=true
	if _is_streamed(texture):_textures.append({"texture":weakref(texture)})
	elif texture is AtlasTexture:_texture(texture.atlas,seen)

func _is_streamed(texture:Texture2D)->bool:
	# Disabled streaming and Compatibility load STEX fully resident at mip 0.
	# Those valid textures need the ordinary draw path, without an engine ticket.
	return texture.is_class("StreamedTexture2D") and texture.has_method("get_streaming_mip_level") and texture.has_method("is_streaming_active") and texture.call("is_streaming_active")

func has_textures()->bool:return not _textures.is_empty()

func clear()->void:
	_textures.clear()

func snapshot()->Dictionary:
	return {"textures":_textures.size(),"profile":profile.duplicate()}
