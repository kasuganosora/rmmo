extends SceneTree
const Snapshot=preload("res://tools/deferred_profile_snapshot.gd")
var failures:=0
var checks:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func run()->void:
	var capture:=Snapshot.new()
	var profile:={"frames":0,"stage_ring":[],"stage_slow":[],"per_asset":{},"main_thread_budgets":{"interactive":{"frames":0}}}
	for i in 1024:profile.stage_ring.append({"at_us":i+1,"total_us":i,"detail":{"items":[i]}})
	profile.stage_slow=profile.stage_ring.slice(0,24)
	var source:=profile.duplicate(true)
	var first:=capture.capture(profile,1)
	check(profile==source,"observation leaves live producer counters and history unchanged")
	check(capture.copied_stage_rows==1024,"first observation retains existing history once")
	for i in 120:capture.capture(profile,1)
	check(capture.copied_stage_rows==1024,"120 unchanged observations never recopy the history ring")
	check(not first.has("stage_ring") and not first.has("stage_slow") and not first.has("per_asset"),"per-frame counter snapshots omit historical and detailed aggregate owners")
	for i in 40:
		profile.stage_ring.pop_front();profile.stage_ring.append({"at_us":1025+i,"total_us":i})
	profile.frames=40;profile.main_thread_budgets.interactive.frames=40
	var second:=capture.capture(profile,1)
	check(capture.copied_stage_rows==1064 and capture.stages.back().at_us==1064,"ring rotation preserves only the 40 newly observed stage rows")
	check(first.frames==0 and first.main_thread_budgets.interactive.frames==0 and second.frames==40,"past scalar and nested budget observations remain stable")
	profile.stage_ring[0].detail.items[0]=-1
	check(capture.stages[40].detail.items[0]==40,"retained stage details do not alias mutable live history")
	var different:={"stage_ring":[{"at_us":3,"total_us":7}]}
	capture.capture(different,2)
	check(capture.stages.back().observed_queue_id==2 and capture.copied_stage_rows==1065,"different queue owns its own history cursor")
	check(capture.capture({},3).is_empty(),"empty history is a valid observation")
	print("DEFERRED_PROFILE_SNAPSHOT checks=",checks," failures=",failures)
	quit(1 if failures else 0)
