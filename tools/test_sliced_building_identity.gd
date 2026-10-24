extends SceneTree
const Batch=preload("res://scripts/world3d/ground_batcher.gd")
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
class CPUResultBatch extends "res://scripts/world3d/ground_batcher.gd":
	var results:Array=[]
	func _commit(group:Dictionary,data:Dictionary,_started:int)->void:
		var arrays:Array=[]
		for slot:Dictionary in data.slots:arrays.append(slot.arrays)
		results.append([group.mesh_cache_key,Cpu.geometry_signature(arrays)])
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func identities(nodes:Array)->int:
	var count:=0
	for node:MeshInstance3D in nodes:
		if Cpu.capture(node.mesh).has_meta("static_batch_geometry_signature"):count+=1
	return count
func run()->void:
	var trials:Array=[];var expected:Array=[]
	for trial:int in 2:
		var host:=Node3D.new();root.add_child(host);var batch:=CPUResultBatch.new();host.add_child(batch);batch.set_process(false)
		var nodes:Array=[];var material:=StandardMaterial3D.new()
		for i:int in 98:
			var mesh:=Cpu.new();var vertices:=PackedVector3Array();var normals:=PackedVector3Array()
			for j:int in 200:
				vertices.append_array(PackedVector3Array([Vector3(j*.001,i*.0001,0),Vector3(j*.001+1,i*.0001,0),Vector3(j*.001,i*.0001,1)]))
				for k:int in 3:normals.append(Vector3.UP)
			var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices;arrays[Mesh.ARRAY_NORMAL]=normals
			mesh.surfaces=[arrays];mesh.bounds=AABB(Vector3.ZERO,Vector3(2,1,1));mesh.materials=[material]
			var node:=MeshInstance3D.new();node.name="part_%03d"%i;node.mesh=mesh;node.position=Vector3(i*.01,0,0)
			node.set_meta("ground_batch_record",{"uuid":str(node.name),"kind":"box","size":[1,1,1],"building":{"id":"building","floor":0,"part":str(node.name),"role":"wall"}})
			host.add_child(node);nodes.append(node)
		batch.request_residency_sync(nodes);var max_hashes:=0
		while not batch._preparation.is_empty():
			var before:=identities(nodes);batch._prepare_step(1);max_hashes=maxi(max_hashes,identities(nodes)-before)
		var early:=identities(nodes);var began:=Time.get_ticks_usec()
		while not batch.pending.is_empty():batch._build_next(true)
		var launch_us:=Time.get_ticks_usec()-began;var commit_hashes:=identities(nodes)-early
		check(early+commit_hashes==98,"all 98 uncached geometry identities are actually exercised")
		check(early==98 and commit_hashes==0 and max_hashes<=1,"worker launch has no bulk geometry hashing beyond bounded preparation")
		while not batch._workers.is_empty():batch._finish_worker(0)
		check(batch.results.size()==1,"98 sources retain one spatial building batch")
		if expected.is_empty():expected=batch.results.duplicate(true)
		check(batch.results==expected,"same building identity and exact output geometry on repeat")
		trials.append({"prepare_hashes":early,"launch_hashes":commit_hashes,"max_hashes_per_tiny_slice":max_hashes,"launch_us":launch_us})
		batch.clear(false);host.free()
	print("SLICED_BUILDING_IDENTITY ",JSON.stringify({"trials":trials,"failures":failures}));quit(1 if failures else 0)
