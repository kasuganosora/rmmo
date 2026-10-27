extends "res://tools/test_deferred_typed_demand_scan.gd"
## Default-off diagnostic contract. This never opens a map or a renderer.
func reasons(snapshot_:Dictionary)->Dictionary:
	return snapshot_.get("source_counts",{})
func object_is_alive(reference:WeakRef)->bool:
	return reference.get_ref()!=null
func diagnostic_contract_test()->void:
	var trace=preload("res://scripts/world3d/demand_revision_trace.gd").new(20)
	var object:=RefCounted.new();var weak:WeakRef=weakref(object)
	var malformed:Dictionary={"clip":object,"priority":object,"kind":object,"group_id":object,"rank_from_player":object}
	trace.change("opaque","x".repeat(200),malformed,object,1)
	malformed.clear();object=null
	check(not object_is_alive(weak),"diagnostic never retains opaque Objects from malformed demand values")
	var observed:Dictionary=trace.snapshot();var event:Dictionary=observed.events[0]
	check(event.id.length()==128 and event.id_truncated and event.old_value==[null,null,"","",false] and event.new_value==null,"long IDs and non-scalar fields are bounded and sanitized")
	var ticket:Dictionary=trace.begin_refresh(1,-1,Vector3.ZERO,null,Time.get_ticks_usec(),1,0)
	trace.change("during_refresh","x",null,null,2)
	trace.end_refresh(ticket,2,0,0,{})
	observed=trace.snapshot()
	check(observed.events.back().causes.get("opaque",0)==1 and observed.pending_causes.get("during_refresh",0)==1,"new revisions during a refresh remain pending for the next boundary")
	ticket=trace.begin_refresh(2,1,Vector3(3,4,5),Vector3.ZERO,Time.get_ticks_usec(),1,0)
	trace.end_refresh(ticket,2,0,0,{})
	observed=trace.snapshot()
	check(observed.events.back().causes.get("during_refresh",0)==1 and observed.events.back().priority==Vector3(3,4,5),"next refresh captures reentrant cause and current rank position")
	var scope_trace=preload("res://scripts/world3d/demand_revision_trace.gd").new(8)
	scope_trace.scope_change("set_scope",{"old":true},{"new":true},1)
	var scope_event:Dictionary=scope_trace.snapshot().events[0]
	check(scope_event.scope_added==["new"] and scope_event.scope_removed==["old"] and not scope_event.scope_truncated,"same-size scope replacement records exact changed IDs")
	var large:Dictionary={}
	for i:int in 20:large["scope_%d"%i]=true
	scope_trace.scope_change("set_scope",{},large,2);scope_event=scope_trace.snapshot().events.back()
	check(scope_event.scope_added.size()==16 and scope_event.scope_added_count==20 and scope_event.scope_truncated,"scope change bounds stored IDs and reports truncation")

func scheduling_equivalence_test()->void:
	var without:=Deferred.new();var with_trace:=Deferred.new();var rows:Array=[]
	for i:int in 64:rows.append(item("same_%d"%i,float(i*4),1,"shared_%d"%(i%7)))
	without.pending=rows.duplicate();with_trace.pending=rows.duplicate();with_trace.start_demand_revision_trace(4096)
	var same:=true
	for step:int in 32:
		var point:=Vector3(float(step*5),float(step%4),0)
		var clip:=AABB(point-Vector3(15,2,15),Vector3(30,4,30))
		for queue:Deferred in [without,with_trace]:
			queue.prioritize(point);queue.set_demand("mixed",clip,-1)
			if step%5==0:queue.set_demand_scope(["mixed","player"])
			if step%5==2:queue.set_demand_scope([])
			if step%7==0:queue.release_demand("mixed")
			queue._refresh_demanded()
		same=same and snapshot(without)==snapshot(with_trace) and without._demanded.size()==with_trace._demanded.size()
		for i:int in mini(without._demanded.size(),with_trace._demanded.size()):same=same and is_same(without._demanded[i],with_trace._demanded[i])
	check(same,"32 mixed movement/scope/release changes preserve every rank, path and owner with diagnostics enabled")
	without.free();with_trace.free()
