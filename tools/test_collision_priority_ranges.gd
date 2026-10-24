extends "res://tools/test_incremental_collision_priority.gd"
## Repeated stationary arrivals must not revisit every already partitioned row
## in GDScript. Compare the entire stable order, not just the four counts.
func run()->void:
	var baseline:bool="--baseline" in OS.get_cmdline_user_args()
	var mesh:=BoxMesh.new();mesh.size=Vector3(2,1,2)
	var jobs:Array=[]
	for i:int in 4000:jobs.append(source(mesh,i))
	var cursor:=0;var next_id:=jobs.size();var classes:Dictionary={};var dirty:Dictionary={};var partition:Dictionary={}
	var draw:={"low":Vector2i(-1,-1),"high":Vector2i(1,1)};var bodies:Dictionary={};var meshes:Dictionary={}
	var origin:=Vector3.ZERO;var elapsed:=0;var rows:=0;var bulk:=0;var reused_class_owners:=0
	for update:int in 48:
		var expected:=jobs.duplicate();Stream.prioritize_local_collisions(expected,cursor,origin,bodies,draw,meshes)
		var before:=jobs.duplicate();var args:Array=[Stream,jobs,cursor,origin,bodies,draw,meshes,classes,dirty]
		if not baseline:args.append(partition)
		var work:RefCounted=Plan.new.callv(args);var atomic:=true
		while not work.advance(1000):atomic=atomic and jobs==before
		check(atomic and ids(jobs)==ids(expected) and is_same(jobs[cursor],before[cursor]),"arrival preserves full stable order and active owner "+str(update))
		elapsed+=int(work.profile.elapsed_us)+int(work.profile.get("setup_us",0));rows+=int(work.profile.rows);bulk+=int(work.profile.get("bulk_reused_rows",0))
		if update>0 and is_same(work.classifications,classes):reused_class_owners+=1
		classes=work.classifications
		if not baseline:partition=work.get("partition")
		if update==47:break
		for i:int in 7:bodies[jobs[cursor+i].uuid]=true
		cursor+=7;dirty={}
		for i:int in 24:
			var row:=source(mesh,next_id);next_id+=1;jobs.append(row);dirty[row.uuid]=true
	var changed:Dictionary=jobs[cursor+20]
	changed.ground_batch_record={"terrain_mesh":{}};changed.render_bounds={"chunk_min":Vector2i(1000,1000),"chunk_max":Vector2i(1001,1001)};changed.render_dependents=[{"chunk_min":Vector2i.ZERO,"chunk_max":Vector2i.ONE}]
	var expected:=jobs.duplicate();Stream.prioritize_local_collisions(expected,cursor,origin,bodies,draw,meshes)
	var args:Array=[Stream,jobs,cursor,origin,bodies,draw,meshes,classes,{changed.uuid:true}]
	if not baseline:args.append(partition)
	var work:RefCounted=Plan.new.callv(args)
	while not work.advance(1000):pass
	check(ids(jobs)==ids(expected) and int(work.profile.get("bulk_reused_rows",0))==0,"changed old support falls back to exact stable repair")
	classes=work.classifications
	if not baseline:partition=work.get("partition")
	var replacement:=jobs.duplicate();args=[Stream,replacement,cursor,origin,bodies,draw,meshes,classes,{}]
	if not baseline:args.append(partition)
	work=Plan.new.callv(args)
	while not work.advance(1000):pass
	check(replacement==jobs and int(work.profile.get("bulk_reused_rows",0))==0,"replacement array cannot inherit another queue's range ownership")
	origin=Vector3(160,0,0);expected=jobs.duplicate();Stream.prioritize_local_collisions(expected,cursor,origin,bodies,draw,meshes)
	args=[Stream,jobs,cursor,origin,bodies,draw,meshes,{},{}]
	if not baseline:args.append(partition)
	work=Plan.new.callv(args)
	while not work.advance(1000):pass
	check(ids(jobs)==ids(expected) and int(work.profile.get("bulk_reused_rows",0))==0,"movement reclassifies the live queue")
	if not baseline:
		check(rows==3999+47*24 and bulk>180000,"stationary append visits only first partition and new rows in script")
		check(reused_class_owners==47,"completed range updates transfer the classification owner without copying every old key")
		partition=work.get("partition");classes=work.classifications
		for i:int in 64:jobs.append(source(mesh,next_id));next_id+=1
		var before:=jobs.duplicate();var previous_bytes:=var_to_bytes(classes)
		work=Plan.new.callv([Stream,jobs,cursor,origin,bodies,draw,meshes,classes,{},partition])
		check(not work.advance(1) and jobs==before and var_to_bytes(classes)==previous_bytes,"cancelled range reuse leaves queue and previous classifications untouched")
		work=null
	print("COLLISION_PRIORITY_RANGES ",JSON.stringify({"baseline":baseline,"script_rows":rows,"bulk_reused_rows":bulk,"work_us":elapsed,"failures":failures}));quit(1 if failures else 0)
