extends RefCounted
## Blender-authored wall-mounted iron bracket, dish, beeswax and wick.
const DATA=preload("res://scripts/world3d/candle_sconce_data.gd").DATA
const SIZE=Vector3(.26,.54,.46)
const FLAME=Vector3(0,.278,.12)
static var _meshes:Dictionary={}

static func valid(r:Dictionary)->bool:
	return r.get("collision")=="none" and r.get("building",{}).get("role")=="light_sconce"

static func mesh(r:Dictionary,_base:Material=null)->ArrayMesh:
	var key:=str(r.size)
	if _meshes.has(key):return _meshes[key]
	var result:=ArrayMesh.new();var all_arrays:Array=[]
	var scale_:Vector3=Vector3(r.size[0],r.size[1],r.size[2])/SIZE
	for slot in DATA.surfaces.size():
		var surface:Dictionary=DATA.surfaces[slot]
		var m:=StandardMaterial3D.new()
		m.albedo_color=[Color(.095,.079,.064),Color(.82,.68,.38),Color(.022,.013,.008)][slot]
		m.metallic=.78 if slot==0 else 0.0;m.roughness=.52 if slot==0 else .79
		# Keep each independently paintable surface below the editor's 128-face cap.
		for start in range(0,surface.triangles.size(),120):
			var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES);st.set_material(m)
			for t in range(start,mini(start+120,surface.triangles.size())):
				for index in surface.triangles[t]:
					var v:Array=surface.vertices[index];var p:=Vector3(v[0],v[1],v[2])*scale_
					st.set_uv(Vector2(p.x,p.y));st.add_vertex(p)
			st.generate_normals();st.generate_tangents();var arrays:=st.commit_to_arrays()
			result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays);result.surface_set_material(result.get_surface_count()-1,m);all_arrays.append(arrays)
	preload("res://scripts/world3d/ground_cpu_mesh.gd").remember(result,all_arrays)
	_meshes[key]=result
	return result
