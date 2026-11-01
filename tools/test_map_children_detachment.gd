extends "res://tools/test_held_node_reservation.gd"
const Driver=preload("res://scripts/world3d/map_children_detachment.gd")
const Budget=preload("res://scripts/world3d/frame_work_budget.gd")
class Cover extends Node:
	func is_opaque_drawn()->bool:return true
class ScriptedMap extends Node3D:
	pass
func map_fixture(count:int=12)->Dictionary:
	var f:=fixture()
	f.map.set_meta("runtime_record_metadata_cpu_only",true)
	f.bodies=f.nodes.slice(0,2)
	f.children=[];f.child_ids=[];f.journal.child_exits=[];f.journal.all_alive=[]
	for i:int in count:
		var child:=Node3D.new();child.name="child_%d"%i
		f.map.add_child(child,false,Node.INTERNAL_MODE_BACK if i==count-1 else Node.INTERNAL_MODE_DISABLED)
		var leaf:=Node3D.new();child.add_child(leaf)
		f.children.append(child);f.child_ids.append(child.get_instance_id());f.child_ids.append(leaf.get_instance_id())
		child.tree_exiting.connect(_child_exit.bind(child.get_instance_id(),f.journal,f.child_ids))
	f.cover=Cover.new();f.owner.add_child(f.cover)
	f.stage=Node3D.new();f.owner.add_child(f.stage)
	return f
func _child_exit(id:int,journal:Dictionary,ids:Array)->void:
	journal.child_exits.append(id)
	journal.all_alive.append(ids.all(func(value:int)->bool:return instance_from_id(value)!=null))
func map_reserve(f:Dictionary)->Dictionary:
	var plan:Dictionary=Queue.reserve_runtime_map_forest(f.bodies,f.map,f.owner)
	check(not plan.is_empty(),"plain runtime map admits one forest reservation")
	check(plan.children.size()==f.children.size() and plan.direct_snapshots==1,"one shallow snapshot includes internal children")
	check(f.service.pending.size()==1 and f.service.pending[0].roots.size()==f.bodies.size()+f.children.size()+1,"all planned roots share one FIFO ticket")
	check(plan.hold.begin_disposal(),"begin precedes terminal close and donation")
	f.plan=plan;f.hold=plan.hold;donate(f)
	for body:Node in f.bodies:check(f.hold.remove_owned_node(body,f.owner),"body guard detaches independent prefix")
	f.service.set_process(false)
	return plan
func start_driver(f:Dictionary)->Node:
	var driver:=Driver.new();f.owner.add_child(driver)
	f.driver_result={"done":false,"ok":false,"profile":{}}
	driver.finished.connect(func(ok:bool):f.driver_result.done=true;f.driver_result.ok=ok;f.driver_result.profile=driver.profile.duplicate(),CONNECT_ONE_SHOT)
	driver.configure_map(f.owner,f.map,f.plan.children,f.hold,f.cover,f.stage)
	return driver
func success_case()->void:
	var f:=map_fixture();var expected:Array=[]
	for i:int in range(f.children.size()-1,-1,-1):expected.append(f.children[i].get_instance_id())
	map_reserve(f)
	var ledger:RefCounted=Budget.shared();ledger.covered_limits=Budget.COVERED.duplicate();ledger.covered_limits.retire=1
	ledger.record(Engine.get_process_frames(),"retire",1000)
	var driver:=start_driver(f);driver.advance()
	check(driver.profile.visited==0 and driver.profile.budget_denials==1,"spent shared lane performs no new removal")
	var turns:=0
	while not f.driver_result.done and turns<64:
		check(not f.service._advance(f.service.pending[0],0),"native cursor stays behind incomplete forest")
		check(f.leaf_ref.get_ref()!=null and f.service.pending[0].freed==0,"resource donor and detached nodes survive every partial frame")
		await process_frame;turns+=1;f.service.set_process(false)
	check(f.driver_result.done and f.driver_result.ok and f.driver_result.profile.slices>1,"real retire lane splits direct subtree exits across frames")
	check(f.journal.child_exits==expected and f.journal.all_alive.all(func(v:bool)->bool:return v),"reverse direct order exits each subtree once while all handles remain alive")
	check(f.map.get_child_count(true)==0 and f.children.all(func(n:Node)->bool:return n.get_parent()==null),"cursor leaves an empty root and independent detached children")
	check(f.hold.remove_owned_node(f.map,f.owner),"empty final MapRoot uses the same active guard")
	check(f.journal.exit_reads==[true],"final root exit still borrows body, Resource and CPU records")
	check(f.hold.commit(),"checked commit accepts only the independent forest")
	cases.append({"case":"complete","driver":f.driver_result.profile,"held":f.hold.status()})
	drain(f.service)
	check(f.child_ids.all(func(id:int)->bool:return instance_from_id(id)==null),"all direct roots and descendants retire exactly once")
	check(f.journal.leaf_freed==1 and f.records[0].values==PackedInt32Array([1,2,3]),"FIFO resource releases once and shared CPU borrower survives")
	cleanup(f)
