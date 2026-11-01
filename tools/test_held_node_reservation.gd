extends SceneTree
const Queue=preload("res://scripts/world3d/resource_retirement.gd")
var checks:=0
var failures:Array[String]=[]
var cases:Array=[]
var baseline:=false
var output:=""
class Leaf extends Resource:
	var on_free:Callable
	func _notification(what:int)->void:
		if what==NOTIFICATION_PREDELETE and on_free.is_valid():on_free.call()
class Owner extends Node3D:
	var on_exit:Callable
	func _exit_tree()->void:
		if on_exit.is_valid():on_exit.call()
func _initialize()->void:run.call_deferred()
func check(ok:bool,message:String)->void:
	checks+=1;print("PASS " if ok else "FAIL ",message)
	if not ok:failures.append(message)
func fixture()->Dictionary:
	var service:=Queue._service();service.set_process(false)
	var owner_host:=Node3D.new();root.add_child(owner_host)
	var owner:=Owner.new();owner_host.add_child(owner)
	var nodes:Array[Node]=[];var ids:Array[int]=[]
	for i:int in 2:
		var body:=StaticBody3D.new();owner.add_child(body);nodes.append(body);ids.append(body.get_instance_id())
		var collider:=CollisionShape3D.new();collider.shape=BoxShape3D.new();body.add_child(collider);ids.append(collider.get_instance_id())
	var map:=Node3D.new();owner.add_child(map);nodes.append(map);ids.append(map.get_instance_id())
	var records:Array=[{"uuid":"borrowed","values":PackedInt32Array([1,2,3])}];map.set_meta("records",records)
	var journal:Dictionary={"leaf_freed":0,"off_main":0,"exit_reads":[]}
	var leaf:=Leaf.new();leaf.on_free=func():journal.leaf_freed+=1;journal.off_main+=int(not Thread.is_main_thread())
	var leaf_ref:WeakRef=weakref(leaf);var prefix_ref:WeakRef=weakref(nodes[0])
	map.tree_exiting.connect(func():journal.exit_reads.append(prefix_ref.get_ref()!=null and leaf_ref.get_ref()!=null and map.get_meta("records")[0].values==PackedInt32Array([1,2,3])))
	return {"service":service,"owner":owner,"owner_host":owner_host,"nodes":nodes,"ids":ids,"map":map,"records":records,"journal":journal,"leaf":leaf,"leaf_ref":leaf_ref}
func reserve(f:Dictionary)->RefCounted:
	var owned:Array[Node]=[];owned.assign(f.nodes)
	if baseline:
		print("ADMISSION_DIAG ",JSON.stringify({"roots":owned.size(),"enabled":Queue.native_node_retirement_enabled,"native":ClassDB.class_has_method("Node","rmmo_retire_detached_nodes_step"),"main":Thread.is_main_thread(),"service_valid":is_instance_valid(Queue._service())}))
		check(Queue.defer_node_trees(owned),"legacy synchronous reservation admitted before owners")
		f.service.set_process(false);return null
	var script:Script=load("res://scripts/world3d/resource_retirement.gd")
	var hold:RefCounted=script.call("reserve_node_trees",owned,f.owner)
	check(hold!=null,"held reservation admitted before owners")
	f.service.set_process(false);return hold
func donate(f:Dictionary)->void:
	Queue.defer_private_array([f.leaf],true);f.erase("leaf")
	Queue.defer_cpu_values([f.records],0);f.service.set_process(false)
func drain(service:Node)->void:
	var iterations:=0
	while not service.pending.is_empty() and iterations<1000:
		if service._advance(service.pending[0],0):service._finish_front()
		iterations+=1
	check(service.pending.is_empty(),"FIFO including CPU owner tail completes without a held-ticket deadlock")
	service.set_process(false)
func cleanup(f:Dictionary)->void:
	if is_instance_valid(f.owner):f.owner.free()
	if is_instance_valid(f.owner_host):f.owner_host.free()
	if is_instance_valid(f.service):f.service.free()
