extends "res://tools/test_deferred_typed_demand_scan.gd"
## CPU-only scheduler reproduction; no assets, jobs, SceneTree processing or GPU.
## This is a synthetic invalidation case, not a captured axel_town cost sample.
## Support identities are built through the real registration API, never by
## assigning _runtime_building_supports/_runtime_support_order as old replays did.
const SOURCE_ROWS:=1024
const BUILDINGS:=64
const SUPPORTS:=64
const OUTSIDE_ROWS:=24
const STEPS:=24
const WORK_KEYS:Array[String]=[
	"demand_refreshes","demand_refresh_us","max_demand_refresh_us",
	"demand_input_rows","demand_distance_evaluations","demand_scores_reused",
	"demand_membership_hits","demand_membership_misses","demand_kind_tests",
	"demand_membership_rows_created","demand_membership_rows_reused",
	"demand_candidate_rows_created","demand_candidate_rows_reused",
	"support_set_id_queries","support_array_key_queries","support_array_key_rows",
	"support_sets_reused","support_candidate_visits","support_promotions",
	"typed_partition_builds","typed_full_scan_prefilter_tests",
	"typed_incremental_classifications","pending_index_builds","pending_indexed_items",
	"requeue_membership_scan_rows","requeue_record_scan_rows"
]

func append_source(q:Deferred,entries:Dictionary,id:String,index:int,position:Vector3,kind:String,group:String="")->Dictionary:
	var record:={"uuid":id}
	var bounds:=AABB(position,Vector3.ONE)
	var entry:={"compact_record":record,"record_index":index,"bounds":bounds,"group_id":group,"asset_path":"","reason":kind,"memory_bytes":65536}
	var row:={"record":record,"path":Deferred.reference_path(entry),"bounds":bounds,"digest":"","native_reference":true,"reference_entry":entry,"reference_prepared":false,"group_id":group,"memory":{"estimated_bytes":65536,"exclusive":false}}
	entries[id]=entry;q.pending.append(row)
	return row

func return_fixture()->Dictionary:
	var q:=Deferred.new();var map:=Node3D.new();var entries:Dictionary={}
	q._map=map;q._reference_index={"models":{}}
	map.set_meta("extras",{"rmmo_records":[]})
	var supports:Dictionary={}
	for i:int in SUPPORTS:supports["source_%d"%(SOURCE_ROWS-SUPPORTS+i)]=true
	for i:int in SOURCE_ROWS:
		var position:=Vector3(float(i%32)*4.,0.,float(i/32)*4.)
		var reason:String=["native_road","native_bridge","native_fortification","ordinary"][i%4]
		if i>=SOURCE_ROWS-SUPPORTS:position=Vector3(8000.+float(i),0.,0.);reason="terrain_context_global"
		var group:String="building:source_%d"%i if i<BUILDINGS else ""
		var row:=append_source(q,entries,"source_%d"%i,i,position,reason,group)
		if i<BUILDINGS:q.register_runtime_building(row.record.uuid,row.bounds,supports)
	for i:int in OUTSIDE_ROWS:
		append_source(q,entries,"outside_%d"%i,SOURCE_ROWS+i,Vector3(16000.+float(i)*32.,0.,0.),"native_road")
	q.prioritize(Vector3.ZERO);q.set_process(false);q._refresh_demanded()
	return {"queue":q,"map":map,"entries":entries}

