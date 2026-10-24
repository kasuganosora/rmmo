extends SceneTree
## A continuous source stream must not starve completed groups. The fake
## preparation consumes its allowance just like a large collect/prepare pass.
class BusyBatcher extends "res://scripts/world3d/ground_batcher.gd":
	var prepare_turns:=0
	var production_turns:=0
	var completed_turns:=0
	func _prepare_step(budget_usec:int)->void:
		prepare_turns+=1
		var began:=Time.get_ticks_usec()
		while Time.get_ticks_usec()-began<maxi(1,budget_usec):pass
	func _build_next(_background:bool=false)->void:
		pending.pop_front();production_turns+=1
	func _finish_worker(index:int)->void:
		_workers[index].thread.wait_to_finish();_workers.remove_at(index);completed_turns+=1
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func run()->void:
	var legacy:="--expect-starved" in OS.get_cmdline_user_args()
	for budget:int in [1,1000]:
		var batcher:=BusyBatcher.new();batcher._preparation={"phase":"collect"}
		for i:int in 64:batcher.pending.append(str(i))
		for frame:int in 24:batcher._process_work(budget)
		check(batcher.production_turns==0 if legacy else batcher.production_turns>=12,"continuous preparation has expected production progress at %dus: %d"%[budget,batcher.production_turns])
		check(batcher.prepare_turns>=12,"source preparation also keeps progressing")
		batcher._preparation={};var previous:int=batcher.production_turns
		batcher.pending.append("after_preparation")
		batcher._process_work(budget)
		check(batcher.production_turns>previous,"without preparation, production consumes available budget")
		var worker:=Thread.new();worker.start(func():return {})
		while worker.is_alive():await process_frame
		batcher._workers.append({"thread":worker});batcher._preparation={"phase":"collect"}
		for frame:int in 4:batcher._process_work(budget)
		check(batcher.completed_turns==0 if legacy else batcher.completed_turns==1,"joined output also gets a turn while sources keep arriving")
		if not batcher._workers.is_empty():batcher._finish_worker(0)
		batcher.free()
	print("BATCH_PRODUCTION_FAIRNESS failures=",failures);quit(1 if failures else 0)
