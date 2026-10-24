extends "res://tools/test_collision_priority_reuse.gd"
var trial_rows:Array=[]
func planned(rows:Array,draw:Dictionary,meshes:Dictionary,bodies:Dictionary,batched:Dictionary,budget:int=0)->Array:
	var map:=Node.new();var jobs:Array=[]
	map.set_meta("stream_candidates",rows);map.set_meta("stream_plan_cursor",0);map.set_meta("stream_plan_bins",[[],[],[],[],[]])
	map.set_meta("fortification_collision_sources",batched)
	if draw.has("entry_clip"):map.set_meta("entry_stream_clip",draw.entry_clip)
	else:map.set_meta("stream_sources",{"remote":Vector2i(91,91),"other":Vector2i(-89,-89)})
	while not Stream._plan_jobs(map,jobs,meshes,bodies,Vector2i.ZERO,budget):pass
	map.free();return jobs
func oracle(rows:Array,draw:Dictionary,meshes:Dictionary,bodies:Dictionary,batched:Dictionary)->Array:
	var solid:Dictionary={"entry_clip":draw.entry_clip} if draw.has("entry_clip") else {"low":Vector2i(-2,-2),"high":Vector2i(2,2),"sources":[{"low":Vector2i(89,89),"high":Vector2i(93,93)},{"low":Vector2i(-91,-91),"high":Vector2i(-87,-87)}]}
	var bins:Array=[[],[],[],[],[]];var jobs:Array=[]
	for item:Dictionary in rows:
		if not Stream._needs_work(item,draw,solid,meshes,bodies,batched):continue
		var visible:bool=Stream._draws(item,draw);var bin:=1 if Stream._overlaps(item,solid) else 3
		if Stream.Landscape.ground(item):bin=0 if visible else 4
		elif item.has("render_building"):bin=2 if visible else 0
		bins[bin].append(item)
	for bin:Array in bins:jobs.append_array(bin)
	return jobs
func compare(rows:Array,draw:Dictionary,_origin:Vector3,label:String)->void:
	if draw.is_empty() or draw.get("sources",[]).size()!=2 and not draw.has("entry_clip"):return
	trial_rows=rows
	var node:=MeshInstance3D.new();node.set_meta(Stream.GroundBatcher.SUSPENDED_DRAW,true)
	var deleted:=Node.new();deleted.free()
	var meshes:={"row7":node,"row8":deleted};var bodies:={"row19":node};var batched:={"row20":true}
	var expected:=oracle(rows,draw,meshes.duplicate(),bodies.duplicate(),batched)
	for budget:int in [0,1]:
		var actual:=planned(rows,draw,meshes.duplicate(),bodies.duplicate(),batched,budget)
		var same:=ids(actual)==ids(expected)
		for i:int in actual.size():same=same and is_same(actual[i],expected[i])
		check(same,"job plan preserves exact owners and stable bins: "+label+" budget="+str(budget))
	node.free()
func run()->void:
	super.run()
	var draw:={"low":Vector2i(-1,-1),"high":Vector2i(1,1),"sources":[{"low":Vector2i(90,90),"high":Vector2i(92,92)},{"low":Vector2i(-90,-90),"high":Vector2i(-88,-88)}]}
	var timings:Array=[]
	for round_:int in 4:
		var began:=Time.get_ticks_usec()
		for repeat:int in 20:planned(trial_rows,draw,{},{},{})
		timings.append(Time.get_ticks_usec()-began)
	print("STREAM_JOB_CLASSIFICATION ",JSON.stringify({"rows":trial_rows.size(),"plans":20,"trials_us":timings,"failures":failures}))
	quit(1 if failures else 0)
