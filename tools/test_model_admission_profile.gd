extends SceneTree
## CPU-only scheduler/accounting regressions; no model/GPU resources are loaded.
const Preparation=preload("res://scripts/world3d/model_parse_preparation.gd")
var failures:=0
var passed:=0
class Probe extends RefCounted:
	var mutex:=Mutex.new()
	var active:=0
	var peak:=0
	func parse(_path:String)->Dictionary:
		mutex.lock();active+=1;peak=maxi(peak,active);mutex.unlock()
		OS.delay_msec(12)
		mutex.lock();active-=1;mutex.unlock()
		return {"error":OK}
	func cache(path:String)->Dictionary:
		OS.delay_msec(3)
		return {"hit":true,"packed":RefCounted.new(),"bytes":123,"source_digest":"a".repeat(64)} if path=="cached" else {"hit":false,"reason":"fixture_miss"}

func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("PASS: " if ok else "FAIL: ",label)
	if ok:passed+=1
	else:failures+=1

func check_balanced(result:Dictionary,label:String)->void:
	var profile:Dictionary=result.admission_profile
	var stages_balanced:=true
	for stage:Dictionary in profile.stages.values():
		stages_balanced=stages_balanced and stage.started==stage.joined and stage.active_jobs==0 and stage.active_reserved_bytes==0
	var accounted:=0
	for duration in profile.blocked_us_by_reason.values():accounted+=int(duration)
	var per_task:=0
	for task:Dictionary in profile.tasks.values():
		var reasons:=0
		for duration in task.blocked_us_by_reason.values():reasons+=int(duration)
		if reasons!=task.blocked_us:stages_balanced=false
		per_task+=int(task.blocked_us)
	check(stages_balanced and profile.ledger_at_return.jobs==0 and profile.ledger_at_return.reserved_bytes==0,label+": stage joins and ownership ledger balance")
	check(accounted==profile.blocked_us and per_task==accounted and accounted<=profile.elapsed_us,label+": blocking intervals partition scheduler wait, not overlapping worker time")

func run()->void:
	var probe:=Probe.new();var job:=Preparation.new();job.inflight_byte_limit=100
	job.memory_estimator=func(_path:String):return {"estimated_bytes":60,"exclusive":false}
	var result:Dictionary=job.run(["a","b","c"],probe.parse,4)
	var profile:Dictionary=result.admission_profile
	check(result.error==OK and probe.peak==1 and profile.blocked_us_by_reason.get("byte_limit",0)>0,"byte-bound queue records real waits without increasing parallel peak")
	check(profile.tasks.b.queue_us>0 and profile.tasks.c.queue_us>0 and profile.tasks.c.stages[0].queue_us==profile.tasks.c.queue_us,"each delayed dependency reports enqueue-to-dispatch wait")
	check(profile.tasks.a.memory.compiled_read_reservation_bytes==60 and profile.tasks.a.retained_charge_bytes==60 and result.result_resident_estimate_bytes==180,"completed resources remain explicitly charged after admission release")
	check_balanced(result,"byte-limited")
	job=Preparation.new();probe=Probe.new();job.inflight_byte_limit=100
	job.memory_estimator=func(path:String):return {"estimated_bytes":120 if path=="huge" else 1,"exclusive":false}
	result=job.run(["a","huge","c"],probe.parse,4);profile=result.admission_profile
	check(profile.blocked_us_by_reason.get("exclusive_drain",0)>0 and profile.blocked_us_by_reason.get("active_exclusive",0)>0 and probe.peak==1,"candidate drain and active-exclusive waits are distinct and preserve isolation")
	check_balanced(result,"exclusive")
	job=Preparation.new();probe=Probe.new();job.inflight_byte_limit=100
	job.memory_estimator=func(_path:String):return {"estimated_bytes":1,"exclusive":false}
	result=job.run(["a","b"],probe.parse,1)
	check(result.admission_profile.blocked_us_by_reason.get("worker_limit",0)>0,"worker slot limit has its own measured wait")
	check_balanced(result,"single worker")
	job=Preparation.new();probe=Probe.new();job.cache_reader=probe.cache
	job.eligibility_checker=func(_path:String):return true
	job.memory_estimator=func(_path:String):return {"estimated_bytes":7,"exclusive":false}
	result=job.run(["cached","raw"],probe.parse,2);profile=result.admission_profile
	check(result.error==OK and profile.stages.compiled_read.started==2 and profile.stages.raw_import.started==1,"native miss transitions to a separately admitted fallback stage")
	check(profile.tasks.cached.compiled and profile.tasks.cached.compiled_payload_bytes==123 and profile.tasks.raw.stages.size()==2,"compressed payload bytes are observed independently of peak estimate")
	check(profile.tasks.cached.memory.estimated_bytes==7 and profile.tasks.raw.memory.estimated_bytes==7 and result.result_resident_estimate_bytes==14,"compiled hit and fallback retain same conservative charge exactly once")
	check_balanced(result,"two-stage")
	job=Preparation.new();job.cancel()
	result=job.run(["never"],func(_path:String):return {"error":OK})
	check(result.cancelled and result.admission_profile.tasks.never.state=="queued" and result.admission_profile.stages.is_empty(),"cancelled unscheduled dependency is not mislabeled as prepared")
	check_balanced(result,"cancelled")
	print("MODEL_ADMISSION_PROFILE passed=",passed," failures=",failures)
	quit(0 if failures==0 else 1)
