extends SceneTree
## Reject semantics and byte identity, then unpainted unindexed-surface pressure.
const Paint=preload("res://scripts/world3d/surface_materials.gd")
var checks:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func surface(triangles:int)->Array:
	var vertices:=PackedVector3Array();vertices.resize(triangles*3)
	for i:int in triangles:
		var offset:=Vector3(i*2,0,0)
		vertices[i*3]=offset
		vertices[i*3+1]=offset+Vector3.RIGHT
		vertices[i*3+2]=offset+Vector3.FORWARD
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX);arrays[Mesh.ARRAY_VERTEX]=vertices
	return arrays
func run()->void:
	var first:=surface(2)
	for indexed:bool in [false,true]:
		var extra:=surface(3)
		if indexed:extra[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,2,3,4,5,6,7,8])
		var source:Array=[first,extra]
		var original:=var_to_bytes(source)
		var complete:=Paint.geometry_arrays(source)
		var partial:=Paint.geometry_arrays(source,false,true)
		check(complete.ok and partial.ok,"valid indexed/unindexed input accepted")
		check(var_to_bytes(complete.surfaces.slice(0,1))==var_to_bytes(partial.surfaces),"partial topology and signature byte-identical to full first surface")
		check(var_to_bytes(source)==original,"borrowed arrays are immutable")
	for channel:int in [Mesh.ARRAY_BONES,Mesh.ARRAY_CUSTOM0,Mesh.ARRAY_CUSTOM1,Mesh.ARRAY_CUSTOM2,Mesh.ARRAY_CUSTOM3]:
		var unsupported:=surface(1);unsupported[channel]=PackedInt32Array([1])
		var full:=Paint.geometry_arrays([first,unsupported])
		var partial:=Paint.geometry_arrays([first,unsupported],false,true)
		check(not partial.ok and var_to_bytes(full)==var_to_bytes(partial),"unpainted unsupported channel keeps exact rejection")
	for size:int in [0,50001]:
		var unsupported:=surface(size)
		var full:=Paint.geometry_arrays([unsupported])
		var partial:=Paint.geometry_arrays([first,unsupported],false,true)
		check(not partial.ok and var_to_bytes(full)==var_to_bytes(partial),"unpainted invalid triangle count keeps exact rejection")
	var indexed:=surface(1);indexed[Mesh.ARRAY_INDEX]=PackedInt32Array();indexed[Mesh.ARRAY_INDEX].resize(150003)
	check(not Paint.geometry_arrays([first,indexed],false,true).ok,"indexed count still determines size rejection")
	# Four untouched slots at the accepted limit: 600,000 indices would be
	# allocated/written per call solely to discard them before grouping.
	var tail:=surface(50000)
	var pressure:Array=[first,tail,tail,tail,tail]
	var times:Array=[]
	for sample:int in 5:
		var began:=Time.get_ticks_usec()
		for repetition:int in 16:
			var result:=Paint.geometry_arrays(pressure,false,true)
			check(result.ok and result.surfaces.size()==1,"stress returns only required topology")
		times.append(Time.get_ticks_usec()-began)
	print("TOPOLOGY_ELISION ",JSON.stringify({"checks":checks,"failures":failures,"rounds_us":times,"calls_per_round":16,"unneeded_indices_per_call":600000,"source_sha256":FileAccess.get_sha256("res://scripts/world3d/surface_materials.gd")}))
	quit(1 if failures else 0)
