extends SceneTree
const Stream=preload("res://scripts/world3d/world_stream.gd")
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func classify(rows:Array,draw:Dictionary,solid:Dictionary,meshes:Dictionary,bodies:Dictionary,reuse:bool)->Array:
	var groups:Dictionary={};var cells:Dictionary={};var result:Array=[]
	var can_reuse:=not Stream._draw_uses_exact_geometry(draw) and not Stream._draw_uses_exact_geometry(solid)
	for spec:Dictionary in rows:
		if Stream._job_bin(spec,draw,solid,meshes,bodies,{},groups,cells,can_reuse)>=0 if reuse else Stream._needs_work(spec,draw,solid,meshes,bodies):result.append(spec.uuid)
	return result
func run()->void:
	var box:=BoxMesh.new();var rows:Array=[];var meshes:Dictionary={};var bodies:Dictionary={};var owned:Array[Node]=[]
	var bounds:Dictionary={"chunk_min":Vector2i(999,999),"chunk_max":Vector2i(1000,1000)}
	var dependents:Array=[]
	for i in 64:dependents.append(bounds.duplicate())
	dependents.append({"chunk_min":Vector2i.ZERO,"chunk_max":Vector2i.ONE})
	for i in 2400:
		var row:Dictionary={"uuid":"part%d"%i,"mesh":box,"transform":Transform3D(Basis.IDENTITY,Vector3(i%4,0,0)),"chunk":Vector2i.ZERO,"chunk_min":Vector2i.ZERO,"chunk_max":Vector2i.ONE,"extras":{"rmmo_collision":"none" if i%5==0 else "block","hostile":i%9==0},"render_building":"shared","render_bounds":bounds,"render_dependents":dependents,"native_visual":i%13==0}
		rows.append(row)
		if i%3==0:
			var node:=Node3D.new();meshes[row.uuid]=node;owned.append(node)
			if i%6==0:node.set_meta(Stream.GroundBatcher.SUSPENDED_DRAW,true)
		if i%4==0:
			var node:=Node3D.new();bodies[row.uuid]=node;owned.append(node)
	var draw:Dictionary={"low":Vector2i(-1,-1),"high":Vector2i(1,1)}
	var classic:=0;var reused:=0;var expected:Array=[]
	for i in 8:
		var began:=Time.get_ticks_usec();expected=classify(rows,draw,draw,meshes,bodies,false);classic+=Time.get_ticks_usec()-began
		began=Time.get_ticks_usec();var actual:=classify(rows,draw,draw,meshes,bodies,true);reused+=Time.get_ticks_usec()-began
		check(actual==expected,"shared building bounds preserve live visual/body/hostile decisions")
	# Same group name with different owners must never alias; exact clips also
	# depend on individual transforms, including nested additional source clips.
	rows[17].render_bounds=bounds.duplicate();rows[17].render_dependents=[]
	var exact:Dictionary={"low":draw.low,"high":draw.high,"entry_clip":AABB(Vector3(-1,-1,-1),Vector3(2,2,2))}
	for area:Dictionary in [draw,exact,{"low":draw.low,"high":draw.high,"sources":[exact]}]:
		check(classify(rows,area,draw,meshes,bodies,true)==classify(rows,area,draw,meshes,bodies,false),"different bounds owners and exact nested clips retain individual classification")
	for node:Node in owned:node.free()
	check(classify(rows,draw,draw,meshes,bodies,true)==classify(rows,draw,draw,meshes,bodies,false),"freed node references are read live")
	var map:=Node3D.new();var jobs:Array=[];map.set_meta("stream_append_pending",rows)
	while map.has_meta("stream_append_pending"):Stream.append_ready_jobs(map,jobs,0,draw,draw,{}, {})
	var ids:Array=[]
	for spec:Dictionary in jobs:ids.append(spec.uuid)
	check(ids==classify(rows,draw,draw,{}, {},false),"production append preserves exact stable order without duplicates")
	map.free()
	print("APPEND_BOUNDS_REUSE ",JSON.stringify({"rows":rows.size(),"iterations":8,"classic_us":classic,"reused_us":reused,"shared_group_evaluations_per_slice":1,"individual_evaluations_per_slice":256,"failures":failures}))
	quit(1 if failures else 0)
