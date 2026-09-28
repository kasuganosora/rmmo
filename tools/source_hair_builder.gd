extends RefCounted
## Offline importer of preserved native source meshes and bone chains.
const SOURCE = "D:/code/rmmo_runtime/assets/characters/source_hair/koikatu/"
var bones: Dictionary
var objects: Dictionary
var skeleton: Skeleton3D
const PIGMENT = """shader_type spatial;
render_mode cull_disabled, diffuse_burley;
uniform vec4 hair_color : source_color = vec4(0.25,0.13,0.07,1.0);
uniform vec4 hair_color2 : source_color = vec4(0.25,0.13,0.07,1.0);
uniform vec4 hair_color3 : source_color = vec4(0.25,0.13,0.07,1.0);
uniform sampler2D color_mask : filter_linear_mipmap;
uniform bool has_mask = false;
void fragment() {
    vec3 mask = has_mask ? texture(color_mask, UV).rgb : vec3(0.0);
    // Source FORWARD pixel program: sequential RGB mask blends from white.
    vec3 base = mix(vec3(1.0), hair_color.rgb, mask.r);
    base = mix(base, hair_color2.rgb, mask.g);
    base = mix(base, hair_color3.rgb, mask.b);
    ALBEDO = base;
    ROUGHNESS = 0.48;
    SPECULAR = 0.34;
    if (!FRONT_FACING) NORMAL = -NORMAL;
}
"""

func material(data: Dictionary, id: String, folder: String) -> Material:
	var src: Dictionary = data.materials[id]
	var is_hair: bool = not str(src.m_Name).contains("ribon") and not str(src.m_Name).contains("acs")
	var colors: Dictionary = {}
	for pair in src.m_SavedProperties.m_Colors:colors[pair[0]] = pair[1]
	var c: Dictionary = colors.get("_Color", {"r":0.3,"g":0.2,"b":0.1,"a":1.0})
	if not is_hair:
		var plain := StandardMaterial3D.new()
		plain.albedo_color = Color(c.r,c.g,c.b,c.a)
		plain.roughness = 0.7
		plain.cull_mode = BaseMaterial3D.CULL_DISABLED
		# Restore source fabric shading. Imported UVs already flip V, so the
		# source texture transform needs the same coordinate conversion.
		for pair in src.m_SavedProperties.m_TexEnvs:
			if pair[0] != "_MainTex" or pair[1].m_Texture.m_PathID == "0":continue
			var image := Image.load_from_file(folder + "/" + data.textures[pair[1].m_Texture.m_PathID].file)
			assert(image != null and not image.is_empty(), "Missing accessory source texture")
			image.generate_mipmaps()
			plain.albedo_texture = ImageTexture.create_from_image(image)
			var scale_: Dictionary = pair[1].m_Scale
			var offset: Dictionary = pair[1].m_Offset
			plain.uv1_scale = Vector3(scale_.x, scale_.y, 1)
			plain.uv1_offset = Vector3(offset.x, 1.0 - scale_.y - offset.y, 0)
		return plain
	var mat := ShaderMaterial.new()
	mat.resource_name=src.m_Name
	mat.shader = Shader.new()
	mat.shader.code = PIGMENT
	mat.set_shader_parameter("hair_color", Color(c.r,c.g,c.b,1))
	for channel in [2,3]:
		var shade:Dictionary=colors.get("_Color%d"%channel,c)
		mat.set_shader_parameter("hair_color%d"%channel,Color(shade.r,shade.g,shade.b,1))
	for pair in src.m_SavedProperties.m_TexEnvs:
		if pair[0] != "_ColorMask" or pair[1].m_Texture.m_PathID == "0":continue
		var image := Image.load_from_file(folder + "/" + data.textures[pair[1].m_Texture.m_PathID].file)
		image.generate_mipmaps()
		mat.set_shader_parameter("color_mask", ImageTexture.create_from_image(image))
		mat.set_shader_parameter("has_mask", true)
	preload("res://tools/bake_source_hair_material.gd").decorate(mat,src,data,folder)
	return mat
func v(d: Dictionary) -> Vector3:
	return Vector3(d.x, d.y, -d.z)

func local_xform(d: Dictionary) -> Transform3D:
	var q: Dictionary = d.m_LocalRotation
	var b := Basis(Quaternion(-q.x, -q.y, q.z, q.w))
	var s: Dictionary = d.m_LocalScale
	return Transform3D(b.scaled(Vector3(s.x, s.y, s.z)), v(d.m_LocalPosition))

func matrix(d: Dictionary) -> Transform3D:
	return Transform3D(Basis(Vector3(d.e00, d.e10, -d.e20), Vector3(d.e01, d.e11, -d.e21), Vector3(-d.e02, -d.e12, d.e22)), Vector3(d.e03, d.e13, -d.e23))

