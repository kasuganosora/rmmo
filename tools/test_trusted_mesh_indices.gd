extends SceneTree
const Prep=preload("res://scripts/world3d/static_mesh_cpu_preparation.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Policy=preload("res://scripts/world3d/runtime_package_policy.gd")
var failed:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failed+=1
func run()->void:
	var vertices:=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.FORWARD])
	var indices:=PackedInt32Array();indices.resize(3*1024*1024)
	for i:int in indices.size():indices[i]=i%3
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_INDEX]=indices
	var trials:Array=[];var expected:=PackedVector3Array()
	for strict:bool in [true,false,false,true]:
		Policy.verify_packages=strict
		var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		var cpu:Mesh=Cpu.remember(mesh,[arrays])
		var scene:=MeshInstance3D.new();scene.mesh=mesh
		var began:=Time.get_ticks_usec();var result:=Prep.capture(scene,true);var elapsed:=Time.get_ticks_usec()-began
		var faces:PackedVector3Array=cpu.collision_faces()
		check(result.error.is_empty() and faces.size()==indices.size(),"complete indexed geometry captured")
		if expected.is_empty():expected=faces
		else:check(expected==faces,"trusted/diagnostic paths produce identical full triangle arrays")
		trials.append({"strict":strict,"elapsed_us":elapsed,"validation_us":result.get("index_validation_us",-1),"indices_checked":result.get("indices_checked",-1),"face_us":result.face_us})
		scene.free()
	Policy.verify_packages=false
	print("TRUSTED_MESH_INDICES ",JSON.stringify({"trials":trials,"failures":failed}));quit(1 if failed else 0)
