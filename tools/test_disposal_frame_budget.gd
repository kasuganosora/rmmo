extends SceneTree
const Queue=preload("res://scripts/world3d/resource_retirement.gd")
const Budget=preload("res://scripts/world3d/frame_work_budget.gd")
const Bodies=preload("res://scripts/world3d/map_body_detachment.gd")
const Children=preload("res://scripts/world3d/map_children_detachment.gd")
var checks:=0
var failures:=0
var cases:Array=[]
class Cover extends Node:
	func is_opaque_drawn()->bool:return true
class RetiredNode extends Node:
	var journal:Dictionary
	var label:String
	var delay_us:=0
	func _notification(what:int)->void:
		if what!=NOTIFICATION_PREDELETE:return
		var began:=Time.get_ticks_usec()
		while Time.get_ticks_usec()-began<delay_us:pass
		journal.freed.append(label)
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1
	print("PASS " if ok else "FAIL ",label)
func _initialize()->void:run.call_deferred()
func busy_exit(journal:Dictionary,label:String)->void:
	journal.exits.append({"label":label,"frame":Engine.get_process_frames()})
	var began:=Time.get_ticks_usec()
	# Force one indivisible exit beyond the 1ms admission allowance. This is a
	# deterministic scheduling oracle, never a performance result or threshold.
	while Time.get_ticks_usec()-began<2000:pass
func donor(journal:Dictionary,label:String,delay_us:int)->Node:
	var node:=RetiredNode.new();node.journal=journal;node.label=label;node.delay_us=delay_us
	return node
func start_children(f:Dictionary)->void:
	var driver:=Children.new();f.owner.add_child(driver);f.child_driver=driver
	driver.finished.connect(func(ok:bool):f.child_done=true;f.child_ok=ok;f.child_profile=driver.profile.duplicate(),CONNECT_ONE_SHOT)
	driver.configure_map(f.owner,f.map,f.plan.children,f.plan.hold,f.cover,f.stage)
	driver.set_process(false)
	driver.advance()
	f.child_started_frame=Engine.get_process_frames()
	f.child_immediate_visited=int(driver.profile.visited)
	f.child_immediate_denials=int(driver.profile.budget_denials)
func run_case(full_ledger:bool)->void:
	await process_frame
	Budget.enabled=full_ledger
	Budget._shared=Budget.new()
	var f:Dictionary={"journal":{"freed":[],"exits":[]},"body_done":false,"body_ok":false,"child_done":false,"child_ok":false,"child_started_frame":-1}
	f.owner=Node3D.new();root.add_child(f.owner)
	f.cover=Cover.new();f.owner.add_child(f.cover)
	f.stage=Node3D.new();f.owner.add_child(f.stage)
	f.map=Node3D.new();f.map.set_meta("runtime_record_metadata_cpu_only",true);f.owner.add_child(f.map)
	f.body=Node3D.new();f.owner.add_child(f.body)
	f.body.tree_exited.connect(busy_exit.bind(f.journal,"body"),CONNECT_ONE_SHOT)
	for i:int in 2:
		var child:=Node3D.new();f.map.add_child(child)
		child.tree_exited.connect(busy_exit.bind(f.journal,"child_%d"%i),CONNECT_ONE_SHOT)
	var predecessor:Array[Node]=[donor(f.journal,"first",2000),donor(f.journal,"second",2000)]
	check(Queue.defer_node_trees(predecessor),"actual native queue accepts finite predecessor roots")
	f.plan=Queue.reserve_runtime_map_forest([f.body],f.map,f.owner)
	check(not f.plan.is_empty() and f.plan.hold.begin_disposal(),"real map forest reserves behind predecessors")
	var sentinel:Array[Node]=[donor(f.journal,"sentinel",0)]
	check(Queue.defer_node_trees(sentinel),"actual native queue accepts later FIFO sentinel")
	f.service=Queue.existing_service();f.service.set_process(false)
	var driver:=Bodies.new();f.owner.add_child(driver);f.body_driver=driver
	driver.finished.connect(func(ok:bool):
		f.body_done=true;f.body_ok=ok;f.body_profile=driver.profile.duplicate()
		if ok:start_children(f)
	,CONNECT_ONE_SHOT)
	driver.configure(f.owner,[f.body],f.plan.hold,f.cover,f.stage);driver.set_process(false)
	f.service._process(0.)
	check(f.journal.freed==["first"],"service processes one indivisible predecessor under its existing allowance")
	driver.advance()
	check(driver.profile.visited==0 and driver.profile.budget_denials==1,"earlier native work denies same-frame body detach in mode "+str(full_ledger))
	check(f.journal.exits.is_empty(),"no exit starts after predecessor consumed the frame allowance")
	var turns:=0
	while not f.child_done and turns<60:
		await process_frame;turns+=1
		f.service._process(0.)
		if not f.body_done:f.body_driver.advance()
		elif not f.child_done:f.child_driver.advance()
	check(f.body_done and f.body_ok and f.child_done and f.child_ok,"finite earlier FIFO work cannot permanently starve the detachment drivers")
	check(f.child_immediate_visited==0 and f.child_immediate_denials==1,"synchronous body-finished continuation cannot give children a fresh 1ms allowance")
	check(f.journal.freed==["first","second"],"held forest and later sentinel remain alive until all exits complete")
	check(f.body_profile.detached==1 and f.child_profile.detached==2,"body and reverse direct children each detach exactly once")
	check(f.map.get_child_count(true)==0 and f.plan.hold.remove_owned_node(f.map,f.owner) and f.plan.hold.commit(),"final empty map commits the actual independent forest")
	for turn:int in 60:
		await process_frame
		f.service._process(0.)
		if f.service.pending.is_empty():break
	check(f.service.pending.is_empty() and f.journal.freed==["first","second","sentinel"],"complete FIFO drains once and releases later ownership")
	cases.append({"full_ledger":full_ledger,"turns":turns,"body":f.body_profile,"children":f.child_profile,"journal":f.journal,"budget":Budget.report()})
	f.owner.free();f.service.free()
	await process_frame
func run()->void:
	create_timer(30).timeout.connect(func():printerr("DISPOSAL_BUDGET_TIMEOUT");quit(2))
	if not ClassDB.class_has_method("Node","rmmo_retire_detached_nodes_step"):
		check(false,"requires actual native node retirement API");quit(1);return
	var selected:="all";var output:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--case="):selected=arg.trim_prefix("--case=")
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	if selected in ["all","default"]:await run_case(false)
	if selected in ["all","enabled"]:await run_case(true)
	Budget.enabled=false
	var report:Dictionary={"checks":checks,"failures":failures,"cases":cases,"timing_claims":false}
	if not output.is_empty():FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("DISPOSAL_BUDGET ",JSON.stringify({"checks":checks,"failures":failures}))
	quit(1 if failures else 0)
