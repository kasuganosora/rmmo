extends SceneTree
const Preparation=preload("res://scripts/world3d/static_mesh_cpu_preparation.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
var checks:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func fixture(count:int)->Dictionary:
	var host:=Node3D.new();var refs:Array=[]
	for i:int in count:
		var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3.RIGHT,Vector3.UP,Vector3.ONE])
		arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,2,2,1,3])
		arrays[Mesh.ARRAY_NORMAL]=PackedVector3Array([Vector3.FORWARD,Vector3.FORWARD,Vector3.FORWARD,Vector3.FORWARD])
		arrays[Mesh.ARRAY_TEX_UV]=PackedVector2Array([Vector2.ZERO,Vector2.RIGHT,Vector2.UP,Vector2.ONE])
		var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{2.:PackedInt32Array([0,1,2])})
		mesh.surface_set_material(0,StandardMaterial3D.new())
		refs.append(weakref(mesh))
		for shared:int in 2:
			var node:=MeshInstance3D.new();node.mesh=mesh;host.add_child(node)
	return {"host":host,"refs":refs}
func run()->void:
	check(DisplayServer.get_name()!="headless","private GPU renderer for exact source buffer snapshots")
	var f:=fixture(12);var expected:Array=[]
	for ref:WeakRef in f.refs:
		var mesh:Mesh=ref.get_ref()
		expected.append({"arrays":mesh.surface_get_arrays(0),"lods":Cpu.capture_lods(mesh,0)})
	var cursor:=Preparation.begin(f.host,true)
	var turns:=0
	while not Preparation.advance(cursor,1):
		turns+=1;await process_frame
	check(turns>1 and cursor.profile.captured_meshes==12,"bounded slices finish each unique mesh once across shared instances")
	check(cursor.profile.error.is_empty() and cursor.nodes.is_empty() and cursor.profile.face_bytes>0,"completion retains complete collision buffers and no pending graph")
	for i:int in f.refs.size():
		var mesh:Mesh=f.refs[i].get_ref();var cpu:Mesh=mesh.get_meta("ground_cpu_cache")
		check(var_to_bytes(cpu.surfaces[0])==var_to_bytes(expected[i].arrays) and cpu.lods[0]==expected[i].lods,"all channels and LOD indices remain exact "+str(i))
		check(cpu._collision_faces==mesh.get_faces() and cpu.materials[0]==mesh.surface_get_material(0),"collision winding and material identity remain exact "+str(i))
	f.host.free();cursor.clear()
	var cancelled:=fixture(8)
	cursor=Preparation.begin(cancelled.host,true)
	Preparation.advance(cursor,1);Preparation.advance(cursor,1)
	cancelled.host.free();RenderingServer.force_sync();await process_frame
	check(cancelled.refs.all(func(ref:WeakRef):return ref.get_ref()==null),"cancellation between slices retains no source mesh through cursor or CPU weak backreference")
	check(Preparation.advance(cursor,1) and not cursor.profile.error.is_empty(),"resuming an abandoned cursor rejects freed nodes without touching renderer")
	cursor.clear()
	print("STATIC_MESH_CPU_SLICES checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
