extends SceneTree
const Paint=preload("res://scripts/world3d/surface_materials.gd")
var failed:=0
func check(value: bool,label_: String) -> void:
	print(("PASS " if value else "FAIL ")+label_)
	if not value: failed+=1
func _initialize() -> void:
	var node:=MeshInstance3D.new(); node.mesh=BoxMesh.new(); node.mesh.material=StandardMaterial3D.new()
	var geo:=Paint.geometry(node); var entries: Array=[]; var mat:={"name":"white","color":[1,1,1,1],"roughness":.8}
	for face in geo.surfaces[0].faces:
		entries.append({"mesh":".","surface":0,"face":face,"geometry":geo.surfaces[0].signature,"mapping":"uv","material":mat.duplicate(true),"scale":[2,3],"offset":[.2,.1],"rotation":30})
	var result:=Paint.painted_mesh(node,entries); check(result.ok and result.mesh.get_surface_count()==1,"same UV transforms and materials merge across authored faces")
	var expected: PackedVector2Array=Paint._uvs(geo.surfaces[0],entries[0]); var arrays: Array=result.mesh.surface_get_arrays(0); var source: Array=geo.surfaces[0].arrays; var match_:=true
	for i in arrays[Mesh.ARRAY_VERTEX].size():
		var found:=false
		for j in source[Mesh.ARRAY_VERTEX].size():
			if arrays[Mesh.ARRAY_VERTEX][i].is_equal_approx(source[Mesh.ARRAY_VERTEX][j]) and arrays[Mesh.ARRAY_NORMAL][i].is_equal_approx(source[Mesh.ARRAY_NORMAL][j]) and arrays[Mesh.ARRAY_TEX_UV][i].is_equal_approx(expected[j]): found=true; break
		match_=match_ and found
	check(match_,"merged vertices keep position, hard normals and exact rotated/scaled UVs")
	var different:=entries.duplicate(true); different[0].offset=[0,0]; result=Paint.painted_mesh(node,different); check(result.ok and result.mesh.get_surface_count()==1 and exact_uv(node,different,result.mesh),"different face UV offsets stay exact inside one material surface")
	different=entries.duplicate(true); different[0].material.color=[.5,.5,.5,1]; result=Paint.painted_mesh(node,different); check(result.ok and result.mesh.get_surface_count()==2,"different face material retains independent surface")
	different=entries.duplicate(true)
	for entry in different: entry.mapping="planar"
	result=Paint.painted_mesh(node,different); check(result.ok and result.mesh.get_surface_count()==1 and exact_uv(node,different,result.mesh),"face-dependent planar UVs stay exact inside one material surface")
	check(entries.size()==6 and entries.all(func(e):return e.mapping=="uv" and e.material.color==[1,1,1,1]),"render optimization does not mutate authored face records")
	node.free(); print("UV_BATCH_FINISHED failures=%d"%failed); quit(0 if failed==0 else 1)

func exact_uv(node:MeshInstance3D,entries:Array,result:Mesh)->bool:
	var geo:=Paint.geometry(node);var expected:Array=[]
	for entry in entries:
		var data:Dictionary=geo.surfaces[entry.surface];var uvs:PackedVector2Array=Paint._uvs(data,entry)
		for triangle in data.faces[entry.face].triangles:
			for corner in 3:
				var i:int=data.indices[triangle*3+corner]
				expected.append([data.arrays[Mesh.ARRAY_VERTEX][i],data.arrays[Mesh.ARRAY_NORMAL][i],uvs[i]])
	for slot in result.get_surface_count():
		var arrays:Array=result.surface_get_arrays(slot)
		for i in arrays[Mesh.ARRAY_VERTEX].size():
			if not expected.any(func(e):return e[0].is_equal_approx(arrays[Mesh.ARRAY_VERTEX][i]) and e[1].is_equal_approx(arrays[Mesh.ARRAY_NORMAL][i]) and e[2].is_equal_approx(arrays[Mesh.ARRAY_TEX_UV][i])):return false
	return true
