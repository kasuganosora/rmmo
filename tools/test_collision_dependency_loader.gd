extends "res://tools/test_collision_asset_descriptor.gd"
const Loader=preload("res://scripts/world3d/collision_dependency_loader.gd")
const Index=preload("res://scripts/world3d/map_dependency_index.gd")
const MapFixture=preload("res://tools/test_map_dependency_index.gd")
var cleanup_gates:Array=[]
var previous_dispatch_first:=false
class GateLoader extends "res://scripts/world3d/collision_dependency_loader.gd":
	var gate:=Semaphore.new()
	var starts:=0
	var hold:=true
	static func gated(task:Callable,semaphore:Semaphore)->Dictionary:
		semaphore.wait();return task.call()
	func _start_worker(thread:Thread,task:Callable)->int:
		if not hold:return super._start_worker(thread,task)
		var code:=thread.start(gated.bind(task,gate))
		if code==OK:starts+=1
		return code
	func open()->void:
		hold=false
		for i in starts:gate.post()
		starts=0
class FailedLoader extends "res://scripts/world3d/collision_dependency_loader.gd":
	func _start_worker(_thread:Thread,_task:Callable)->int:return ERR_CANT_CREATE

func entry(index:Dictionary,at:int)->Dictionary:
	var row:Dictionary=index.rows[at]
	return {"record_index":at,"compact_record":index.extras.rmmo_records[at],"bounds":row.bounds,"group_id":row.group_id,"asset_path":row.asset_path}
func attach(service:Node,issued:Dictionary,path:String)->Node3D:
	var map:=Node3D.new();root.add_child(map);map.add_child(service)
	check(service.configure(issued.index,path,folder,issued.proof,map,7).ok,"map owns configured collision loader and residency")
	return map
func wait_terminal(service:Node,entries:Array)->void:
	for i in 900:
		await process_frame
		var status:Dictionary=service.coverage(entries)
		if status.ok or (status.pending.is_empty() and not status.fallback.is_empty()):return
func wait_drained(planning:RefCounted,preparing:RefCounted)->void:
	for i in 300:
		await process_frame
		if planning.count()==0 and preparing.count()==0:return

