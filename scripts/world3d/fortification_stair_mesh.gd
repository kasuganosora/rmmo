extends RefCounted
## One shared-material mesh for a broad internal stone stair.
const Paint=preload("res://scripts/world3d/surface_materials.gd")
static func spec(height: float,radius: float) -> Dictionary:
	var count:=ceili(height/.18)
	var sweep:=PI*1.25
	var open_steps:=mini(count,ceili(3.8/(height/count)))
	return {"count":count,"sweep":sweep,"open_steps":open_steps,"open_angle":sweep*open_steps/count,"outer":radius-.55,"inner":radius-.55-2.8}
static func quad(st: SurfaceTool,a: Vector3,b: Vector3,c: Vector3,d: Vector3) -> void:
	for tri in [[a,b,c],[a,c,d]]:
		var n: Vector3=(tri[2]-tri[0]).cross(tri[1]-tri[0]).normalized()
		for p in tri:
			st.set_normal(n); st.set_uv(Vector2(p.x,p.z) if absf(n.y)>.6 else Vector2(p.dot(Vector3.UP.cross(n)),p.y)); st.add_vertex(p)
static func wedge(st: SurfaceTool,r0: float,r1: float,a: float,b: float,low0: float,low1: float,high0: float,high1: float) -> void:
	var p: Array=[]
	for h in [[low0,low1],[high0,high1]]:
		p.append_array([Vector3(cos(a)*r0,h[0],sin(a)*r0),Vector3(cos(a)*r1,h[0],sin(a)*r1),Vector3(cos(b)*r1,h[1],sin(b)*r1),Vector3(cos(b)*r0,h[1],sin(b)*r0)])
	for face in [[0,3,2,1],[4,5,6,7],[0,1,5,4],[1,2,6,5],[2,3,7,6],[3,0,4,7]]: quad(st,p[face[0]],p[face[1]],p[face[2]],p[face[3]])
static func build(record: Dictionary) -> ArrayMesh:
	var height: float=record.size[1]-1.1; var offset: float=-record.size[1]*.5; var s:=spec(height,record.size[0]*.5)
	var st:=SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES); st.set_material(Paint.make_material(record.fortification_materials.stone))
	for i in s.count:
		var a: float=s.sweep*i/s.count; var b: float=s.sweep*(i+1)/s.count; var low: float=offset+height*i/s.count; var high: float=offset+height*(i+1)/s.count
		wedge(st,s.inner,s.outer+.08,a,b,high-.45,high-.45,high,high)
		# Smooth sloping inner parapet; outer edge is enclosed by the tower wall.
		wedge(st,s.inner,s.inner+.16,a,b,low,high,low+1.05,high+1.05)
	st.generate_tangents(); st.index()
	var arrays:=st.commit_to_arrays(); var result:=ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays); result.surface_set_material(0,Paint.make_material(record.fortification_materials.stone))
	preload("res://scripts/world3d/ground_cpu_mesh.gd").remember(result,[arrays])
	return result
