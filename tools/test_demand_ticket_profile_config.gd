extends SceneTree
const Runner=preload("res://tools/profile_axel_demand_tickets.gd")
class FakeQueue extends Node:
	var drops:=0
	func stop_demand_ticket_trace()->Dictionary:return {"events":[],"dropped":drops}
var passed:=0
var failed:=0
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	print("PASS " if value else "FAIL ",label)
	if value:passed+=1
	else:failed+=1
func run()->void:
	var config:Dictionary=Runner.ticket_configuration(PackedStringArray())
	check(config.error.is_empty() and config.phase=="white_native_return" and config.capacity==16384,"defaults are explicit")
	config=Runner.ticket_configuration(PackedStringArray(["--demand-ticket-phase=white_walk_return","--demand-ticket-capacity=72"]))
	check(config.error.is_empty() and config.phase=="white_walk_return" and config.capacity==72,"explicit walk and capacity")
	for args:Array in [["--demand-ticket-phase=x"],["--demand-ticket-capacity=-1"],["--demand-ticket-capacity=16385"],["--demand-ticket-capacity=x"],["--demand-ticket-phase=white_native_return","--demand-ticket-phase=white_native_return"],["--demand-ticket-capacity=1","--demand-ticket-capacity=2"]]:
		check(not Runner.ticket_configuration(PackedStringArray(args)).error.is_empty(),"invalid config rejected: "+str(args))
	var probe=Runner.new();var map:=Node3D.new();var queue:=FakeQueue.new();queue.name="DeferredAssets";map.add_child(queue)
	probe.mesh_map=map;probe.ticket_config=config
	probe.phase="white_walk_return_straight";probe._ticket_boundary("start")
	probe.phase="white_walk_return_turn";probe._ticket_boundary("transition")
	probe.phase="white_walk_reload";probe._ticket_boundary("end");probe._stop_ticket_capture()
	check(probe.report.demand_ticket_status=="complete_return_leg" and probe.report.demand_ticket_boundaries.size()==3,"both walk segments and end are recorded")
	queue.drops=1;probe._stop_ticket_capture()
	check(probe.report.demand_ticket_status=="incomplete_event_overflow","dropped ticket events invalidate complete capture")
	probe.report.demand_ticket_boundaries_dropped=1;queue.drops=0;probe._stop_ticket_capture()
	check(probe.report.demand_ticket_status=="incomplete_boundary_overflow","lost phase boundary invalidates coverage")
	map.free();probe.free()
	print("DEMAND_TICKET_PROFILE_CONFIG passed=",passed," failures=",failed);quit(0 if failed==0 else 1)
