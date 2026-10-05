extends RefCounted
## Blender geometry is used only while authoring; frozen houses embed both surfaces.
const Art=preload("res://scripts/asset/art_paths.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
static var _data:Dictionary={}
static var _meshes:Dictionary={}

static func mesh(r:Dictionary,_base:Material=null)->ArrayMesh:
	if _data.is_empty():
		var path:=Art.path("timber_door/timber_door_mesh.json")
		if not FileAccess.file_exists(path):return null
		var value:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
		if not value is Dictionary or not value.get("surfaces") is Array or value.surfaces.size()!=2:return null
		_data=value
	var key:Array=r.size
	if _meshes.has(key):return _meshes[key]
	var paint:={"name":"三色斜拼整木门板","color":[1.0,1.0,1.0,1.0],"roughness":.82,"metallic":0.0,"texture_path":Art.external_root().path_join("packs/default/assets/materials/wood/solid_timber/texture.png")}
	if not Paint.material_valid(paint) or Paint.texture(paint)==null:return null
	var wood:StandardMaterial3D=Paint.make_material(paint).duplicate()
	wood.vertex_color_use_as_albedo=true
	var iron:=StandardMaterial3D.new();iron.albedo_color=Color(.055,.047,.037);iron.metallic=.72;iron.roughness=.45
	var result:=ArrayMesh.new();var arrays_all:Array=[]
	var scale_:=Vector3(r.size[0]/1.4,r.size[1]/2.2,r.size[2]/.065)
	for slot in _data.surfaces.size():
		var surface:Dictionary=_data.surfaces[slot];var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for triangle:Array in surface.triangles:
			for index in triangle:
				var a:Array=surface.vertices[index];var uv:Array=surface.uvs[index];var n:Array=surface.normals[index];var c:Array=surface.colors[index]
				st.set_uv(Vector2(uv[0],uv[1]));st.set_normal((Vector3(n[0],n[1],n[2])/scale_).normalized());st.set_color(Color(c[0],c[1],c[2],c[3]))
				st.add_vertex(Vector3(a[0],a[1],a[2])*scale_)
		st.generate_tangents();st.index();var arrays:=st.commit_to_arrays()
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);result.surface_set_material(slot,wood if slot==0 else iron);arrays_all.append(arrays)
	preload("res://scripts/world3d/ground_cpu_mesh.gd").remember(result,arrays_all)
	if _meshes.size()>=128:_meshes.erase(_meshes.keys()[0])
	_meshes[key]=result
	return result
