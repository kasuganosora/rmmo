extends SceneTree
## Pure scheduling contract: no scene rendering, mesh upload or test map writes.
const Batch=preload("res://scripts/world3d/ground_batcher.gd")

class WaitingWorker extends RefCounted:
	func is_alive()->bool:return true

class SchedulerProbe extends "res://scripts/world3d/ground_batcher.gd":
	var seen_budget_usec:=-1
	var finished_workers:=0
	var built_groups:=0
	var unit_delay_usec:=0
	func _prepare_step(budget_usec:int)->void:seen_budget_usec=budget_usec
	func _finish_worker(index:int)->void:
		finished_workers+=1;_workers.remove_at(index)
	func _build_next(_background:bool=false)->void:
		pending.pop_front();built_groups+=1
		if unit_delay_usec>0:OS.delay_usec(unit_delay_usec)

var failures:=0
var checks:=0

func check(condition:bool,message:String)->void:
	checks+=1
	if not condition:failures+=1;push_error(message)

func _initialize()->void:_run.call_deferred()

func _run()->void:
	var batch:=SchedulerProbe.new()
	check(batch.effective_work_budget_usec()==2000,"interactive default remains 2 ms")
	batch._process(0.)
	check(batch.seen_budget_usec==-1,"empty preparation performs no redundant prepare call")
	batch._preparation={"phase":"collect"}
	for budget in [2000,8000,16000,24000]:
		var token:=batch.begin_loading_budget(budget)
		check(token>0 and batch.effective_work_budget_usec()==budget,"loading budget accepts "+str(budget))
		batch._process(0.)
		check(batch.seen_budget_usec>budget/2 and batch.seen_budget_usec<=budget,"preparation receives remaining loading budget "+str(budget))
		check(batch.end_loading_budget(token) and batch.effective_work_budget_usec()==2000,"loading completion restores interactive budget")
	check(batch.begin_loading_budget(0)==0 and batch.begin_loading_budget(-1)==0 and batch.begin_loading_budget(24001)==0,"invalid loading budget is rejected")
	check(batch.effective_work_budget_usec()==2000 and batch.stats().loading_budget_scopes==0,"rejected budget has no effect")
	var outer:=batch.begin_loading_budget(8000)
	var inner:=batch.begin_loading_budget(16000)
	check(batch.end_loading_budget(outer) and batch.effective_work_budget_usec()==16000,"ending older load preserves newer load")
	check(not batch.end_loading_budget(outer) and not batch.end_loading_budget(0),"unknown and repeated tokens are harmless")
	batch.work_budget_usec=3000
	check(batch.effective_work_budget_usec()==16000,"base budget change does not interrupt active load")
	check(batch.end_loading_budget(inner) and batch.effective_work_budget_usec()==3000,"ending load restores current base budget")
	outer=batch.begin_loading_budget(8000);inner=batch.begin_loading_budget(16000)
	check(batch.end_loading_budget(inner) and batch.effective_work_budget_usec()==8000,"nested completion restores outer allowance")
	batch.clear(false)
	check(batch.effective_work_budget_usec()==8000,"map rebuild clear preserves load's scope")
	batch._preparation={"phase":"collect"}
	batch.residency_budget_frame=Engine.get_process_frames();batch.residency_budget_remaining_usec=700
	batch._process(0.)
	check(batch.seen_budget_usec>350 and batch.seen_budget_usec<=700,"shared residency allowance still limits loading work")
	batch.seen_budget_usec=-1;batch.residency_budget_remaining_usec=0
	batch._process(0.)
	check(batch.seen_budget_usec==-1,"exhausted residency allowance defers preparation")
	batch.residency_budget_frame=-1;batch.end_loading_budget(outer)
	batch.work_budget_usec=2000
	outer=batch.begin_loading_budget(24000)
	for i in Batch.MAX_WORKERS:batch._workers.append({"thread":WaitingWorker.new()})
	batch._process(0.)
	check(batch.finished_workers==0 and batch._workers.size()==Batch.MAX_WORKERS,"temporary 24 ms load never joins a live worker")
	batch._workers.clear();batch.end_loading_budget(outer)
	batch.work_budget_usec=24000
	for i in Batch.MAX_WORKERS:batch._workers.append({"thread":WaitingWorker.new()})
	batch._process(0.)
	check(batch.finished_workers==0,"ordinary covered loading never joins a live worker when the shared ledger is disabled")
	batch._workers.clear();batch.work_budget_usec=2000
	batch.pending.assign(["first","second"]);batch.unit_delay_usec=4000
	batch._process(0.)
	check(batch.built_groups==1 and batch.pending.size()==1,"an indivisible over-budget unit defers the following group")
	outer=batch.begin_loading_budget(16000)
	var stats:=batch.stats()
	check(stats.work_budget_usec==16000 and stats.base_work_budget_usec==2000 and stats.loading_budget_scopes==1,"monitor exposes effective and base allowance")
	batch._exit_tree()
	check(batch.effective_work_budget_usec()==2000 and not batch.end_loading_budget(outer),"exit clears temporary load scopes")
	batch.free()
	var ledger=preload("res://scripts/world3d/frame_work_budget.gd")
	ledger.enabled=true
	var shared_batch:=SchedulerProbe.new();shared_batch.work_budget_usec=24000
	shared_batch._preparation={"phase":"collect"}
	for i in Batch.MAX_WORKERS:shared_batch._workers.append({"thread":WaitingWorker.new()})
	shared_batch._process(0.)
	check(shared_batch.finished_workers==0,"shared frame budget never joins a live worker during covered entry")
	check(shared_batch.seen_budget_usec<=5000 and shared_batch.seen_budget_usec>0,"covered batch work uses its reserved portion of the whole frame")
	shared_batch._workers.clear();shared_batch.free();ledger.enabled=false
	_test_settled_budget()
	print("GROUND_BATCH_LOADING_BUDGET checks=",checks," failures=",failures)
	quit(1 if failures else 0)