func check_production_invariants(q:Deferred,label:String)->void:
	check(q._indexed and q._pending_by_record_id.size()==q.pending_count(),label+": authoritative indexed UUID ownership")
	check(q._runtime_building_records.size()==BUILDINGS and q._runtime_building_supports.size()==BUILDINGS and q._runtime_support_set_ids.size()==BUILDINGS,label+": every registered building has a support ID")
	check(q._support_set_interns.size()==1,label+": identical ordered support sets share one intern")
	if q._support_set_interns.size()==1:
		var id:int=q._support_set_interns.keys()[0]
		var shared:Dictionary=q._support_set_interns[id]
		var consistent:bool=shared.users==BUILDINGS and shared.order.size()==SUPPORTS
		for uuid:String in q._runtime_building_records:
			consistent=consistent and q._runtime_support_set_ids.get(uuid)==id and q._runtime_support_order[uuid]==shared.order and q._runtime_building_supports[uuid].keys()==shared.order
		check(consistent,label+": support intern users and exact order match registrations")
	var native_bounds:=true
	for row:Dictionary in q._pending_by_record_id.values():
		native_bounds=native_bounds and row.has("demand_rect") and row.demand_rect==Rect2(Vector2(row.bounds.position.x,row.bounds.position.z),Vector2(row.bounds.size.x,row.bounds.size.z))
	check(native_bounds,label+": native XZ bounds populated through the actual index")
	check(q._pending_kinds!=null and q._pending_kinds.owners.size()==q.pending_count() and q._pending_kinds.building_count==BUILDINGS,label+": current incremental typed catalogue")
	check(int(q.profile.get("support_array_key_queries",0))==0 and int(q.profile.get("support_array_key_rows",0))==0,label+": no legacy Array support-key fallback")
	check(int(q.profile.get("support_set_id_queries",0))>0,label+": scheduler actually uses support IDs")

func work_snapshot(q:Deferred)->Dictionary:
	var result:Dictionary={}
	for key:String in WORK_KEYS:result[key]=int(q.profile.get(key,0))
	return result

func work_delta(q:Deferred,before:Dictionary)->Dictionary:
	var result:=work_snapshot(q)
	for key:String in WORK_KEYS:
		# A lifetime maximum is not a cumulative counter.
		if key!="max_demand_refresh_us":result[key]-=int(before.get(key,0))
	return result

func exact_full_scan_oracle(q:Deferred,label:String)->void:
	# prioritize() updates the current position even when it deliberately keeps
	# the previous rank anchor. Refresh the optimized path at that same current
	# position before comparing it with a freshly rebuilt full-scan oracle.
	var oracle_position:Vector3=q._priority
	q._demand_revision+=1;q._refresh_demanded()
	var expected:=snapshot(q);var owners:Array=q._demanded.duplicate()
	var old_typed:bool=Deferred.typed_demand_scan_enabled
	var old_membership:bool=Deferred.demand_membership_cache_enabled
	Deferred.typed_demand_scan_enabled=false;Deferred.demand_membership_cache_enabled=false
	q._demand_revision+=1;q._refresh_demanded()
	var same:bool=q._priority==oracle_position and snapshot(q)==expected and q._demanded.size()==owners.size()
	for i:int in mini(owners.size(),q._demanded.size()):same=same and is_same(owners[i],q._demanded[i])
	check(same,label+": full scan preserves exact UUID/order/path/head/rank/priority and owner identity")
	Deferred.typed_demand_scan_enabled=old_typed;Deferred.demand_membership_cache_enabled=old_membership
	q._demand_revision+=1;q._refresh_demanded()
	var restored:bool=q._priority==oracle_position and snapshot(q)==expected and q._demanded.size()==owners.size()
	for i:int in mini(owners.size(),q._demanded.size()):restored=restored and is_same(owners[i],q._demanded[i])
	check(restored,label+": restored optimized path preserves the same order and exact owners")

func rank_anchor_boundary()->void:
	var f:=return_fixture();var q:Deferred=f.queue
	var revision:int=q._demand_revision
	q.prioritize(Vector3(31.999,0,0));q._refresh_demanded()
	check(q._priority_rank_anchor==Vector3.ZERO and q._demand_revision==revision,"movement under 32m inside the chunk retains the rank anchor and revision")
	q.prioritize(Vector3(32,0,0));q._refresh_demanded()
	# This position also crosses a chunk boundary: ticket revisions may advance
	# alongside the rank revision, so do not assert an exact increment count.
	check(q._priority_rank_anchor==Vector3(32,0,0) and q._demand_revision>revision,"movement at 32m updates the anchor even when the chunk also changes")
	exact_full_scan_oracle(q,"32m boundary")
	q.free();f.map.free()

