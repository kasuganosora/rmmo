extends SceneTree
const Cpu=preload("res://scripts/world3d/ground_cpu_mesh.gd")
const Terrain=preload("res://scripts/world3d/terrain_collision_preparer.gd")
const Prefetch=preload("res://scripts/world3d/collision_face_prefetch.gd")
const Token=preload("res://scripts/world3d/asset_worker_drainer.gd").CancelToken
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func surface(count:int,indexed:bool)->Array:
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	var vertices:=PackedVector3Array();vertices.resize(count)
	for i:int in count:vertices[i]=Vector3(i%19*.1,(i%7)*.15,-float(i/19)*.1)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	if indexed:
		var indices:=PackedInt32Array();indices.resize(count)
		for i:int in count:indices[i]=count-1-i
		arrays[Mesh.ARRAY_INDEX]=indices
	return arrays
func oracle(surfaces:Array,basis:Basis)->PackedVector3Array:
	var result:=PackedVector3Array()
	for arrays:Array in surfaces:
		var vertices:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var indices:Variant=arrays[Mesh.ARRAY_INDEX]
		if indices!=null and not indices.is_empty():
			for i:int in indices:result.append(basis*vertices[i])
		else:
			for vertex:Vector3 in vertices:result.append(basis*vertex)
	return result
func run()->void:
	var rotations:Array=[Basis.IDENTITY,Basis(Vector3.UP,.63).scaled_local(Vector3(1.3,.7,2.1)),Basis.from_euler(Vector3(.31,-.2,.51)).scaled_local(Vector3(-.8,2.,1.4))]
	for mixed:bool in [false,true]:
		var surfaces:Array=[surface(900,false),surface(600,mixed),surface(0,false)]
		var before:=var_to_bytes(surfaces)
		for basis:Basis in rotations:
			var expected:=oracle(surfaces,basis)
			var result:=Terrain._extract(surfaces,basis)
			check(result==expected,"generic extraction preserves every ordered vertex under identity/rotated/nonuniform/reflected basis")
			var local:=oracle(surfaces,Basis.IDENTITY);var local_before:=var_to_bytes(local)
			check(Terrain._extract([],basis,local)==expected and var_to_bytes(local)==local_before,"completed local-space input remains unchanged")
			var snapshot:Dictionary={"id":"road","count":1500,"faces":PackedVector3Array(),"basis":basis,"surfaces":surfaces}
			var packet:=Prefetch._build([snapshot],Token.new())
			check(packet.faces.road==expected,"lookahead uses the exact same indexed and unindexed triangle order")
			check(snapshot.faces.is_empty(),"fresh lookahead never fills or transforms the borrowed empty snapshot")
			var completed:Dictionary={"id":"road","count":local.size(),"faces":local,"basis":basis,"surfaces":[]}
			var transformed:=Prefetch._build([completed],Token.new())
			check(transformed.faces.road==expected and var_to_bytes(local)==local_before,"completed lookahead preserves its local-space input")
			if basis!=Basis.IDENTITY:
				transformed.faces.road[0]=Vector3(777,777,777)
				check(var_to_bytes(local)==local_before,"transformed completed output has private ownership")
			packet.faces.road[0]=Vector3(999,999,999);result[0]=Vector3(888,888,888)
			check(var_to_bytes(surfaces)==before,"mutable output never aliases source channels")
			var stopped:=Token.new();stopped.cancel()
			check(Prefetch._build([snapshot],stopped).is_empty(),"cancelled lookahead exposes no partial result")
	var large:Array=[surface(150000,false),surface(150000,false)]
	var basis:Basis=rotations[1];var expected:=oracle(large,basis);var before:=var_to_bytes(large)
	var trials:Array=[]
	for trial:int in 4:
		var began:=Time.get_ticks_usec();var faces:=PackedVector3Array()
		for repeat:int in 6:
			var cpu:=Cpu.new();cpu.surfaces=large;faces=cpu.collision_faces()
		var copy_us:=Time.get_ticks_usec()-began;began=Time.get_ticks_usec()
		for repeat:int in 6:faces=Terrain._extract(large,basis)
		var transform_us:=Time.get_ticks_usec()-began
		var local:=oracle(large,Basis.IDENTITY);var local_before:=var_to_bytes(local)
		began=Time.get_ticks_usec()
		for repeat:int in 6:faces=Terrain._extract([],basis,local)
		var completed_transform_us:=Time.get_ticks_usec()-began;began=Time.get_ticks_usec()
		var snapshot:Dictionary={"id":"road","count":300000,"faces":PackedVector3Array(),"basis":basis,"surfaces":large}
		var packet:Dictionary
		for repeat:int in 6:packet=Prefetch._build([snapshot],Token.new())
		var prefetch_us:=Time.get_ticks_usec()-began
		var completed:Dictionary={"id":"road","count":300000,"faces":local,"basis":basis,"surfaces":[]}
		began=Time.get_ticks_usec()
		var completed_packet:Dictionary
		for repeat:int in 6:completed_packet=Prefetch._build([completed],Token.new())
		trials.append({"copy_us":copy_us,"extract_transform_us":transform_us,"completed_transform_us":completed_transform_us,"prefetch_us":prefetch_us,"completed_prefetch_us":Time.get_ticks_usec()-began})
		check(faces==expected and packet.faces.road==expected and completed_packet.faces.road==expected and snapshot.faces.is_empty() and var_to_bytes(local)==local_before and var_to_bytes(large)==before,"large extraction/transform/prefetch outputs and source ownership agree")
	print("COLLISION_FACE_BULK ",JSON.stringify({"trials":trials,"vertices":300000,"calls_per_trial":6,"failures":failures}))
	quit(1 if failures else 0)
