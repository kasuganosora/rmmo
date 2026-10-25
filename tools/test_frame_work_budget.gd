extends SceneTree
const Budget=preload("res://scripts/world3d/frame_work_budget.gd")
var failures:=0
var passed:=0
func check(ok:bool,label:String)->void:
	print("PASS " if ok else "FAIL ",label)
	if ok:passed+=1
	else:failures+=1
func _initialize()->void:
	var budget:=Budget.new();var total:=0
	for lane:String in Budget.INTERACTIVE:
		var allowed:int=budget.request(1,lane,100000)
		check(allowed==Budget.INTERACTIVE[lane],"lane keeps its own interactive reservation: "+lane)
		budget.record(1,lane,allowed);total+=allowed
	check(total==6000 and budget.request(1,"publication",1000)==0,"independent callbacks cannot each spend a whole-frame budget")
	check(budget.request(1,"invalid",1000)==0,"unknown lanes do not consume unspecified capacity")
	check(budget.request(2,"publication",99999)==1500,"new render frame resets spent work")
	budget.record(2,"publication",20000)
	check(budget.request(2,"batch",1000)==0,"indivisible overrun suppresses subsequent production")
	check(budget.request(2,"retire",1000)==250,"overrun preserves a bounded retirement progress slice")
	budget.record(2,"retire",250)
	check(budget.request(2,"retire",1000)==0,"retirement exception cannot repeat within the frame")
	check(budget.request(3,"collision",99999,true)==0,"previously starved batch owns next frame before earlier collision callback")
	check(budget.request(3,"batch",99999,true)==5000,"protected turn still obeys the covered lane cap")
	budget.record(3,"batch",100)
	check(budget.request(3,"collision",99999,true)==8000,"served protected turn restores covered loading reservations")
	budget.record(3,"collision",8000)
	# Current covered cap is 32 ms: the preceding batch/collision callbacks
	# charged 0.1 + 8 ms. The old 7 ms expectation predated that policy.
	check(budget.request(3,"publication",99999)==23900,"covered siblings receive only the remaining 32 ms allowance")
	check(budget.request(4,"publication",99999)==1500,"covered budget does not leak into the next interactive frame")
	var report:Dictionary=budget.snapshot()
	check(report.over_budget_frames==1 and report.max_frame_us==20250,"overshoot is reported instead of pretending a hard time cap")
	check(report.lanes.publication.max_call_us==20000,"actual indivisible cost remains visible")
	fairness()
	Budget.enabled=false
	check(Budget.allowance("batch",12000)==12000,"disabled control keeps previous local budget unchanged")
	print("FRAME_WORK_BUDGET passed=",passed," failures=",failures)
	quit(1 if failures else 0)

func fairness()->void:
	var budget:=Budget.new()
	var lanes:Array=Budget.INTERACTIVE.keys()
	var grants:Dictionary={};var waiting:Dictionary={};var max_wait:=0;var total_actual:=0
	var capped:=true;var repeated_zero:=true;var bounded_grants:=true
	for frame in 48:
		var order:Array=lanes.duplicate()
		if frame%2==1:order.reverse()
		var frame_grants:=0
		for lane:String in order:
			var allowed:int=budget.request(frame,lane,100000)
			if allowed>0:
				capped=capped and allowed<=int(Budget.INTERACTIVE[lane])
				grants[lane]=int(grants.get(lane,0))+1;waiting[lane]=0;frame_grants+=1
				# Every admitted unit deliberately exceeds the entire frame cap.
				budget.record(frame,lane,20000);total_actual+=20000
				repeated_zero=repeated_zero and budget.request(frame,lane,100000)==0
			else:
				waiting[lane]=int(waiting.get(lane,0))+1;max_wait=maxi(max_wait,int(waiting[lane]))
		# One normal unit plus the pre-existing single retire exception at most.
		bounded_grants=bounded_grants and frame_grants<=2
	check(grants.size()==lanes.size() and lanes.all(func(lane):return grants[lane]>=4),"persistent early overruns cannot starve any active lane across frames")
	check(max_wait<=lanes.size(),"FIFO protects every continuously requesting lane within a bounded rotation")
	check(capped and repeated_zero,"protected turn neither enlarges lane quota nor bypasses exhausted zero allowance")
	check(bounded_grants,"fairness does not grant every lane a post-overrun minimum")
	check(budget.snapshot().elapsed_us==total_actual,"fairness charges all indivisible overruns without forgiving debt")
	var absent:=Budget.new()
	absent.request(1,"collision",2000);absent.record(1,"collision",20000)
	check(absent.request(1,"navigation",500)==0,"late navigation queues a protected turn after overrun")
	check(absent.request(2,"retire",500)==0 and absent.snapshot().current_priority_lane=="navigation","persistent retire does not steal the absent navigation's one protected frame")
	check(absent.request(3,"retire",500)==500 and absent.snapshot().absent_protected_turns==1,"absent protected head expires and persistent retirement receives the next turn")
	absent.record(3,"retire",500)
	check(absent.request(4,"wind",500)==500,"missing protected head cannot leave a permanent service lock")
	var empty:=Budget.new()
	check(empty.request(1,"navigation",0)==0 and empty.snapshot().waiting_lanes.is_empty(),"zero requested work never creates fairness debt")
	empty.request(1,"collision",2000);empty.record(1,"collision",20000);empty.request(1,"batch",1000)
	check(empty.request(2,"batch",0)==0 and empty.request(2,"retire",500)==0,"zero-size protected request cannot unlock other production in the same frame")
	check(empty.request(3,"retire",500)==500,"zero-size or absent head expires rather than starving retirement")
