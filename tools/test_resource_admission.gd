extends SceneTree
var failures:=0
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if not value:failures+=1
func _initialize()->void:
	var queue=preload("res://scripts/world3d/resource_admission.gd").new()
	queue.worker_limit=4;queue.byte_limit=100
	check(queue.reserve("a",{"estimated_bytes":60,"exclusive":false}),"first active dependency reserves decoded peak")
	check(not queue.reserve("a",{"estimated_bytes":1,"exclusive":false}),"shared dependency cannot be admitted twice")
	check(not queue.reserve("b",{"estimated_bytes":50,"exclusive":false}),"byte cap limits jobs before worker count")
	check(queue.blocking_reason("b",{"estimated_bytes":50,"exclusive":false})=="byte_limit","byte capacity denial is explicit")
	check(queue.set_stage("a","ready") and queue.snapshot().stages.ready.reserved_bytes==60 and queue.reserved_bytes==60,"ready output keeps its original reservation")
	var observed:Dictionary=queue.snapshot();observed.stages.ready.reserved_bytes=0
	check(queue.snapshot().stages.ready.reserved_bytes==60,"diagnostic snapshots cannot mutate the live ledger")
	check(queue.reserve("c",{"estimated_bytes":40,"exclusive":false}),"smaller independent dependency uses available bytes")
	check(not queue.has_capacity(),"full byte capacity skips unadmittable dependency expansion")
	check(not queue.can_admit("d",{"estimated_bytes":1,"exclusive":false}),"completed but unconsumed results keep their reservation")
	queue.release("c")
	check(queue.reserve("d",{"estimated_bytes":30,"exclusive":false}),"consuming one result immediately permits a replacement")
	check(not queue.reserve("huge",{"estimated_bytes":120,"exclusive":false}),"oversized task waits until other outputs are consumed")
	check(queue.inspect("huge",{"estimated_bytes":120,"exclusive":false}).reason=="exclusive_drain","oversized candidate reports drain rather than spare worker capacity")
	queue.release("a");queue.release("d")
	check(queue.reserve("huge",{"estimated_bytes":120,"exclusive":false}) and not queue.can_admit("small",{"estimated_bytes":1,"exclusive":false}),"oversized required dependency runs exclusively without deadlock")
	check(queue.blocking_reason("small",{"estimated_bytes":1,"exclusive":false})=="active_exclusive","active oversized owner explains blocked siblings")
	queue.release("huge")
	check(queue.reserve("small_exclusive",{"estimated_bytes":1,"exclusive":true}) and not queue.has_capacity(),"even a small exclusive owner closes dispatch while worker slots remain")
	queue.release("small_exclusive")
	check(queue.reserve("unknown",{}) and not queue.can_admit("small",{"estimated_bytes":1,"exclusive":false}),"unknown peak estimate never overlaps another job")
	queue.release("unknown");queue.release("unknown")
	check(queue.reserved_bytes==0 and queue.count()==0,"repeat disposal cannot make capacity negative")
	check(not queue.set_stage("gone","ready") and queue.snapshot().stages.is_empty(),"stage transition cannot resurrect a released lease")
	queue.worker_limit=1;queue.reserve("only",{"estimated_bytes":1,"exclusive":false})
	check(queue.blocking_reason("second",{"estimated_bytes":1,"exclusive":false})=="worker_limit","worker ceiling is distinguished from byte ceiling")
	queue.release("only");queue.worker_limit=0
	check(queue.blocking_reason("off",{"estimated_bytes":1000,"exclusive":true})=="disabled" and not queue.can_admit("off",{"estimated_bytes":1000,"exclusive":true}),"disabled scheduler cannot admit even an exclusive candidate")
	print("RESOURCE_ADMISSION failures=",failures);quit(1 if failures else 0)