func partial_detach()->void:
	var f:=fixture();var hold:=reserve(f)
	if f.service.pending.is_empty():cleanup(f);return
	if not baseline:
		check(hold.begin_disposal(),"explicit permanent boundary precedes producer close and owner donation")
		check(not hold.commit(),"commit rejects roots that have not left the scene")
	donate(f);f.owner.remove_child(f.nodes[0])
	var ticket:Dictionary=f.service.pending[0]
	check(not f.service._advance(ticket,0),"an incomplete detach transaction keeps its FIFO fence")
	check(is_instance_valid(f.nodes[0]),"detached prefix survives service progress until explicit commit")
	check(int(ticket.freed)==0,"held reservation performs zero native destruction work")
	check(is_instance_valid(f.nodes[1]) and f.nodes[1].is_inside_tree(),"still-live roots are never destroyed")
	check(f.leaf_ref.get_ref()!=null and int(f.service.profile.get("geometry_batches",0))==0,"resource and CPU owner donations remain behind the held node fence")
	for i:int in range(1,f.nodes.size()):f.owner.remove_child(f.nodes[i])
	check(f.journal.exit_reads==[true],"last map exit callback reads retained detached sibling and owner data")
	if not baseline:
		check(hold.commit(),"explicit commit accepts the fully detached root list")
		check(hold.status().commit_root_checks==4,"commit records actual lifecycle-check work including rejected early call")
	drain(f.service)
	check(f.ids.all(func(id:int)->bool:return instance_from_id(id)==null),"every original node identity retires after complete detach")
	check(f.journal.leaf_freed==1 and f.journal.off_main==0,"owner resource releases once on MAIN after node retirement")
	check(int(f.service.profile.get("geometry_batches",0))==1,"CPU donation starts exactly once after the node fence completes")
	check(f.records[0].values==PackedInt32Array([1,2,3]),"external CPU borrower is unchanged")
	if hold!=null:cases.append({"case":"explicit_commit","status":hold.status()})
	cleanup(f)
func before_disposal_cancel(drop:bool)->void:
	var f:=fixture();var hold:=reserve(f);var weak:WeakRef=weakref(hold)
	if drop:hold=null
	else:hold.cancel()
	if drop:check(weak.get_ref()==null,"FIFO and owner signal never retain the caller Hold")
	drain(f.service)
	check(f.nodes.all(func(n:Node)->bool:return is_instance_valid(n) and n.is_inside_tree()),"cancelling an unarmed reservation never destroys a valid map")
	check(int(f.service.profile.get("node_units",0))==0,"unarmed cancellation does no node destruction work")
	cleanup(f)
func abort_case(kind:String)->void:
	var f:=fixture();var hold:=reserve(f);check(hold.begin_disposal(),kind+": enter irreversible disposal")
	var state:RefCounted=f.service.pending[0].detachment;donate(f);f.owner.remove_child(f.nodes[0])
	match kind:
		"cancel":hold.cancel()
		"drop":
			var weak:WeakRef=weakref(hold);hold=null;check(weak.get_ref()==null,"armed caller Hold really releases without a signal cycle")
		"owner_exit":f.owner.get_parent().remove_child(f.owner)
		"owner_free":f.owner.free()
	check(is_instance_valid(f.nodes[0]),kind+": abort callback does not synchronously destroy the detached prefix")
	drain(f.service)
	check(f.ids.all(func(id:int)->bool:return instance_from_id(id)==null),kind+": interrupted permanent disposal finishes all remaining roots")
	check(f.journal.exit_reads==[true] and f.journal.leaf_freed==1,kind+": exit borrowers remain intact before final owner release")
	check(state.finished and not state.held,kind+": terminal state cannot retain a FIFO hold")
	cases.append({"case":kind,"status":state.status()});cleanup(f)
func foreign_adoption(at_commit:bool,in_tree:bool)->void:
	var f:=fixture();var hold:=reserve(f);hold.begin_disposal();donate(f)
	var foreign:=Node3D.new()
	if in_tree:root.add_child(foreign)
	for node:Node in f.nodes:f.owner.remove_child(node)
	foreign.add_child(f.nodes[0])
	var label:String=("commit" if at_commit else "abort")+(" live" if in_tree else " off-tree")+" foreign adoption"
	if at_commit:
		check(not hold.commit(),label+": rejects a root that is not independently detached")
		check(not f.service._advance(f.service.pending[0],0) and is_instance_valid(f.nodes[0]),label+": refused commit keeps the borrower behind the held fence")
	hold.cancel();drain(f.service)
	var borrowed_alive:bool=is_instance_valid(f.nodes[0]) and instance_from_id(f.ids[1])!=null
	check(borrowed_alive and foreign.get_child_count()==1 and foreign.get_child(0)==f.nodes[0],label+": foreign parent retains body and shape unchanged")
	check(hold.status().relinquished_roots==1,label+": old ownership relinquishes exactly the adopted root")
	check(f.ids.slice(2).all(func(id:int)->bool:return instance_from_id(id)==null),label+": all other roots finish retirement")
	check(f.records[0].values==PackedInt32Array([1,2,3]) and f.journal.leaf_freed==1,label+": borrowed CPU data and FIFO owner tail remain correct")
	cases.append({"case":label,"status":hold.status()});foreign.free();cleanup(f)
