extends "res://tools/test_navigation_record_retirement.gd"
## Exercise the actual queue with delayed navigation and real decoded records.
## --late-ticket reproduces CPU ownership escaping before the old Nodes die.

func run()->void:
	load_input()
	preload("res://scripts/world3d/frame_work_budget.gd").enabled=false
	var late_ticket:=OS.get_cmdline_user_args().has("--late-ticket")
	if not ClassDB.class_has_method("Node","rmmo_retire_detached_nodes_step"):
		var plain:=Node.new();var roots_:Array[Node]=[plain]
		check(not Retirement.defer_node_trees(roots_) and is_instance_valid(plain),"unpatched engine declines ownership without side effects")
		plain.free();finish_report({"fallback":true});return
	var service:=Retirement._service();service.set_process(false)
	var journal:=Journal.new();var map:=fixture(journal,true);map.name="SameMap";root.add_child(map)
	var borrowed:Dictionary=map.get_meta("extras").rmmo_records[0]
	var digest:=var_to_bytes(borrowed)
	var identities:Array[int]=[map.get_instance_id()]
	var mesh:=BoxMesh.new();var shape:=BoxShape3D.new()
	for i in 512:
		var visual:=MeshInstance3D.new();visual.mesh=mesh;map.add_child(visual)
		identities.append(visual.get_instance_id())
	var body:=StaticBody3D.new();root.add_child(body)
	var collider:=CollisionShape3D.new();collider.shape=shape;body.add_child(collider)
	identities.append(body.get_instance_id());identities.append(collider.get_instance_id())
	var owned:Array[Node]=[body,map]
	var exit_seen:Array=[]
	map.tree_exiting.connect(func():exit_seen.append(map.get_meta("extras").rmmo_records.size()))
	var nav:=Nav.new();root.add_child(nav);nav.set_process(false);install_sources(nav,map)
	if not late_ticket:check(Retirement.defer_node_trees(owned),"native node ticket admitted before metadata preparation")
	Stream.prepare_map_disposal(map,self,nav);service.set_process(false)
	check(nav._specs.size()==count,"navigation retains its immutable sources during node preparation")
	var started:=Semaphore.new();var release:=Semaphore.new();var worker:=Thread.new()
	var worker_error:=worker.start(_wait_worker.bind(started,release))
	check(worker_error==OK,"real navigation consumer starts")
	if worker_error==OK:started.wait();nav._face_worker=worker
	check(nav.retire_background("node_fixture"),"navigation retires independently of the old map")
	nav.set_process(false);nav._process(0.)
	check(is_instance_valid(nav) and not nav.is_queued_for_deletion(),"live worker preserves navigation and record lease")
	release.post()
	while worker.is_alive():await process_frame;service.set_process(false)
	nav._process(0.);nav=null
	for i in 3:await process_frame;service.set_process(false)
	if late_ticket:check(Retirement.defer_node_trees(owned),"late baseline ticket admitted after metadata")
	service.set_process(false)
	check(service.pending[0].kind=="node_trees","node destruction is the first fence before MAIN and CPU metadata")
	var early_deadline:=Time.get_ticks_msec()+15000
	while not service.pending.is_empty() and service.pending[0].kind!="node_trees" and Time.get_ticks_msec()<early_deadline:
		if service._advance(service.pending[0],1000):service._finish_front()
		await process_frame;service.set_process(false)
	check(int(service.profile.get("geometry_batches",0))==0,"CPU metadata cannot start while its old node owners are alive")
	check(not service._advance(service.pending[0],1000) and map.is_inside_tree(),"uncommitted scene roots block the queue without destruction")
	var began:=Time.get_ticks_usec()
	root.remove_child(body);root.remove_child(map)
	var commit_us:=Time.get_ticks_usec()-began
	check(is_instance_valid(map) and not map.is_inside_tree() and exit_seen==[count],"commit detaches immediately and exit observers see intact metadata")
	check(not PhysicsServer3D.body_get_space(body.get_rid()).is_valid(),"collision space is released immediately before native destruction")
	var replacement:=Node3D.new();replacement.name="SameMap";root.add_child(replacement)
	replacement.set_meta("uuid",borrowed.uuid)
	var timing:Dictionary=await drain(service)
	check(identities.all(func(id):return instance_from_id(id)==null),"every old node is destroyed after the queued slices")
	check(is_instance_valid(replacement) and replacement.is_inside_tree() and str(replacement.name)=="SameMap","returning to the same map and UUID cannot destroy new nodes")
	check(journal.freed==count and journal.off_main==0,"all Resource leaves die once on MAIN")
	check(var_to_bytes(borrowed)==digest,"surviving metadata borrower is never mutated")
	check(int(service.profile.get("geometry_batches",0))==1 and int(service.profile.get("geometry_last_thread_id",0))!=OS.get_thread_caller_id(),"decoded roots release once on the CPU lane after all consumers")
	check(int(service.profile.get("node_units",0))==identities.size(),"native work counter accounts for every plain node exactly once")
	var measured_profile:Dictionary=service.profile.duplicate()
	replacement.free();service.free();borrowed={}
	await _loader_exit_contract()
	_shutdown_contract()
	finish_report({"late_ticket":late_ticket,"nodes":identities.size(),"entries":count,"commit_us":commit_us,"retirement":timing,"profile":measured_profile,"scope":"real retirement queue and navigation; component, not map/FPS"})