func rank_trial()->Dictionary:
	var f:=return_fixture();var q:Deferred=f.queue
	check_production_invariants(q,"rank setup")
	# Opposite points remain in chunk (0,0) but are over 32m apart. Prewarm the
	# first anchor via the real prioritize path before measuring alternating moves.
	q.prioritize(Vector3(28,0,28));q._refresh_demanded()
	q.prioritize(Vector3(4,0,4));q._refresh_demanded()
	var before:=work_snapshot(q);var samples:Array=[]
	for step:int in STEPS:
		# Diagonal movement exceeds the 32m rank threshold while all actual
		# prioritize() ticket envelopes stay in the same chunk.
		var started:=Time.get_ticks_usec()
		q.prioritize(Vector3(28,0,28) if step%2==0 else Vector3(4,0,4));q._refresh_demanded()
		samples.append(Time.get_ticks_usec()-started)
	var delta:=work_delta(q,before)
	check(delta.demand_refreshes==STEPS and delta.demand_membership_misses==0,"rank-only updates reuse stable membership through real prioritize")
	check(delta.support_array_key_queries==0 and delta.support_array_key_rows==0,"rank trial keeps production integer support keys")
	var result:={"kind":"same_chunk_rank_updates","samples_us":samples,"work":delta,"demanded":q._demanded_count()}
	exact_full_scan_oracle(q,"rank result");check_production_invariants(q,"rank result")
	q.free();f.map.free();return result

func unrelated_requeue_trial(expect_current:bool)->Dictionary:
	var f:=return_fixture();var q:Deferred=f.queue
	check_production_invariants(q,"return setup")
	var expected:=snapshot(q);var owners:Array=q._demanded.duplicate()
	var before:=work_snapshot(q);var samples:Array=[];var stable:=true
	for step:int in STEPS:
		var uuid:="outside_%d"%step;var old:Dictionary=q._pending_by_record_id[uuid]
		check(not q._demanded_by_id.has(uuid),"outside source is not demanded before retirement %d"%step)
		# Production retirement calls requeue only after resident ownership has
		# gone. This object-free fixture reproduces its scheduler side only.
		old.published=true;q._remove_published_demand([old])
		check(q.requeue_references([f.entries[uuid]])==1,"real requeue admits one retired source %d"%step)
		var revision:int=q._demand_revision
		check(q.requeue_references([f.entries[uuid],f.entries[uuid]])==0 and q._demand_revision==revision,"duplicate requeue is a true no-op %d"%step)
		var started:=Time.get_ticks_usec();q._refresh_demanded();samples.append(Time.get_ticks_usec()-started)
		stable=stable and snapshot(q)==expected and q._demanded.size()==owners.size() and not q._demanded_by_id.has(uuid)
		for i:int in mini(owners.size(),q._demanded.size()):stable=stable and is_same(owners[i],q._demanded[i])
	var delta:=work_delta(q,before)
	check(stable,"unrelated requeue changes no live UUID/order/path/head/rank/priority or owner")
	check(delta.pending_index_builds==0 and delta.typed_partition_builds==0,"real sparse requeue keeps spatial and typed catalogues incremental")
	check(delta.support_array_key_queries==0 and delta.support_array_key_rows==0,"return trial never falls back to large Array keys")
	var repeated:bool=delta.demand_refreshes==STEPS and delta.demand_membership_misses>=STEPS*q._demands.size() and delta.demand_input_rows>=STEPS*owners.size()
	if expect_current:check(repeated,"current implementation repeats whole live demand work for irrelevant requeue")
	var result:={"kind":"unrelated_single_source_requeue","samples_us":samples,"work":delta,"demanded":q._demanded_count(),"exact_demand_unchanged":stable,"current_global_invalidation_reproduced":repeated}
	exact_full_scan_oracle(q,"return result");check_production_invariants(q,"return result")
	q.free();f.map.free();return result

func run()->void:
	var logger:=Errors.new();OS.add_logger(logger)
	var expect_current:=OS.get_cmdline_user_args().has("--expect-current-invalidation")
	check(Deferred.support_set_ids_enabled and Deferred.demand_membership_cache_enabled and Deferred.incremental_pending_index_enabled,"production scheduling optimizations enabled")
	rank_anchor_boundary()
	var trials:Array=[rank_trial(),unrelated_requeue_trial(expect_current)]
	OS.remove_logger(logger);check(logger.errors.is_empty(),"zero script/engine errors")
	print("DEMAND_RETURN_REFRESH ",JSON.stringify({"trials":trials,"passed":passed,"failures":failed,"engine_errors":logger.errors,"scope":"Synthetic CPU-only scheduler replay; no map load, upload, physics, publication, GPU or IO. Timings are not production performance. Exact oracle runs outside measured intervals."}))
	quit(1 if failed else 0)
