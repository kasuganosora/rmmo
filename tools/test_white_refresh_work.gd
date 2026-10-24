extends "res://tools/test_support_promotion_dedup.gd"
const Stream=preload("res://scripts/world3d/world_stream.gd")
func run()->void:
	var q:=make_queue();var reports:Array=[]
	for round_:int in 4:
		var began:=Time.get_ticks_usec()
		for i:int in 24:q._priority=Vector3(i*4,0,i*2);q._demand_revision+=1;q._refresh_demanded()
		reports.append({"us":Time.get_ticks_usec()-began,"rows":q._demanded.size(),"distance_evaluations":q.profile.get("demand_distance_evaluations",-1)})
	q.free()
	var mesh:=BoxMesh.new();var rows:Array=[]
	for i:int in 4600:
		var position:=Vector3((i%37)*4.-72.,0.,(i%19)*4.-36.)
		var low:=Stream.chunk_key(position-Vector3.ONE);var high:=Stream.chunk_key(position+Vector3.ONE)
		rows.append({"uuid":"row%d"%i,"mesh":mesh,"transform":Transform3D(Basis.IDENTITY,position),"chunk":low,"chunk_min":low,"chunk_max":high,"extras":{}})
	var priority:Array=[];var draw:={"low":Vector2i(-1,-1),"high":Vector2i(1,1)}
	for i:int in 4:
		var jobs:=rows.duplicate();var began:=Time.get_ticks_usec()
		Stream.prioritize_local_collisions(jobs,1,Vector3.ZERO,{},draw,{})
		priority.append(Time.get_ticks_usec()-began)
	print("WHITE_REFRESH_REPRO ",JSON.stringify({"demand_24_refreshes":reports,"collision_4600_rows_us":priority}));quit()