func bone(id: String) -> int:
	if bones.has(id):
		return bones[id]
	var d: Dictionary = objects[id].data
	var parent := -1
	if d.m_Father.m_PathID != "0":
		parent = bone(d.m_Father.m_PathID)
	var index := skeleton.get_bone_count()
	var go: Dictionary = objects[d.m_GameObject.m_PathID].data
	skeleton.add_bone(str(go.m_Name) + "_" + str(index))
	bones[id] = index
	skeleton.set_bone_parent(index, parent)
	var rest := local_xform(d)
	skeleton.set_bone_rest(index, rest)
	skeleton.set_bone_pose_position(index, rest.origin)
	skeleton.set_bone_pose_rotation(index, rest.basis.get_rotation_quaternion())
	skeleton.set_bone_pose_scale(index, rest.basis.get_scale())
	return index

func load_source(name_: String) -> Node3D:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SOURCE + name_ + "/source.json"))
	objects = data.objects
	bones = {}
	var result := Node3D.new()
	result.name = name_
	skeleton = Skeleton3D.new()
	skeleton.name = "SourceSkeleton"
	result.add_child(skeleton)
	for id in objects:
		if objects[id].type == "Transform":
			bone(id)
	var chains:Array=[]
	for item in objects.values():
		var config:Dictionary=item.data
		if not config.has("m_Damping") or not config.has("m_Root"):continue
		var chain:Array[int]=[]
		var key:String=config.m_Root.m_PathID
		while key!="0":
			chain.append(bones[key])
			var children:Array=objects[key].data.m_Children
			assert(children.size()<=1,"Native spring source has a branched chain; explicit split required")
			key=children[0].m_PathID if children.size()==1 else "0"
		chains.append({"bones":chain,"source_config":config})
	skeleton.set_meta("source_spring_chains",chains)
	for item in objects.values():
		if item.type != "SkinnedMeshRenderer":
			continue
		var r: Dictionary = item.data
		if not r.m_Enabled:
			continue
		var src: Dictionary = data.meshes[r.m_Mesh.m_PathID]
		var skin := Skin.new()
		assert(src.bind_poses.size() == r.m_Bones.size())
		for i in r.m_Bones.size():
			skin.add_bind(bones[r.m_Bones[i].m_PathID], matrix(src.bind_poses[i]))
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		var uvs := PackedVector2Array()
		var uvs2 := PackedVector2Array()
		var tangents:=PackedFloat32Array()
		var source_tangents:Array=src.get("tangents",[])
		assert(source_tangents.is_empty() or source_tangents.size()==src.vertices.size())
		var source_uv2:Array=src.get("uv2",[])
		assert(source_uv2.is_empty() or source_uv2.size()==src.vertices.size(),"Incomplete source UV2")
		var indices_b := PackedInt32Array()
		var weights := PackedFloat32Array()
		for i in src.vertices.size():
			var p: Array = src.vertices[i]
			vertices.append(Vector3(p[0], p[1], -p[2]))
			p = src.normals[i]
			normals.append(Vector3(p[0], p[1], -p[2]))
			p = src.uv[i]
			uvs.append(Vector2(p[0], 1.0 - p[1]))
			if not source_uv2.is_empty():
				p=source_uv2[i]
				uvs2.append(Vector2(p[0],1.0-p[1]))
			if not source_tangents.is_empty():
				p=source_tangents[i]
				# Reflection reverses handedness; flipping V reverses it again.
				tangents.append_array(PackedFloat32Array([p[0],p[1],-p[2],p[3]]))
			for j in 4:
				indices_b.append(src.bone_indices[i][j])
				weights.append(src.bone_weights[i][j])
		var mesh := ArrayMesh.new()
		mesh.resource_name=src.name
		for sub in src.triangles:
			var indices := PackedInt32Array()
			for tri in sub:
				indices.append_array(PackedInt32Array([tri[0], tri[2], tri[1]]))
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = vertices
			arrays[Mesh.ARRAY_NORMAL] = normals
			arrays[Mesh.ARRAY_TEX_UV] = uvs
			if not uvs2.is_empty():arrays[Mesh.ARRAY_TEX_UV2]=uvs2
			if not tangents.is_empty():arrays[Mesh.ARRAY_TANGENT]=tangents
			arrays[Mesh.ARRAY_BONES] = indices_b
			arrays[Mesh.ARRAY_WEIGHTS] = weights
			arrays[Mesh.ARRAY_INDEX] = indices
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.skin = skin
		skeleton.add_child(instance)
		instance.skeleton = NodePath("..")
		for i in mesh.get_surface_count():
			assert(i < r.m_Materials.size())
			mesh.surface_set_material(i, material(data, r.m_Materials[i].m_PathID, SOURCE + name_))
	return result