func service_free_in_exit()->void:
	var f:=fixture();var hold:=reserve(f);hold.begin_disposal();donate(f);f.owner.remove_child(f.nodes[0])
	# This is deliberately reentrant: service teardown occurs on an owner exit stack.
	f.owner.on_exit=func():f.service.free();check(is_instance_valid(f.nodes[0]) and f.leaf_ref.get_ref()!=null,"service.free on owner exit stack preserves detached prefix and owners")
	f.owner.free()
	check(is_instance_valid(f.nodes[0]),"shutdown tail waits until the entire synchronous owner exit returns")
	await process_frame
	await process_frame
	check(f.ids.all(func(id:int)->bool:return instance_from_id(id)==null),"off-tree shutdown tail eventually drains without the former service")
	check(f.journal.exit_reads==[true] and f.journal.leaf_freed==1,"reentrant service shutdown preserves all exit borrowers")
	f.owner_host.free()
func shutdown_case(order:String)->void:
	var f:=fixture();var hold:=reserve(f);hold.begin_disposal();donate(f);f.owner.remove_child(f.nodes[0])
	# Keep the Hold until shutdown; State is independently retained by its ticket.
	set_meta("shutdown_hold",hold)
	var tail:=Leaf.new();tail.on_free=_shutdown_done.bind(f)
	Queue.defer_private_array([tail],true);tail=null;f.service.set_process(false)
	if order=="service_first":root.move_child(f.service,root.get_child_count()-1)
	else:root.move_child(f.owner_host,root.get_child_count()-1)
	f.owner.on_exit=func():check(is_instance_valid(f.nodes[0]) and f.leaf_ref.get_ref()!=null,"full shutdown keeps borrowed prefix alive on owner exit: "+order)
	quit(0)
func _shutdown_done(f:Dictionary)->void:
	check(f.ids.all(func(id:int)->bool:return instance_from_id(id)==null),"final shutdown fence releases every old node before its owner tail")
	check(f.journal.exit_reads==[true] and f.journal.leaf_freed==1,"both shutdown phases finished before owner donations release")
	finish()
func finish()->void:
	var result:Dictionary={"checks":checks,"failures":failures,"cases":cases,"baseline":baseline,"scope":"independent held retirement component; no World3D async detach hookup"}
	if not output.is_empty():FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("HELD_NODE_RESERVATION57 ",JSON.stringify(result));quit(0 if failures.is_empty() else 1)
func unsupported_case()->void:
	var f:=fixture();var owned:Array[Node]=[];owned.assign(f.nodes)
	var script:Script=load("res://scripts/world3d/resource_retirement.gd")
	var hold:RefCounted=script.call("reserve_node_trees",owned,f.owner)
	check(hold==null and not Queue.defer_node_trees(owned) and f.service.pending.is_empty() and f.nodes.all(func(n:Node)->bool:return n.is_inside_tree()),"unsupported engine declines both APIs without taking ownership or changing the valid map")
	cleanup(f);finish()
func run()->void:
	var shutdown_order:=""
	for arg:String in OS.get_cmdline_user_args():
		if arg=="--baseline":baseline=true
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		if arg.begins_with("--shutdown="):shutdown_order=arg.trim_prefix("--shutdown=")
	preload("res://scripts/world3d/frame_work_budget.gd").enabled=false
	if "--unsupported" in OS.get_cmdline_user_args():unsupported_case();return
	if not shutdown_order.is_empty():shutdown_case(shutdown_order);return
	if "--foreign-only" in OS.get_cmdline_user_args():
		for live:bool in [false,true]:
			foreign_adoption(true,live);foreign_adoption(false,live)
		finish();return
	partial_detach()
	if not baseline:
		before_disposal_cancel(false);before_disposal_cancel(true)
		for kind:String in ["cancel","drop","owner_exit","owner_free"]:abort_case(kind)
		await service_free_in_exit()
	finish()