func _loader_exit_contract()->void:
	var drainer_type=preload("res://scripts/world3d/asset_worker_drainer.gd")
	var drainer:Node=drainer_type.for_tree(self)
	var service:=Retirement._service();service.set_process(false)
	var map:=Node3D.new();root.add_child(map)
	var loader:=preload("res://scripts/world3d/deferred_asset_loader.gd").new()
	loader.name="DeferredAssets";map.add_child(loader);loader.set_process(false)
	loader._map=map;loader._drainer=drainer;loader._active=true
	var publications:Array=[];loader.published.connect(func(items):publications.append(items))
	var started:=Semaphore.new();var release:=Semaphore.new();var worker:=Thread.new()
	var token:RefCounted=drainer_type.CancelToken.new();token.set_meta("cpu_metadata_only",true)
	check(worker.start(_wait_worker.bind(started,release))==OK,"real loader worker starts behind a release gate")
	started.wait();drainer.watch(worker,token)
	loader._jobs["same_model"]={"worker":worker,"token":token}
	var loader_id:=loader.get_instance_id();var roots_:Array[Node]=[map]
	check(Retirement.defer_node_trees(roots_),"pending loader uses the same permanent node queue")
	Stream.prepare_map_disposal(map,self);root.remove_child(map);service.set_process(false)
	check(loader._cancelled and token.is_cancelled() and loader._jobs.is_empty(),"scene exit cancels and transfers workers before delayed Node destruction")
	check(worker.is_alive() and drainer.jobs.size()==1 and drainer.jobs[0].abandoned,"commit never joins the blocked worker")
	loader._process(0.)
	check(publications.is_empty(),"a still-valid detached loader cannot publish stale results")
	var deadline:=Time.get_ticks_msec()+10000
	while not service.pending.is_empty() and Time.get_ticks_msec()<deadline:
		if service._advance(service.pending[0],1000):service._finish_front()
		await process_frame;service.set_process(false)
	check(instance_from_id(loader_id)==null and worker.is_alive(),"old loader dies while its independent worker owner remains alive")
	release.post()
	while not drainer.jobs.is_empty() and Time.get_ticks_msec()<deadline:await process_frame;service.set_process(false)
	check(drainer.jobs.is_empty() and publications.is_empty(),"late result drains exactly once without returning to the old map")
	service.free()

func _shutdown_contract()->void:
	var service:=Retirement._service();service.set_process(false)
	var live:=Node.new();root.add_child(live)
	var detached:=Node.new();var child:=Node.new();detached.add_child(child)
	var child_id:=child.get_instance_id();var dead_id:=detached.get_instance_id()
	var roots_:Array[Node]=[live,detached]
	check(Retirement.defer_node_trees(roots_),"shutdown fixture reserves live and detached roots")
	service.free()
	check(is_instance_valid(live) and live.is_inside_tree(),"shutdown never destroys a still-live scene owner")
	check(instance_from_id(dead_id)==null and instance_from_id(child_id)==null,"shutdown also drains detached roots behind a live reservation")
	live.free()
	Retirement.native_node_retirement_enabled=false
	var disabled:=Node.new();roots_=[disabled]
	check(not Retirement.defer_node_trees(roots_) and is_instance_valid(disabled),"disabled native path leaves synchronous caller ownership intact")
	disabled.free();Retirement.native_node_retirement_enabled=true

func finish_report(result:Dictionary)->void:
	result.checks=checks;result.failures=failures
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):FileAccess.open(arg.trim_prefix("--output="),FileAccess.WRITE).store_string(JSON.stringify(result,"\t"))
	print("MAP_NODE_RETIREMENT ",JSON.stringify(result));quit(0 if failures.is_empty() else 1)
