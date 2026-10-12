extends "res://tools/test_collision_dependency_loader.gd"
## Deterministic scheduling fixture, not a shape-cost benchmark. A real Store
## advances one exact shape, then a bounded injected wait consumes its grant.
const FrameBudget=preload("res://scripts/world3d/frame_work_budget.gd")
var previous_dispatch:=false
var previous_profile:=false
var previous_none:=false
var previous_budget:=false
var previous_shared:RefCounted

class ObservedStore extends "res://scripts/world3d/collision_instance_residency.gd":
	var service:WeakRef
	var calls:=0
	var grants:Array[int]=[]
	var workers:Array[int]=[]
	var consumed_usec:=0
	var units:=0
	func step(budget_usec:int=1500)->Dictionary:
		calls+=1;grants.append(budget_usec)
		var owner:Node=service.get_ref()
		workers.append(owner._planning.active_workers()+owner._preparing.active_workers())
		var began:=Time.get_ticks_usec()
		# Retain the production shape builder, identity and physics watermarks.
		# Only cost is injected, simulating one indivisible native operation.
		var result:Dictionary=super.step(mini(1,budget_usec))
		units+=int(result.get("units",0))
		if budget_usec>0:
			var deadline:=began+budget_usec+200
			OS.delay_usec(maxi(0,deadline-Time.get_ticks_usec()))
			# Windows may wake a short delay early. At most this tiny fixture's
			# remaining 1.7 ms is spun; assert actual cost, not timer precision.
			while Time.get_ticks_usec()<deadline:pass
		consumed_usec+=Time.get_ticks_usec()-began
		return result