func run()->void:
	var logger:=Errors.new();OS.add_logger(logger)
	var map:=Node3D.new();map.set_meta("extras",{"rmmo_records":[]})
	var q:=Deferred.new();q._map=map
	q.pending=[item("one",0),item("two",8)]
	var clip:=AABB(Vector3(-2,-1,-2),Vector3(4,2,4))
	check(q._demand_revision_trace==null,"diagnostic is disabled by default and allocates no trace")
	q.set_demand("normal",clip,0);q._refresh_demanded()
	check(q._demand_revision_trace==null,"normal updates and refreshes do not create diagnostic state")
	var baseline:=snapshot(q);var owners:Array=q._demanded.duplicate()
	q.start_demand_revision_trace(256)
	var started:Dictionary=q.demand_revision_trace_snapshot()
	check(started.events.is_empty() and started.dropped_changes==0 and started.dropped_refreshes==0,"enable starts an empty bounded session")
	q._candidates_revision=-1;q._refresh_demanded()
	var data:Dictionary=q.demand_revision_trace_snapshot()
	check(data.events.size()==1 and data.events[0].type=="refresh" and data.events[0].initial,"first actual refresh is recorded even without a new revision")
	var stable:Dictionary=snapshot(q);var same:bool=baseline==stable
	for i:int in mini(owners.size(),q._demanded.size()):same=same and is_same(owners[i],q._demanded[i])
	check(same,"enabling diagnostics preserves exact schedule and owner identities")
	var rev:=q._demand_revision
	q.set_demand("",clip,0);q.set_demand("normal",clip,0);q.release_demand("missing")
	check(q._demand_revision==rev and q.demand_revision_trace_snapshot().events.size()==1,"invalid and unchanged operations do not create false events")
	var moved:=AABB(Vector3(-1,8,-2),Vector3(4,3,4))
	q.set_demand("normal",moved,-1,"all",true);q.release_demand("normal")
	q.set_demand("new",clip,2);q._refresh_demanded()
	data=q.demand_revision_trace_snapshot();var counts:=reasons(data)
	check(counts.get("set_demand",0)==2 and counts.get("release_demand",0)==1,"changed tickets and release produce separate source counts")
	var last:Dictionary=data.events.back()
	check(last.type=="refresh" and last.causes.get("set_demand",0)==2 and last.causes.get("release_demand",0)==1,"refresh aggregates every revision since its previous refresh")
	var change:Dictionary=data.events[1]
	check(change.new_value[0]==moved and change.new_value[1]==-1 and change.new_value[4],"event preserves full 3D clip, priority and rank mode")
	q._reference_index={"models":{},"groups":{"building:g":{"bounds":clip}}}
	q.set_group_demand("group","building:g",-2);rev=q._demand_revision
	q.set_group_demand("group","building:g",-2)
	check(q._demand_revision==rev,"same group demand remains a no-op")
	q.set_demand_scope(["group"])
	q.allow_demand_in_scope("new");q.retry_failed(clip)
	q.register_runtime_building("not-pending",clip,{})
	q.prioritize(Vector3.ZERO);q.prioritize(Vector3(31.9,0,0));q.prioritize(Vector3(32.,0,0))
	var entry:={"compact_record":{"uuid":"new-requeue"},"record_index":42,"bounds":clip,"asset_path":"","group_id":""}
	check(q.requeue_references([entry])==1 and q.requeue_references([entry])==0,"real requeue accepts once and rejects duplicate")
	q._entry_prefetch={"previous_scope":[]};q.finish_entry_prefetch();q._refresh_demanded()
	data=q.demand_revision_trace_snapshot();counts=reasons(data)
	for label:String in ["group_demand","set_scope","allow_scope","retry_failed","priority_anchor","requeue","finish_entry_prefetch"]:
		check(int(counts.get(label,0))>0,"real revision source recorded: "+label)
	check(int(counts.get("priority_anchor",0))==2,"rank anchor reports initial and 32m crossing, not movement inside threshold")
	var fresh:=Deferred.new();fresh.start_demand_revision_trace(8)
	fresh.register_runtime_building("fresh-building",clip,{})
	check(int(reasons(fresh.demand_revision_trace_snapshot()).get("register_building",0))==1,"pending-index rebuild registration records its actual revision")
	fresh.register_runtime_building("fresh-building",clip,{})
	check(int(reasons(fresh.demand_revision_trace_snapshot()).get("register_building",0))==1,"unchanged building registration does not report a change")
	fresh.free()
	var saved:Dictionary=data.duplicate(true)
	q.start_demand_revision_trace(2)
	q.set_demand("overflow1",clip,1);q.set_demand("overflow2",clip,2);q.set_demand("overflow3",clip,3);q._refresh_demanded()
	data=q.demand_revision_trace_snapshot()
	check(data.events.size()==2 and data.dropped_changes==1 and data.dropped_refreshes==1,"bounded session distinguishes dropped changes and refreshes")
	q.start_demand_revision_trace(3);data=q.demand_revision_trace_snapshot()
	check(data.events.is_empty() and data.dropped_changes==0 and data.dropped_refreshes==0 and data.source_counts.is_empty(),"new session resets events, counts and dropped totals")
	check(not saved.events.is_empty(),"reset never clears an already returned snapshot")
	q.stop_demand_revision_trace();q.set_demand("after",clip,0);q._refresh_demanded()
	check(q._demand_revision_trace==null,"stop removes the diagnostic session")
	diagnostic_contract_test()
	scheduling_equivalence_test()
	q.free();map.free();OS.remove_logger(logger)
	check(logger.errors.is_empty(),"zero engine/script errors")
	for issue:String in logger.errors:print("ENGINE_ERROR ",issue)
	print("DEMAND_REVISION_TRACE passed=",passed," failures=",failed);quit(0 if failed==0 else 1)
