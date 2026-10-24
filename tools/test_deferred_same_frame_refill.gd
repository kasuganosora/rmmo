extends SceneTree
## Scheduling only: no files, model resources, real workers or renderer work.
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
class Probe extends Deferred:
	var dispatch_calls:=0
	var started:=0
	var release_slot:=true
	var stale_revision:=false
	var publication_delay:=0
	var cancel_during_publication:=false
	var dispatch_deadlines:Array=[]
	func _refresh_demanded()->void:pass
	func _retire_stale_prepared(_required:Dictionary)->void:pass
	func _poll_jobs(_required:Dictionary)->void:pass
	func _resume_pixel_jobs(_tree:SceneTree)->void:pass
	func _main_thread_budget_usec()->int:return 2000
	func _dispatch_jobs(_tree:SceneTree,_prefetch_only:bool=false)->void:
		dispatch_calls+=1;dispatch_deadlines.append(_dispatch_deadline)
		if _cancelled or Time.get_ticks_usec()>=_dispatch_deadline:return
		if _jobs.size()<4:
			started+=1;_jobs["new"]={"worker":Thread.new()}
	func _publish_ready(_began:int,_budget_usec:int=INTERACTIVE_BUDGET_US)->Dictionary:
		if publication_delay:OS.delay_usec(publication_delay)
		if release_slot:_jobs.old.consumed=true
		if stale_revision:_demand_revision+=1
		if cancel_during_publication:_cancelled=true
		return {"units":0,"unit_us":0,"max_unit_us":0}
	func _job_consumed(job:Dictionary)->bool:return job.get("consumed",false)
	func _discard_job(path:String)->void:_jobs.erase(path)
	func is_complete()->bool:return false
var failures:=0
var checks:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label_:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS: " if ok else "FAIL: ",label_)
func fixture()->Probe:
	var p:=Probe.new();root.add_child(p);p.set_process(false)
	p._active=true;p._candidates_revision=0;p._demand_revision=0
	p._jobs={"old":{"accepted":true},"b":{"worker":Thread.new()},"c":{"worker":Thread.new()},"d":{"worker":Thread.new()}}
	return p
func dispose(p:Probe)->void:
	p._jobs.clear();p._active=false;p.free()
func run()->void:
	var p:=fixture();var before:=Time.get_ticks_usec();p._process(0)
	check(p.started==1 and p.dispatch_calls==2,"a consumed result refills its worker slot in the same frame")
	check(p.dispatch_deadlines.size()==2 and p.dispatch_deadlines[1]<=before+2500,"refill uses the original frame deadline, not a new publication budget")
	dispose(p)
	p=fixture();p.publication_delay=5000;p._process(0)
	check(p.started==0 and p.dispatch_calls==1,"an indivisible overrun cannot dispatch in the frame tail")
	dispose(p)
	p=fixture();p.stale_revision=true;p._process(0)
	check(p.started==0 and p.dispatch_calls==1 and p._jobs.size()==4,"changed demand retains result owners and waits for the next demand refresh")
	dispose(p)
	p=fixture();p.release_slot=false;p._process(0)
	check(p.started==0 and p.dispatch_calls==1,"unchanged slots do not trigger another scheduling scan")
	dispose(p)
	p=fixture();p.cancel_during_publication=true;p._process(0)
	check(p.started==0 and p.dispatch_calls==1,"publication cancellation cannot refill the queue")
	dispose(p)
	print("DEFERRED_SAME_FRAME_REFILL checks=",checks," failures=",failures)
	quit(0 if failures==0 else 1)