func reentrant_case(shutdown:bool,foreign_adoption:bool)->void:
	var f:=map_fixture(3);map_reserve(f)
	var child:Node=f.plan.children[0];var id:int=child.get_instance_id()
	var foreign:=Node3D.new();var observed:Dictionary={"active":false,"blocked":false,"alive":false,"commit":true}
	child.tree_exited.connect(func():
		observed.active=f.hold.status().detach_depth==1
		f.hold.cancel();observed.commit=f.hold.commit()
		var ticket:Dictionary=f.service.pending[0]
		observed.blocked=not f.service._advance(ticket,0) and int(ticket.freed)==0
		# Explicitly exercise the strongest shutdown path while remove_child is
		# still on stack. The complete FIFO must transfer, never fallback/free.
		if shutdown:f.service._drain_shutdown(true)
		else:f.service._finish_node_trees_shutdown(ticket)
		observed.alive=is_instance_valid(child) and f.leaf_ref.get_ref()!=null
		if foreign_adoption:foreign.add_child(child)
	,CONNECT_ONE_SHOT)
	check(f.hold.remove_owned_node(child,f.map),"guarded operation returns from its real tree_exited callback")
	check(observed.active and observed.blocked and not observed.commit and observed.alive,"cancel, service progress, commit and shutdown fallback preserve on-stack subtree")
	check(f.hold.status().detach_depth==0,"topology guard ends only after remove_child returns")
	if shutdown:
		check(f.service.pending.is_empty() and f.hold.status().shutdown_deferrals==1,"shutdown transfers the complete FIFO to exactly one delayed tail")
		await process_frame;await process_frame
	else:drain(f.service)
	if foreign_adoption:
		check(instance_from_id(id)!=null and child.get_parent()==foreign,"foreign off-tree adoption survives normal abort and shutdown")
		check(f.hold.status().relinquished_roots==1,"post-remove foreign root is relinquished exactly once")
	else:check(instance_from_id(id)==null,"unadopted subtree retires only after the callback stack returns")
	check(f.journal.exit_reads==[true] and f.journal.leaf_freed==1,"remaining MapRoot callback runs before donated resources release")
	check(f.hold.status().finished,"cancelled forest ends without an orphan held ticket")
	cases.append({"case":"reentrant","shutdown":shutdown,"foreign":foreign_adoption,"held":f.hold.status()})
	foreign.free();cleanup(f)
func changed_snapshot_case(add_child:bool)->void:
	var f:=map_fixture(3);map_reserve(f)
	if add_child:f.map.add_child(Node3D.new())
	else:f.plan.children[0].free()
	Budget.shared().covered_limits.retire=1000
	var driver:=start_driver(f);driver.advance()
	var turns:=0
	while not f.driver_result.done and turns<16:await process_frame;turns+=1;f.service.set_process(false)
	if add_child:
		check(f.driver_result.done and not f.driver_result.ok and f.driver_result.profile.reason=="map_children_changed","new unscheduled child refuses a false complete cursor")
		f.hold.cancel();drain(f.service)
	else:
		check(f.driver_result.done and f.driver_result.ok and f.driver_result.profile.skipped_freed==1,"producer-close deletion in the shallow snapshot is skipped safely")
		check(f.hold.remove_owned_node(f.map,f.owner) and f.hold.commit(),"freed snapshot entries do not block final independent commit")
		drain(f.service)
	check(f.child_ids.all(func(id:int)->bool:return instance_from_id(id)==null),"changed-snapshot disposal has no leaked child identities")
	cleanup(f)
