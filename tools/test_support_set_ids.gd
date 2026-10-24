extends "res://tools/test_shared_support_refresh.gd"
## Exact scheduler oracle and bounded registration lifetime; no map/GPU work.
class CollisionQueue extends Deferred:
	func _support_order_hash(_order:Array)->int:return 7

func compare_ids(q:Deferred,label:String)->void:
	Deferred.support_set_ids_enabled=false;q._demand_revision+=1;q._refresh_demanded()
	var expected:=snapshot(q);var owners:Array=q._demanded.duplicate()
	Deferred.support_set_ids_enabled=true;q._demand_revision+=1;q._refresh_demanded()
	var same:=expected==snapshot(q) and owners.size()==q._demanded.size()
	for i:int in mini(owners.size(),q._demanded.size()):same=same and is_same(owners[i],q._demanded[i])
	check(same,label)

func collision_lifetime_test()->void:
	var q:=CollisionQueue.new();var bounds:=AABB(Vector3.ZERO,Vector3.ONE)
	q.register_runtime_building("one",bounds,{"a":true,"b":true})
	q.register_runtime_building("two",bounds,{"a":true,"b":true})
	var original:int=q._runtime_support_set_ids.one
	check(q._runtime_support_set_ids.two==original and q._support_set_interns[original].users==2,"same ordered sets share an exact ID and count both users")
	q.register_runtime_building("reverse",bounds,{"b":true,"a":true})
	q.register_runtime_building("other",bounds,{"c":true,"d":true})
	check(q._support_set_interns.size()==3 and q._support_set_buckets.size()==1,"forced hash collisions distinguish order and different same-length sets")
	var summary:=q.support_set_snapshot()
	check(summary.registered_buildings==4 and summary.unique_nonempty_sets==3 and summary.unique_set_length_histogram=={"2":3} and summary.registration_set_length_histogram=={"2":4} and summary.registered_support_rows==8 and summary.max_set_length==2,"on-demand scalar histogram distinguishes unique sets from registration users")
	var reverse_id:int=q._runtime_support_set_ids.reverse
	q.register_runtime_building("one",bounds,{"b":true,"a":true})
	check(q._runtime_support_set_ids.one==reverse_id and q._runtime_support_order.one==["b","a"] and q._support_set_interns[original].users==1,"same-bounds reordered registration changes exact ID and decrements old users")
	q.register_runtime_building("two",bounds,{})
	check(not q._support_set_interns.has(original) and not q._runtime_support_set_ids.has("two"),"last user replacement removes old intern and empty set owns no ID")
	for i:int in 64:
		q.register_runtime_building("other",bounds,{"changing_%d"%i:true})
		check(q._support_set_interns.size()==2 and q._support_set_buckets[7].size()==2,"updates retain only live ordered sets %d"%i)
	q.register_runtime_building("one",bounds,{})
	q.register_runtime_building("reverse",bounds,{})
	q.register_runtime_building("other",bounds,{})
	check(q._support_set_interns.is_empty() and q._support_set_buckets.is_empty() and q._runtime_support_set_ids.is_empty(),"all released registrations leave no historical intern roots")
	q.register_runtime_building("one",bounds,{"a":true})
	q.configure_references({},"","")
	check(q._runtime_support_order.is_empty() and q._runtime_support_set_ids.is_empty() and q._support_set_interns.is_empty() and q._support_set_buckets.is_empty(),"reference reconfiguration clears all support identity owners")
	q.register_runtime_building("one",bounds,{"b":true})
	q.shutdown()
	check(q._runtime_support_order.is_empty() and q._runtime_support_set_ids.is_empty() and q._support_set_interns.is_empty() and q._support_set_buckets.is_empty(),"shutdown clears support identity owners")
	q.free()

