extends SceneTree
## CPU face workload shaped like the entry model. Renderer costs are measured
## separately on the real map; this fixture deliberately starts with CPU data.
const Prep=preload("res://scripts/world3d/static_mesh_cpu_preparation.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
func _initialize()->void:run.call_deferred()
func run()->void:
	var vertices:=PackedVector3Array();var indices:=PackedInt32Array()
	for i:int in 264:vertices.append(Vector3(i%11,float(i/11),i*.01))
	for i:int in 672:indices.append(i%vertices.size())
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_INDEX]=indices
	var expected:=PackedVector3Array()
	for index:int in indices:expected.append(vertices[index])
	var host:=Node3D.new();root.add_child(host);var owners:Array=[]
	for i:int in 2007:
		var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
		owners.append(Cpu.remember(mesh,[arrays]));var node:=MeshInstance3D.new();node.mesh=mesh;host.add_child(node)
	var cursor:=Prep.begin(host,true);var began:=Time.get_ticks_usec()
	while not Prep.advance(cursor,16000):pass
	var elapsed:=Time.get_ticks_usec()-began;var correct:bool=cursor.profile.error.is_empty()
	for cpu:Mesh in owners:
		if cpu._collision_faces!=expected:correct=false
	print("INITIAL_CPU_CAPTURE_PROFILE ",JSON.stringify({"correct":correct,"us":elapsed,"profile":cursor.profile}))
	host.free();owners.clear();quit(0 if correct else 1)
