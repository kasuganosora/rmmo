extends "res://tools/test_collision_dependency_loader.gd"
## GPU setup publishes two real native products, without collision geometry
## sidecars. Source-less CPU consumers preserve every scheduling/owner contract.
const Deferred=preload("res://scripts/world3d/deferred_asset_loader.gd")
const NonePreparation=preload("res://scripts/world3d/collision_not_required_preparation.gd")
const NativeFixture=preload("res://tools/collision_native_fixture.gd")
const Policy=preload("res://scripts/world3d/runtime_package_policy.gd")
var previous_policy:=false
var previous_root:=""
var publication:Dictionary={}
var replacement:Dictionary={}
var previous_none:=false
var previous_collision_first:=false

class ResultGateLoader extends "res://scripts/world3d/collision_dependency_loader.gd":
	var release_gate:=Semaphore.new()
	var produced:=Semaphore.new()
	var launches:=0
	static func late_result(task:Callable,done:Semaphore,gate:Semaphore)->Dictionary:
		var result:Dictionary=task.call()
		done.post();gate.wait()
		return result
	func _start_worker(thread:Thread,task:Callable)->int:
		launches+=1
		# First plan completes normally; hold the actual prepared proof packet.
		return thread.start(late_result.bind(task,produced,release_gate)) if launches==2 else super._start_worker(thread,task)

func no_physics(service:Node,map:Node)->bool:
	var snapshot:Dictionary=service.snapshot().store
	return snapshot.get("instances",0)==0 and snapshot.get("owned_bodies",0)==0 and snapshot.get("shape_count",0)==0 and snapshot.get("reserved_bytes",0)==0 and physics_nodes(map)==0

func physics_nodes(node:Node)->int:
	var count:=1 if node is CollisionObject3D or node is CollisionShape3D else 0
	for child:Node in node.get_children():count+=physics_nodes(child)
	return count

func dump_if_unready(service:Node,entries:Array,label:String)->void:
	if not service.coverage(entries).ok:
		print("STATE ",label," ",JSON.stringify({"coverage":service.coverage(entries),"profile":service.snapshot()}))

