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
	for budget in [2000,8000,16000,24000]:
		var token:=batch.begin_loading_budget(budget)
		check(token>0 and batch.effective_work_budget_usec()==budget,"loading budget accepts "+str(budget))
		batch._process(0.)
		check(batch.seen_budget_usec==budget,"preparation receives loading budget "+str(budget))
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
	batch.residency_budget_frame=Engine.get_process_frames();batch.residency_budget_remaining_usec=700
	batch._process(0.)
	check(batch.seen_budget_usec==700,"shared residency allowance still limits loading work")
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
	for i in Batch.MAX_WORKERS:shared_batch._workers.append({"thread":WaitingWorker.new()})
	shared_batch._process(0.)
	check(shared_batch.finished_workers==0,"shared frame budget never joins a live worker during covered entry")
	check(shared_batch.seen_budget_usec<=5000 and shared_batch.seen_budget_usec>0,"covered batch work uses its reserved portion of the whole frame")
	shared_batch._workers.clear();shared_batch.free();ledger.enabled=false
	print("GROUND_BATCH_LOADING_BUDGET checks=",checks," failures=",failures)
	quit(1 if failures else 0)
