extends RefCounted
## Approved Blender surfaces; authoring only. Frozen maps carry their own geometry.
const Art=preload("res://scripts/asset/art_paths.gd")
const Paint=preload("res://scripts/world3d/surface_materials.gd")
static var _data:Dictionary={}
static var _meshes:Dictionary={}

static func mesh(record:Dictionary)->ArrayMesh:
	if _data.is_empty():
		var parsed:Variant=JSON.parse_string(FileAccess.get_file_as_string(Art.path("interior_timber_door/interior_timber_door_mesh.json")))
		if not parsed is Dictionary or parsed.get("surfaces",[]).size()!=3:return null
		_data=parsed
	var frame:bool=record.building_shape=="interior_door_frame"
	var key:Array=[frame,record.size]
	if _meshes.has(key):return _meshes[key]
	var paint:={"name":"室内三色斜拼木门","color":[1.0,1.0,1.0,1.0],"roughness":.82,"metallic":0.0,"texture_path":Art.external_root().path_join("packs/default/assets/materials/wood/solid_timber/texture.png")}
	if not Paint.material_valid(paint) or Paint.texture(paint)==null:return null
	var wood:StandardMaterial3D=Paint.make_material(paint).duplicate();wood.vertex_color_use_as_albedo=true
	var brass:=StandardMaterial3D.new();brass.albedo_color=Color(.48,.36,.14);brass.metallic=.72;brass.roughness=.34
	var reference:=Vector3(1.428,2.32,.154) if frame else Vector3(1.2,2.2,.075)
	var scale_:=Vector3(record.size[0],record.size[1],record.size[2])/reference
	var result:=ArrayMesh.new();var arrays_all:Array=[]
	for surface:Dictionary in _data.surfaces:
		if (surface.motion_group=="static_frame")!=frame:continue
		var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for triangle:Array in surface.triangles:
			for index in triangle:
				var a:Array=surface.vertices[index];var uv:Array=surface.uvs[index];var n:Array=surface.normals[index];var c:Array=surface.colors[index]
				st.set_uv(Vector2(uv[0],uv[1]));st.set_normal((Vector3(n[0],n[1],n[2])/scale_).normalized());st.set_color(Color(c[0],c[1],c[2],c[3]))
				st.add_vertex((Vector3(a[0],a[1],a[2])-Vector3(0,.054 if frame else 0,0))*scale_)
		st.generate_tangents();st.index();var arrays:=st.commit_to_arrays()
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);result.surface_set_material(result.get_surface_count()-1,wood if surface.material==0 else brass);arrays_all.append(arrays)
	preload("res://scripts/world3d/ground_cpu_mesh.gd").remember(result,arrays_all)
	if _meshes.size()>=128:_meshes.erase(_meshes.keys()[0])
	_meshes[key]=result
	return result
