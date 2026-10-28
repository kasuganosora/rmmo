extends SceneTree
const Probe=preload("res://tools/frame_budget_probe.gd")
var failures:=0
var checks:=0
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures+=1
	print(("PASS: " if ok else "FAIL: ")+message)
func counters(service:int,publication:int,units:int,frames:int)->Dictionary:
	return {"elapsed_us":service,"publication_us":publication,"publication_units":units,"frames":frames}
func profile(mode:String,covered:Dictionary,interactive:Dictionary)->Dictionary:
	var modes:Dictionary={}
	if not covered.is_empty():modes.covered_loading=covered
	if not interactive.is_empty():modes.interactive=interactive
	return {"main_thread_budget_mode":mode,"main_thread_budgets":modes}
func _initialize()->void:
	var probe:=Probe.new()
	var baseline:=probe.sample({})
	check(baseline.baseline and baseline.delta.elapsed_us==0,"empty first observation is a baseline")
	var covered:=profile("covered_loading",counters(100,70,3,1),{})
	var original:=var_to_bytes(covered)
	var first:=probe.sample(covered)
	check(first.delta.elapsed_us==100 and first.delta.publication_us==70 and first.delta.publication_units==3,"new covered mode after baseline records its first service and publications")
	check(first.by_mode_delta.get("covered_loading",{}).get("publication_us",-1)==70 and first.cumulative.publication_us==70,"covered delta and cumulative publication are distinct from interactive")
	check(var_to_bytes(covered)==original,"observing counters does not mutate queue data")
	var same:=probe.sample(covered)
	check(same.delta.elapsed_us==0 and same.delta.publication_units==0,"unchanged counters add no repeated work")
	var switched:=profile("interactive",counters(150,90,4,2),counters(60,40,2,1))
	var second:=probe.sample(switched)
	check(second.delta.elapsed_us==110 and second.delta.publication_us==60 and second.delta.publication_units==3,"mode switch includes work in both modes between observations")
	check(second.by_mode_delta.get("covered_loading",{}).get("publication_us",-1)==20 and second.by_mode_delta.interactive.publication_us==40,"mode deltas stay separate across a switch")
	check(second.cumulative.elapsed_us==210 and second.cumulative.publication_us==130 and second.cumulative.frames==3,"cumulative service totals include both modes")
	check(second.last_mode=="interactive" and not second.baseline and not second.counter_reset,"mode annotation describes last service without resetting counters")
	var returned:=probe.sample(profile("covered_loading",counters(180,105,5,3),counters(60,40,2,1)))
	check(returned.delta.elapsed_us==30 and returned.delta.publication_us==15 and returned.delta.publication_units==1,"returning to cover does not replay previous covered work")
	var extra:=Probe.extra_values(second)
	check(extra.size()==Probe.EXTRA_COLUMNS.size(),"extended schema and values stay aligned")
	check(extra[0]=="interactive" and extra[3]==50 and extra[4]==20 and extra[6]==60 and extra[7]==40,"extended delta columns expose both modes")
	check(extra[9]==150 and extra[10]==90 and extra[12]==60 and extra[13]==40,"extended cumulative columns retain raw per-mode values")
	var reset:=probe.sample(profile("interactive",counters(180,105,5,3),counters(5,3,1,1)))
	check(reset.counter_reset and reset.delta.elapsed_us==0 and reset.cumulative.elapsed_us==185,"counter reset is explicit and does not invent a negative or valid interval")
	var recovered:=probe.sample(profile("interactive",counters(180,105,5,3),counters(12,7,2,2)))
	check(not recovered.counter_reset and recovered.delta.elapsed_us==7 and recovered.delta.publication_us==4,"following reset, ordinary deltas resume from the new epoch")
	var late:=Probe.new().sample(profile("covered_loading",counters(1000,800,30,20),{}))
	check(late.baseline and late.delta.publication_us==0 and late.cumulative.publication_us==800,"late first observation exposes totals without claiming earlier work in one frame")
	# Captured final counters from the real green_01 sample; no map or engine work.
	var captured:=Probe.snapshot(profile("interactive",counters(6683339,4907927,1732,506),counters(957,0,0,6)))
	check(captured.totals.publication_us==4907927 and captured.totals.elapsed_us==6684296 and captured.totals.frames==512,"real covered loading totals are not reported as zero after switching interactive")
	var cleared:=probe.sample({})
	check(cleared.counter_reset and cleared.delta.elapsed_us==0,"disappearing mode counters explicitly mark a reset")
	var next:=probe.sample(profile("covered_loading",counters(9,5,1,1),{}))
	check(not next.counter_reset and next.delta.elapsed_us==9,"new counters after disappearance start from zero")
	var other:={"main_thread_budget_mode":"future_mode","main_thread_budgets":{"future_mode":counters(10,8,2,1)}}
	check(Probe.snapshot(other).totals.publication_us==8,"aggregate counters include newly recorded modes without misclassifying them")
	var benchmark:=Probe.new();benchmark.sample(switched);var began:=Time.get_ticks_usec()
	for i in 10000:benchmark.sample(switched)
	print("FRAME_BUDGET_PROBE_MICRO iterations=10000 total_us=",Time.get_ticks_usec()-began," scope=counter_helper_only_not_full_sampler")
	print("FRAME_BUDGET_PROBE_FINISHED checks=",checks," failures=",failures)
	quit(1 if failures else 0)
