extends RefCounted
## Blender-authored wall-mounted iron bracket, dish, beeswax and wick.
const DATA=preload("res://scripts/world3d/candle_sconce_data.gd").DATA
const SIZE=Vector3(.26,.54,.46)
const FLAME=Vector3(0,.278,.12)
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
static var cpu_index_enabled:=true # Same-code diagnostic of disposable GPU uploads.
static var _meshes:Dictionary={}
static var _cpu_meshes:Dictionary={}
static var _misses:=0

static func valid(r:Dictionary)->bool:
	return r.get("collision")=="none" and r.get("building",{}).get("role")=="light_sconce"

static func mesh(r:Dictionary,_base:Material=null)->ArrayMesh:
	var key:=Vector3(r.size[0],r.size[1],r.size[2])
	var existing:Mesh=_meshes[key].get_ref() if _meshes.has(key) else null
	if existing!=null:return existing
	var cpu:Mesh=cpu_mesh(r)
	var result:ArrayMesh=cpu.restore()
	_meshes[key]=weakref(result)
	_cpu_meshes[key]=weakref(Cpu.capture(result))
	return result

static func cpu_mesh(r:Dictionary)->Mesh:
	var key:=Vector3(r.size[0],r.size[1],r.size[2])
	var existing:Mesh=_cpu_meshes[key].get_ref() if _cpu_meshes.has(key) else null
	if existing!=null:return existing
	var gpu:Mesh=_meshes[key].get_ref() if _meshes.has(key) else null
	if gpu!=null:
		existing=Cpu.capture(gpu);_cpu_meshes[key]=weakref(existing);return existing
	_misses+=1
	if _misses%64==0:
		for cache:Dictionary in [_meshes,_cpu_meshes]:
			for value:Variant in cache.keys():
				if cache[value].get_ref()==null:cache.erase(value)
	var all_arrays:Array=[];var materials:Array=[]
	var scale_:Vector3=key/SIZE
	for slot in DATA.surfaces.size():
		var surface:Dictionary=DATA.surfaces[slot]
		var m:=StandardMaterial3D.new()
		m.albedo_color=[Color(.095,.079,.064),Color(.82,.68,.38),Color(.022,.013,.008)][slot]
		m.metallic=.78 if slot==0 else 0.0;m.roughness=.52 if slot==0 else .79
		# Keep each independently paintable surface below the editor's 128-face cap.
		for start in range(0,surface.triangles.size(),120):
			var st:=SurfaceTool.new();st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for t in range(start,mini(start+120,surface.triangles.size())):
				for index in surface.triangles[t]:
					var v:Array=surface.vertices[index];var p:=Vector3(v[0],v[1],v[2])*scale_
					st.set_uv(Vector2(p.x,p.y));st.add_vertex(p)
			st.generate_normals();st.generate_tangents();var arrays:=st.commit_to_arrays()
			all_arrays.append(arrays);materials.append(m)
	var result:Mesh=Cpu.from_surfaces(all_arrays,materials)
	_cpu_meshes[key]=weakref(result)
	return result