func run()->void:
	previous_dispatch=Loader.dispatch_before_installation
	previous_profile=Loader.dispatch_profile_enabled
	previous_none=Loader.no_collision_proof_enabled
	previous_budget=FrameBudget.enabled;previous_shared=FrameBudget._shared
	Loader.no_collision_proof_enabled=false
	Loader.dispatch_profile_enabled=true;FrameBudget.enabled=true
	var errors:=Errors.new();OS.add_logger(errors)
	create_timer(45).timeout.connect(func():
		for gate:Semaphore in cleanup_gates:gate.post();gate.post()
		push_error("collision dispatch overlap timeout");quit(2)
	)
	folder=Paths.cache_directory("collision_dispatch_test_%d"%Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(folder)
	var model:=folder.path_join("fixture.glb");fixture(model)
	var built:=await worker(Builder.build.bind(model,folder,Builder.estimate(model,folder).estimated_bytes))
	check(built.ok and verify_png(built.private_preparation),"real embedded-PNG GLB produces the independent collision sidecar")
	if not built.ok:Drainer.dispose_result(built);finish(errors);return
	Drainer.dispose_result(built)
	var helper:=MapFixture.new();helper.folder=folder;helper.content_root=folder
	var records:Array=[]
	for i in 2:records.append({"uuid":"item"+str(i),"kind":"asset","asset_path":model,"position":[i*10,0,0],"rotation":[0,0,0],"size":[1,1,1],"collision":"block"})
	var author:=helper.fixture("map",records)
	check(Index.build(author.path,folder,records).ok,"real referenced records build the ownership index")
	var issued:=Index.read_for_loading(author.path,folder)
	check(issued.ok,"independent reader issues the actual map proof")
	if not issued.ok:helper.free();finish(errors);return
	var seed:Array=[entry(issued.index,0)]
	var plan:=await worker(Loader.Adapter.plan.bind(issued.index,seed,author.path,folder,issued.proof))
	check(plan.ok,"seed shape work has a real dependency plan")
	if not plan.ok:helper.free();finish(errors);return
	var preparation:=Admission.new();preparation.worker_limit=1
	check(preparation.reserve("seed",{"estimated_bytes":plan.estimated_bytes,"exclusive":false}),"fixture retains the seed worker and packet's complete preparation charge")
	var prepared:=await worker(Loader.Adapter.prepare.bind(plan,plan.estimated_bytes))
	preparation.park("seed")
	check(prepared.ok,"worker supplies a typed exact-geometry Batch without visual publication")
	if not prepared.ok:Drainer.dispose_result(prepared);preparation.release("seed");helper.free();finish(errors);return
	await case_order(issued,author.path,prepared.batch,false,true)
	await case_order(issued,author.path,prepared.batch,true,true)
	await case_order(issued,author.path,prepared.batch,false,false)
	prepared.clear();plan.clear();preparation.release("seed")
	check(preparation.reserved_bytes==0,"fixture seed packet is released after every Store has retired its ownership")
	helper.free();await process_frame;await process_frame
	finish(errors)

func case_order(issued:Dictionary,path:String,batch:RefCounted,dispatch_first:bool,admissible:bool)->void:
	Loader.dispatch_before_installation=dispatch_first
	FrameBudget._shared=FrameBudget.new()
	var service:=GateLoader.new();cleanup_gates.append(service.gate)
	var map:=attach(service,issued,path)
	# Swap only the empty Store for an observing subclass. All actual batch
	# admission, triangle construction, cancellation and watermarks stay real.
	service._store.free()
	var store:=ObservedStore.new();map.add_child(store);store.service=weakref(service)
	check(store.configure(map,path,issued.index.source_sha256,7).ok and store.enqueue(batch,7).ok,"observing Store owns a real unfinished source-bound instance")
	service._store=store
	var entries:Array=[entry(issued.index,1)]
	service.request(entries,0,"foreground");service.set_process(false)
	if not admissible:service._planning.byte_limit=1
	service._advance_queue(0,true)
	check(service.starts==0 and store.calls==0 and service.profile.plan_jobs==0,"zero local budget performs neither worker dispatch nor shape work")
	FrameBudget.shared().record(Engine.get_process_frames(),"collision",2000)
	service._advance_queue(1500,true)
	check(service.starts==0 and store.calls==0,"exhausted shared lane cannot be bypassed by dispatch-first")
	await process_frame
	var began:=Time.get_ticks_usec()
	service._advance_queue(1500,true)
	var elapsed:=Time.get_ticks_usec()-began
	var snapshot:Dictionary=service.snapshot()
	var budget:Dictionary=FrameBudget.report()
	print("DISPATCH_CASE ",JSON.stringify({"dispatch_first":dispatch_first,"admissible":admissible,"starts":service.starts,"store_calls":store.calls,"store_grants":store.grants,"workers_at_store":store.workers,"elapsed_us":elapsed,"charged_us":budget.current_lanes.get("collision",0),"idle_frames":snapshot.get("dispatch_budget_idle_frames",0)}))
	if dispatch_first:
		check(service.starts==1 and service.profile.plan_jobs==1 and service._planning.active_workers()==1,"dispatch-first starts one genuinely blocked CPU worker before shape installation")
		check(store.calls==1 and store.workers==[1] and store.grants[0]>0 and store.grants[0]<1500,"shape work still receives only the same frame's unspent allowance")
		check(snapshot.get("dispatch_budget_idle_frames",0)==0,"overlapped worker is not reported as an idle budget-starved slot")
	else:
		check(service.starts==0 and service.profile.plan_jobs==0 and store.calls==1 and store.workers==[0],"late-dispatch control spends its shape grant without starting the waiting worker")
		check(snapshot.get("dispatch_budget_idle_frames",0)==(1 if admissible else 0),"idle diagnostic counts only budget-delayed work that could actually be admitted")
	check(store.units==1 and store.debug_snapshot().shape_count==1 and store.debug_snapshot().pending==1,"same exact geometry builder advances a real shape without completing the instance")
	check(budget.current_lanes.get("collision",0)>=store.consumed_usec and budget.current_lanes.get("collision",0)>=1500,"indivisible overrun is charged to the original frame rather than granting another budget")
	check(not service.coverage(entries).ok and not store.instance_readiness("item0",7).ok,"dispatch and partial shapes grant no early collision or physics readiness")
	var planning:RefCounted=service._planning;var preparing:RefCounted=service._preparing
	var retained:int=planning.reserved_bytes
	service.cancel("fixture_cancel")
	check(planning.reserved_bytes==retained and store.debug_snapshot().reserved_bytes==0,"cancel retires shape ownership but retains every still-running worker reservation")
	service.open();await wait_drained(planning,preparing)
	check(planning.reserved_bytes==0 and preparing.reserved_bytes==0 and not service.coverage(entries).ok,"worker drainer releases both ledgers without publishing a cancelled result")
	map.free();await process_frame

func finish(errors:Logger)->void:
	Loader.dispatch_before_installation=previous_dispatch
	Loader.dispatch_profile_enabled=previous_profile
	Loader.no_collision_proof_enabled=previous_none
	FrameBudget.enabled=previous_budget;FrameBudget._shared=previous_shared
	remove_fixture(folder);OS.remove_logger(errors)
	check(errors.errors.is_empty(),"zero unexpected engine or script errors")
	for issue:String in errors.errors:print("ENGINE_ERROR ",issue)
	print("COLLISION_DISPATCH_OVERLAP passed=",passed," failures=",failed)
	quit(0 if failed==0 else 1)