func _test_settled_budget()->void:
	var controls=preload("res://scripts/world3d/runtime_probe_controls.gd")
	var map:=Node3D.new();var batch:=SchedulerProbe.new()
	var queue:=preload("res://scripts/world3d/deferred_asset_loader.gd").new()
	queue.name="DeferredAssets";map.add_child(queue);map.add_child(batch)
	queue._candidates_revision=queue._demand_revision
	map.set_meta("stream_chunk",Vector2i.ZERO);map.set_meta("stream_target",Vector2i.ZERO)
	check(batch.effective_work_budget_usec()==2000,"ordinary rendering retains the measured default")
	controls.white_materials=true;controls.discard_map_textures=true
	check(batch.effective_work_budget_usec()==6000,"settled white map borrows idle publication/collision allowance")
	var scope:=batch.begin_loading_budget(8000)
	check(batch.effective_work_budget_usec()==8000,"explicit loading scope overrides borrowed budget")
	batch.end_loading_budget(scope)
	queue._demand_revision+=1
	check(batch.effective_work_budget_usec()==2000,"unrefreshed demand revokes allowance before jobs exist")
	queue._candidates_revision=queue._demand_revision
	queue._jobs["new"]={}
	check(batch.effective_work_budget_usec()==2000,"active resource work revokes allowance")
	queue._jobs.clear()
	var stream=preload("res://scripts/world3d/world_stream.gd")
	map.set_meta("stream_budget_origin",Vector3.ZERO)
	map.set_meta("stream_jobs",[{}])
	check(stream.interactive_work_budget_usec(map,Vector3.ZERO)==6000,"unfinished stationary residency borrows the idle publication lane")
	check(stream.interactive_work_budget_usec(map,Vector3.ONE)==3000,"moving focus keeps ordinary residency slice")
	check(stream.interactive_work_budget_usec(map,Vector3.ZERO,1)==3000,"explicit residency count limit does not borrow")
	batch.share_residency_budget(Time.get_ticks_usec()-6100);batch.seen_budget_usec=-1
	batch._preparation={"phase":"collect"};batch._process(0.)
	check(batch.seen_budget_usec==-1,"borrowed streaming and batch work cannot each spend six milliseconds")
	map.remove_meta("stream_jobs")
	for key:String in ["stream_jobs","stream_append_pending","stream_candidates","stream_candidate_work","stream_collision_priority_work"]:
		map.set_meta(key,[{}])
		check(batch.effective_work_budget_usec()==2000,key+" blocks borrowing")
		map.remove_meta(key)
	map.set_meta("stream_target",Vector2i.ONE)
	check(batch.effective_work_budget_usec()==2000,"changed chunk destination revokes allowance")
	map.set_meta("stream_target",Vector2i.ZERO);map.set_meta("stream_source_revision",1)
	check(batch.effective_work_budget_usec()==2000,"unapplied source transaction revokes allowance")
	map.set_meta("stream_applied_source_revision",1)
	var preparation:=preload("res://scripts/world3d/retirement_schema_preparation.gd").new()
	map.set_meta("retirement_schema_preparation",preparation)
	check(batch.effective_work_budget_usec()==2000,"pending retirement preparation revokes allowance")
	preparation.complete=true
	check(batch.effective_work_budget_usec()==6000,"completed retirement preparation does not pin the slow budget")
	var ledger:=preload("res://scripts/world3d/frame_work_budget.gd").new()
	map.set_meta("retirement_frame_budget",ledger)
	ledger.record(Engine.get_process_frames(),"retire",10)
	check(batch.effective_work_budget_usec()==2000,"same-frame retirement work keeps its allowance")
	ledger._frame-=1
	batch.share_residency_budget(Time.get_ticks_usec()-1000)
	check(batch.residency_budget_remaining_usec>4000 and batch.residency_budget_remaining_usec<=5000,"borrowed budget charges elapsed streaming work")
	batch._preparation={"phase":"collect"};queue._demand_revision+=1
	batch._process(0.)
	check(batch.seen_budget_usec>0 and batch.seen_budget_usec<=2000,"new demand after allowance grant is rechecked on consumption")
	queue._candidates_revision=queue._demand_revision
	batch.share_residency_budget(Time.get_ticks_usec()-7000);batch.seen_budget_usec=-1
	batch._process(0.)
	check(batch.seen_budget_usec==-1,"streaming overrun exhausts borrowed budget")
	Batch.settled_white_budget_enabled=false
	check(batch.effective_work_budget_usec()==2000,"same-code control restores former allowance")
	Batch.settled_white_budget_enabled=true
	controls.white_materials=false;controls.discard_map_textures=false
	map.free()
