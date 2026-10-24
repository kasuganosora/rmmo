extends "res://tools/test_deferred_collision_publication.gd"
func run()->void:
	var logger:=Errors.new();OS.add_logger(logger)
	var trials:Array=[]
	for borrow:bool in [false,true,true,false]:
		Deferred.borrow_publication_rows_enabled=borrow
		var rows:Array=[]
		for at:int in 4096:rows.append(item("row%d"%at,"reference:batch%d"%(at/64),float(at%512)))
		var f:=fixture(rows);var q:Node=f.queue;var first:Array=[]
		var started:=Time.get_ticks_usec()
		for repeat:int in 24:
			q._publication_queues.clear();first=q._publication_ready()
		trials.append({"borrow":borrow,"us":Time.get_ticks_usec()-started,"copies":q.profile.publication_snapshot_rows_copied,"heads":first.size()})
		var path:String=first[0].path;var borrowed:Array=q._publication_queues[path].items;var original:Array=borrowed.duplicate()
		check(is_same(borrowed,q._demanded_by_path[path])==borrow,"cursor owns the expected copied or borrowed generation")
		q._remove_published_demand([first[0]])
		check(borrowed==original and not is_same(borrowed,q._demanded_by_path[path]),"publication replaces the live path without mutating an existing cursor")
		q._demand_revision+=1;q._refresh_demanded()
		check(q._publication_queues.is_empty() and borrowed==original,"rank refresh resets cursors while old borrowed arrays stay intact")
		q._publication_ready()
		check(not q._demanded_by_id.has(first[0].record.uuid),"new cursor cannot revive a removed owner")
		q.shutdown();check(q._jobs.is_empty() and q._admission.reserved_bytes==0,"cancel releases jobs and admission")
		f.map.free()
	check(trials[0].copies==98304 and trials[1].copies==0,"24 cursor generations remove 98304 redundant reference copies")
	for trial:Dictionary in trials:check(trial.heads==64,"every accepted path keeps the same ready head")
	Deferred.borrow_publication_rows_enabled=true;OS.remove_logger(logger)
	check(logger.errors.is_empty(),"zero engine/script errors")
	print("PUBLICATION_BORROWED_ROWS ",JSON.stringify({"trials":trials,"failures":failures}));quit(1 if failures else 0)