func live_scheduler_test()->void:
	var q:=make_queue()
	for id:String in q._runtime_building_supports.keys():q.register_runtime_building(id,AABB(Vector3.ZERO,Vector3.ONE),q._runtime_building_supports[id])
	for i:int in 12:
		q._priority=Vector3(i*4,0,i*2);q.pending[2301].published=i%2==0
		q._demand_scope={"ticket3":true,"ticket0":true} if i%3==0 else {}
		q.instance_errors={"row2300":"fixture"} if i%2==0 else {}
		compare_ids(q,"exact IDs/owners/ranks/path heads/dispatch with movement, scope, publication and error %d"%i)
	var reverse:Dictionary={};var keys:Array=q._runtime_building_supports.row1.keys();keys.reverse()
	for id:String in keys:reverse[id]=true
	q.register_runtime_building("row1",AABB(Vector3.ZERO,Vector3.ONE),reverse)
	compare_ids(q,"reversed support insertion order preserves closure score ties")
	reverse.row2399=true;q.register_runtime_building("row1",AABB(Vector3.ZERO,Vector3.ONE),reverse)
	compare_ids(q,"changed support membership replaces its intern before live refresh")
	q._demand_scope={};q.instance_errors={};q._refresh_demanded()
	var old:Dictionary=q._pending_by_record_id.row1;var retained_id:int=q._runtime_support_set_ids.row1
	q._remove_published_demand([old])
	check(q._runtime_support_set_ids.row1==retained_id,"publication retains authored support identity for later residency return")
	var map:=Node3D.new();map.set_meta("extras",{"rmmo_records":[]});q._map=map;q._reference_index={"models":{}}
	var entry:={"compact_record":{"uuid":"row1"},"asset_path":old.path,"bounds":old.bounds,"group_id":old.group_id,"record_index":1}
	check(q.requeue_references([entry])==1,"real residency requeue accepts the retired owner once")
	check(q._runtime_support_set_ids.row1==retained_id,"requeue keeps registered exact support identity")
	compare_ids(q,"returned source and preserved support identity match old full scheduler")
	q._remove_published_demand([q._pending_by_record_id.row1])
	check(q._support_set_interns[retained_id].users==1,"republication does not duplicate registration users")
	q.free();map.free()

func dense_queue()->Deferred:
	var q:=Deferred.new();var supports:Dictionary={}
	for i:int in 256:
		var id:="terrain_context_global_shared_%04d"%i
		supports[id]=true;q.pending.append(item(id,8000,1,"support"))
	for i:int in 128:
		var row:=item("house_%03d"%i,float(i%16)*8.,1,"house_%d"%(i%17));row.group_id="building:"+row.record.uuid
		q.pending.append(row);q.register_runtime_building(row.record.uuid,row.bounds,supports)
	for i:int in 4:q.set_demand("ticket%d"%i,AABB(Vector3(-1,-1,-1),Vector3(2000,3,2000)),4-i,"building",i%2==0)
	return q

func benchmark_ids()->Array:
	var trials:Array=[]
	for ids:bool in [false,true,true,false]:
		Deferred.support_set_ids_enabled=ids;var q:=dense_queue();q._refresh_demanded()
		var before_arrays:int=q.profile.get("support_array_key_queries",0);var before_rows:int=q.profile.get("support_array_key_rows",0);var before_ids:int=q.profile.get("support_set_id_queries",0)
		var began:=Time.get_ticks_usec()
		for i:int in 32:q._priority=Vector3(i*4,0,i*2);q._demand_revision+=1;q._refresh_demanded()
		trials.append({"ids":ids,"us":Time.get_ticks_usec()-began,"array_key_queries":int(q.profile.get("support_array_key_queries",0))-before_arrays,"array_key_rows":int(q.profile.get("support_array_key_rows",0))-before_rows,"id_queries":int(q.profile.get("support_set_id_queries",0))-before_ids,"snapshot":var_to_str(snapshot(q)).sha256_text()})
		q.free()
	for trial:Dictionary in trials:
		check(trial.snapshot==trials[0].snapshot,"ABBA exact ordered scheduler result")
		check(trial.array_key_rows==0 and trial.id_queries>16000 if trial.ids else trial.array_key_rows>4000000 and trial.id_queries==0,"ABBA large Array key workload replaced only in ID mode")
	return trials

func run()->void:
	var logger:=Errors.new();OS.add_logger(logger)
	collision_lifetime_test();live_scheduler_test()
	var trials:=benchmark_ids();Deferred.support_set_ids_enabled=true
	OS.remove_logger(logger);check(logger.errors.is_empty(),"zero engine/script errors")
	for issue:String in logger.errors:print("ENGINE_ERROR ",issue)
	print("SUPPORT_SET_IDS ",JSON.stringify({"trials":trials,"passed":passed,"failures":failed,"work_note":"array_key_rows counts key payload lengths passed to get/set; it is not a timed native hash instruction count"}));quit(1 if failed else 0)
