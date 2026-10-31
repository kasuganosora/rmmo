extends SceneTree
## Contract tests for out-of-order service; real dispatch/ownership is covered
## separately by test_completed_result_service with two actual worker threads.
const Order=preload("res://scripts/world3d/publication_order.gd")
var failures:=0
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",label)
	if not ok:failures+=1
func head(path:String)->Dictionary:
	return {"path":path,"record":{"uuid":path},"group_id":"building:"+path}
func choose(order:RefCounted,heads:Array,jobs:Dictionary,costs:Dictionary,critical:String="",pressure:bool=true)->Dictionary:
	var priorities:Dictionary={};var ranks:Dictionary={}
	for i in heads.size():
		priorities[heads[i].path]=-2 if heads[i].path==critical else 10
		ranks[heads[i].path]=i
	var remaining:Dictionary=costs if order.needs_drain_target(heads,jobs) else {}
	return order.choose(heads,priorities,ranks,jobs,pressure,remaining)
func job()->Dictionary:return {"token":RefCounted.new()}
func _initialize()->void:
	var old:bool=Order.completed_owner_drain_enabled;Order.completed_owner_drain_enabled=true
	var order:=Order.new();var a:=head("large");var b:=head("short");var c:=head("new_short")
	var jobs:={"large":job(),"short":job()};var costs:={"large":100,"short":8,"new_short":1}
	check(choose(order,[a,b],jobs,costs,"",false).path=="large","without result pressure original nearby-building order remains")
	check(choose(order,[a,b],jobs,costs).path=="short","ready shorter owner overtakes unrelated nearer building under pressure")
	jobs.new_short=job()
	check(choose(order,[a,b,c],jobs,costs).path=="new_short","later completed short owner preempts a longer private cursor")
	check(choose(order,[a,b,c],jobs,costs,"large").path=="large","new critical demand preempts every completion preference immediately")
	check(choose(order,[a,b],jobs,costs).path=="short","blocked target absent from ready set cannot hold service")
	jobs.erase("short")
	check(choose(order,[a],jobs,costs).path=="large","cancelled target cannot retain its slot in the selector")
	var stale:int=jobs.large.token.get_instance_id();jobs.large=job();jobs.new_short=job()
	check(choose(order,[a,c],jobs,costs).path=="new_short" and not order._drain_age.has(stale),"same source path with a new generation inherits no stale target or aging")
	check(choose(order,[],jobs,costs).is_empty() and order._drain_path.is_empty(),"no eligible results leaves no sticky target")
	# A completed packet costs no remaining member construction but still must
	# appear in the loader's ready set before it can be selected for commit.
	order=Order.new();costs.short=0;jobs.short=job()
	check(choose(order,[a,b],jobs,costs).path=="short","ready fully constructed packet is selected before more construction")
	# Repeated distinct short arrivals may overtake only a bounded number of
	# times. A protected long owner continues despite further tiny arrivals.
	order=Order.new();jobs={"large":job()};costs={"large":1000}
	var picked_large:=false;var short_head:Dictionary={}
	for i in Order.MAX_DRAIN_BYPASSES+1:
		if not short_head.is_empty():jobs.erase(short_head.path)
		short_head=head("short%d"%i);jobs[short_head.path]=job();costs[short_head.path]=1
		if choose(order,[a,short_head],jobs,costs).path=="large":picked_large=true;break
	check(picked_large,"continuous short completions cannot indefinitely starve a large owner")
	var large_turns:=0;var peer_turns:=0
	for i in 102:
		jobs.erase(short_head.path);short_head=head("incoming%d"%i);jobs[short_head.path]=job();costs[short_head.path]=1
		var selected:=choose(order,[a,short_head],jobs,costs)
		if selected.path=="large":large_turns+=1
		else:peer_turns+=1
	check(large_turns>=96 and peer_turns>=6,"protected owner makes sustained progress while peers retain bounded service")
	check(choose(order,[a,short_head],jobs,costs,"",false).path=="large" and order._drain_path.is_empty(),"pressure disappearance immediately restores original priority policy")
	Order.completed_owner_drain_enabled=old
	print("COMPLETED_RESULT_ORDER checks=",checks," failures=",failures);quit(1 if failures else 0)
