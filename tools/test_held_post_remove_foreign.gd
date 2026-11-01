extends "res://tools/test_held_node_reservation.gd"
## Actual held queue and actual service.free -> deferred shutdown-tail route.
## The foreign parent takes the Node on tree_exited, not before abort starts.

func adoption_during_remove(shutdown:bool)->void:
	var f:=fixture();var hold:=reserve(f)
	if hold==null:cleanup(f);return
	check(hold.begin_disposal(),"callback adoption: permanent disposal begins")
	var foreign:=Node3D.new() # Deliberately not in SceneTree; still owns children.
	var adopted:Node=f.nodes[0]
	var journal:Dictionary={"calls":0,"parent_was_null":false,"old_inside":false}
	adopted.tree_exited.connect(func():
		journal.calls+=1;journal.parent_was_null=adopted.get_parent()==null;journal.old_inside=adopted.is_inside_tree()
		foreign.add_child(adopted)
	,CONNECT_ONE_SHOT)
	donate(f)
	var state:RefCounted=f.service.pending[0].detachment
	var label:="shutdown" if shutdown else "normal abort"
	if shutdown:
		f.service.free()
		check(is_instance_valid(adopted) and f.leaf_ref.get_ref()!=null,"shutdown: service exit defers destruction beyond its own exit stack")
		await process_frame
		await process_frame
	else:
		hold.cancel();drain(f.service)
	check(journal.calls==1 and journal.parent_was_null and not journal.old_inside,label+": actual tree_exited callback adopted the parentless root exactly once")
	var borrowed_alive:bool=is_instance_valid(f.nodes[0]) and instance_from_id(f.ids[1])!=null
	check(borrowed_alive and foreign.get_child_count()==1 and foreign.get_child(0)==f.nodes[0],label+": callback-adopted foreign body and shape survive unchanged")
	check(hold.status().relinquished_roots==1,label+": relinquishes exactly the root adopted during remove")
	check(f.ids.slice(2).all(func(id:int)->bool:return instance_from_id(id)==null),label+": every other old root finishes retirement")
	check(f.journal.exit_reads==[true],label+": final map exit reads the adopted prefix and retained donor")
	check(f.journal.leaf_freed==1 and f.journal.off_main==0,label+": donor releases exactly once on MAIN after old roots finish")
	check(f.records[0].values==PackedInt32Array([1,2,3]),label+": external CPU borrower remains unchanged")
	check(state.finished and not state.held,label+": no held FIFO state survives")
	cases.append({"case":label,"status":hold.status(),"callback":journal.duplicate(),"borrowed_alive":borrowed_alive,"other_roots_alive":f.ids.slice(2).filter(func(id:int)->bool:return instance_from_id(id)!=null).size(),"exit_reads":f.journal.exit_reads.duplicate()})
	foreign.free();cleanup(f)

func independent_root_fallback()->void:
	var service:=Queue._service();service.set_process(false)
	var foreign:=Node3D.new()
	var borrowed:=Node3D.new();foreign.add_child(borrowed)
	var borrowed_child:=Node3D.new();borrowed.add_child(borrowed_child)
	var orphan:=Node3D.new();var orphan_child:=Node3D.new();orphan.add_child(orphan_child)
	var borrowed_id:int=borrowed.get_instance_id();var borrowed_child_id:int=borrowed_child.get_instance_id()
	var orphan_id:int=orphan.get_instance_id();var orphan_child_id:int=orphan_child.get_instance_id()
	var roots:Array[Node]=[borrowed,orphan];var stack:Array[Node]=[]
	service._finish_node_trees_shutdown({"roots":roots,"stack":stack})
	check(instance_from_id(borrowed_id)!=null and instance_from_id(borrowed_child_id)!=null and foreign.get_child_count()==1,"fallback: off-tree parent ownership is not mistaken for an independent detached root")
	check(instance_from_id(orphan_id)==null and instance_from_id(orphan_child_id)==null,"fallback: actual independent root still retires its complete subtree")
	check(roots.is_empty() and stack.is_empty(),"fallback: private handle containers are relinquished")
	foreign.free();service.free()

func finish()->void:
	var result:Dictionary={"checks":checks,"failures":failures,"cases":cases,"scope":"held abort and deferred shutdown-tail post-remove foreign ownership; real queue, MAIN only"}
	if not output.is_empty():FileAccess.open(output,FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("HELD_POST_REMOVE_FOREIGN59 ",JSON.stringify(result));quit(0 if failures.is_empty() else 1)

func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	preload("res://scripts/world3d/frame_work_budget.gd").enabled=false
	check(ClassDB.class_has_method("Node","rmmo_retire_detached_nodes_step"),"native node retirement is available")
	if not ClassDB.class_has_method("Node","rmmo_retire_detached_nodes_step"):finish();return
	await adoption_during_remove(false)
	await adoption_during_remove(true)
	independent_root_fallback()
	finish()
