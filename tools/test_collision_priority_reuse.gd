extends SceneTree
const Stream=preload("res://scripts/world3d/world_stream.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func ids(rows:Array)->Array:
	var result:Array=[]
	for row:Dictionary in rows:result.append(row.uuid)
	return result
func compare(rows:Array,draw:Dictionary,origin:Vector3,label:String)->void:
	var reference:=rows.duplicate();var candidate:=rows.duplicate()
	Stream.collision_priority_reuse_enabled=false
	Stream.prioritize_local_collisions(reference,1,origin,{"row19":true},draw,{"row7":true})
	Stream.collision_priority_reuse_enabled=true
	Stream.prioritize_local_collisions(candidate,1,origin,{"row19":true},draw,{"row7":true})
	var same:=ids(reference)==ids(candidate)
	for i:int in rows.size():same=same and is_same(reference[i],candidate[i])
	check(same,label)
	check(is_same(candidate[0],rows[0]) and is_same(candidate[1],rows[1]),"completed prefix and current collision preparation stay in place")
func run()->void:
	var mesh:=BoxMesh.new();mesh.size=Vector3(2,1,2)
	var rows:Array=[];var bounds:={"chunk_min":Vector2i(-2,-2),"chunk_max":Vector2i(2,2)}
	var dependents:Array=[]
	for i:int in 4600:
		var position:=Vector3((i%37)*4.-72.,0.,(i%19)*4.-36.)
		var low:=Stream.chunk_key(position-Vector3.ONE);var high:=Stream.chunk_key(position+Vector3.ONE)
		var spec:={"uuid":"row%d"%i,"mesh":mesh,"transform":Transform3D(Basis.IDENTITY,position),"chunk":low,"chunk_min":low,"chunk_max":high,"render_building":"group","render_bounds":bounds,"render_dependents":dependents,"extras":{}}
		if i%47==0:spec.extras.rmmo_collision="none"
		if i%59==0:spec.extras.ally=true
		if i%71==0:spec.native_visual=true
		if i%83==0:spec.ground_batch_record={"terrain_mesh":{}}
		rows.append(spec)
	var draw:={"low":Vector2i(-1,-1),"high":Vector2i(1,1),"sources":[{"low":Vector2i(90,90),"high":Vector2i(92,92)},{"low":Vector2i(-90,-90),"high":Vector2i(-88,-88)}]}
	compare(rows,draw,Vector3.ZERO,"shared envelopes retain exact ground/local/visual/rest order")
	# Equal group names do not prove shared mutable envelopes or dependencies.
	rows[11].render_bounds={"chunk_min":Vector2i(1000,1000),"chunk_max":Vector2i(1001,1001)}
	rows[12].render_bounds=rows[11].render_bounds
	rows[12].render_dependents=[bounds]
	rows[13].erase("render_bounds");rows[14].erase("render_building")
	compare(rows,draw,Vector3(200,0,0),"different envelope/dependency identities and ungrouped parts fall back correctly")
	compare(rows,{"entry_clip":AABB(Vector3(-2,-2,-2),Vector3(4,4,4))},Vector3.ZERO,"entry clip uses each part's exact mesh bounds")
	var nested:={"low":Vector2i(1000,1000),"high":Vector2i(1001,1001),"sources":[{"low":Vector2i(1000,1000),"high":Vector2i(1001,1001),"sources":[{"entry_clip":AABB(Vector3(-2,-2,-2),Vector3(4,4,4))}]}]}
	compare(rows,nested,Vector3(200,0,0),"nested entry source cannot reuse whole-group visibility")
	bounds.chunk_min=Vector2i(1000,1000);bounds.chunk_max=Vector2i(1001,1001)
	compare(rows,draw,Vector3(200,0,0),"changed shared bounds are read again on the next reorder")
	dependents.append({"chunk_min":Vector2i.ZERO,"chunk_max":Vector2i.ONE})
	compare(rows,draw,Vector3(200,0,0),"changed dependent support is read on the next reorder")
	compare(rows,{},Vector3.ZERO,"collision-only order remains unchanged")
	var measurements:Array=[]
	for enabled:bool in [false,true,true,false]:
		Stream.collision_priority_reuse_enabled=enabled
		var began:=Time.get_ticks_usec()
		for repeat:int in 20:
			var jobs:=rows.duplicate()
			Stream.prioritize_local_collisions(jobs,1,Vector3(200,0,0),{},draw,{})
		measurements.append({"reuse":enabled,"elapsed_us":Time.get_ticks_usec()-began})
	Stream.collision_priority_reuse_enabled=true
	print("COLLISION_PRIORITY_REUSE ",JSON.stringify({"rows":rows.size(),"reorders":20,"measurements":measurements,"failures":failures}))
	quit(1 if failures else 0)