func abort_reenters_shutdown_case()->void:
	var f:=map_fixture(3);map_reserve(f)
	var state:RefCounted=f.service.pending[0].detachment
	var ticket:Dictionary=f.service.pending[0]
	var child:Node=f.plan.children[0]
	var observed:Dictionary={"active":false,"alive":false}
	child.tree_exited.connect(func():
		observed.active=f.hold.status().detach_depth==1
		f.service._drain_shutdown(true)
		observed.alive=is_instance_valid(child) and f.leaf_ref.get_ref()!=null and int(ticket.freed)==0
	,CONNECT_ONE_SHOT)
	f.hold.cancel();f.service._drain_shutdown(true)
	check(observed.active and observed.alive,"abort-owned removal also protects callbacks from recursive shutdown")
	check(f.service.pending.is_empty() and int(ticket.freed)==0,"former service never consumes a forwarded native cursor or finishes an empty FIFO")
	await process_frame;await process_frame
	check(state.finished and f.child_ids.all(func(id:int)->bool:return instance_from_id(id)==null),"forwarded abort completes once after the original call stack returns")
	check(f.journal.exit_reads==[true] and f.journal.leaf_freed==1,"recursive shutdown retains last-root borrowers and releases the donor once")
	cleanup(f)
func cover_exit_on_child_case()->void:
	var f:=map_fixture(4);map_reserve(f)
	var child:Node=f.plan.children[0]
	child.tree_exited.connect(func():f.cover.free(),CONNECT_ONE_SHOT)
	Budget.shared().covered_limits.retire=1000
	var driver:=start_driver(f);driver.advance()
	var turns:=0
	while not f.driver_result.done and turns<16:await process_frame;turns+=1;f.service.set_process(false)
	check(f.driver_result.done and not f.driver_result.ok and f.driver_result.profile.reason=="cover_exited","cover exit on actual child callback completes the driver before its coroutine owner disappears")
	check(f.hold.status().aborted and f.hold.status().detach_depth==0,"cover cancellation leaves topology stack before abort can advance")
	drain(f.service)
	check(f.child_ids.all(func(id:int)->bool:return instance_from_id(id)==null) and f.journal.leaf_freed==1,"cover cancellation finishes all child roots and donor tail")
	cleanup(f)
func service_queue_free_case(entry:String)->void:
	var f:=map_fixture(3);map_reserve(f)
	var ticket:Dictionary=f.service.pending[0]
	var state:RefCounted=ticket.detachment
	var child:Node=f.plan.children[0]
	var service_ref:WeakRef=weakref(f.service)
	var observed:Dictionary={"active":false,"alive":false,"queued_alive":false,"called":false}
	child.tree_exited.connect(func():
		observed.called=true;observed.active=state.detach_depth==1
		# Direct free is prohibited while this service is calling. Use the
		# supported deferred lifetime operation on the real callback stack.
		f.service.queue_free()
		observed.queued_alive=service_ref.get_ref()!=null and f.service.is_queued_for_deletion()
		observed.alive=is_instance_valid(child) and f.leaf_ref.get_ref()!=null and int(ticket.freed)==0
	,CONNECT_ONE_SHOT)
	f.hold.cancel()
	var budget_enabled:bool=Budget.enabled;Budget.enabled=false
	match entry:
		"advance":f.service._advance(ticket,0)
		"process":
			var attempts:=0
			while service_ref.get_ref()!=null and not observed.called and attempts<8:
				f.service._process(0.);attempts+=1
		"shutdown":f.service._drain_shutdown(true)
	Budget.enabled=budget_enabled
	check(observed.called and observed.active and observed.queued_alive,"real "+entry+" callback queues service destruction while its method is active")
	check(observed.alive,"real "+entry+" queued destruction preserves on-stack roots and donors")
	check(state.detach_depth==0 and service_ref.get_ref()!=null,"real "+entry+" returns before deferred service destruction")
	await process_frame;await process_frame
	check(service_ref.get_ref()==null and state.finished and f.child_ids.all(func(id:int)->bool:return instance_from_id(id)==null) and f.ids.all(func(id:int)->bool:return instance_from_id(id)==null),"real "+entry+" queued service and forest finish exactly once")
	check(f.journal.exit_reads==[true] and f.journal.leaf_freed==1,"real "+entry+" preserves final borrowers and resource release order")
	cases.append({"case":"service_queue_free","entry":entry,"observed":observed,"held":state.status()})
	cleanup(f)