func run()->void:
	previous_dispatch_first=Loader.dispatch_before_installation
	if "--dispatch-first" in OS.get_cmdline_user_args():Loader.dispatch_before_installation=true
	create_timer(45).timeout.connect(func():
		for gate:Semaphore in cleanup_gates:gate.post();gate.post()
		push_error("collision loader CPU timeout");quit(2)
	)
	var errors:=Errors.new();OS.add_logger(errors)
	folder=Paths.cache_directory("collision_loader_test_%d"%Time.get_ticks_usec());DirAccess.make_dir_recursive_absolute(folder)
	var model:=folder.path_join("fixture.glb");fixture(model)
	var built:=await worker(Builder.build.bind(model,folder,Builder.estimate(model,folder).estimated_bytes))
	check(built.ok and verify_png(built.private_preparation),"real source producer supplies PNG-bearing collision asset")
	if not built.ok:Drainer.dispose_result(built);finish(errors);return
	Drainer.dispose_result(built)
	var missing:=folder.path_join("missing.glb");put(missing,FileAccess.get_file_as_bytes(model))
	var other_missing:=folder.path_join("other_missing.glb");put(other_missing,FileAccess.get_file_as_bytes(model))
	var helper:=MapFixture.new();helper.folder=folder;helper.content_root=folder
	var records:Array=[]
	for i in 6:records.append({"uuid":"item"+str(i),"kind":"asset","asset_path":model,"position":[i*10,0,0],"rotation":[0,0,0],"size":[1,1,1],"collision":"block"})
	records.append({"uuid":"missing","kind":"asset","asset_path":missing,"position":[100,0,0],"rotation":[0,0,0],"size":[1,1,1],"collision":"block"})
	records.append(helper.box("native",200))
	records.append({"uuid":"missing_again","kind":"asset","asset_path":missing,"position":[120,0,0],"rotation":[0,0,0],"size":[1,1,1],"collision":"block"})
	records.append({"uuid":"other_missing","kind":"asset","asset_path":other_missing,"position":[140,0,0],"rotation":[0,0,0],"size":[1,1,1],"collision":"block"})
	var map_file:=helper.fixture("map",records);check(Index.build(map_file.path,folder,records).ok,"real map directory includes multiple static references and fallback entries")
	var issued:=Index.read_for_loading(map_file.path,folder);check(issued.ok,"scheduler receives actual reader proof")
	if not issued.ok:helper.free();finish(errors);return
	var first:Array=[entry(issued.index,0),entry(issued.index,1)]
	var service:=Loader.new();var map:=attach(service,issued,map_file.path)
	check(not service.instance_readiness("item0").ok and service.instance_readiness("item0").state=="unrequested","unrequested empty store is never a collision-ready instance")
	var requested:=service.request(first,0,"player")
	check(requested.ok and requested.accepted.size()==2 and not service.coverage(first).ok,"request only queues work; admission is not readiness")
	var reconciliations:int=service.profile.request_reconciliations
	for i in 20:service.request(first,0,"player")
	check(service.profile.request_reconciliations==reconciliations,"identical physics-tick tickets do not repeat reconciliation or sorting")
	Trace.start();await wait_terminal(service,first);var trace:=Trace.stop()
	check(service.coverage(first).ok and service.instance_readiness("item0").state=="ready","real plan/prepare/store shapes become ready after physics synchronization")
	var stats:Dictionary=service.snapshot()
	check(stats.plan_jobs==2 and stats.prepare_jobs==2 and stats.peak_workers<=2 and stats.max_pending<=4,"two-stage work obeys both worker and total pending limits")
	check(stats.planning.reserved_bytes==0 and stats.preparing.reserved_bytes==0 and stats.store.reserved_bytes>0,"consumption transfers charge to bounded residency without releasing its owners")
	check(count_label(trace,"deferred.model_parse")==0 and count_label(trace,"deferred.scene_generate")==0,"runtime scheduler never imports render resources or decodes textures")
	var forged:=first.duplicate(true);forged[0].compact_record.position[0]=99
	check(not service.coverage(forged).ok and not service.request(forged,0,"forged").ok,"coverage and requests require exact author entry identity")
	service.request([first[0]],0,"camera");service.release_request("player")
	check(service.instance_readiness("item0").ok and service.instance_readiness("item1").state=="unrequested","one consumer withdrawal retains another consumer and discards only unneeded instance")
	var holder:=Node3D.new();root.add_child(holder);map.reparent(holder);await physics_frame;await process_frame
	check(service.instance_readiness("item0").ok,"synchronous map reparent preserves live collision dependency ownership")
	service.release_request("camera");await process_frame
	check(service.snapshot().store.reserved_bytes==0,"last consumer withdrawal releases store payload and shape charges")
	var fallbacks:Array=[entry(issued.index,6),entry(issued.index,7)]
	service.request(fallbacks,0,"fallbacks");await wait_terminal(service,fallbacks)
	check(service.coverage(fallbacks).fallback.size()==2 and not service.coverage(fallbacks).ok and service.error.is_empty(),"missing sidecar and native unsupported record explicitly return ordinary-render fallback")
	check(service.snapshot().fallback_reasons.get("collision_asset_missing",0)==1 and service.snapshot().fallback_reasons.get("unsupported_record",0)==1,"fallback profile distinguishes absent cache from unsupported author records")
	map.free();holder.free()
	# A ready but unconsumed CPU packet keeps its full preparation lease.
	service=Loader.new();map=attach(service,issued,map_file.path);service.request([first[0]],0,"hold");service.set_process(false)
	for i in 600:
		service._poll()
		if service._work.get("item0",{}).get("stage","")=="ready":break
		if service._work.has("item0"):
			var stage:String=service._work.item0.stage
			if stage=="queued":service._launch("item0","plan")
			elif stage=="planned":service._launch("item0","prepare")
		await process_frame
	check(service._work.get("item0",{}).get("stage","")=="ready" and service._preparing.reserved_bytes>0 and service._preparing.active_workers()==0,"joined unconsumed result is parked with all bytes still reserved")
	service.release_request("hold")
	check(service._preparing.reserved_bytes==0 and service._planning.reserved_bytes==0,"withdrawal clears completed packet before releasing both stage leases")
	map.free()
	# Admission order is request order within priority, so an exact foot record
	# can precede lower record-index camera neighbors in the same ticket.
	service=Loader.new();map=attach(service,issued,map_file.path)
	var ordered:Array=[entry(issued.index,5),entry(issued.index,0)]
	service.request(ordered,0,"ordered");service.set_process(false)
	check(service._work.item5.order<service._work.item0.order,"same-priority request preserves exact-foot-first order")
	ordered[0].record_index=999
	check(service._work.item5.entry.record_index==5,"worker entry snapshots cannot be mutated through caller request dictionaries")
	map.free()
	# Stable descriptor with a replaced author GLB must become fallback, never
	# collision-ready; the caller's ordinary import remains its validation path.
	var author:=FileAccess.get_file_as_bytes(model);var changed:=author.duplicate();var json_length:int=changed.decode_u32(12);changed.encode_float(28+json_length+12,2.0);put(model,changed)
	service=Loader.new();map=attach(service,issued,map_file.path);service.request([first[0]],0,"changed");await wait_terminal(service,[first[0]])
	check(service.status("item0").state=="fallback" and not service.coverage([first[0]]).ok and service.snapshot().store.instances==0,"source SHA mismatch falls back without any physics readiness or body publication")
	map.free();put(model,author)
	# Plan memory and prepare memory are independent; oversized work falls back
	# instead of an exclusive exception or a parked-plan readmission deadlock.
	service=Loader.new();map=attach(service,issued,map_file.path);service._preparing.byte_limit=1;service.request([first[0]],0,"tiny")
	await wait_terminal(service,[first[0]])
	check(service.status("item0").state=="fallback" and service.profile.prepare_jobs==0 and service._planning.reserved_bytes==0,"insufficient preparation budget rejects before worker allocation and releases plan charge")
	map.free()
	var failed_service:=FailedLoader.new();map=attach(failed_service,issued,map_file.path);failed_service.request([first[0]],0,"failed")
	await wait_terminal(failed_service,[first[0]])
	check(failed_service.status("item0").reason=="thread_start" and failed_service.snapshot().planning.reserved_bytes==0,"thread-start failure leaves no thread or reservation")
	map.free()
	# Two blocked real plan workers plus queued siblings, then a foreground
	# request. No test thread holds a renderer or a production worker-pool slot.
	var gated:=GateLoader.new();cleanup_gates.append(gated.gate);map=attach(gated,issued,map_file.path)
	var four:Array=[]
	for i in 4:four.append(entry(issued.index,i))
	gated.request(four,10,"distant")
	for i in 90:
		await process_frame
		if gated.starts==2:break
	check(gated.starts==2 and gated.snapshot().pending==4,"two asynchronous workers and two queued records fill the explicit bound")
	var fifth:Array=[entry(issued.index,4)];gated.request(fifth,-2,"critical")
	check(gated.snapshot().pending<=4 and gated.snapshot().planning.active_workers<=2,"foreground replacement does not discount cancelled in-flight work")
	gated.release_request("distant");gated.open();await wait_terminal(gated,fifth)
	check(gated.coverage(fifth).ok and gated.profile.max_pending<=4,"critical request advances once cancelled workers drain without unbounded backlog")
	map.free()
	gated=GateLoader.new();cleanup_gates.append(gated.gate);map=attach(gated,issued,map_file.path);gated.request(first,0,"exit")
	for i in 90:
		await process_frame
		if gated.starts==2:break
	var planning:RefCounted=gated._planning;var preparing:RefCounted=gated._preparing;var gate:Semaphore=gated.gate;var started:int=gated.starts
	var before:int=planning.reserved_bytes;map.free()
	check(before>0 and planning.reserved_bytes==before,"map destruction never live-joins or releases running worker charge")
	for i in started:gate.post()
	await wait_drained(planning,preparing)
	check(planning.reserved_bytes==0 and preparing.reserved_bytes==0,"tree drainer joins detached workers and releases retained ledgers")
	await prefetch_cases(issued,map_file.path,first)
	await negative_candidate_cases(issued,map_file.path,missing)
	helper.free();finish(errors)

