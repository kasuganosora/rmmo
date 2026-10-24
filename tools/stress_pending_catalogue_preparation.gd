extends "res://tools/test_deferred_typed_demand_scan.gd"
const Preparation=preload("res://scripts/world3d/pending_catalogue_preparation.gd")
const Loader=preload("res://scripts/world3d/map_loader.gd")

func records(count_:int)->Array:
	var result:Array=[]
	for i:int in count_:
		var row:=item("row%d"%i,float((i%64)*16-512),1,"path%d"%(i%23))
		row.bounds.position.z=(i/64)*16-256
		if i%37==0:row.bounds.size=Vector3(512,1,512)
		if i%5==0:row.group_id="building:%d"%(i%13)
		row.reference_entry={"reason":["native_road","native_bridge","native_fortification","ordinary"][i%4]}
		result.append(row)
	return result

func tickets(q:Deferred,iteration:int=0)->void:
	q._priority=Vector3(iteration*7-50,0,iteration*3-20)
	q._demands={}
	for kind:String in ["building","road","structure","all"]:
		var radius:=32. if iteration%3==1 else 2400.
		q._demands[kind]={"kind":kind,"priority":iteration%3,"clip":AABB(q._priority-Vector3(radius,1,radius),Vector3(radius*2,2,radius*2))}
	q._demands.group={"kind":"all","priority":-1,"group_id":"building:1","clip":AABB()}
	q._demand_scope={"road":true,"structure":true} if iteration%3==2 else {}
	q._demand_membership.clear();q._demand_revision+=1

func work(jobs:Array,indices:Array)->Array:
	var result:Array=[]
	for i:int in indices:result.append(Preparation.prepare(jobs[i]))
	return result

func run()->void:
	var logger:=Errors.new();OS.add_logger(logger)
	var original:=records(2048);var baseline:=Deferred.new();baseline.pending=original.duplicate(true);tickets(baseline)
	var began:=Time.get_ticks_usec();baseline._index_pending();baseline._typed_full_scan_inputs()
	var legacy_us:=Time.get_ticks_usec()-began
	var fresh:=original.duplicate(true);var thread:=Thread.new()
	thread.start(Preparation.prepare.bind(fresh));var prepared:RefCounted=thread.wait_to_finish()
	var q:=Deferred.new();q.pending=fresh;tickets(q)
	check(q.adopt_prepared_pending(prepared),"joined parser catalogue is adopted once")
	check(prepared.consumed and prepared.owners.is_empty() and q._pending_by_record_id.size()==2048,"ownership transfer keeps adopted containers intact")
	check(not q.adopt_prepared_pending(prepared),"consumed output cannot be adopted twice")
	check(var_to_bytes(baseline.pending)==var_to_bytes(q.pending),"exact source rows and cached bounds match the old index")
	check(q._pending_index==baseline._pending_index and q._pending_native_index==baseline._pending_native_index and q._large_pending==baseline._large_pending,"exact cell membership and large-first order")
	for iteration:int in 24:
		for queue:Deferred in [baseline,q]:
			if iteration==3:
				var removed:Array=queue.pending.slice(0,80)
				for row:Dictionary in removed:row.published=true
				queue._remove_published_demand(removed)
			if iteration==6:
				queue.register_runtime_building("row123",queue._pending_by_record_id.row123.bounds,{"row2000":true})
			if iteration==9:
				var row:=item("return",50,1,"path0");row.group_id="building:return";row.bounds.size=Vector3(512,1,512)
				queue.pending.append(row);queue._index_pending_item(row)
			queue.instance_errors={"row200":"intentional fixture error"};tickets(queue,iteration);queue._refresh_demanded()
		check(snapshot(q)==snapshot(baseline),"live ranks, paths, scope, support, publication and return match %d"%iteration)
	check(int(q.profile.get("pending_index_builds",0))==0,"all 2048 initial index rows stay off main")
	var checks:=[records(4),records(4),records(4),records(4)]
	checks[1][1].record.uuid=checks[1][0].record.uuid
	for i:int in checks.size():
		var packet:RefCounted=Preparation.prepare(checks[i]);var receiver:=Deferred.new();receiver.pending=checks[i]
		if i==0:receiver.pending=receiver.pending.duplicate()
		if i==2:receiver.pending.append(item("added",0))
		if i==3:receiver._runtime_building_records.learned=AABB()
		check(not receiver.adopt_prepared_pending(packet) and not receiver._indexed,"mismatched/aliased/changed/learned queues retain fallback %d"%i)
		receiver._index_pending();check(receiver._indexed,"fallback remains usable %d"%i);receiver.free()
	var loader:=Loader.new();loader._deferred_assets=records(8);loader._prepared_pending=Preparation.prepare(loader._deferred_assets)
	var actual:Deferred=loader._new_deferred()
	check(actual._indexed and actual.profile.pending_worker_indexed_rows==8 and loader._prepared_pending==null,"real map loader hands off preparation to the initial queue")
	actual.free();loader.free()
	var parallel:Array=[]
	# Fixed twelve independent private catalogues in every run; never share a
	# mutable pending row between workers or increase useful work with threads.
	for workers:int in [1,3,12]:
		var jobs:Array=[]
		for i:int in 12:jobs.append(original.duplicate(true))
		var threads:Array=[];began=Time.get_ticks_usec()
		for worker:int in workers:
			var indices:Array=[]
			for i:int in range(worker,12,workers):indices.append(i)
			var worker_thread:=Thread.new();worker_thread.start(work.bind(jobs,indices));threads.append(worker_thread)
		var outputs:Array=[]
		for worker_thread:Thread in threads:outputs.append_array(worker_thread.wait_to_finish())
		var elapsed:=Time.get_ticks_usec()-began;var worker_us:=0;var rows:=0;var adopt_us:=0
		for packet:RefCounted in outputs:
			rows+=packet.count;worker_us+=packet.elapsed_us
			var receiver:=Deferred.new();receiver.pending=packet.rows
			check(receiver.adopt_prepared_pending(packet),"private catalogue transfer at %d workers"%workers)
			adopt_us+=receiver.profile.pending_worker_adopt_us;receiver.free()
		check(rows==24576,"fixed total work at %d workers"%workers)
		parallel.append({"workers":workers,"wall_us":elapsed,"worker_sum_us":worker_us,"main_adopt_us":adopt_us,"rows":rows})
	var report:={"legacy_main_us":legacy_us,"worker_prepare_us":q.profile.pending_worker_prepare_us,"main_adopt_us":q.profile.pending_worker_adopt_us,"parallel":parallel}
	q.free();baseline.free();OS.remove_logger(logger)
	check(logger.errors.is_empty(),"zero script/engine errors");report.failures=failed
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):var file:=FileAccess.open(arg.trim_prefix("--output="),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("PENDING_CATALOGUE_PREPARATION ",JSON.stringify(report));quit(1 if failed else 0)