func driver_service_close_case()->void:
	var f:=map_fixture(3);map_reserve(f)
	var child:Node=f.plan.children[0]
	var state:RefCounted=f.service.pending[0].detachment
	var observed:Dictionary={"aborted_immediately":false,"remaining_untouched":false,"next_remove_refused":false}
	child.tree_exited.connect(func():
		f.service.free()
		observed.aborted_immediately=state.aborted
		observed.remaining_untouched=f.plan.children[1].get_parent()==f.map
	,CONNECT_ONE_SHOT)
	var budget_enabled:bool=Budget.enabled;Budget.enabled=false
	var driver:=start_driver(f);driver.advance()
	observed.next_remove_refused=not f.hold.remove_owned_node(f.plan.children[1],f.map)
	Budget.enabled=budget_enabled
	check(observed.aborted_immediately and observed.remaining_untouched and observed.next_remove_refused,"service close marks abort on the real callback stack and refuses further normal driver removal")
	await process_frame;await process_frame
	check(state.finished and f.child_ids.all(func(id:int)->bool:return instance_from_id(id)==null) and f.ids.all(func(id:int)->bool:return instance_from_id(id)==null),"immediate service-close abort retains the remaining forest for its tail")
	cases.append({"case":"driver_service_close","observed":observed,"held":state.status()})
	cleanup(f)
func fallback_contract_case()->void:
	var owner:=Node3D.new();root.add_child(owner)
	var scripted:=ScriptedMap.new();scripted.set_meta("runtime_record_metadata_cpu_only",true);owner.add_child(scripted)
	var unknown:=Node3D.new();owner.add_child(unknown)
	check(Queue.reserve_runtime_map_forest([],scripted,owner).is_empty(),"scripted roots preserve opaque exit and PREDELETE topology")
	check(Queue.reserve_runtime_map_forest([],unknown,owner).is_empty(),"unknown plain roots require the runtime map contract")
	var ordinary:Array[Node]=[scripted];var hold:RefCounted=Queue.reserve_node_trees(ordinary,owner)
	check(hold!=null and not hold.commit(),"ordinary independent-root API keeps its existing contract")
	hold.cancel();drain(Queue._service());check(is_instance_valid(scripted) and scripted.get_parent()==owner,"unarmed cancellation never modifies ordinary live roots")
	owner.free()
func run()->void:
	var selected_case:="all"
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):output=arg.trim_prefix("--out=")
		if arg.begins_with("--case="):selected_case=arg.trim_prefix("--case=")
	if not ClassDB.class_has_method("Node","rmmo_retire_detached_nodes_step"):
		check(false,"candidate43+ native detached node cursor is required");quit(2);return
	var original_budget_enabled:bool=Budget.enabled;Budget.enabled=true
	if selected_case=="all":
		await success_case()
		for shutdown:bool in [false,true]:
			for foreign:bool in [false,true]:await reentrant_case(shutdown,foreign)
		await abort_reenters_shutdown_case();await cover_exit_on_child_case()
		await changed_snapshot_case(false);await changed_snapshot_case(true)
		fallback_contract_case()
	if selected_case in ["all","service_lifetime"]:
		for entry:String in ["advance","process","shutdown"]:await service_queue_free_case(entry)
	if selected_case in ["all","service_close"]:await driver_service_close_case()
	Budget.shared().covered_limits=Budget.COVERED.duplicate()
	Budget.enabled=original_budget_enabled
	var report:Dictionary={"checks":checks,"failures":failures,"cases":cases}
	if not output.is_empty():
		var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("MAP_CHILDREN_RESULT ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