func negative_candidate_cases(issued:Dictionary,path:String,missing:String)->void:
	var service:=Loader.new();var map:=attach(service,issued,path)
	var absent:Array=[entry(issued.index,6)]
	service.request(absent,0,"absent");await wait_terminal(service,absent)
	var count:int=service.profile.plan_jobs
	check(count==1 and service.snapshot().negative_candidate_sources==1 and not service.coverage(absent).ok,"only an actual missing candidate plan seeds an attempt-local negative")
	var sibling:Array=[entry(issued.index,8)]
	service.request(sibling,0,"sibling");await process_frame
	check(service.profile.plan_jobs==count and service.snapshot().negative_candidate_hits==1 and service.coverage(sibling).fallback==["missing_again"],"same-source later record falls back without another plan thread or readiness")
	service.release_request("sibling");service.request(sibling,0,"sibling")
	check(service.profile.plan_jobs==count and service.snapshot().negative_candidate_sources==1,"ticket withdrawal and retry do not multiply source-negative entries within one attempt")
	var different:Array=[entry(issued.index,9)]
	service.request(different,0,"different");await wait_terminal(service,different)
	check(service.profile.plan_jobs==count+1 and service.snapshot().negative_candidate_sources==2,"a different source receives its own actual probe and negative identity")
	var supported:Array=[entry(issued.index,0)]
	service.request(supported,0,"supported");await wait_terminal(service,supported)
	check(service.coverage(supported).ok and service.profile.prepare_jobs==1,"missing-source negatives do not contaminate valid collision products")
	# Repairing the sidecar does not make this attempt's previous miss authoritative
	# or ready; ordinary render remains its fallback until a new map load attempt.
	var repaired:=await worker(Builder.build.bind(missing,folder,Builder.estimate(missing,folder).estimated_bytes))
	check(repaired.ok,"real offline producer repairs previously missing derived sidecar")
	Drainer.dispose_result(repaired)
	service.release_request("absent");service.request(absent,0,"absent")
	check(service.profile.plan_jobs==count+2 and not service.coverage(absent).ok and service.coverage(absent).fallback==["missing"],"current attempt preserves fallback after repair without pretending old absence grants readiness")
	map.free()
	service=Loader.new();map=attach(service,issued,path)
	service.request(absent,0,"new_attempt");await wait_terminal(service,absent)
	check(service.coverage(absent).ok and service.profile.plan_jobs==1 and service.snapshot().negative_candidate_sources==0,"new loader attempt retries and accepts a repaired sidecar")
	map.free()
	# Payload/source failures are not candidate absence and cannot poison siblings.
	var author:=FileAccess.get_file_as_bytes(missing);var changed:=author.duplicate();var json_length:int=changed.decode_u32(12);changed.encode_float(28+json_length+12,2.0);put(missing,changed)
	service=Loader.new();map=attach(service,issued,path);service.request(absent,0,"source_changed");await wait_terminal(service,absent)
	check(service.status("missing").state=="fallback" and service.snapshot().negative_candidate_sources==0,"prepare source mismatch is never stored as a negative candidate")
	service.request(sibling,0,"retry_sibling");await wait_terminal(service,sibling)
	check(service.profile.plan_jobs==2 and service.snapshot().negative_candidate_sources==0,"source-error sibling executes its own validation rather than reusing an instance failure")
	map.free();put(missing,author)

