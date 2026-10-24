extends "res://tools/test_collision_priority_reuse.gd"
const Plan=preload("res://scripts/world3d/collision_priority_plan.gd")
func source(mesh:Mesh,i:int)->Dictionary:
	var point:=Vector3((i%37)*4.-72.,0.,(i%19)*4.-36.)
	var low:=Stream.chunk_key(point-Vector3.ONE);var high:=Stream.chunk_key(point+Vector3.ONE)
	return {"uuid":"row%d"%i,"mesh":mesh,"transform":Transform3D(Basis.IDENTITY,point),"chunk":low,"chunk_min":low,"chunk_max":high,"extras":{}}
func run()->void:
	var baseline:bool="--baseline" in OS.get_cmdline_user_args()
	var mesh:=BoxMesh.new();mesh.size=Vector3(2,1,2)
	var jobs:Array=[]
	for i:int in 2400:jobs.append(source(mesh,i))
	var cursor:=0;var next_id:=jobs.size();var classifications:Dictionary={};var dirty:Dictionary={}
	var draw:={"low":Vector2i(-1,-1),"high":Vector2i(1,1)};var bodies:Dictionary={};var meshes:Dictionary={}
	var origin:=Vector3.ZERO;var elapsed:=0;var classified:=0;var reused:=0;var expected_classified:=jobs.size()-1
	for update:int in 32:
		var expected:=jobs.duplicate();Stream.prioritize_local_collisions(expected,cursor,origin,bodies,draw,meshes)
		var original:=jobs.duplicate();var unchanged:=true
		var work:RefCounted=Plan.new(Stream,jobs,cursor,origin,bodies,draw,meshes) if baseline else Plan.new.callv([Stream,jobs,cursor,origin,bodies,draw,meshes,classifications,dirty])
		while not work.advance(1000):unchanged=unchanged and jobs==original
		elapsed+=int(work.profile.elapsed_us)
		check(unchanged,"partial reorder keeps active jobs unchanged")
		classified+=int(work.profile.get("classified_rows",work.profile.rows));reused+=int(work.profile.get("reused_rows",0))
		if not baseline:classifications=work.classifications
		check(ids(jobs)==ids(expected),"continuous arrivals match full stable priority order "+str(update))
		check(is_same(jobs[cursor],original[cursor]),"active asynchronous collision keeps its exact source")
		if update==31:break
		for i:int in 4:bodies[jobs[cursor+i].uuid]=true
		cursor+=4;dirty={}
		for i:int in 12:
			var row:=source(mesh,next_id);next_id+=1;jobs.append(row);dirty[row.uuid]=true
		expected_classified+=12
	# Existing support bounds can change on Index.append without adding its UUID.
	var changed:Dictionary=jobs[cursor+20];changed.ground_batch_record={"terrain_mesh":{}};changed.render_bounds={"chunk_min":Vector2i(1000,1000),"chunk_max":Vector2i(1001,1001)};changed.render_dependents=[{"chunk_min":Vector2i.ZERO,"chunk_max":Vector2i.ONE}]
	dirty={changed.uuid:true};var expected:=jobs.duplicate();Stream.prioritize_local_collisions(expected,cursor,origin,bodies,draw,meshes)
	var work:RefCounted=Plan.new(Stream,jobs,cursor,origin,bodies,draw,meshes) if baseline else Plan.new.callv([Stream,jobs,cursor,origin,bodies,draw,meshes,classifications,dirty])
	while not work.advance(1):pass
	check(ids(jobs)==ids(expected),"affected existing support is reclassified even when already queued")
	# A destination change discards the old classification scope.
	origin=Vector3(160,0,0);expected=jobs.duplicate();Stream.prioritize_local_collisions(expected,cursor,origin,bodies,draw,meshes)
	work=Plan.new(Stream,jobs,cursor,origin,bodies,draw,meshes)
	while not work.advance(1000):pass
	check(ids(jobs)==ids(expected),"movement still fully reclassifies the pending plan")
	var map:=Node3D.new();map.set_meta("stream_append_pending",[changed])
	check(Stream.append_ready_jobs(map,jobs,cursor,draw,draw,meshes,bodies) and map.get_meta("stream_collision_priority_dirty",{}).has(changed.uuid),"changed queued support requests priority repair without duplicate insertion")
	var expected_scan:=jobs.size()-cursor
	for i:int in 20:
		map.set_meta("stream_append_pending",[changed]);Stream.append_ready_jobs(map,jobs,cursor,draw,draw,meshes,bodies)
	check(int(map.get_meta("stream_job_catalog_scan_rows"))==expected_scan,"repeated arrivals reuse queued identities without a full tail scan")
	var replacement:Array=jobs.duplicate();map.set_meta("stream_append_pending",[changed]);Stream.append_ready_jobs(map,replacement,cursor,draw,draw,meshes,bodies)
	check(int(map.get_meta("stream_job_catalog_scan_rows"))==expected_scan*2,"replacement queue rebuilds its own membership catalog")
	map.set_meta("stream_append_pending",[changed]);Stream.append_ready_jobs(map,replacement,cursor+1,draw,draw,meshes,bodies)
	check(int(map.get_meta("stream_job_catalog_scan_rows"))==expected_scan*3-1,"external cursor changes invalidate cached consumed membership")
	map.free()
	var before:=jobs.duplicate();var cache_bytes:=var_to_bytes(classifications)
	work=Plan.new.callv([Stream,jobs,cursor,origin,bodies,draw,meshes,classifications,{}]) if not baseline else Plan.new(Stream,jobs,cursor,origin,bodies,draw,meshes)
	check(not work.advance(1) and jobs==before and var_to_bytes(classifications)==cache_bytes,"cancelled partial priority work cannot mutate the queue or previous cache")
	work=null
	if not baseline:check(classified==expected_classified and reused>50000,"stationary arrivals classify each pending source only once")
	print("INCREMENTAL_COLLISION_PRIORITY ",JSON.stringify({"baseline":baseline,"classified":classified,"reused":reused,"us":elapsed,"failures":failures}));quit(1 if failures else 0)
