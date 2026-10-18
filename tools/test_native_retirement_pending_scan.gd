extends "res://tools/test_native_retirement_scheduling.gd"
const Native=preload("res://scripts/world3d/native_residency.gd")
class Navigation:
	extends Node
	var _local_clip:=AABB(Vector3(-100,0,-100),Vector3.ONE)
func run()->void:
	var saved:=Native.lazy_pending_scan_enabled
	var host:=Host.new();var queue:=Queue.new();var nav:=Navigation.new();host._navigation=nav
	var service:=Native.new();service._host=host;service._queue=queue;service.grace_msec=100
	for i:int in 2046:queue.pending.append({"record":{"uuid":"pending%d"%i}})
	queue.pending.append({"record":{"uuid":"unit3"}})
	for i:int in 32:
		service._units[str(i)]={"entries":[{"compact_record":{"uuid":"unit%d"%i},"reason":"native_road"}],"bounds":AABB(Vector3(3200+i,0,0),Vector3.ONE),"kind":"all"}
	for mode:String in ["needed","fresh","grace","expired","empty"]:
		var expected:Dictionary={}
		for enabled:bool in [false,true]:
			Native.lazy_pending_scan_enabled=enabled;service._resident={};service._cursor=0;service.profile={}
			queue._demands={"all":{"clip":AABB(Vector3(3100,0,-100),Vector3(300,1,300))}} if mode=="needed" else {}
			if mode!="empty":
				for i:int in 32:service._resident[str(i)]={"outside_since":-1 if mode=="fresh" else (950 if mode=="grace" else 0),"ids":["spec%d"%i]}
			var candidates:Array=service._retirement_candidates(1000)
			var state:Dictionary={"candidates":candidates,"cursor":service._cursor,"resident":service._resident.duplicate(true),"scanned":service.profile.scanned_units}
			if not enabled:expected=state
			else:
				check(state==expected,"same candidates, grace timestamps and round-robin cursor: "+mode)
				check(int(service.profile.get("pending_membership_builds",0))==(1 if mode=="expired" else 0),"pending lookup only for expired eligible units: "+mode)
				if mode=="expired":check(candidates.size()==15 and "3" not in candidates,"one fresh pending lookup protects the matching ownership unit across the entire slice")
	# Never reuse a guard across calls: remove/add a pending owner and revisit
	# the same observation slice to prove the next lookup sees the change.
	service._resident={"3":{"outside_since":0,"ids":["spec3"]}};service._cursor=0;queue._demands={}
	check(service._retirement_candidates(1000).is_empty(),"pending member blocks a mature unit")
	queue.pending.pop_back()
	check(service._retirement_candidates(1000)==["3"],"removing pending member is visible on the next poll")
	queue.pending.append({"record":{"uuid":"unit3"}})
	check(service._retirement_candidates(1000).is_empty(),"newly pending member is protected immediately")
	Native.lazy_pending_scan_enabled=saved
	service.free();queue.free();nav.free();host.free()
	print("NATIVE_RETIREMENT_PENDING_SCAN checks=",checks," failures=",failures);quit(1 if failures else 0)