func prefetch_cases(issued:Dictionary,path:String,entries:Array)->void:
	var owner:=Node.new();root.add_child(owner)
	var service:=Loader.new();owner.add_child(service)
	check(service.begin_prefetch(owner,issued.index,path,folder,issued.proof).ok,"live loader owner starts CPU-only preparation without a map")
	check(service.matches_context(issued.index,path,folder,issued.proof) and not service.matches_context(issued.index,path+".other",folder,issued.proof) and not service.matches_context(issued.index.duplicate(),path,folder,issued.proof),"prefetch handoff context binds exact sealed index, proof, root and source path")
	service.request(entries,-3,"entry_safety")
	for i in 600:
		service.pump_prefetch()
		if service.snapshot().ready_count==entries.size():break
		await process_frame
	var snapshot:Dictionary=service.snapshot()
	check(snapshot.ready_count==2 and snapshot.prepare_jobs==2 and snapshot.prefetch_ready_count==2,"same bounded queue completes real CPU batches before map adoption")
	check(snapshot.store.is_empty() and snapshot.accepted==0 and owner.get_child_count()==1 and not service.is_processing(),"prefetch creates no residency, nodes or physics shapes and is caller-pumped")
	check(not service.coverage(entries).ok and snapshot.preparing.reserved_bytes>0 and snapshot.preparing.active_workers==0,"CPU-ready output grants no physics readiness and retains completed byte charge")
	var plans:int=service.profile.plan_jobs;var prepares:int=service.profile.prepare_jobs
	for i in 20:service.pump_prefetch()
	check(service.profile.plan_jobs==plans and service.profile.prepare_jobs==prepares,"repeated pump cannot dispatch or duplicate completed work")
	var rejected:=Node3D.new();rejected.set_meta("source_map_sha256","0".repeat(64))
	check(not service.handoff(rejected,11).ok and service.get_parent()==owner and not service._cancelled,"wrong map revision cannot steal or cancel the legitimate prefetch owner")
	rejected.free()
	var map:=Node3D.new();map.set_meta("source_map_sha256",issued.index.source_sha256)
	check(service.handoff(map,11).ok and service.get_parent()==map and not map.is_inside_tree(),"explicit handoff transfers the same queue into an off-tree result map")
	var retained:int=service._preparing.reserved_bytes
	owner.free()
	for i in 3:await process_frame
	check(is_instance_valid(service) and not service._cancelled and service.snapshot().ready_count==2 and service._preparing.reserved_bytes==retained and map.get_child_count()==1,"off-tree handoff survives deferred disposal and old loader destruction without creating a Store")
	check(not service.adopt(map,11).ok and service.snapshot().store.is_empty(),"off-tree adoption cannot publish CPU results or build shapes")
	root.add_child(map)
	check(not service.adopt(map,12).ok and service.adopt(map,11).ok and service.adopt(map,11).ok,"live adoption preserves epoch and is idempotent for the same map")
	check(map.get_node_or_null("CollisionInstanceResidency")!=null and service._tickets.has("entry_safety"),"adoption creates one residency and inherits the entry-safety request")
	await wait_terminal(service,entries)
	check(service.coverage(entries).ok and service.profile.plan_jobs==plans and service.profile.prepare_jobs==prepares,"adopted CPU batches install and become physics-ready without re-dispatch")
	check(service.profile.prefetch_first_dispatch_us<service.profile.handoff_us and service.profile.prefetch_ready_at_adopt==2 and service.profile.handoff_us<service.profile.adopted_us,"profile identifies dispatch and ready work before map adoption")
	map.free()
	# Completed packets are reclaimed if an off-tree result is never adopted.
	owner=Node.new();root.add_child(owner);service=Loader.new();owner.add_child(service)
	service.begin_prefetch(owner,issued.index,path,folder,issued.proof);service.request([entries[0]],-3,"entry_safety")
	for i in 600:
		service.pump_prefetch()
		if service.snapshot().ready_count==1:break
		await process_frame
	var planning:RefCounted=service._planning;var preparing:RefCounted=service._preparing
	map=Node3D.new();map.set_meta("source_map_sha256",issued.index.source_sha256);service.handoff(map,13)
	check(preparing.reserved_bytes>0,"unconsumed handoff owns a real retained CPU result")
	map.free();owner.free()
	check(planning.reserved_bytes==0 and preparing.reserved_bytes==0,"freeing an unadopted result releases every completed packet and lease")
	# A real blocked worker handed off with the result is cancelled, never joined
	# by map.free; its independent drainer keeps the original plan reservation.
	owner=Node.new();root.add_child(owner);var gated:=GateLoader.new();cleanup_gates.append(gated.gate);owner.add_child(gated)
	gated.begin_prefetch(owner,issued.index,path,folder,issued.proof);gated.request(entries,-3,"entry_safety")
	for i in 90:
		gated.pump_prefetch()
		if gated.starts==2:break
		await process_frame
	planning=gated._planning;preparing=gated._preparing
	var gate:Semaphore=gated.gate;var starts:int=gated.starts;var before:int=planning.reserved_bytes
	map=Node3D.new();map.set_meta("source_map_sha256",issued.index.source_sha256)
	check(starts==2 and gated.handoff(map,14).ok,"in-flight CPU workers can transfer to the off-tree result without joining")
	map.free();owner.free()
	check(before>0 and planning.reserved_bytes==before,"unadopted map destruction retains cancelled active-worker accounting")
	for i in starts:gate.post()
	await wait_drained(planning,preparing)
	check(planning.reserved_bytes==0 and preparing.reserved_bytes==0,"drainer finishes cancelled handoff workers before releasing their leases")
	# Bare detachment is not the explicit off-tree ownership protocol.
	owner=Node.new();root.add_child(owner);service=Loader.new();owner.add_child(service)
	service.begin_prefetch(owner,issued.index,path,folder,issued.proof);service.request(entries,-3,"entry_safety")
	owner.remove_child(service);await process_frame
	check(service._cancelled,"unannounced prefetch detachment cancels rather than retaining an ownerless queue")
	service.free();owner.free()

func finish(errors:Logger)->void:
	Loader.dispatch_before_installation=previous_dispatch_first
	remove_fixture(folder);OS.remove_logger(errors)
	check(errors.errors.is_empty(),"zero unexpected engine errors")
	for issue:String in errors.errors:print("ENGINE_ERROR ",issue)
	print("COLLISION_DEPENDENCY_LOADER passed=",passed," failures=",failed);quit(0 if failed==0 else 1)