func run()->void:
	previous_policy=Policy.verify_packages;Policy.verify_packages=true
	var manager:=root.get_node("AssetManager");previous_root=manager.content_root_override
	previous_none=Loader.no_collision_proof_enabled
	previous_collision_first=Deferred.collision_first_enabled
	var errors:=Errors.new();OS.add_logger(errors)
	create_timer(45).timeout.connect(func():
		for gate:Semaphore in cleanup_gates:gate.post();gate.post()
		push_error("collision none loader CPU timeout");quit(2)
	)
	check(not previous_none,"no-collision proof remains opt-in by default")
	Loader.no_collision_proof_enabled=true
	folder=Paths.external_root().path_join("review_artifacts/collision_none_loader_test_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	DirAccess.make_dir_recursive_absolute(folder);manager.content_root_override=folder
	var model:=folder.path_join("fixture.glb");fixture(model)
	var original:=FileAccess.get_file_as_bytes(model)
	publication=NativeFixture.publish(model,folder)
	check(publication.get("ok",false) and publication.get("model",{}).get("native_candidate",{}).get("collision_none_safe",false),"GPU setup publishes an actual native absence contract")
	if not publication.get("ok",false):print(publication);finish(errors);return
	fixture(model,4);replacement=NativeFixture.publish(model,folder)
	check(replacement.get("ok",false) and replacement.get("payload_sha")!=publication.payload_sha,"late failure uses an actual distinct native publication")
	if not replacement.get("ok",false):print(replacement);finish(errors);return
	check(NativeFixture.install(publication),"restore the original complete publication before runtime")
	put(model,original);check(DirAccess.rename_absolute(model,model+".held")==OK,"remove authoring GLB before all scheduler consumers")
	check(Cache.candidate(model,folder).is_empty(),"native model deliberately has no collision geometry sidecar")
	var helper:=MapFixture.new();helper.folder=folder;helper.content_root=folder
	var records:Array=[]
	# The last 129 ordinary none records also exercise the real 8 MiB cap.
	for i in 133:
		records.append({"uuid":"item"+str(i),"kind":"asset","asset_path":model,"position":[i*10,0,0],"rotation":[0,0,0],"size":[1,1,1],"collision":"walk" if i in [1,3] else "none"})
	var author:=helper.fixture("map",records)
	check(not author.is_empty() and NativeFixture.index_build(author.path,folder,records).ok,"real rmres records produce the ownership directory")
	var issued:=NativeFixture.index_read(author.path,folder)
	check(issued.ok,"real directory reader issues the source-bound ownership proof")
	if not issued.ok:helper.free();finish(errors);return
	await mixed_and_shared(issued,author.path)
	await late_cancel(issued,author.path,0)
	await late_cancel(issued,author.path,2)
	await late_cancel(issued,author.path,-1)
	await late_failure(issued,author.path)
	await prefetch_none(issued,author.path)
	await failure_cases(issued,author.path)
	await capacity_case(issued,author.path)
	await deferred_case(issued,author.path)
	helper.free()
	await process_frame;await process_frame
	finish(errors)

func mixed_and_shared(issued:Dictionary,path:String)->void:
	var service:=Loader.new();var map:=attach(service,issued,path)
	var mixed:Array=[entry(issued.index,0),entry(issued.index,1)]
	check(service.request(mixed,0,"mixed").accepted.size()==2 and not service.coverage(mixed).ok,"same-source mixed records begin pending in one shared transaction")
	Trace.start();await wait_terminal(service,mixed);var trace:=Trace.stop()
	var stats:Dictionary=service.snapshot()
	check(stats.plan_jobs==1 and stats.prepare_jobs==1,"none and walk share exactly one plan and one preparation job")
	check(service.status("item0").state=="not_required" and service.status("item0").ok,"explicit none obtains only the typed collision-not-required capability")
	check(service.status("item1").state=="fallback" and not service.status("item1").ok and not service.coverage(mixed).ok,"same-source walk never inherits its sibling's no-collision receipt")
	check(stats.get("none_source_sha_calls",0)==0 and stats.get("none_native_identity_reads",0)==2 and stats.get("none_map_sha_calls",0)==2,"one batch shares native before/after identity and map checks with zero GLB hashes")
	check(no_physics(service,map) and stats.accepted==0 and stats.none_proof_bytes==NonePreparation.RECEIPT_BYTES,"none proof owns bounded metadata and no Store instance, collider, shape or geometry batch")
	check(count_label(trace,"deferred.model_parse")==0 and count_label(trace,"deferred.scene_generate")==0 and count_label(trace,"deferred.cpu_capture")==0,"metadata proof never invokes the render importer or image/geometry capture")
	check(stats.negative_candidate_sources==1,"actual absent sidecar records an attempt-local source miss")
	var later:Array=[entry(issued.index,2),entry(issued.index,3)]
	service.request(later,0,"later");await wait_terminal(service,later)
	check(service.profile.plan_jobs==2 and service.profile.prepare_jobs==2 and service.status("item2").ok and service.status("item3").state=="fallback","cached sidecar absence still validates each new UUID and preserves mixed collision semantics")
	check(service.snapshot().none_proof_bytes==2*NonePreparation.RECEIPT_BYTES and no_physics(service,map),"later same-source receipts retain their own charge without fake geometry")
	service.request([mixed[0]],0,"camera")
	service.release_request("mixed")
	check(service.status("item0").ok and service.status("item1").state=="unrequested" and service.snapshot().none_proof_bytes==2*NonePreparation.RECEIPT_BYTES,"withdrawing one shared UUID consumer retains the other consumer and receipt")
	service.release_request("camera")
	check(service.status("item0").state=="unrequested" and service.snapshot().none_proof_bytes==NonePreparation.RECEIPT_BYTES,"last consumer releases exactly its receipt charge")
	service.release_request("later")
	check(service.snapshot().none_proof_bytes==0 and service._planning.reserved_bytes==0 and service._preparing.reserved_bytes==0,"all mixed tickets release proof metadata and both worker ledgers")
	map.free()

func late_cancel(issued:Dictionary,path:String,removed_index:int)->void:
	var service:=ResultGateLoader.new();cleanup_gates.append(service.release_gate)
	var map:=attach(service,issued,path)
	var pair:Array=[entry(issued.index,0),entry(issued.index,2)]
	service.request(pair,0,"moving")
	var produced:=false
	for i in 600:
		await process_frame
		if service.produced.try_wait():produced=true;break
	var remove_all:=removed_index<0
	var removed:="item2" if remove_all else "item"+str(removed_index)
	var kept:="item2" if removed_index==0 else "item0"
	var survivor:Dictionary=pair[1] if removed_index==0 else pair[0]
	var old_job:String=service._states.get(kept,{}).get("job_id","")
	var retained:int=service._preparing.reserved_bytes
	check(produced and retained>0,"real prepared batch is held in flight before "+removed+" withdrawal")
	if remove_all:
		service.release_request("moving")
		service.request([survivor],0,"new_click")
	else:service.request([survivor],0,"moving")
	var new_job:String=service._states.get(kept,{}).get("job_id","")
	if remove_all:
		check(not old_job.is_empty() and old_job!=new_job and service.status(removed).state=="unrequested","withdrawing every consumer invalidates the old generation before a new click requeues its UUID")
	else:
		check(not old_job.is_empty() and old_job==new_job and service.status(removed).state=="unrequested","withdrawing batch "+("leader" if removed_index==0 else "nonleader")+" retains shared work while removing only its capability consumer")
	check(service._preparing.reserved_bytes>=retained and not service.status(kept).ok,"cancel does not release the old worker's actual proof packet or grant early readiness")
	service.release_gate.post()
	await wait_terminal(service,[survivor]);await wait_drained(service._planning,service._preparing)
	dump_if_unready(service,[survivor],"late_cancel")
	check(service.status(kept).ok and service.status(removed).state=="unrequested" and service.profile.get("none_accepted",0)==1,"late prepared batch cannot resurrect a withdrawn UUID or publish into a different generation")
	if not remove_all:check(service.profile.plan_jobs==1 and service.profile.prepare_jobs==1,"partial withdrawal does not repeat completed native identity work for the survivor")
	check(service._planning.reserved_bytes==0 and service._preparing.reserved_bytes==0 and service.snapshot().none_proof_bytes==NonePreparation.RECEIPT_BYTES,"only the survivor retains its independent receipt after both generations drain")
	check(no_physics(service,map),"late cancellation never creates bodies or shapes")
	map.free()

func late_failure(issued:Dictionary,path:String)->void:
	var service:=ResultGateLoader.new();cleanup_gates.append(service.release_gate)
	var map:=attach(service,issued,path)
	var pair:Array=[entry(issued.index,0),entry(issued.index,2)]
	service.request(pair,0,"moving");service.set_process(false)
	var old_job:String=service._states.item0.job_id
	for i in 600:
		service._poll()
		if service._work.get(old_job,{}).get("stage","")=="planned":break
		if service._work.get(old_job,{}).get("stage","")=="queued":service._launch(old_job,"plan")
		await process_frame
	check(service._work.get(old_job,{}).get("stage","")=="planned","late-failure fixture completes actual planning before its native publication is changed")
	check(NativeFixture.install(replacement),"replace the frozen job's real native publication")
	service._launch(old_job,"prepare")
	var produced:=false
	for i in 600:
		await process_frame
		if service.produced.try_wait():produced=true;break
	check(NativeFixture.install(publication),"restore original native publication before a new generation plans")
	check(produced and service._preparing.reserved_bytes>0,"actual changed-native preparation returns late while holding its worker lease")
	service.request([pair[1]],0,"moving")
	service.request([pair[0]],-5,"new_click")
	check(service._states.item0.job_id!=old_job and service._states.item2.job_id==old_job,"re-added UUID owns a new generation while its old sibling retains the failed batch")
	service.request([pair[0]],-7,"new_click")
	check(service._work[old_job].priority==0 and service._work[service._states.item0.job_id].priority==-7,"re-added UUID priority updates only its current job and cannot promote the old shared batch")
	await wait_terminal(service,[pair[0]])
	check(service.status("item0").ok and service.snapshot().none_proof_bytes==NonePreparation.RECEIPT_BYTES,"restored native publication gives the new generation its real receipt before the old error arrives")
	service.release_gate.post()
	await wait_terminal(service,pair);await wait_drained(service._planning,service._preparing)
	check(service.status("item0").ok and service.status("item2").state=="fallback" and service.profile.fallbacks==1,"late failure only affects matching old job IDs and cannot overwrite the new ready receipt")
	check(service.snapshot().none_proof_bytes==NonePreparation.RECEIPT_BYTES and service._planning.reserved_bytes==0 and service._preparing.reserved_bytes==0 and no_physics(service,map),"late failure preserves exact retained accounting and publishes no geometry")
	map.free()

func prefetch_none(issued:Dictionary,path:String)->void:
	var owner:=Node.new();root.add_child(owner)
	var service:=Loader.new();owner.add_child(service)
	check(service.begin_prefetch(owner,issued.index,path,folder,issued.proof).ok,"none proof can prepare under the real map-loader CPU owner")
	var entries:Array=[entry(issued.index,0),entry(issued.index,2)]
	service.request(entries,-3,"entry_safety")
	for i in 600:
		service.pump_prefetch()
		if service.snapshot().ready_count==1:break
		await process_frame
	var snapshot:Dictionary=service.snapshot()
	check(snapshot.ready_count==1 and snapshot.plan_jobs==1 and snapshot.prepare_jobs==1,"two same-source none records finish one CPU-only prefetched batch")
	check(not service.coverage(entries).ok and snapshot.none_proof_bytes==0 and snapshot.preparing.reserved_bytes>0,"completed prefetch is not adopted readiness and retains full packet accounting")
	check(snapshot.store.is_empty() and owner.get_child_count()==1 and physics_nodes(owner)==0,"prefetch creates no Store, collider or physics shape")
	var map:=Node3D.new();map.set_meta("source_map_sha256",issued.index.source_sha256)
	check(service.handoff(map,11).ok and not service.adopt(map,11).ok,"off-tree handoff cannot publish no-collision capabilities")
	owner.free();await process_frame
	root.add_child(map)
	check(not service.adopt(map,12).ok and service.adopt(map,11).ok,"live adoption requires the handoff epoch")
	await wait_terminal(service,entries)
	check(service.coverage(entries).ok and service.profile.plan_jobs==1 and service.profile.prepare_jobs==1,"same prefetched proof packet becomes usable only after live adoption without redispatch")
	check(no_physics(service,map) and service.snapshot().none_proof_bytes==2*NonePreparation.RECEIPT_BYTES,"adopted none still publishes no empty Store instance or fake physics body")
	map.free()

func failure_cases(issued:Dictionary,path:String)->void:
	var entries:Array=[entry(issued.index,0)]
	for stage:String in ["plan","prepare"]:
		var service:=Loader.new();var map:=attach(service,issued,path)
		if stage=="plan":service._planning.byte_limit=1
		else:service._preparing.byte_limit=1
		service.request(entries,0,"tiny");await wait_terminal(service,entries)
		check(service.status("item0").reason=="preparation_capacity" and not service.coverage(entries).ok and service.profile.prepare_jobs==0,"tiny "+stage+" budget falls back before unadmitted allocation")
		check(service._planning.reserved_bytes==0 and service._preparing.reserved_bytes==0 and service.snapshot().none_proof_bytes==0 and no_physics(service,map),"tiny "+stage+" budget leaves no worker or proof charge")
		map.free()
	var failed_service:=FailedLoader.new();var map:=attach(failed_service,issued,path)
	failed_service.request(entries,0,"failed");await wait_terminal(failed_service,entries)
	check(failed_service.status("item0").reason=="thread_start" and failed_service._planning.reserved_bytes==0 and failed_service._preparing.reserved_bytes==0 and no_physics(failed_service,map),"thread-start failure releases both stage reservations without a receipt")
	map.free()
	var gated:=GateLoader.new();cleanup_gates.append(gated.gate);map=attach(gated,issued,path)
	gated.request(entries,0,"cancel")
	for i in 90:
		await process_frame
		if gated.starts==1:break
	var planning:RefCounted=gated._planning;var preparing:RefCounted=gated._preparing
	var before:int=planning.reserved_bytes
	gated.cancel("fixture_cancel")
	check(gated.starts==1 and before>0 and planning.reserved_bytes==before and not gated.coverage(entries).ok,"explicit cancellation retains the real active worker lease and refuses readiness")
	gated.open();await wait_drained(planning,preparing)
	check(planning.reserved_bytes==0 and preparing.reserved_bytes==0 and gated.snapshot().none_proof_bytes==0 and no_physics(gated,map),"cancelled worker drains before all accounting returns to zero")
	map.free()

func capacity_case(issued:Dictionary,path:String)->void:
	var service:=Loader.new();var map:=attach(service,issued,path);var entries:Array=[]
	for i in range(4,133):entries.append(entry(issued.index,i))
	service.request(entries,0,"capacity");await wait_terminal(service,entries)
	var coverage:Dictionary=service.coverage(entries);var snapshot:Dictionary=service.snapshot()
	check(coverage.ready.size()==128 and coverage.fallback.size()==1 and coverage.pending.is_empty(),"129 real receipts hit the 8 MiB bound with exactly one explicit fallback")
	check(snapshot.none_proof_bytes==Loader.MAX_NONE_PROOF_BYTES and snapshot.fallback_reasons.get("none_proof_capacity",0)==1,"proof capacity rejects the extra receipt without an uncharged exception")
	check(snapshot.plan_jobs==5 and snapshot.prepare_jobs==5 and snapshot.max_pending<=Loader.MAX_PENDING and snapshot.peak_workers<=Loader.MAX_WORKERS,"five bounded batches obey shared worker and queue limits")
	check(snapshot.planning.reserved_bytes==0 and snapshot.preparing.reserved_bytes==0 and no_physics(service,map),"capacity rejection releases completed workers and never creates geometry")
	service.cancel("capacity_cleanup")
	check(service.snapshot().none_proof_bytes==0,"cancelling accepted receipts releases the entire retained metadata cap")
	map.free()

func deferred_case(issued:Dictionary,path:String)->void:
	Deferred.collision_first_enabled=true
	var service:=Loader.new();var map:=attach(service,issued,path)
	map.set_meta("extras",{"rmmo_records":[]})
	var queue:=Deferred.new();var rows:Array=[]
	for i in 2:
		var value:=entry(issued.index,i)
		rows.append({"record":value.compact_record,"path":value.asset_path,"bounds":value.bounds,"reference_entry":value,"native_reference":false,"group_id":value.group_id})
	queue.pending=rows;queue.configure_references(issued.index,path,folder,issued.proof)
	map.add_child(queue);queue.activate(map);queue._active=false;queue.set_process(false)
	var clip:AABB=rows[0].bounds.grow(.1)
	check(not queue.ensure_collision(clip,"none_fixture") and not queue.geometry_published(clip),"actual Deferred begins with both collision and visual geometry pending")
	for i in 600:
		await process_frame
		if queue.ensure_collision(clip,"none_fixture"):break
	check(queue.ensure_collision(clip,"none_fixture") and not queue.geometry_published(clip),"verified none satisfies exact collision coverage while the full visual gate remains closed")
	var mixed_clip:AABB=clip.merge(rows[1].bounds.grow(.1))
	queue.ensure_collision(mixed_clip,"mixed_fixture")
	await wait_terminal(service,[entry(issued.index,0),entry(issued.index,1)])
	check(not queue.ensure_collision(mixed_clip,"mixed_fixture") and not queue.geometry_published(mixed_clip) and service.status("item1").state=="fallback","unpublished walk in the same-source clip still requires the ordinary geometry path")
	check(no_physics(service,map) and not rows[0].get("published",false) and not rows[1].get("published",false),"no-collision capability cannot mark pending visuals published or fabricate support")
	var planning:RefCounted=service._planning;var preparing:RefCounted=service._preparing
	map.free();await wait_drained(planning,preparing)
	Deferred.collision_first_enabled=previous_collision_first

func finish(errors:Logger)->void:
	root.get_node("AssetManager").content_root_override=previous_root;Policy.verify_packages=previous_policy
	Loader.no_collision_proof_enabled=previous_none
	Deferred.collision_first_enabled=previous_collision_first
	remove_fixture(folder);OS.remove_logger(errors)
	check(errors.errors.is_empty(),"zero unexpected engine or script errors")
	for issue:String in errors.errors:print("ENGINE_ERROR ",issue)
	print("COLLISION_NONE_LOADER passed=",passed," failures=",failed)
	quit(0 if failed==0 else 1)
