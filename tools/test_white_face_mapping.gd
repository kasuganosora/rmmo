extends SceneTree
const Paint=preload("res://scripts/world3d/surface_materials.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Controls=preload("res://scripts/world3d/runtime_probe_controls.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func triangles(mesh:Mesh)->Array:
	var cpu:Mesh=Cpu.capture(mesh);var result:Array=[]
	for slot:int in cpu.surfaces.size():
		var surface:Array=cpu.surfaces[slot];var vertices:PackedVector3Array=surface[Mesh.ARRAY_VERTEX];var indices:Variant=surface[Mesh.ARRAY_INDEX]
		var count:int=vertices.size() if indices==null or indices.is_empty() else indices.size()
		for at:int in range(0,count,3):
			var corners:Array=[]
			for corner:int in 3:
				var i:int=at+corner if indices==null or indices.is_empty() else indices[at+corner]
				corners.append([vertices[i],surface[Mesh.ARRAY_NORMAL][i]])
			result.append(var_to_str([corners,cpu.materials[slot].cull_mode]))
	result.sort();return result
func run()->void:
	Controls.discard_map_textures=true;Controls.enable_white_materials()
	var reports:Array=[]
	for cull:int in [BaseMaterial3D.CULL_BACK,BaseMaterial3D.CULL_FRONT,BaseMaterial3D.CULL_DISABLED]:
		var box:=BoxMesh.new();box.subdivide_width=3;box.subdivide_depth=3;box.subdivide_height=3;box.material=Controls.white_material(cull)
		var source:Mesh=Cpu.capture(box);var fixture:=MeshInstance3D.new();root.add_child(fixture);fixture.mesh=source
		var geo:=Paint.geometry(fixture);var entries:Array=[]
		for face:int in geo.surfaces[0].faces:
			entries.append({"mesh":".","surface":0,"face":face,"geometry":geo.surfaces[0].signature,"mapping":"uv" if face%2 else "planar","material":{"name":"fixture","color":[.3,.4,.5,1.],"roughness":.8},"scale":[2.,3.],"offset":[.2,.1],"rotation":30.})
		var record:={"surface_paint":entries};var before:=var_to_bytes(record);var expected:=triangles(source)
		for fast:bool in [false,true,true,false]:
			Paint.white_face_mapping_elision_enabled=fast
			var total:=0;var replaced:=0
			for i:int in 24:
				var node:=MeshInstance3D.new();root.add_child(node);node.mesh=source
				var began:=Time.get_ticks_usec();Paint.apply(node,record,null,{},true);total+=Time.get_ticks_usec()-began
				if not is_same(node.mesh,source):replaced+=1
				if i==0:check(not node.has_meta("paint_error") and triangles(node.mesh)==expected,"white geometry retains oriented triangles, normals and culling")
				node.free()
			reports.append({"fast":fast,"cull":cull,"us":total,"rebuilt_meshes":replaced})
			check(replaced==(0 if fast else 24),"white isolation removes face remapping and extra mesh ownership")
		check(var_to_bytes(record)==before,"white diagnostic leaves authored face definitions unchanged")
		Controls.white_materials=false;Paint.white_face_mapping_elision_enabled=true
		var node:=MeshInstance3D.new();root.add_child(node);node.mesh=source;Paint.apply(node,record,null,{},true)
		check(not node.has_meta("paint_error") and not is_same(node.mesh,source) and Cpu.capture(node.mesh).materials[0].albedo_color.is_equal_approx(Color(.3,.4,.5,1.)),"disabling white mode restores authored material processing")
		node.free();fixture.free();Controls.white_materials=true
	print("WHITE_FACE_MAPPING ",JSON.stringify({"trials":reports,"failures":failures}));quit(1 if failures else 0)
